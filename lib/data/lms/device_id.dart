import 'dart:math';

import '../cache_store.dart';

/// 一网畅学签到要带的设备号。
///
/// 服务端用它做「同一条签到，一台设备只能签一个账号」的校验，所以必须是
/// **本机稳定**的随机串：第一次生成后加密存起来，之后一直复用。
/// 不要用 ANDROID_ID / IMEI 这类系统标识——既拿不到，也没必要。
///
/// 格式对齐 USST 参考实现（usst-jwgl-client）：标准 UUID v4
/// （`xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`）。旧版本存的 32 位十六进制串
/// 会在下次读取时自动迁移成 UUID，避免服务端按 UUID 校验时出问题。
class TronDeviceId {
  TronDeviceId._();

  static const String _key = 'tronclass_device_id_v1';

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  static String? _cached;

  static Future<String> get() async {
    final cached = _cached;
    if (cached != null && _uuidPattern.hasMatch(cached)) {
      return cached;
    }
    final entry = await CacheStore.read(_key, secure: true);
    final saved = entry?.data;
    if (saved is String && _uuidPattern.hasMatch(saved)) {
      _cached = saved;
      return saved;
    }
    final id = _randomUuid();
    _cached = id;
    await CacheStore.write(_key, id, secure: true);
    return id;
  }

  /// 生成 UUID v4。
  static String _randomUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    // version = 4，variant = RFC 4122。
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
