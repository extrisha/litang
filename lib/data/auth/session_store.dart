import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../cache_store.dart';

import 'cas_client.dart';

/// 本地保存的登录会话。
///
/// [password] 只在用户勾选「记住密码」时保存，加密方式见 [SessionStore]。
class StoredSession {
  const StoredSession({
    required this.cookies,
    required this.username,
    required this.savedAt,
    this.password,
  });

  final List<CasCookie> cookies;

  /// 学号（用于自动登录和展示）。
  final String username;

  /// 加密保存的密码；没勾选记住密码时为 null。
  final String? password;

  final DateTime savedAt;

  bool get canAutoLogin =>
      username.isNotEmpty && (password?.isNotEmpty ?? false);
}

/// 登录凭据存储。
///
/// 使用 [FlutterSecureStorage]：Android 走 Keystore + EncryptedSharedPreferences
/// （AES-256），iOS 走 Keychain，密文只存在本机，不进任何服务器、也不写日志。
class SessionStore {
  // v2：新增加密保存的学号/密码，旧格式直接作废
  static const String _key = 'usst_cas_session_v2';
  static const FlutterSecureStorage _storage = kDefaultSecureStorage;

  Future<void> save(
    CasClient client, {
    required String username,
    String? password,
  }) async {
    try {
      String previous;
      try {
        previous = await loadUsername();
      } catch (_) {
        previous = '';
      }
      if (previous != username.trim()) {
        // Legacy schedules had no owner; never carry one into another account.
        await CacheStore.remove(
          'usst_course_snapshot_v2',
          secure: true,
          requirePersistence: true,
        );
      }
      final payload = encode(
        StoredSession(
          cookies: client.jar.cookies,
          username: username,
          password: password,
          savedAt: DateTime.now(),
        ),
      );
      await _storage.write(key: _key, value: payload);
    } catch (_) {
      // 存储失败不影响本次登录
    }
  }

  Future<StoredSession?> load() async {
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

  /// Background widgets need the local account key, not a network login.
  Future<String> loadUsername() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return '';
    final value = jsonDecode(raw);
    if (value is! Map) throw const FormatException('本地账号记录无法解析');
    return (value['username'] ?? '').toString().trim();
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // ignore
    }
  }

  /// 序列化（独立成静态方法，方便单测）。
  static String encode(StoredSession session) => jsonEncode(<String, dynamic>{
    'username': session.username,
    'password': session.password,
    'savedAt': session.savedAt.toIso8601String(),
    'cookies': session.cookies.map((c) => c.toJson()).toList(),
  });

  static StoredSession decode(Map<String, dynamic> map) {
    final cookies = (map['cookies'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => CasCookie.fromJson(e as Map<String, dynamic>))
        .toList();
    return StoredSession(
      cookies: cookies,
      username: map['username'] as String? ?? '',
      password: map['password'] as String?,
      savedAt:
          DateTime.tryParse(map['savedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
