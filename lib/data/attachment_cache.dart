import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 作业附件下载目录（持久化，可手动清理）。
class AttachmentCache {
  AttachmentCache._();

  /// 当前下载目录占用，下载/清理后自动通知界面刷新。
  static final ValueNotifier<int> sizeNotifier = ValueNotifier<int>(0);
  static final Map<String, Future<String>> _downloads = {};
  static final Map<String, CancelToken> _tokens = {};
  static int _generation = 0;
  static Future<void>? _clearing;

  @visibleForTesting
  static Future<Directory> Function()? directoryOverride;

  /// Upload IDs are stable within a source/account. A replacement upload gets
  /// its own ID; size/version further distinguishes updated metadata.
  static String key({
    required String source,
    required String account,
    required String attachmentId,
    String version = '',
  }) => sha256
      .convert(
        utf8.encode(jsonEncode([source, account, attachmentId, version])),
      )
      .toString();

  static Future<Directory> _dir() async {
    final base =
        await (directoryOverride?.call() ?? getApplicationDocumentsDirectory());
    final dir = Directory('${base.path}/downloads');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String safeFilename(String name) {
    var safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    while (safe.contains('..')) {
      safe = safe.replaceAll('..', '_');
    }
    final stripped = safe.replaceAll(RegExp(r'[._]'), '');
    if (stripped.isEmpty) {
      safe = 'attachment_${DateTime.now().millisecondsSinceEpoch}';
    }
    return safe;
  }

  /// Stream into a temporary file, then publish atomically. Partial downloads
  /// never count as hits. Unversioned content is revalidated after one day.
  static Future<String> download({
    required String key,
    required String name,
    required Future<void> Function(String path, CancelToken token) receive,
    Duration maxAge = const Duration(days: 1),
  }) async {
    await _clearing;
    final active = _downloads[key];
    if (active != null) return active;
    final token = CancelToken();
    final generation = _generation;
    late final Future<String> operation;
    operation =
        (() async {
          final base = await _dir();
          final dir = Directory('${base.path}/$key');
          await dir.create(recursive: true);
          final file = File('${dir.path}/${safeFilename(name)}');
          if (await file.exists() &&
              await file.length() > 0 &&
              DateTime.now().difference(await file.lastModified()) < maxAge) {
            return file.path;
          }
          final part = File('${file.path}.part');
          try {
            if (token.isCancelled) throw token.cancelError!;
            await receive(part.path, token);
            if (token.isCancelled) throw token.cancelError!;
            if (generation != _generation) throw StateError('附件缓存已清理');
            if (!await part.exists() || await part.length() == 0) {
              throw StateError('附件内容为空，请重新下载');
            }
            await part.rename(file.path);
            await refreshSize();
            return file.path;
          } finally {
            if (await part.exists()) await part.delete();
          }
        })().whenComplete(() {
          if (identical(_downloads[key], operation)) {
            _downloads.remove(key);
            _tokens.remove(key);
          }
        });
    _tokens[key] = token;
    _downloads[key] = operation;
    return operation;
  }

  static void cancel(String key) => _tokens[key]?.cancel('已取消下载');

  static Future<int> size() async {
    final dir = await _dir();
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && !entity.path.endsWith('.part')) {
        total += await entity.length();
      }
    }
    sizeNotifier.value = total;
    return total;
  }

  static Future<void> refreshSize() async {
    await size();
  }

  static Future<void> clear() {
    if (_clearing != null) return _clearing!;
    _generation++;
    for (final token in _tokens.values) {
      token.cancel('附件缓存已清理');
    }
    final pending = _downloads.values.toList();
    late final Future<void> operation;
    operation =
        (() async {
          await Future.wait(
            pending.map((f) async {
              try {
                await f;
              } catch (_) {
                // 这里只是「等在途下载全部结束」再删目录：单个下载失败
                // 不影响清理，且失败原因已由各自的下载流程记录，不再重复打日志。
              }
            }),
          );
          final dir = await _dir();
          if (await dir.exists()) await dir.delete(recursive: true);
          sizeNotifier.value = 0;
        })().whenComplete(() {
          if (identical(_clearing, operation)) _clearing = null;
        });
    return _clearing = operation;
  }
}
