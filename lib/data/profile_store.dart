import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 论坛/个人页使用的本地资料（昵称、头像），按教务学号隔离。
class UserProfile {
  const UserProfile({required this.nickname, required this.avatar});

  final String nickname;

  /// 用 emoji 当头像，省掉图片上传。
  final String avatar;

  static const UserProfile fallback = UserProfile(nickname: '', avatar: '🎓');

  Map<String, String> toJson() => <String, String>{
    'nickname': nickname,
    'avatar': avatar,
  };

  static UserProfile fromJson(Map<String, dynamic> json) => UserProfile(
    nickname: json['nickname'] as String? ?? '',
    avatar: json['avatar'] as String? ?? '🎓',
  );
}

/// 个人资料存储（加密），按教务学号隔离。
class ProfileStore {
  static const String _key = 'usst_user_profile_v1';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String _keyFor(String username) {
    final user = username.trim();
    return user.isEmpty ? _key : '${_key}_$user';
  }

  static const List<String> avatars = <String>[
    '🎓',
    '🐱',
    '🐶',
    '🦊',
    '🐼',
    '🐰',
    '🍊',
    '🌙',
    '⭐',
    '🍀',
    '🎧',
    '🧋',
  ];

  static Future<UserProfile?> load({String username = ''}) async {
    try {
      final raw = await _storage.read(key: _keyFor(username));
      if (raw == null || raw.isEmpty) {
        return null;
      }
      return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(UserProfile profile, {String username = ''}) async {
    try {
      await _storage.write(
        key: _keyFor(username),
        value: jsonEncode(profile.toJson()),
      );
    } catch (_) {
      // ignore
    }
  }

  static Future<void> clear({String username = ''}) async {
    try {
      await _storage.delete(key: _keyFor(username));
    } catch (_) {
      // ignore
    }
  }
}
