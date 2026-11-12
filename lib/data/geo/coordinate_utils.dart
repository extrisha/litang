import 'dart:math' as math;

/// WGS-84（系统 GPS 原始坐标）与 GCJ-02（国内火星坐标系）互转工具。
///
/// 一网畅学（TronClass）雷达签到按 USST 参考实现（usst-jwgl-client 的
/// `CoordinateUtils.kt`）要求 GCJ-02：系统定位拿到 WGS-84 后必须先
/// [wgs84ToGcj02] 再上报。
///
/// 注意 `transformDelta` 的入参顺序是 `(x = 经度 - 105, y = 纬度 - 35)`，
/// 两个参数在公式里不对称，写反会让结果偏出约 390 米，雷达签到直接判超范围。
class CoordinateUtils {
  CoordinateUtils._();

  static const double earthRadius = 6378137.0;
  static const double _ee = 0.006693421622965943;

  /// 判断坐标是否在中国境外（境外不做 GCJ-02 偏移）。
  static bool isOutOfChina(double latitude, double longitude) {
    return longitude < 72.004 ||
        longitude > 137.8347 ||
        latitude < 0.8293 ||
        latitude > 55.8271;
  }

  static (double latitude, double longitude) wgs84ToGcj02(
    double latitude,
    double longitude,
  ) {
    if (isOutOfChina(latitude, longitude)) {
      return (latitude, longitude);
    }
    final (dLat, dLng) = _delta(longitude - 105.0, latitude - 35.0);
    final radLat = latitude / 180.0 * math.pi;
    var magic = math.sin(radLat);
    magic = 1.0 - _ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    final deltaLat =
        (dLat * 180.0) /
        ((earthRadius * (1.0 - _ee)) / (magic * sqrtMagic) * math.pi);
    final deltaLng =
        (dLng * 180.0) /
        (earthRadius / sqrtMagic * math.cos(radLat) * math.pi);
    return (latitude + deltaLat, longitude + deltaLng);
  }

  static (double latitude, double longitude) gcj02ToWgs84(
    double latitude,
    double longitude,
  ) {
    if (isOutOfChina(latitude, longitude)) {
      return (latitude, longitude);
    }
    final (dLat, dLng) = _delta(longitude - 105.0, latitude - 35.0);
    final radLat = latitude / 180.0 * math.pi;
    var magic = math.sin(radLat);
    magic = 1.0 - _ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    final deltaLat =
        (dLat * 180.0) /
        ((earthRadius * (1.0 - _ee)) / (magic * sqrtMagic) * math.pi);
    final deltaLng =
        (dLng * 180.0) /
        (earthRadius / sqrtMagic * math.cos(radLat) * math.pi);
    return (latitude - deltaLat, longitude - deltaLng);
  }

  /// 两点球面距离（米），Haversine。
  static double distanceMeters(
    double latitudeA,
    double longitudeA,
    double latitudeB,
    double longitudeB,
  ) {
    final radLatA = latitudeA * math.pi / 180.0;
    final radLatB = latitudeB * math.pi / 180.0;
    final a = radLatA - radLatB;
    final b = (longitudeA - longitudeB) * math.pi / 180.0;
    final s =
        2 *
        math.asin(
          math.sqrt(
            math.pow(math.sin(a / 2), 2) +
                math.cos(radLatA) *
                    math.cos(radLatB) *
                    math.pow(math.sin(b / 2), 2),
          ),
        );
    return s * earthRadius;
  }

  /// 参考实现里的 `transformDelta(x, y)`：x 是经度差、y 是纬度差。
  static (double dLat, double dLng) _delta(double x, double y) {
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
