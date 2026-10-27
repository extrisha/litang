import 'dart:math';

import '../cache_store.dart';

/// 一网畅学签到要带的设备号。
///
/// 服务端用它做「同一条签到，一台设备只能签一个账号」的校验，所以必须是
/// **本机稳定**的随机串：第一次生成后加密存起来，之后一直复用。
/// 不要用 ANDROID_ID / IMEI 这类系统标识——既拿不到，也没必要。
class TronDeviceId {
  TronDeviceId._();

  static const String _key = 'tronclass_device_id_v1';

  static String? _cached;

  static Future<String> get() async {
    final cached = _cached;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final entry = await CacheStore.read(_key, secure: true);
    final saved = entry?.data;
    if (saved is String && saved.isNotEmpty) {
      _cached = saved;
      return saved;
    }
    final id = _randomHex(32);
    _cached = id;
    await CacheStore.write(_key, id, secure: true);
    return id;
  }

  static String _randomHex(int length) {
    const alphabet = '0123456789abcdef';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }
}
