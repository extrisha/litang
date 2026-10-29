import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/cas_client.dart';
import '../auth/jwgl_auth.dart';

/// 一网畅学（Tronclass）静默登录：复用教务 CAS 会话走 Keycloak 的 CAS broker。
class TronclassAuth {
  TronclassAuth._();

  static final TronclassAuth instance = TronclassAuth._();

  static const String _key = 'usst_tronclass_cookies_v1';
  static const String host = '1906.usst.edu.cn';
  static const String homeUrl = 'https://1906.usst.edu.cn/user/index';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  List<CasCookie> _cookies = <CasCookie>[];
  DateTime? _validatedAt;
  String? _validatedUser;

  /// 同一个刷新流程里会被调用多次；15 秒内不重复探 1906。
  static const Duration _sessionTtl = Duration(seconds: 15);

  List<CasCookie> get cookies => List<CasCookie>.unmodifiable(_cookies);

  CasClient? get client => JwglAuth.instance.client;

  /// 静默登录；成功返回 true。
  Future<bool> ensureLoggedIn() async {
    final jwgl = JwglAuth.instance;
    if (!jwgl.isLoggedIn) {
      return false;
    }
    final checkedAt = _validatedAt;
    if (checkedAt != null &&
        _validatedUser == jwgl.studentId &&
        DateTime.now().difference(checkedAt) < _sessionTtl) {
      return true;
    }
    if (!await jwgl.ensureSession()) {
      if (!await jwgl.reauthenticate()) {
        return false;
      }
    }
    // 第一次失败时后台强制重登教务，再试一次，尽量不让用户手动点
    for (var attempt = 0; attempt < 2; attempt++) {
      final casClient = jwgl.client;
      if (casClient == null) {
        return false;
      }
      try {
        // 已经持有 1906 的 cookie 时先探一下轻量接口。
        // /login 是 800KB+ 的 SPA 页面，每次刷新都拉一遍非常拖慢，能省就省。
        if (casClient.jar.cookiesForHost(host).isNotEmpty) {
          if (await _probe(casClient)) {
            return await _cacheCookies(casClient);
          }
        }
        // 没有 cookie 或已经失效，才走 /login 让 Keycloak/CAS 完成认证
        await casClient.getJson(Uri.parse('https://$host/login'));
        if (await _probe(casClient)) {
          return await _cacheCookies(casClient);
        }
      } catch (_) {
        // 继续重试
      }
      if (attempt == 0) {
        final ok = await jwgl.reauthenticate();
        if (!ok) return false;
      }
    }
    _validatedAt = null;
    _validatedUser = null;
    return false;
  }

  /// 用最轻的接口判断 1906 会话是否仍然有效。
  Future<bool> _probe(CasClient client) async {
    try {
      final resp = await client.getApi(
        Uri.parse('https://$host/api/radar/rollcalls?api_version=1.1.0'),
      );
      if ((resp.statusCode ?? 0) != 200) return false;
      // 会话失效时这里会跳到登录页（HTML），用 JSON 前缀再兜一层
      return (resp.data ?? '').trimLeft().startsWith('{');
    } catch (_) {
      return false;
    }
  }

  Future<bool> _cacheCookies(CasClient client) async {
    _cookies = client.jar.cookiesForHost(host);
    _validatedAt = DateTime.now();
    _validatedUser = JwglAuth.instance.studentId;
    await _save();
    return _cookies.isNotEmpty;
  }

  Future<List<CasCookie>> loadCookies() async {
    if (_cookies.isNotEmpty) {
      return cookies;
    }
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) {
        return _cookies;
      }
      _cookies = (jsonDecode(raw) as List<dynamic>)
          .map((e) => CasCookie.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // ignore
    }
    return cookies;
  }

  /// 合并 CAS 与一网畅学本身的 Cookie，供内嵌 WebView 注入使用。
  Future<List<CasCookie>> getMergedCookies() async {
    final tronclass = await loadCookies();
    final cas = JwglAuth.instance.client?.jar.cookies ?? const <CasCookie>[];
    final cookies = <CasCookie>[];
    final seen = <String>{};
    for (final cookie in <CasCookie>[...cas, ...tronclass]) {
      if (seen.add('${cookie.name}|${cookie.domain}|${cookie.path}')) {
        cookies.add(cookie);
      }
    }
    return cookies;
  }

  Future<void> _save() async {
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode(_cookies.map((c) => c.toJson()).toList()),
      );
    } catch (_) {
      // ignore
    }
  }
}
