import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 线上版本信息。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.notes,
    required this.githubUrl,
    required this.giteeUrl,
    required this.sha256,
    this.minVersionCode = 0,
    this.mandatory = false,
  });

  final String version;
  final int versionCode;
  final String notes;
  final String githubUrl;
  final String giteeUrl;
  final String sha256;

  /// 云端要求的最低版本号：当前版本低于它就必须更新，弹窗不可关闭。
  /// 0 表示不强制。
  final int minVersionCode;

  /// 这次更新是不是强制的（由 [UpdateService.check] 结合本机版本算出来）。
  final bool mandatory;

  UpdateInfo withMandatory(bool value) => UpdateInfo(
    version: version,
    versionCode: versionCode,
    notes: notes,
    githubUrl: githubUrl,
    giteeUrl: giteeUrl,
    sha256: sha256,
    minVersionCode: minVersionCode,
    mandatory: value,
  );

  static UpdateInfo? fromJson(Map<String, dynamic> json) {
    final version = (json['version'] ?? '').toString().trim();
    final code = (json['versionCode'] as num?)?.toInt() ?? 0;
    if (version.isEmpty || code <= 0) return null;
    return UpdateInfo(
      version: version,
      versionCode: code,
      notes: (json['notes'] ?? '').toString(),
      githubUrl: (json['apk_github'] ?? '').toString(),
      giteeUrl: (json['apk_gitee'] ?? '').toString(),
      sha256: (json['sha256'] ?? '').toString().toLowerCase(),
      minVersionCode: (json['minVersionCode'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 自动更新：Gitee 优先（国内快），GitHub 兜底。
class UpdateService {
  UpdateService._();

  static const String githubManifest =
      'https://raw.githubusercontent.com/extrisha/litang/main/update.json';
  static const String giteeManifest =
      'https://gitee.com/extrisha/litang/raw/main/update.json?download=1';

  /// 返回新版本；没有更新或检查失败返回 null。
  static Future<UpdateInfo?> check() async {
    final info =
        await _fetchManifest(giteeManifest) ??
        await _fetchManifest(githubManifest);
    if (info == null) return null;
    final current = await _currentVersionCode();
    if (info.versionCode <= current) return null;
    if (info.githubUrl.isEmpty && info.giteeUrl.isEmpty) return null;
    return info.withMandatory(isMandatory(current: current, min: info.minVersionCode));
  }

  /// 是否必须更新：本机版本低于云端要求的最低版本。
  /// 纯函数，方便单测；min <= 0 一律不强制（默认行为）。
  static bool isMandatory({required int current, required int min}) =>
      min > 0 && current < min;

  /// 手动下载兜底：自动下载失败时让用户去浏览器拿安装包。
  static const String releasePage =
      'https://github.com/extrisha/litang/releases/latest';

  static Future<int> _currentVersionCode() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<UpdateInfo?> _fetchManifest(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: <String, String>{'User-Agent': 'Litang-Updater'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      return UpdateInfo.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// 下载 APK，返回本地路径。默认 Gitee 优先（国内更快），失败自动切 GitHub。
  static Future<String> download(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final urls = candidateUrls(info);
    Object? lastError;
    for (var i = 0; i < urls.length; i++) {
      try {
        final path = await _downloadOne(
          urls[i],
          info.version,
          info.sha256,
          onProgress,
          allowFallback: i < urls.length - 1,
        );
        return path;
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('下载失败：${lastError ?? '没有可用的下载地址'}');
  }

  /// 候选下载地址（按顺序试）。
  ///
  /// 顺序是 **Gitee → Gitee 的 v 前缀备选 → GitHub**：
  /// 国内连 Gitee 更稳，GitHub 放最后兜底（海外或直连能通的场景）。
  ///
  /// Gitee 的地址里写死了 release tag，而 tag 有没有 `v` 前缀是靠人记的
  /// （历史上 v0.2.x / v0.3.0 带 v，0.4.x 不带），写错就是 404，
  /// 所以两种写法都排进去，谁通用谁。
  static List<String> candidateUrls(UpdateInfo info) {
    final out = <String>[];
    void add(String url) {
      if (url.isNotEmpty && !out.contains(url)) out.add(url);
    }

    add(info.giteeUrl);
    for (final url in _tagVariants(info.giteeUrl)) {
      add(url);
    }
    add(info.githubUrl);
    return out;
  }

  /// 把 `/download/<tag>/` 里的 tag 在「带 v」和「不带 v」之间来回换。
  static List<String> _tagVariants(String url) {
    if (url.isEmpty) return const <String>[];
    final match = RegExp(r'/download/([^/]+)/').firstMatch(url);
    if (match == null) return const <String>[];
    final tag = match.group(1)!;
    final alt = tag.startsWith('v') ? tag.substring(1) : 'v$tag';
    if (alt.isEmpty) return const <String>[];
    return <String>[url.replaceFirst(match.group(0)!, '/download/$alt/')];
  }

  static Future<String> _downloadOne(
    String url,
    String version,
    String expectedSha256,
    void Function(double)? onProgress, {
    bool allowFallback = false,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] = 'Litang-Updater';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/litang-$version.apk');
      final sink = file.openWrite();
      var received = 0;
      final total = response.contentLength ?? 0;
      final watch = Stopwatch()..start();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call(received / total);
        }
        // 下载 5 秒后如果速度低于 120KB/s，放弃当前源，切下一个源
        if (allowFallback && watch.elapsed.inSeconds >= 5) {
          final seconds = watch.elapsedMilliseconds / 1000;
          if (seconds > 0 && received / seconds < 120 * 1024) {
            await sink.close();
            try {
              await file.delete();
            } catch (_) {
              // ignore
            }
            throw _SlowDownload();
          }
        }
      }
      await sink.close();
      if (expectedSha256.isNotEmpty) {
        final digest = sha256.convert(await file.readAsBytes()).toString();
        if (digest != expectedSha256) {
          await file.delete();
          throw Exception('安装包校验失败');
        }
      }
      return file.path;
    } finally {
      client.close();
    }
  }

  /// 调系统安装器。
  static Future<void> install(String path) async {
    await OpenFilex.open(path);
  }
}

class _SlowDownload implements Exception {}
