import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../cache_store.dart';

/// 高校体育（sportcampus）的登录凭据。
///
/// 这是**另一套账号**：手机号 + 密码，和学号 / 统一身份认证无关，
/// 所以单独存一份，不和 CAS 的 `SessionStore` 混在一起——
/// 换教务账号不该动它，退出教务也不该把它清掉。
class SportCampusCredentials {
  const SportCampusCredentials({
    required this.mobile,
    required this.deviceId,
    required this.savedAt,
    this.password,
  });

  final String mobile;

  /// 未勾选「记住」时为 null：本次会话还能用，冷启动后要重新输入。
  final String? password;

  /// 设备指纹。登录时作为 `info` 上报，学校侧的记录按它区分设备，
  /// 每次登录都换一个新的容易被风控判成异常设备，所以要持久化。
  final String deviceId;

  final DateTime savedAt;

  bool get canAutoLogin => mobile.isNotEmpty && (password?.isNotEmpty ?? false);

  SportCampusCredentials copyWith({String? password, DateTime? savedAt}) {
    return SportCampusCredentials(
      mobile: mobile,
      deviceId: deviceId,
      password: password ?? this.password,
      savedAt: savedAt ?? this.savedAt,
    );
  }
}

/// 高校体育凭据存储。
///
/// 和 `SessionStore` 同一套加密后端：[FlutterSecureStorage]，
/// Android 走 Keystore + EncryptedSharedPreferences（AES-256），
/// iOS 走 Keychain。**明文不进磁盘、不进日志、不上传**。
class SportCampusStore {
  // v1：手机号 / 加密密码 / 设备指纹
  static const String _key = 'usst_sportcampus_cred_v1';
  static const FlutterSecureStorage _storage = kDefaultSecureStorage;

  Future<void> save(SportCampusCredentials credentials) async {
    try {
      await _storage.write(key: _key, value: encode(credentials));
    } catch (_) {
      // 存储失败不影响本次登录：本次会话仍然可用，只是下次要重新输入
    }
  }

  Future<SportCampusCredentials?> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      return decode(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // ignore：清不掉也只是下次多输一次密码
    }
  }

  /// 序列化（独立成静态方法，方便单测）。
  static String encode(SportCampusCredentials credentials) =>
      jsonEncode(<String, dynamic>{
        'mobile': credentials.mobile,
        'password': credentials.password,
        'deviceId': credentials.deviceId,
        'savedAt': credentials.savedAt.toIso8601String(),
      });

  static SportCampusCredentials decode(Map<String, dynamic> map) {
    return SportCampusCredentials(
      mobile: map['mobile'] as String? ?? '',
      password: map['password'] as String?,
      deviceId: map['deviceId'] as String? ?? '',
      savedAt:
          DateTime.tryParse(map['savedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
