import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/geo/coordinate_utils.dart';

void main() {
  test('上海 WGS84 转 GCJ02 后有偏移', () {
    final (lat, lng) = CoordinateUtils.wgs84ToGcj02(31.2304, 121.4737);
    expect(lat, closeTo(31.2285, 0.003));
    expect(lng, closeTo(121.4754, 0.003));
  });

  test('境外坐标不转换', () {
    final (lat, lng) = CoordinateUtils.wgs84ToGcj02(48.8566, 2.3522);
    expect(lat, 48.8566);
    expect(lng, 2.3522);
  });

  test('GCJ02 转回 WGS84 接近原坐标', () {
    const lat = 31.2304;
    const lng = 121.4737;
    final (gcjLat, gcjLng) = CoordinateUtils.wgs84ToGcj02(lat, lng);
    final (backLat, backLng) = CoordinateUtils.gcj02ToWgs84(gcjLat, gcjLng);
    expect(backLat, closeTo(lat, 0.0001));
    expect(backLng, closeTo(lng, 0.0001));
  });
}
