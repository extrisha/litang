import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/geo/campus_buildings.dart';
import 'package:project_usst/data/geo/coordinate_utils.dart';
import 'package:project_usst/data/lms/radar_target.dart';
import 'package:project_usst/data/lms/rollcall_api.dart';

Rollcall _rollcall({
  String courseName = '高等数学',
  String? classroom,
  double? latitude,
  double? longitude,
  double? scope,
}) => Rollcall(
  id: '123',
  courseName: courseName,
  type: 'radar',
  timeText: '08:00',
  isRadar: true,
  classroom: classroom,
  latitude: latitude,
  longitude: longitude,
  scope: scope,
);

void main() {
  group('resolveRadarTarget', () {
    test('有教师基准点时优先用它，精度 5m', () {
      final target = resolveRadarTarget(
        rollcall: _rollcall(
          classroom: '三教101',
          latitude: 31.294512,
          longitude: 121.555612,
          scope: 50,
        ),
        random: Random(1),
      );

      expect(target, isNotNull);
      expect(target!.source, RadarTargetSource.teacher);
      expect(target.accuracy, kRadarTeacherAccuracy);
      // 只叠加 ±1.5m 级别的扰动，不会跑出教室。
      expect(target.latitude, closeTo(31.294512, 0.00002));
      expect(target.longitude, closeTo(121.555612, 0.00002));
      expect(target.label, contains('教师基准点'));
      expect(target.label, contains('50'));
    });

    test('无教师基准点时用教室匹配的教学楼基准点，精度 15m', () {
      final target = resolveRadarTarget(
        rollcall: _rollcall(classroom: '三教101'),
        random: Random(2),
      );
      final building = kUsstBuildings.firstWhere((b) => b.id == 'b_516_3j_e');

      expect(target!.source, RadarTargetSource.building);
      expect(target.accuracy, kRadarBuildingAccuracy);
      expect(target.latitude, building.latitude);
      expect(target.longitude, building.longitude);
      expect(target.label, contains('三教'));
    });

    test('教室名没写楼时用课程名兜底', () {
      final target = resolveRadarTarget(
        rollcall: _rollcall(courseName: '大学物理（四教）', classroom: 'A301'),
      );
      expect(target!.source, RadarTargetSource.building);
      expect(target.label, contains('四教'));
    });

    test('教师基准点为 0,0 视为没下发', () {
      final target = resolveRadarTarget(
        rollcall: _rollcall(
          classroom: '卓越楼201',
          latitude: 0,
          longitude: 0,
        ),
      );
      expect(target!.source, RadarTargetSource.building);
      expect(target.label, contains('卓越楼'));
    });

    test('什么都匹配不到时吸附设备定位 800m 内最近教学楼', () {
      final (wgsLat, wgsLng) = CoordinateUtils.gcj02ToWgs84(
        31.286636,
        121.557302,
      );
      final target = resolveRadarTarget(
        rollcall: _rollcall(courseName: '线上课', classroom: '腾讯会议'),
        devicePosition: DeviceLocation(
          latitude: wgsLat,
          longitude: wgsLng,
          accuracy: 40,
        ),
      );

      expect(target!.source, RadarTargetSource.building);
      expect(target.label, contains('四教'));
      expect(target.label, contains('吸附'));
    });

    test('设备定位离校区很远时上报真实定位（WGS-84 转 GCJ-02）', () {
      final target = resolveRadarTarget(
        rollcall: _rollcall(courseName: '线上课', classroom: '腾讯会议'),
        devicePosition: const DeviceLocation(
          latitude: 39.908692,
          longitude: 116.397477,
          accuracy: 30,
        ),
      );

      expect(target!.source, RadarTargetSource.device);
      expect(target.accuracy, 30);
      expect(target.latitude, closeTo(39.910096, 1e-5));
      expect(target.longitude, closeTo(116.403721, 1e-5));
    });

    test('没有设备定位又匹配不到教学楼时返回 null', () {
      final target = resolveRadarTarget(
        rollcall: _rollcall(courseName: '线上课', classroom: '腾讯会议'),
      );
      expect(target, isNull);
    });
  });

  test('教师基准点扰动幅度不超过 ±1.5m', () {
    final baseLat = 31.294512;
    final baseLng = 121.555612;
    for (var seed = 0; seed < 50; seed++) {
      final target = resolveRadarTarget(
        rollcall: _rollcall(latitude: baseLat, longitude: baseLng),
        random: Random(seed),
      )!;
      final distance = CoordinateUtils.distanceMeters(
        baseLat,
        baseLng,
        target.latitude,
        target.longitude,
      );
      expect(distance, lessThan(3));
    }
  });

  group('内部模式的四种取点方式', () {
    // 北京天安门：离上理远得很，不会被吸附到教学楼
    const farAway = DeviceLocation(
      latitude: 39.908692,
      longitude: 116.397477,
      accuracy: 25,
    );

    test('device：只用本机定位，教师点和教学楼都不参与', () {
      final target = resolveRadarTarget(
        rollcall: _rollcall(
          classroom: '三教101',
          latitude: 31.294512,
          longitude: 121.555612,
        ),
        mode: RadarLocationMode.device,
        devicePosition: farAway,
      )!;
      expect(target.source, RadarTargetSource.device);
      expect(target.accuracy, 25);
      expect(target.latitude, closeTo(39.910096, 1e-5));
      expect(target.label, '本机定位');
    });

    test('device：没有定位就返回 null，不偷偷用教学楼', () {
      final target = resolveRadarTarget(
        rollcall: _rollcall(classroom: '三教101'),
        mode: RadarLocationMode.device,
      );
      expect(target, isNull);
    });

    test('teacher：没有教师点就返回 null', () {
      final target = resolveRadarTarget(
        rollcall: _rollcall(classroom: '三教101'),
        mode: RadarLocationMode.teacher,
        devicePosition: farAway,
      );
      expect(target, isNull);
    });

    test('teacher：有教师点时优先于本机定位', () {
      final target = resolveRadarTarget(
        rollcall: _rollcall(latitude: 31.294512, longitude: 121.555612),
        mode: RadarLocationMode.teacher,
        devicePosition: farAway,
        random: Random(3),
      )!;
      expect(target.source, RadarTargetSource.teacher);
      expect(target.accuracy, kRadarTeacherAccuracy);
    });

    test('building：锁定教学楼优先于教室名匹配', () {
      final target = resolveRadarTarget(
        rollcall: _rollcall(classroom: '三教101'),
        mode: RadarLocationMode.building,
        preferredBuildingId: 'b_516_4j_w',
      )!;
      expect(target.source, RadarTargetSource.building);
      expect(target.label, contains('四教'));
      expect(target.accuracy, kRadarBuildingAccuracy);
    });

    test('building：没锁定时按教室名匹配', () {
      final target = resolveRadarTarget(
        rollcall: _rollcall(classroom: '综合楼C区201'),
        mode: RadarLocationMode.building,
      )!;
      expect(target.label, contains('综合楼C区'));
    });

    test('building：匹配不到就返回 null，不回退定位', () {
      final target = resolveRadarTarget(
        rollcall: _rollcall(courseName: '线上课', classroom: '腾讯会议'),
        mode: RadarLocationMode.building,
        devicePosition: farAway,
      );
      expect(target, isNull);
    });
  });
}
