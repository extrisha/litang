import 'dart:math';

import '../geo/campus_buildings.dart';
import '../geo/coordinate_utils.dart';
import 'rollcall_api.dart';

/// 雷达签到上报点是怎么来的。
enum RadarTargetSource {
  /// 平台随点名下发的教师端实时基准点（必过通道）。
  teacher,

  /// 教学楼基准点（系统里 22 个固定点位）。
  building,

  /// 本机真实定位（WGS-84 转 GCJ-02 后上报）。
  device,
}

/// 雷达签到取点方式。
///
/// 普通用户固定用 [device]（室内 GPS）；内部模式可以切到另外三种。
enum RadarLocationMode {
  /// 自动顺序：教师基准点 → 教室匹配教学楼 → 设备定位吸附 → 设备定位。
  auto,

  /// 只用平台下发的教师基准点。
  teacher,

  /// 只用教学楼（优先 [resolveRadarTarget] 的 `preferredBuildingId`）。
  building,

  /// 只用本机定位。
  device,
}

/// 一次雷达签到要上报的坐标。
class RadarTarget {
  const RadarTarget({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.source,
    this.label = '',
  });

  /// 已换算成 GCJ-02 的纬度。
  final double latitude;

  /// 已换算成 GCJ-02 的经度。
  final double longitude;

  final double accuracy;
  final RadarTargetSource source;

  /// 给用户看的基准说明，例如「三教（本部北校区）」。
  final String label;
}

/// 教师基准点上报精度，参考实现固定 5m。
const double kRadarTeacherAccuracy = 5.0;

/// 教学楼基准点上报精度，参考实现固定 15m。
const double kRadarBuildingAccuracy = 15.0;

/// 教师基准点叠加的自然扰动幅度（±0.000015 度，约 ±1.5 米），
/// 参考实现用它避免服务端把 0 距离判成假点。
const double kRadarTeacherJitterDegrees = 0.00003;

/// 设备定位吸附到教学楼的半径，参考实现取 800 米。
const double kRadarSnapRadiusMeters = 800.0;

/// 按指定模式挑出最合适的上报点。
///
/// - [RadarLocationMode.device]：只用 [devicePosition]，没有就返回 null。
/// - [RadarLocationMode.teacher]：只用平台下发的教师基准点。
/// - [RadarLocationMode.building]：只用教学楼（[preferredBuildingId] 优先，
///   其次按教室名/课程名匹配）。
/// - [RadarLocationMode.auto]：照抄 USST 参考实现
///   `RadarRollcallBottomSheetDialog` 的顺序——教师基准点 → 教学楼 →
///   设备定位吸附 800m 内最近教学楼 → 设备定位。
///
/// 教师基准点会叠加 ±1.5m 扰动（[random] 可注入，方便单测）。
RadarTarget? resolveRadarTarget({
  required Rollcall rollcall,
  RadarLocationMode mode = RadarLocationMode.auto,
  String? preferredBuildingId,
  DeviceLocation? devicePosition,
  Random? random,
}) {
  switch (mode) {
    case RadarLocationMode.device:
      return _deviceTarget(devicePosition);
    case RadarLocationMode.teacher:
      return _teacherTarget(rollcall, random ?? Random());
    case RadarLocationMode.building:
      return _buildingTarget(rollcall, preferredBuildingId);
    case RadarLocationMode.auto:
      final teacher = _teacherTarget(rollcall, random ?? Random());
      if (teacher != null) return teacher;
      final building = _buildingTarget(rollcall, preferredBuildingId);
      if (building != null) return building;
      return _deviceTarget(devicePosition, snapToBuilding: true);
  }
}

RadarTarget? _buildingTarget(Rollcall rollcall, String? preferredBuildingId) {
  if (preferredBuildingId != null) {
    for (final building in kUsstBuildings) {
      if (building.id == preferredBuildingId) {
        return RadarTarget(
          latitude: building.latitude,
          longitude: building.longitude,
          accuracy: kRadarBuildingAccuracy,
          source: RadarTargetSource.building,
          label: '${building.name}（${building.campus}）',
        );
      }
    }
  }
  final building =
      findMatchingBuilding(rollcall.classroom) ??
      findMatchingBuilding(rollcall.courseName);
  if (building == null) return null;
  return RadarTarget(
    latitude: building.latitude,
    longitude: building.longitude,
    accuracy: kRadarBuildingAccuracy,
    source: RadarTargetSource.building,
    label: '${building.name}（${building.campus}）',
  );
}

RadarTarget? _deviceTarget(
  DeviceLocation? devicePosition, {
  bool snapToBuilding = false,
}) {
  if (devicePosition == null) return null;
  final (gcjLat, gcjLng) = CoordinateUtils.wgs84ToGcj02(
    devicePosition.latitude,
    devicePosition.longitude,
  );
  if (snapToBuilding) {
    final (nearest, distance) = findNearestBuilding(gcjLat, gcjLng);
    if (distance <= kRadarSnapRadiusMeters) {
      return RadarTarget(
        latitude: nearest.latitude,
        longitude: nearest.longitude,
        accuracy: kRadarBuildingAccuracy,
        source: RadarTargetSource.building,
        label: '${nearest.name}（${nearest.campus}，已吸附最近教学楼）',
      );
    }
  }
  final accuracy = devicePosition.accuracy;
  return RadarTarget(
    latitude: gcjLat,
    longitude: gcjLng,
    accuracy: (accuracy != null && accuracy > 0)
        ? accuracy
        : kRadarBuildingAccuracy,
    source: RadarTargetSource.device,
    label: '本机定位',
  );
}

RadarTarget? _teacherTarget(Rollcall rollcall, Random random) {
  final latitude = rollcall.latitude;
  final longitude = rollcall.longitude;
  if (latitude == null || longitude == null) {
    return null;
  }
  if (latitude == 0 && longitude == 0) {
    return null;
  }
  if (!latitude.isFinite ||
      !longitude.isFinite ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180) {
    return null;
  }
  // 平台下发的教师基准点本身就是 GCJ-02（参考实现沿用接口坐标约定），
  // 不能再做一次 WGS-84 纠偏，否则又会偏出几百米。
  final jitterLat = (random.nextDouble() - 0.5) * kRadarTeacherJitterDegrees;
  final jitterLng = (random.nextDouble() - 0.5) * kRadarTeacherJitterDegrees;
  final scopeText = rollcall.scope != null && rollcall.scope! > 0
      ? '，范围 ±${rollcall.scope!.round()}m'
      : '';
  return RadarTarget(
    latitude: latitude + jitterLat,
    longitude: longitude + jitterLng,
    accuracy: kRadarTeacherAccuracy,
    source: RadarTargetSource.teacher,
    label: '教师基准点$scopeText',
  );
}

/// 设备定位快照（避免直接依赖 geolocator 的 Position 方便单测）。
class DeviceLocation {
  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.timestamp,
  });

  /// WGS-84 纬度。
  final double latitude;

  /// WGS-84 经度。
  final double longitude;

  /// 米。
  final double? accuracy;
  final DateTime? timestamp;
}
