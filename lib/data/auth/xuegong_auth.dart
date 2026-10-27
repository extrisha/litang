import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cas_client.dart';
import 'jwgl_auth.dart';

/// 学工一体化（new2017）静默登录。
///
/// 学工首页接的是学校 CAS：用教务已登录的会话访问
/// `https://new2017.usst.edu.cn/default.aspx` 会自动完成 SSO，
/// 拿到 new2017 的 cookie 后注入 WebView 即可免登录进入。
///
/// 速度上做了三层优化：
///   1. 成功登录后缓存 cookie + 登录方式（校内 / WebVPN），10 分钟内直接复用；
///   2. 校外优先走已缓存的 WebVPN 地址，避免每次都先等校内地址失败；
///   3. 先直接用当前教务会话试，失效了才做一次 ensureSession，
///      不再在页面层重复 reauthenticate + 重试。
class XuegongAuth {
  XuegongAuth._();

  static final XuegongAuth instance = XuegongAuth._();

  static const String _key = 'usst_xuegong_session_v2';
  static const String _legacyKey = 'usst_xuegong_cookies_v1';
  static const String host = 'new2017.usst.edu.cn';
  static const String homeUrl = 'https://new2017.usst.edu.cn/StuDefault.aspx';
  static const String webVpnHost = 'new2017.webvpn.usst.edu.cn';
  static const String webVpnHomeUrl =
      'https://new2017.webvpn.usst.edu.cn/default.aspx';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// 缓存多久可以直接复用。学工会话本身比这长；超过就重新验一次。
  static const Duration _freshTtl = Duration(minutes: 10);

  /// 单次探测（校内 / WebVPN）最多等多久，避免校外直连卡 30 秒。
  static const Duration _probeTimeout = Duration(seconds: 6);

  List<CasCookie> _cookies = <CasCookie>[];
  bool _viaWebVpn = false;
  DateTime? _savedAt;
  bool _restored = false;

  List<CasCookie> get cookies => List<CasCookie>.unmodifiable(_cookies);

  /// 当前会话应该打开的地址（校外自动用 WebVPN）。
  String get homeUrlForSession => _viaWebVpn ? webVpnHomeUrl : homeUrl;

  /// 最近一次成功登录是否还在可直接复用的窗口内。
  bool get hasFreshSession => _isFresh;

  bool get _isFresh {
    final at = _savedAt;
    return _cookies.isNotEmpty &&
        at != null &&
        DateTime.now().difference(at) < _freshTtl;
  }

  /// 用当前教务会话尝试静默登录学工；成功返回 true 并缓存 cookie。
  ///
  /// [force] 为 true 时跳过 10 分钟缓存，强制验一次。
  Future<bool> ensureLoggedIn({bool force = false}) async {
    await _restore();
    if (!force && _isFresh) {
      return true;
    }

    final jwgl = JwglAuth.instance;
    if (!jwgl.isLoggedIn) {
      return false;
    }
    final client = jwgl.client;
    if (client == null) {
      return false;
    }

    // 1) 先用现有会话试一次。校内直连，校外优先走上次成功的 WebVPN。
    if (await _tryCurrentRoute(client)) {
      return true;
    }

    // 2) 教务会话可能半失效：只刷新一次，再试一次。
    var refreshed = false;
    try {
      refreshed = await jwgl.ensureSession().timeout(
        const Duration(seconds: 12),
      );
    } catch (_) {
      refreshed = false;
    }
    final refreshedClient = jwgl.client;
    if (refreshed && refreshedClient != null) {
      if (await _tryCurrentRoute(refreshedClient)) {
        return true;
      }
    }

    // 3) 最后才用保存的密码完整登一次 WebVPN。
    return _loginViaWebVpn();
  }

  Future<bool> _tryCurrentRoute(CasClient client) async {
    if (_viaWebVpn) {
      if (await _tryWebVpnSso(client)) {
        return true;
      }
      return _tryDirect(client);
    }
    if (await _tryDirect(client)) {
      return true;
    }
    return _tryWebVpnSso(client);
  }

  Future<bool> _tryDirect(CasClient client) async {
    try {
      final resp = await client
          .getJson(Uri.parse('https://$host/default.aspx'))
          .timeout(_probeTimeout);
      final body = resp.data ?? '';
      final finalUrl = resp.realUri.toString();
      if (finalUrl.contains('WeLinkLogOn') || !body.contains('学生主页')) {
        return false;
      }
      final cookies = client.jar.cookiesForHost(host);
      if (cookies.isEmpty) {
        return false;
      }
      _cookies = cookies;
      _viaWebVpn = false;
      await _save();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 校外：先复用当前 CAS 会话走 WebVPN SSO，通常比重新输密码快很多。
  Future<bool> _tryWebVpnSso(CasClient client) async {
    try {
      final resp = await client
          .getJson(Uri.parse(webVpnHomeUrl))
          .timeout(_probeTimeout);
      if (!(resp.data ?? '').contains('学生主页')) {
        return false;
      }
      final cookies = client.jar.cookiesForHost(webVpnHost);
      if (cookies.isEmpty) {
        return false;
      }
      _cookies = cookies;
      _viaWebVpn = true;
      await _save();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 校外兜底：WebVPN 会先跳 ids6-443 登录，登录后直接回到目标页。
  Future<bool> _loginViaWebVpn() async {
    final jwgl = JwglAuth.instance;
    final username = jwgl.savedUsername;
    final password = jwgl.savedPassword;
    if (username.isEmpty || password == null || password.isEmpty) {
      return false;
    }
    try {
      final client = CasClient();
      final result = await client
          .loginAt(Uri.parse(webVpnHomeUrl), username, password)
          .timeout(const Duration(seconds: 18));
      if (!result.body.contains('学生主页')) {
        return false;
      }
      final cookies = client.jar.cookiesForHost(webVpnHost);
      if (cookies.isEmpty) {
        return false;
      }
      _cookies = cookies;
      _viaWebVpn = true;
      await _save();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 读取/恢复上次缓存的 cookie（WebView 注入用）。
  Future<List<CasCookie>> loadCookies() async {
    await _restore();
    return cookies;
  }

  Future<void> _restore() async {
    if (_restored) {
      return;
    }
    _restored = true;
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final list = decoded['cookies'];
          if (list is List) {
            _cookies = list
                .whereType<Map>()
                .map((e) => CasCookie.fromJson(e.cast<String, dynamic>()))
                .toList();
            _viaWebVpn = decoded['viaWebVpn'] == true;
            _savedAt = DateTime.tryParse('${decoded['savedAt'] ?? ''}');
            if (_cookies.isNotEmpty) {
              return;
            }
          }
        } else if (decoded is List) {
          // 兼容旧格式：纯 cookie 数组，没有时间/线路信息。
          _cookies = decoded
              .whereType<Map>()
              .map((e) => CasCookie.fromJson(e.cast<String, dynamic>()))
              .toList();
          if (_cookies.isNotEmpty) {
            return;
          }
        }
      }

      // v1 → v2 迁移：读旧 key，但因为没有 savedAt，第一次仍会验一次。
      final legacy = await _storage.read(key: _legacyKey);
      if (legacy != null && legacy.isNotEmpty) {
        final decoded = jsonDecode(legacy);
        if (decoded is List) {
          _cookies = decoded
              .whereType<Map>()
              .map((e) => CasCookie.fromJson(e.cast<String, dynamic>()))
              .toList();
        }
      }
    } catch (_) {
      // 存储坏了就当作没有缓存，走正常登录。
    }
  }

  Future<void> clear() async {
    _cookies = <CasCookie>[];
    _viaWebVpn = false;
    _savedAt = null;
    _restored = true;
    try {
      await _storage.delete(key: _key);
      await _storage.delete(key: _legacyKey);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _save() async {
    _savedAt = DateTime.now();
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode(<String, dynamic>{
          'savedAt': _savedAt!.toIso8601String(),
          'viaWebVpn': _viaWebVpn,
          'cookies': _cookies.map((c) => c.toJson()).toList(),
        }),
      );
    } catch (_) {
      // ignore
    }
  }
}
