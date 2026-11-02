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
  DateTime? _sessionCheckedAt;

  /// 在途的 [ensureSession] 调用，用来把并发请求合并成一次。
  Future<bool>? _sessionInFlight;

  /// 同一个页面刷新会多次调用 ensureSession；15 秒内不重复打教务首页。
  /// 真正的半失效仍由业务请求失败后的 reauthenticate 兜底。
  static const Duration _sessionTtl = Duration(seconds: 15);

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

  /// 把登录态落盘。
  ///
  /// **失败不算登录失败**：Android Keystore / iOS Keychain 在个别设备上会抛
  /// （密钥被系统重置、锁屏策略、存储损坏…）。这种情况下本次会话已经可用，
  /// 只是下次要重新登录。原来的写法让 `_store.save` 的异常一路冒到登录页，
  /// 用户看到的是「网络异常」——明明是登录成功了的。
  Future<void> _persist() async {
    final client = _client;
    if (client == null) return;
    try {
      await _store.save(
        client,
        username: _savedUsername,
        password: _savedPassword,
      );
    } catch (e) {
      debugPrint('[auth] 保存登录态失败（本次会话仍可用）: $e');
    }
  }

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
    await _persist();
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
    await _persist();
    notifyListeners();
  }

  void _applyLogin(CasClient client, String username, String? password) {
    _client = client;
    _studentId = username;
    _savedUsername = username;
    _savedPassword = password;
    _restored = true;
    _sessionCheckedAt = DateTime.now();
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
        _sessionCheckedAt = DateTime.now();
        notifyListeners();
        return;
      }
      if (await client.silentLogin()) {
        _client = client;
        _sessionCheckedAt = DateTime.now();
        await _persist();
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
          _sessionCheckedAt = DateTime.now();
          await _persist();
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
      await _persist();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 数据页调用：过期时自动恢复，尽量不让用户手动登录。
  ///
  /// 同一时刻只允许一次校验/重登。多个页面同时调本方法时，如果各自都去
  /// checkSession / silentLogin / 密码登录，就会同时向 CAS 发起多次登录，
  /// 互相把对方的会话顶掉——「到处乱点之后 CAS 就废了」有这一份功劳。
  Future<bool> ensureSession() {
    return _sessionInFlight ??= _ensureSessionInner().whenComplete(() {
      _sessionInFlight = null;
    });
  }

  Future<bool> _ensureSessionInner() async {
    final client = _client;
    if (client == null) {
      return _tryAutoLogin();
    }
    final checkedAt = _sessionCheckedAt;
    if (checkedAt != null &&
        DateTime.now().difference(checkedAt) < _sessionTtl) {
      return true;
    }
    if (await client.checkSession()) {
      _sessionCheckedAt = DateTime.now();
      return true;
    }
    _sessionCheckedAt = null;
    if (await client.silentLogin()) {
      _sessionCheckedAt = DateTime.now();
      await _persist();
      return true;
    }
    return _tryAutoLogin();
  }

  /// 用本地保存的学号密码后台登录。
  ///
  /// 失败**不一定**是凭据错了：网络抖动、CAS 风控要求验证码、页面结构变化、
  /// 以及「网页端另开一个会话把 App 顶掉」都会让这里失败。
  ///
  /// 原来的写法是任何异常都走 `_savedPassword = null; _clearAll();`，
  /// 于是一次临时失败就把学号、密码、会话全部抹掉，之后所有页面都只能报
  /// 「请先登录」——用户表现为「突然 CAS 登录失败，怎么进都不行」。
  /// 现在只有服务端**明确拒绝凭据**时才清。
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
      await _persist();
      notifyListeners();
      return true;
    } on CasCaptchaRequired {
      // 需要验证码 ≠ 凭据失效：保留密码，让用户手动登录一次即可
      return false;
    } on CasLoginException catch (e) {
      if (_isCredentialRejection(e.message)) {
        _savedPassword = null;
        await _clearAll();
      }
      return false;
    } catch (_) {
      // 网络 / 解析 / 未知错误：保留凭据，下次再试
      return false;
    }
  }

  /// 服务端是否在明确表示「学号或密码不对 / 账号不可用」。
  static bool _isCredentialRejection(String message) {
    const markers = <String>['密码', '账号', '用户名', '锁定', '禁用', '不存在'];
    return markers.any(message.contains);
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
    _sessionCheckedAt = null;
    try {
      await _store.clear();
    } catch (e) {
      // 清不掉也不能让「退出登录」失败：内存里的登录态已经清了，
      // 下次启动最多是恢复出一个无效会话，会在 checkSession 处被拒。
      debugPrint('[auth] 清除本地登录态失败: $e');
    }
  }
}
