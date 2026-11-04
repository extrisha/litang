import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'cache_store.dart';

/// 一条标定记录：站在某个位置时，系统定位给出的坐标 vs 用户在地图上指的真实位置。
class MapCalibrationSample {
  const MapCalibrationSample({
    required this.gpsLat,
    required this.gpsLng,
    required this.mapLat,
    required this.mapLng,
    required this.accuracy,
    required this.savedAt,
  });

  final double gpsLat;
  final double gpsLng;
  final double mapLat;
  final double mapLng;

  /// 采样时系统上报的精度（米），用于加权。
  final double accuracy;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'gpsLat': gpsLat,
    'gpsLng': gpsLng,
    'mapLat': mapLat,
    'mapLng': mapLng,
    'accuracy': accuracy,
    'savedAt': savedAt.toIso8601String(),
  };

  static MapCalibrationSample? fromJson(Map<String, dynamic> json) {
    final gpsLat = (json['gpsLat'] as num?)?.toDouble();
    final gpsLng = (json['gpsLng'] as num?)?.toDouble();
    final mapLat = (json['mapLat'] as num?)?.toDouble();
    final mapLng = (json['mapLng'] as num?)?.toDouble();
    if (gpsLat == null || gpsLng == null || mapLat == null || mapLng == null) {
      return null;
    }
    return MapCalibrationSample(
      gpsLat: gpsLat,
      gpsLng: gpsLng,
      mapLat: mapLat,
      mapLng: mapLng,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 20,
      savedAt:
          DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// 地图定位偏移标定。
///
/// 示意图本身和真实经纬度有 10~30 m 的局部偏差，纯 GPS 再好也补不回来。
/// 让用户站在一个确定的位置、长按地图指出自己在哪，就能量出这块地的偏差，
/// 之后所有定位点都加上这个偏移。多个点的偏移按精度加权平均。
class MapCalibration {
  MapCalibration._();

  static const String _key = 'map.calibration.v1';
  static const double _mPerDegLat = 110540;
  static const double _mPerDegLng = 95124.9;

  static List<MapCalibrationSample> _samples = <MapCalibrationSample>[];

  static List<MapCalibrationSample> get samples => List.unmodifiable(_samples);
  static bool get active => _samples.isNotEmpty;
  static int get count => _samples.length;

  static Future<void> load() async {
    final entry = await CacheStore.read(_key);
    final raw = entry?.data;
    if (raw is! List) {
      _samples = <MapCalibrationSample>[];
      return;
    }
    _samples = raw
        .whereType<Map>()
        .map((e) => MapCalibrationSample.fromJson(Map<String, dynamic>.from(e)))
        .whereType<MapCalibrationSample>()
        .toList();
  }

  static Future<void> add(MapCalibrationSample sample) async {
    _samples = <MapCalibrationSample>[..._samples, sample];
    await _save();
  }

  /// 删除单个标定点（有些位置吸不准，需要单独剔除）。
  static Future<void> removeAt(int index) async {
    if (index < 0 || index >= _samples.length) return;
    _samples = <MapCalibrationSample>[..._samples]..removeAt(index);
    await _save();
  }

  /// 单个标定点的偏移（米）：东向、北向。
  static (double east, double north) offsetOf(MapCalibrationSample sample) => (
    (sample.mapLng - sample.gpsLng) * _mPerDegLng,
    (sample.mapLat - sample.gpsLat) * _mPerDegLat,
  );

  static Future<void> clear() async {
    _samples = <MapCalibrationSample>[];
    await CacheStore.remove(_key);
  }

  static Future<void> _save() async {
    await CacheStore.write(_key, _samples.map((s) => s.toJson()).toList());
  }

  /// 当前的平均偏移（米）：东向、北向。
  static (double east, double north) get offsetMeters {
    if (_samples.isEmpty) return (0, 0);
    var weightSum = 0.0;
    var east = 0.0;
    var north = 0.0;
    for (final s in _samples) {
      final w = 1.0 / math.pow(math.max(s.accuracy, 3.0), 2);
      weightSum += w;
      east += (s.mapLng - s.gpsLng) * _mPerDegLng * w;
      north += (s.mapLat - s.gpsLat) * _mPerDegLat * w;
    }
    return (east / weightSum, north / weightSum);
  }

  /// 把系统定位点加上标定偏移。
  static LatLng apply(LatLng gps) {
    if (_samples.isEmpty) return gps;
    final (east, north) = offsetMeters;
    return LatLng(
      gps.latitude + north / _mPerDegLat,
      gps.longitude + east / _mPerDegLng,
    );
  }

  /// 供诊断页展示。
  static String describe() {
    if (_samples.isEmpty) return '未校准';
    final (east, north) = offsetMeters;
    final dir = _bearing(east, north);
    return '${_samples.length} 个标定点，偏移 东${east.toStringAsFixed(1)} m / '
        '北${north.toStringAsFixed(1)} m（约 ${math.sqrt(east * east + north * north).toStringAsFixed(1)} m 朝 $dir）';
  }

  static String _bearing(double east, double north) {
    final deg = (math.atan2(east, north) * 180 / math.pi + 360) % 360;
    const names = <String>['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    return names[((deg + 22.5) ~/ 45) % 8];
  }

  // 便于测试与调试的序列化
  static String encodeDebug() =>
      jsonEncode(_samples.map((s) => s.toJson()).toList());

  /// 导出成可粘贴的文本，用于把实测控制点回传给开发方，改进全局配准。
  static String exportForSurvey() {
    if (_samples.isEmpty) return '（还没有标定点）';
    final (east, north) = offsetMeters;
    final buffer = StringBuffer()
      ..writeln('【校园地图标定点】共 ${_samples.length} 个')
      ..writeln(
        '平均偏移：东 ${east.toStringAsFixed(1)} m / 北 ${north.toStringAsFixed(1)} m',
      )
      ..writeln('gps_lat,gps_lng,map_lat,map_lng,accuracy');
    for (final s in _samples) {
      buffer.writeln(
        '${s.gpsLat.toStringAsFixed(7)},${s.gpsLng.toStringAsFixed(7)},'
        '${s.mapLat.toStringAsFixed(7)},${s.mapLng.toStringAsFixed(7)},'
        '${s.accuracy.toStringAsFixed(1)}',
      );
    }
    return buffer.toString();
  }
}
