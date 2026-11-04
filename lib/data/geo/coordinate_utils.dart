import 'dart:math' as math;

/// WGS-84（系统 GPS 原始坐标）与 GCJ-02（国内火星坐标系）互转工具。
///
/// 一网畅学（TronClass）雷达签到按 USST 参考实现（usst-jwgl-client）
/// 要求 GCJ-02：系统定位拿到 WGS-84 后必须先 [wgs84ToGcj02] 再上报。
/// 参考项目的教学楼基准坐标也全部是 GCJ-02。
class CoordinateUtils {
  CoordinateUtils._();

  static const double _earthRadius = 6378137.0;
  static const double _ee = 0.006693421622965943;

  static (double latitude, double longitude) wgs84ToGcj02(
    double latitude,
    double longitude,
  ) {
    if (_outOfChina(latitude, longitude)) {
      return (latitude, longitude);
    }
    final (dLat, dLng) = _delta(latitude - 35.0, longitude - 105.0);
    final radLat = latitude / 180.0 * math.pi;
    var magic = math.sin(radLat);
    magic = 1.0 - _ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    final deltaLat =
        (dLat * 180.0) /
        ((_earthRadius * (1.0 - _ee)) / (magic * sqrtMagic) * math.pi);
    final deltaLng =
        (dLng * 180.0) /
        (_earthRadius / sqrtMagic * math.cos(radLat) * math.pi);
    return (latitude + deltaLat, longitude + deltaLng);
  }

  static (double latitude, double longitude) gcj02ToWgs84(
    double latitude,
    double longitude,
  ) {
    if (_outOfChina(latitude, longitude)) {
      return (latitude, longitude);
    }
    final (dLat, dLng) = _delta(latitude - 35.0, longitude - 105.0);
    final radLat = latitude / 180.0 * math.pi;
    var magic = math.sin(radLat);
    magic = 1.0 - _ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    final deltaLat =
        (dLat * 180.0) /
        ((_earthRadius * (1.0 - _ee)) / (magic * sqrtMagic) * math.pi);
    final deltaLng =
        (dLng * 180.0) /
        (_earthRadius / sqrtMagic * math.cos(radLat) * math.pi);
    return (latitude - deltaLat, longitude - deltaLng);
  }

  static bool _outOfChina(double latitude, double longitude) {
    return longitude < 72.004 ||
        longitude > 137.8347 ||
        latitude < 0.8293 ||
        latitude > 55.8271;
  }

  static (double latitude, double longitude) _delta(double x, double y) {
    final xy = x * y;
    final absX = math.sqrt(x.abs());
    final xPi = x * math.pi;
    final yPi = y * math.pi;

    var lat = 20.0 * math.sin(6.0 * xPi) + 20.0 * math.sin(2.0 * xPi);
    var lng = lat;

    lat += 20.0 * math.sin(yPi) + 40.0 * math.sin(yPi / 3.0);
    lng += 20.0 * math.sin(xPi) + 40.0 * math.sin(xPi / 3.0);

    lat += 160.0 * math.sin(yPi / 12.0) + 320.0 * math.sin(yPi / 30.0);
    lng += 150.0 * math.sin(xPi / 12.0) + 300.0 * math.sin(xPi / 30.0);

    lat *= 2.0 / 3.0;
    lng *= 2.0 / 3.0;

    lat += 2.0 * x - 100.0 + 3.0 * y + 0.2 * y * y + 0.1 * xy + 0.2 * absX;
    lng += 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * xy + 0.1 * absX;

    return (lat, lng);
  }
}
