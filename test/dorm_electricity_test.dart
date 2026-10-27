import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/services/dorm_electricity_service.dart';

void main() {
  group('DormElectricity.fromJson', () {
    test('解析照明和空调两路余量', () {
      final info = DormElectricity.fromJson(<String, dynamic>{
        'SSDZ': '二公寓三号楼237 室',
        'SurplusZM': '29.52 度',
        'SurplusZMMoney': '18.77 元',
        'SurplusKT': '26.47 度',
        'SurplusKTMoney': '16.83 元',
        'HasKT': true,
      });

      expect(info.dormAddress, '二公寓三号楼237 室');
      expect(info.zmKwh, '29.52 度');
      expect(info.zmMoney, '18.77 元');
      expect(info.ktKwh, '26.47 度');
      expect(info.ktMoney, '16.83 元');
      expect(info.hasAirConditioner, isTrue);
      expect(info.zmMoneyValue, 18.77);
      expect(info.ktMoneyValue, 16.83);
      expect(info.zmInArrears, isFalse);
    });

    test('负余额识别为欠费', () {
      final info = DormElectricity.fromJson(<String, dynamic>{
        'SSDZ': '二公寓三号楼237 室',
        'SurplusZM': '-1.47 度',
        'SurplusZMMoney': '-0.93 元',
        'SurplusKT': '26.47 度',
        'SurplusKTMoney': '16.83 元',
        'HasKT': false,
      });

      expect(info.zmMoneyValue, -0.93);
      expect(info.zmInArrears, isTrue);
      expect(info.hasAirConditioner, isFalse);
    });

    test('字段缺失时不抛异常', () {
      final info = DormElectricity.fromJson(<String, dynamic>{});
      expect(info.dormAddress, isEmpty);
      expect(info.zmMoneyValue, isNull);
      expect(info.zmInArrears, isFalse);
      expect(info.hasAirConditioner, isFalse);
    });
  });

  group('DormElectricityCache', () {
    tearDown(DormElectricityCache.clear);

    test('按学号缓存，换账号不串数据', () {
      final info = DormElectricity.fromJson(<String, dynamic>{
        'SSDZ': '二公寓三号楼237 室',
        'SurplusZM': '10 度',
        'SurplusZMMoney': '5 元',
      });
      DormElectricityCache.put('2535055309', info);

      expect(DormElectricityCache.dataFor('2535055309'), same(info));
      expect(DormElectricityCache.dataFor('other'), isNull);
      expect(DormElectricityCache.ageFor('2535055309'), isNotNull);
    });

    test('clear 清空缓存', () {
      final info = DormElectricity.fromJson(<String, dynamic>{});
      DormElectricityCache.put('u', info);
      DormElectricityCache.clear();
      expect(DormElectricityCache.dataFor('u'), isNull);
      expect(DormElectricityCache.ageFor('u'), isNull);
    });
  });
}
