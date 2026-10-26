import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/campus_places.dart';
import 'package:project_usst/data/place_search.dart';

void main() {
  test('官方地图地点数据', () {
    expect(kCampusPlaces.length, greaterThan(80));
    expect(kCampusPlaces.any((p) => p.name.contains('第一教学楼')), isTrue);
    for (final p in kCampusPlaces) {
      expect(p.anchor.dx, inInclusiveRange(0, 1));
      expect(p.anchor.dy, inInclusiveRange(0, 1));
    }
  });

  test('搜索地点', () {
    expect(searchCampusPlaces('第一教学楼').isNotEmpty, isTrue);
    expect(searchCampusPlaces(''), isEmpty);
    expect(searchCampusPlaces('不存在的地方'), isEmpty);
  });

  test('教室名解析到楼栋', () {
    expect(placeForRoom('三教106')?.name.contains('第三教学楼'), isTrue);
    expect(placeForRoom('一教146')?.name.contains('第一教学楼'), isTrue);
    expect(placeForRoom(''), isNull);
  });

  test('楼名别名归一化', () {
    expect(placeForRoom('卓越工程大楼118')?.name.contains('卓越楼'), isTrue);
    expect(placeForRoom('综合A101')?.name.contains('综合楼'), isTrue);
    expect(placeForRoom('二公三')?.name.contains('第二学生公寓三号楼'), isTrue);
    expect(searchCampusPlaces('一教').first.name, contains('第一教学楼'));
    expect(searchCampusPlaces('二公三').first.name, contains('第二学生公寓三号楼'));
  });

  test('真实教务课表里的教室名', () {
    // 取自 2026-2027-1 实际课表
    expect(placeForRoom('一教146')?.name, '第一教学楼');
    expect(placeForRoom('三教317')?.name, '第三教学楼');
    expect(placeForRoom('三教106')?.name, '第三教学楼');
    expect(placeForRoom('综合楼B区201')?.name, '综合楼');
    expect(placeForRoom('卓越楼334')?.name, '卓越楼');
    expect(placeForRoom('国合楼204')?.name, contains('国合楼'));
    expect(placeForRoom('工程实训中心')?.name, '工程实训中心');
    // 教务的占位值不能被当成楼栋
    expect(placeForRoom('未排地点'), isNull);
  });

  test('公共实验楼 = 系统楼（公共实验中心）', () {
    // 教务课表写「公共实验楼」，地图上叫「系统楼（公共实验中心）」
    expect(placeForRoom('公共实验楼100室')?.name, '系统楼（公共实验中心）');
    expect(placeForRoom('公共实验楼4楼')?.name, '系统楼（公共实验中心）');
  });
}
