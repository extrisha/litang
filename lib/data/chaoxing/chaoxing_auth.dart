import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/cas_client.dart';
import 'chaoxing_client.dart';
import 'web_cookie_bridge.dart';

/// 学习通本地会话（只存 cookie，不存密码）。
class ChaoxingStoredSession {
  const ChaoxingStoredSession({required this.cookies, required this.savedAt});

  final List<CasCookie> cookies;
  final DateTime savedAt;
}

/// 学习通凭据存储（Keystore / Keychain）。
class ChaoxingSessionStore {
  static const String _key = 'usst_chaoxing_session_v2';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<void> save(ChaoxingClient client) async {
    try {
      final payload = jsonEncode(<String, dynamic>{
        'savedAt': DateTime.now().toIso8601String(),
        'cookies': client.jar.cookies.map((c) => c.toJson()).toList(),
      });
      await _storage.write(key: _key, value: payload);
    } catch (_) {
      // 存储失败不影响本次登录
    }
  }

  Future<ChaoxingStoredSession?> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ChaoxingStoredSession(
        cookies: (map['cookies'] as List<dynamic>? ?? <dynamic>[])
            .map((e) => CasCookie.fromJson(e as Map<String, dynamic>))
            .toList(),
        savedAt:
            DateTime.tryParse(map['savedAt'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // ignore
    }
  }
}

/// 学习通全局登录态。
///
/// 登录走内嵌网页（见 `ChaoxingLoginPage`）：优先复用教务 CAS 做 SSO，
/// 失败再走超星官方机构登录页；登完只把 cookie 读回来。
/// 这样既不用复现对方的密码加密，也不用在本地保存学习通密码。
class ChaoxingAuth extends ChangeNotifier {
  ChaoxingAuth._();

  static final ChaoxingAuth instance = ChaoxingAuth._();

  final ChaoxingSessionStore _store = ChaoxingSessionStore();

  ChaoxingClient? _client;
  bool _restored = false;

  bool get isLoggedIn => _client != null;

  ChaoxingClient? get client => _client;

  /// 网页登录回来的 cookie → 建客户端。cookie 无效返回 false。
  Future<bool> loginWithCookies(List<CasCookie> cookies) async {
    if (cookies.isEmpty) return false;
    final client = ChaoxingClient(initialCookies: cookies);
    if (!await client.checkSession()) {
      return false;
    }
    _client = client;
    _restored = true;
    await _store.save(client);
    notifyListeners();
    return true;
  }

  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    final stored = await _store.load();
    if (stored == null || stored.cookies.isEmpty) return;
    final client = ChaoxingClient(initialCookies: stored.cookies);
    if (await client.checkSession()) {
      _client = client;
      notifyListeners();
      return;
    }
    // 会话过期了：cookie 留着没用，清掉，让用户重新网页登录
    await _store.clear();
  }

  /// 数据页调用：cookie 失效时先试一次本地恢复。
  ///
  /// 失败时要把 `_client` 清掉 —— 否则 UI 里 `isLoggedIn` 一直是 true，
  /// 页面上就只显示「重试」，永远等不到登录按钮。
  Future<bool> ensureSession() async {
    final client = _client;
    if (client != null && await client.checkSession()) {
      return true;
    }
    _client = null;
    _restored = false;
    await restore();
    final ok = _client != null;
    notifyListeners();
    return ok;
  }

  Future<void> logout() async {
    _client = null;
    await _store.clear();
    // 一并清掉 WebView 里的登录态，免得下次点登录直接是上一个人的账号
    await WebCookieBridge.clear();
    notifyListeners();
  }
}
