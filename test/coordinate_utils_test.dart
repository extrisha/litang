import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/geo/campus_buildings.dart';
import 'package:project_usst/data/geo/coordinate_utils.dart';

void main() {
  // 公开的 GCJ-02 参考向量（eviltransform / 高德系实现通用测试集）。
  const wgsLat = 31.1774276;
  const wgsLng = 121.5272106;
  const gcjLat = 31.17530398364597;
  const gcjLng = 121.531541859215;

  test('WGS84 转 GCJ02 命中标准参考向量', () {
    final (lat, lng) = CoordinateUtils.wgs84ToGcj02(wgsLat, wgsLng);
    expect(lat, closeTo(gcjLat, 1e-6));
    expect(lng, closeTo(gcjLng, 1e-6));
  });

  test('transformDelta 的 x/y 不能写反（写反会偏约 390 米）', () {
    final (lat, lng) = CoordinateUtils.wgs84ToGcj02(
      31.291731,
      121.556084,
    );
    // 一教东这一带 GCJ-02 相对 WGS-84 是「南偏东」约 400 米；
    // 参数写反会变成「北偏西」，正好对上之前雷达签到判超范围的现象。
    expect(lat, lessThan(31.291731));
    expect(lng, greaterThan(121.556084));
    final distance = CoordinateUtils.distanceMeters(
      31.291731,
      121.556084,
      lat,
      lng,
    );
    expect(distance, greaterThan(300));
    expect(distance, lessThan(600));
  });

  test('境外坐标不转换', () {
    final (lat, lng) = CoordinateUtils.wgs84ToGcj02(48.8566, 2.3522);
    expect(lat, 48.8566);
    expect(lng, 2.3522);
  });

  test('GCJ02 转回 WGS84 误差在米级', () {
    final (backLat, backLng) = CoordinateUtils.gcj02ToWgs84(gcjLat, gcjLng);
    final error = CoordinateUtils.distanceMeters(
      wgsLat,
      wgsLng,
      backLat,
      backLng,
    );
    // 参考实现直接减去偏移量、不迭代反解，误差在几米内属正常。
    expect(error, lessThan(10));
  });

  test('两点距离：同点为 0，一教东到三教约 350 米', () {
    expect(CoordinateUtils.distanceMeters(31.29, 121.55, 31.29, 121.55), 0);
    final building = kUsstBuildings.firstWhere((b) => b.id == 'b_516_1j_e');
    final sanjiao = kUsstBuildings.firstWhere((b) => b.id == 'b_516_3j_e');
    final distance = CoordinateUtils.distanceMeters(
      building.latitude,
      building.longitude,
      sanjiao.latitude,
      sanjiao.longitude,
    );
    expect(distance, greaterThan(250));
    expect(distance, lessThan(500));
  });

  group('findMatchingBuilding（照抄参考实现）', () {
    test('教室名直接命中', () {
      expect(findMatchingBuilding('三教101')?.id, 'b_516_3j_e');
      expect(findMatchingBuilding('第四教学楼 205')?.id, 'b_516_4j_w');
      expect(findMatchingBuilding('综合楼B区305')?.id, 'b_516_zh_b');
    });

    test('长名优先，580 体育馆不会命中 1100 体育馆', () {
      expect(findMatchingBuilding('580体育活动中心')?.id, 'b_516_580_ty');
      expect(findMatchingBuilding('1100体育馆')?.id, 'b_1100_jt');
    });

    test('一教按东西和门牌号分流', () {
      expect(findMatchingBuilding('一教西101')?.id, 'b_516_1j_w');
      expect(findMatchingBuilding('一教东101')?.id, 'b_516_1j_e');
      expect(findMatchingBuilding('一教 101')?.id, 'b_516_1j_e');
      // 门牌号取后两位：25 及以内算东侧，26 以上算西侧。
      expect(findMatchingBuilding('一教 130')?.id, 'b_516_1j_w');
      expect(findMatchingBuilding('一教 226')?.id, 'b_516_1j_w');
    });

    test('认不出来的返回 null', () {
      expect(findMatchingBuilding('线上腾讯会议'), isNull);
      expect(findMatchingBuilding(''), isNull);
      expect(findMatchingBuilding(null), isNull);
    });
  });

  test('findNearestBuildingFromWgs84 能吸附到正确教学楼', () {
    // 一教东基准点的 WGS-84 反算值附近，应吸回一教东。
    final (wgsLat2, wgsLng2) = CoordinateUtils.gcj02ToWgs84(
      31.291731,
      121.556084,
    );
    final (nearest, distance) = findNearestBuildingFromWgs84(wgsLat2, wgsLng2);
    expect(nearest.id, 'b_516_1j_e');
    expect(distance, lessThan(5));
  });
}
