import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../services/sport_campus_service.dart';
import '../app_exception.dart';
import 'sport_campus_store.dart';

/// 校园跑（高校体育）登录态与次数。
///
/// 全局单例，页面用 `ListenableBuilder` 订阅即可，不必自己维护一套 state。
///
/// 生命周期：
///   1. [restore] 从加密存储里读回手机号 / 密码 / 设备指纹，并贴出上次的次数；
///   2. [signIn] 首次绑定（登录页调用），成功后按「记住」决定是否落盘密码；
///   3. [refresh] 重新登录一次拿最新次数（接口没有独立的查询接口，
///      次数就在登录响应里，所以刷新 = 再登录一次）。
class SportCampusAuth extends ChangeNotifier {
  SportCampusAuth._();

  static final SportCampusAuth instance = SportCampusAuth._();

  /// 次数是低频数据：10 分钟内不重复登录，避免被风控盯上。
  static const Duration cacheTtl = Duration(minutes: 10);

  final SportCampusStore _store = SportCampusStore();
  SportCampusService? _service;

  String _mobile = '';
  String? _password;
  String _deviceId = '';
  SportCampusProgress? _progress;
  DateTime? _fetchedAt;
  bool _loading = false;
  String? _error;
  bool _restored = false;
  bool _restoring = false;

  /// 是否已经尝试过从磁盘恢复（避免每次 build 都读一次 Keystore）。
  bool get restored => _restored;

  /// 已绑定的手机号（未绑定为空串）。
  String get mobile => _mobile;

  /// 手机号脱敏展示：`138****0000`。
  String get maskedMobile {
    final m = _mobile;
    if (m.length < 7) {
      return m;
    }
    return '${m.substring(0, 3)}****${m.substring(m.length - 4)}';
  }

  /// 内存里是否有可用密码（未勾选「记住」时只在本次会话有效）。
  bool get hasPassword => _password?.isNotEmpty ?? false;

  /// 是否绑定过账号。
  bool get bound => _mobile.isNotEmpty;

  SportCampusProgress? get progress => _progress;

  DateTime? get fetchedAt => _fetchedAt;

  bool get loading => _loading;

  String? get error => _error;

  /// 冷启动恢复：读加密存储 + 贴缓存。重复调用安全。
  Future<void> restore() async {
    if (_restored || _restoring) {
      return;
    }
    _restoring = true;
    try {
      final stored = await _store.load();
      if (stored != null) {
        _mobile = stored.mobile;
        _password = stored.password;
        _deviceId = stored.deviceId;
        if (_mobile.isNotEmpty) {
          await SportCampusCache.load(_mobile);
          _progress = SportCampusCache.dataFor(_mobile);
          _fetchedAt = SportCampusCache.fetchedAtFor(_mobile);
        }
      }
      _deviceId = _ensureDeviceId(_deviceId);
    } finally {
      _restored = true;
      _restoring = false;
      notifyListeners();
    }
  }

  /// 首次绑定 / 换账号。
  ///
  /// [remember] 为 false 时只在本次会话保存密码，冷启动后需要重新输入
  /// （次数缓存仍然保留，卡片能先显示旧值）。
  Future<bool> signIn({
    required String mobile,
    required String password,
    bool remember = true,
  }) async {
    final phone = mobile.trim();
    if (phone.isEmpty || password.isEmpty) {
      _error = '请填写手机号和密码';
      notifyListeners();
      return false;
    }
    if (_loading) {
      return false;
    }

    _deviceId = _ensureDeviceId(_deviceId);
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final progress = await _serviceOrDefault.fetch(
        mobile: phone,
        password: password,
        deviceId: _deviceId,
      );
      _mobile = phone;
      _password = password;
      _progress = progress;
      _fetchedAt = DateTime.now();
      SportCampusCache.put(phone, progress);
      await _store.save(
        SportCampusCredentials(
          mobile: phone,
          password: remember ? password : null,
          deviceId: _deviceId,
          savedAt: DateTime.now(),
        ),
      );
      return true;
    } on AppException catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      // 兜底：不该发生，但绝不能把异常字符串直接甩给用户
      debugPrint('[sportcampus] 登录失败: $e');
      _error = '登录失败，请稍后重试';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 刷新次数。
  ///
  /// [force] 为 true 时跳过 10 分钟缓存（下拉刷新 / 点卡片）。
  Future<void> refresh({bool force = false}) async {
    await restore();
    if (_mobile.isEmpty) {
      // 没绑定不算失败：卡片会显示「去绑定」，不该顶一行红字
      return;
    }

    final age = SportCampusCache.ageFor(_mobile);
    if (!force && _progress != null && age != null && age < cacheTtl) {
      _fetchedAt = SportCampusCache.fetchedAtFor(_mobile) ?? _fetchedAt;
      _error = null;
      notifyListeners();
      return;
    }

    final password = _password;
    if (password == null || password.isEmpty) {
      // 没勾「记住」的账号冷启动后走不到这里（密码在内存里）；
      // 真到了说明用户之前选了不保存，提示他重新输入即可。
      _error = '需要重新输入高校体育密码';
      notifyListeners();
      return;
    }

    if (_loading) {
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final progress = await _serviceOrDefault.fetch(
        mobile: _mobile,
        password: password,
        deviceId: _ensureDeviceId(_deviceId),
      );
      _progress = progress;
      _fetchedAt = DateTime.now();
      SportCampusCache.put(_mobile, progress);
    } on AppException catch (e) {
      _error = e.message;
    } catch (e) {
      debugPrint('[sportcampus] 刷新失败: $e');
      _error = '刷新失败，请稍后重试';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 解绑：清加密凭据 + 次数缓存。
  Future<void> signOut() async {
    await _store.clear();
    await SportCampusCache.clear();
    _mobile = '';
    _password = null;
    _progress = null;
    _fetchedAt = null;
    _error = null;
    notifyListeners();
  }

  SportCampusService get _serviceOrDefault => _service ??= SportCampusService();

  /// 设备指纹：首次生成后落盘复用。每次换新容易被判成异常设备。
  String _ensureDeviceId(String current) {
    if (current.isNotEmpty) {
      return current;
    }
    return _newDeviceId();
  }

  static String _newDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    // RFC 4122 v4 形态，App 端只当作不透明字符串
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
            '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
            '${hex.substring(20)}'
        .toUpperCase();
  }

  /// 测试用：清空内存态（不动磁盘）。
  @visibleForTesting
  void resetForTest() {
    _mobile = '';
    _password = null;
    _deviceId = '';
    _progress = null;
    _fetchedAt = null;
    _loading = false;
    _error = null;
    _restored = false;
    _restoring = false;
    _service = null;
  }
}
