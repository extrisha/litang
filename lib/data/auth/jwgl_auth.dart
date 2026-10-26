import 'package:flutter/foundation.dart';

import 'cas_client.dart';
import 'session_store.dart';

/// 全局登录态。
///
/// 登录成功后：
///   1. 会话 cookie 加密存本地（下次直接用）；
///   2. 勾选「记住密码」时，学号密码也加密存本地；
///   3. cookie 过期先用 CAS 的 TGC 静默重登，TGC 也过期则用保存的密码后台重登。
class JwglAuth extends ChangeNotifier {
  JwglAuth._();

  static final JwglAuth instance = JwglAuth._();

  final SessionStore _store = SessionStore();

  CasClient? _client;
  String? _studentId;
  bool _restored = false;

  String _savedUsername = '';
  String? _savedPassword;

  bool get isLoggedIn => _client != null;

  String? get studentId => _studentId;

  /// 本地保存的学号（WebVPN 等二次登录用）。
  String get savedUsername => _savedUsername;

  /// 本地保存的密码；未勾选记住登录时为 null。
  String? get savedPassword => _savedPassword;

  CasClient? get client => _client;

  /// 本地是否保存了可自动登录的密码。
  bool get hasSavedPassword => _savedPassword?.isNotEmpty ?? false;

  Future<void> login(
    String username,
    String password, {
    bool remember = true,
  }) async {
    if (kIsWeb) {
      throw CasLoginException('网页版无法跨域登录，请安装 App 后使用');
    }
    final client = CasClient();
    await client.login(username, password);
    _applyLogin(client, username.trim(), remember ? password : null);
    await _store.save(
      client,
      username: _savedUsername,
      password: _savedPassword,
    );
    notifyListeners();
  }

  /// 用一个已经登录成功的 [client] 建立登录态。
  ///
  /// 登录页带验证码重试时用：多次提交必须复用同一个 CasClient，
  /// 否则每次换会话，验证码永远对不上。
  Future<void> adopt(
    CasClient client,
    String username,
    String password, {
    bool remember = true,
  }) async {
    final name = username.trim();
    _applyLogin(client, name, remember ? password : null);
    await _store.save(
      client,
      username: _savedUsername,
      password: _savedPassword,
    );
    notifyListeners();
  }

  void _applyLogin(CasClient client, String username, String? password) {
    _client = client;
    _studentId = username;
    _savedUsername = username;
    _savedPassword = password;
    _restored = true;
  }

  /// 启动时恢复登录：cookie → CAS 静默 → 保存的密码，逐级降级。
  Future<void> restore() async {
    if (_restored) {
      return;
    }
    _restored = true;

    final stored = await _store.load();
    if (stored != null) {
      _savedUsername = stored.username;
      _savedPassword = stored.password;
      _studentId = stored.username.isNotEmpty ? stored.username : null;
      final client = CasClient(initialCookies: stored.cookies);
      if (await client.checkSession()) {
        _client = client;
        notifyListeners();
        return;
      }
      if (await client.silentLogin()) {
        _client = client;
        await _store.save(
          client,
          username: _savedUsername,
          password: _savedPassword,
        );
        notifyListeners();
        return;
      }
    }

    if (await _tryAutoLogin()) {
      notifyListeners();
      return;
    }
    await _clearAll();
  }

  /// 强制后台重登：先试 CAS 静默，再用本地保存的密码重新登录。
  /// 用于「会话半失效」——checkSession 通过但业务接口已经不可用的情况。
  Future<bool> reauthenticate() async {
    final current = _client;
    if (current != null) {
      try {
        if (await current.silentLogin()) {
          await _store.save(
            current,
            username: _savedUsername,
            password: _savedPassword,
          );
          notifyListeners();
          return true;
        }
      } catch (_) {
        // 继续尝试密码登录
      }
    }
    final username = _savedUsername;
    final password = _savedPassword;
    if (username.isEmpty || password == null || password.isEmpty) {
      return false;
    }
    try {
      final client = CasClient();
      await client.login(username, password);
      _applyLogin(client, username, password);
      await _store.save(client, username: username, password: password);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 数据页调用：过期时自动恢复，尽量不让用户手动登录。
  Future<bool> ensureSession() async {
    final client = _client;
    if (client == null) {
      return _tryAutoLogin();
    }
    if (await client.checkSession()) {
      return true;
    }
    if (await client.silentLogin()) {
      await _store.save(
        client,
        username: _savedUsername,
        password: _savedPassword,
      );
      return true;
    }
    return _tryAutoLogin();
  }

  /// 用本地保存的学号密码后台登录（失败会清掉已保存凭据，避免反复触发风控）。
  Future<bool> _tryAutoLogin() async {
    final username = _savedUsername;
    final password = _savedPassword;
    if (username.isEmpty || password == null || password.isEmpty) {
      return false;
    }
    try {
      final client = CasClient();
      await client.login(username, password);
      _applyLogin(client, username, password);
      await _store.save(client, username: username, password: password);
      notifyListeners();
      return true;
    } catch (_) {
      // 密码失效/风控验证码等：清掉密码，下次让用户手动登录
      _savedPassword = null;
      await _clearAll();
      return false;
    }
  }

  Future<void> logout() async {
    await _clearAll();
    notifyListeners();
  }

  Future<void> _clearAll() async {
    _client = null;
    _studentId = null;
    _savedUsername = '';
    _savedPassword = null;
    await _store.clear();
  }
}
