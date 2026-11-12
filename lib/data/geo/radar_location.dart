import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../lms/radar_target.dart' show DeviceLocation;

/// 取一次设备定位失败的原因。
enum RadarLocationFailure {
  /// 没有定位权限（用户拒绝，或这次不允许弹窗）。
  permission,

  /// 权限被永久拒绝，只能去应用设置里开。
  permissionForever,

  /// 系统定位服务（GPS 开关）没开。
  serviceDisabled,

  /// 只给了「大致位置」，雷达签到不能接受。
  reducedAccuracy,

  /// 搜星超时 / 没有可用坐标。
  unavailable,
}

/// 一次定位请求的结果（成功给坐标，失败给人话 + 该跳哪个设置页）。
@immutable
class RadarLocationResult {
  const RadarLocationResult.ok(DeviceLocation this.location)
    : failure = null,
      message = null;

  const RadarLocationResult.failed(this.failure, this.message)
    : location = null;

  final DeviceLocation? location;
  final RadarLocationFailure? failure;

  /// 可以直接展示给用户的文案。
  final String? message;

  bool get ok => location != null;
}

/// 雷达签到取坐标的唯一入口。
///
/// 把「权限 → 系统开关 → 精度 → 缓存坐标 → 实时定位 → 超时兜底」这一套
/// （以及国内 ROM 上 GMS 被冻结的坑）收在一处，页面和监控都调它，避免两套
/// 实现慢慢跑偏。
class RadarLocationService {
  RadarLocationService._();

  static final RadarLocationService instance = RadarLocationService._();

  /// 缓存坐标的可用上限。
  static const Duration freshWindow = Duration(seconds: 90);
  static const double freshAccuracy = 50;

  /// 实时定位超时后，最多退回到多久以内的历史坐标。
  static const Duration fallbackWindow = Duration(minutes: 5);
  static const double fallbackAccuracy = 100;

  /// 取一次定位。
  ///
  /// [prompt] 为 true 时（用户主动点签到）会申请权限、必要时跳系统设置；
  /// 为 false 时（后台监控）只做静默尝试，不弹任何东西。
  Future<RadarLocationResult> locate({bool prompt = true}) async {
    final permission = await _ensurePermission(prompt: prompt);
    if (permission != null) {
      return permission;
    }

    final disabled = await _checkServiceEnabled(prompt: prompt);
    if (disabled != null) {
      return disabled;
    }

    final accuracyIssue = await _checkAccuracy();
    if (accuracyIssue != null) {
      return accuracyIssue;
    }

    return _readPosition();
  }

  Future<RadarLocationResult?> _ensurePermission({required bool prompt}) async {
    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && prompt) {
        permission = await Geolocator.requestPermission();
      }
    } catch (_) {
      // 部分平台（桌面/模拟器）没有定位实现，直接当成不可用
      return const RadarLocationResult.failed(
        RadarLocationFailure.unavailable,
        '这台设备拿不到定位，雷达签到请用手机',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      if (prompt) {
        try {
          await Geolocator.openAppSettings();
        } catch (_) {
          // 打不开设置也不影响给提示
        }
      }
      return const RadarLocationResult.failed(
        RadarLocationFailure.permissionForever,
        '定位权限已被永久禁用，请在手机应用设置中允许',
      );
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return RadarLocationResult.failed(
        RadarLocationFailure.permission,
        prompt ? '雷达签到需要定位权限，请在系统设置里允许定位' : '没有定位权限，跳过设备定位',
      );
    }
    return null;
  }

  /// 系统定位开关。
  ///
  /// Android 上部分机型由于国内 ROM 冻结 GMS，`isLocationServiceEnabled()` 会抛
  /// 异常或误报 false；在 Android 上先不强行拦截，交给底层 LocationManager 判。
  Future<RadarLocationResult?> _checkServiceEnabled({
    required bool prompt,
  }) async {
    var enabled = true;
    try {
      enabled = await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      enabled = true;
    }
    if (enabled) {
      return null;
    }
    final android = defaultTargetPlatform == TargetPlatform.android;
    if (android) {
      return null;
    }
    if (prompt) {
      try {
        await Geolocator.openLocationSettings();
      } catch (_) {
        // 打不开设置也给提示
      }
    }
    return const RadarLocationResult.failed(
      RadarLocationFailure.serviceDisabled,
      '系统定位服务未开启，请打开 GPS/定位开关',
    );
  }

  Future<RadarLocationResult?> _checkAccuracy() async {
    try {
      if (await Geolocator.getLocationAccuracy() ==
          LocationAccuracyStatus.reduced) {
        return const RadarLocationResult.failed(
          RadarLocationFailure.reducedAccuracy,
          '当前只给了「大致位置」，雷达签到需要精确位置，请到系统设置里改为「精确」',
        );
      }
    } catch (_) {
      // 部分平台不支持查询精度，继续尝试定位
    }
    return null;
  }

  Future<RadarLocationResult> _readPosition() async {
    Position? last;
    try {
      last = await Geolocator.getLastKnownPosition(
        forceAndroidLocationManager: true,
      );
      if (_isFresh(last)) {
        return RadarLocationResult.ok(_toDevice(last!));
      }
    } catch (_) {
      // 忽略，继续实时定位
    }

    try {
      return RadarLocationResult.ok(
        _toDevice(await _currentPosition(LocationAccuracy.high, 20)),
      );
    } catch (_) {
      try {
        return RadarLocationResult.ok(
          _toDevice(await _currentPosition(LocationAccuracy.medium, 12)),
        );
      } catch (error) {
        // 室内搜星超时时，5 分钟内可用的历史坐标作为保底
        if (last != null && _isUsableFallback(last)) {
          return RadarLocationResult.ok(_toDevice(last));
        }
        return RadarLocationResult.failed(
          RadarLocationFailure.unavailable,
          _messageFor(error),
        );
      }
    }
  }

  Future<Position> _currentPosition(
    LocationAccuracy accuracy,
    int seconds,
  ) {
    // Android 强制走 LocationManager：部分无 GMS / 国内 ROM 的机器上
    // FusedLocationProvider 会一直不回调，最后只能超时。
    final android = defaultTargetPlatform == TargetPlatform.android;
    final settings = android
        ? AndroidSettings(
            accuracy: accuracy,
            timeLimit: Duration(seconds: seconds),
            forceLocationManager: true,
          )
        : LocationSettings(
            accuracy: accuracy,
            timeLimit: Duration(seconds: seconds),
          );
    return Geolocator.getCurrentPosition(locationSettings: settings);
  }

  DeviceLocation _toDevice(Position position) => DeviceLocation(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracy: position.accuracy,
    timestamp: position.timestamp,
  );

  bool _isFresh(Position? position) {
    if (position == null) return false;
    final age = DateTime.now().difference(position.timestamp);
    return !age.isNegative &&
        age <= freshWindow &&
        position.accuracy > 0 &&
        position.accuracy <= freshAccuracy;
  }

  bool _isUsableFallback(Position? position) {
    if (position == null) return false;
    final age = DateTime.now().difference(position.timestamp);
    return !age.isNegative &&
        age <= fallbackWindow &&
        position.accuracy > 0 &&
        position.accuracy <= fallbackAccuracy;
  }

  String _messageFor(Object error) {
    if (error is TimeoutException) {
      return '定位超时：请到室外/窗边，确认 GPS 已开启后重试';
    }
    if (error is LocationServiceDisabledException) {
      return '系统定位服务未开启，请打开 GPS/定位开关';
    }
    if (error is PermissionDeniedException) {
      return '定位权限被拒绝，请在系统设置里允许定位';
    }
    return '定位失败，请确认在室外并开启 GPS 后重试';
  }
}
