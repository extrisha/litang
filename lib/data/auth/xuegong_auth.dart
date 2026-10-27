import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cas_client.dart';
import 'jwgl_auth.dart';

/// 学工一体化（new2017）静默登录。
///
/// 学工首页接的是学校 CAS：用教务已登录的会话访问
/// `https://new2017.usst.edu.cn/default.aspx` 会自动完成 SSO，
/// 拿到 new2017 的 cookie 后注入 WebView 即可免登录进入。
class XuegongAuth {
  XuegongAuth._();

  static final XuegongAuth instance = XuegongAuth._();

  static const String _key = 'usst_xuegong_cookies_v1';
  static const String host = 'new2017.usst.edu.cn';
  static const String homeUrl = 'https://new2017.usst.edu.cn/StuDefault.aspx';
  static const String webVpnHost = 'new2017.webvpn.usst.edu.cn';
  static const String webVpnHomeUrl =
      'https://new2017.webvpn.usst.edu.cn/default.aspx';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  List<CasCookie> _cookies = <CasCookie>[];
  bool _viaWebVpn = false;

  List<CasCookie> get cookies => List<CasCookie>.unmodifiable(_cookies);

  /// 当前会话应该打开的地址（校外自动用 WebVPN）。
  String get homeUrlForSession => _viaWebVpn ? webVpnHomeUrl : homeUrl;

  /// 用当前教务会话尝试静默登录学工；成功返回 true 并缓存 cookie。
  Future<bool> ensureLoggedIn() async {
    final jwgl = JwglAuth.instance;
    if (!jwgl.isLoggedIn) {
      return false;
    }
    if (!await jwgl.ensureSession()) {
      if (!await jwgl.reauthenticate()) {
        return false;
      }
    }
    final client = jwgl.client;
    if (client == null) {
      return false;
    }
    try {
      final resp = await client.getJson(
        Uri.parse('https://$host/default.aspx'),
      );
      final body = resp.data ?? '';
      final finalUrl = resp.realUri.toString();
      final ok = !finalUrl.contains('WeLinkLogOn') && body.contains('学生主页');
      if (!ok) {
        return await _loginViaWebVpn();
      }
      _cookies = client.jar.cookiesForHost(host);
      _viaWebVpn = false;
      await _save();
      return _cookies.isNotEmpty;
    } catch (_) {
      return await _loginViaWebVpn();
    }
  }

  /// 校外：WebVPN 会先跳 ids6-443 登录，登录后直接回到目标页。
  Future<bool> _loginViaWebVpn() async {
    final jwgl = JwglAuth.instance;
    final username = jwgl.savedUsername;
    final password = jwgl.savedPassword;
    if (username.isEmpty || password == null || password.isEmpty) {
      return false;
    }
    try {
      final client = CasClient();
      final result = await client.loginAt(
        Uri.parse(webVpnHomeUrl),
        username,
        password,
      );
      if (!result.body.contains('学生主页')) {
        return false;
      }
      _cookies = client.jar.cookiesForHost(webVpnHost);
      _viaWebVpn = true;
      await _save();
      return _cookies.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 读取/恢复上次缓存的 cookie（WebView 注入用）。
  Future<List<CasCookie>> loadCookies() async {
    if (_cookies.isNotEmpty) {
      return cookies;
    }
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) {
        return _cookies;
      }
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => CasCookie.fromJson(e as Map<String, dynamic>))
          .toList();
      _cookies = list;
    } catch (_) {
      // ignore
    }
    return cookies;
  }

  Future<void> clear() async {
    _cookies = <CasCookie>[];
    _viaWebVpn = false;
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // ignore
    }
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
