import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/services/dorm_electricity_service.dart';

/// 电费缓存：内存 + 磁盘双层。
/// 磁盘那层是给冷启动用的——以前只存内存，重启 App 卡片就空了。
void main() {
  late Directory dir;

  const sample = DormElectricity(
    dormAddress: '二公寓三号楼237 室',
    zmKwh: '29.88 度',
    zmMoney: '19 元',
    ktKwh: '26.47 度',
    ktMoney: '16.83 元',
    hasAirConditioner: true,
  );

  setUp(() async {
    CacheStore.clearMemory();
    DormElectricityCache.resetMemoryForTest();
    dir = await Directory.systemTemp.createTemp('dorm_cache_test');
    CacheStore.directoryOverride = () async => dir;
  });

  tearDown(() async {
    CacheStore.directoryOverride = null;
    CacheStore.clearMemory();
    DormElectricityCache.resetMemoryForTest();
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Windows 上异步写入可能还没释放文件句柄，删不掉就算了
    }
  });

  test('写入后同会话内可直接读（内存层）', () async {
    DormElectricityCache.put('2535055309', sample);
    final cached = DormElectricityCache.dataFor('2535055309');
    expect(cached, isNotNull);
    expect(cached!.dormAddress, sample.dormAddress);
    expect(cached.zmInArrears, isFalse);
  });

  test('冷启动能从磁盘恢复（含写入时间）', () async {
    DormElectricityCache.put('2535055309', sample);
    // put 里的落盘是 unawaited 的，等它完成
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // 模拟重启：内存清空、磁盘保留
    DormElectricityCache.resetMemoryForTest();
    expect(DormElectricityCache.dataFor('2535055309'), isNull);

    await DormElectricityCache.load('2535055309');

    final cached = DormElectricityCache.dataFor('2535055309');
    expect(cached, isNotNull);
    expect(cached!.dormAddress, sample.dormAddress);
    expect(cached.ktMoney, sample.ktMoney);
    expect(cached.hasAirConditioner, isTrue);
    expect(DormElectricityCache.fetchedAtFor('2535055309'), isNotNull);
  });

  test('缓存按学号隔离：换账号看不到上一个人的宿舍', () async {
    DormElectricityCache.put('2535055309', sample);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    DormElectricityCache.resetMemoryForTest();

    await DormElectricityCache.load('9999999999');
    expect(DormElectricityCache.dataFor('9999999999'), isNull);
    expect(DormElectricityCache.dataFor('2535055309'), isNull);
  });

  test('内存里已有数据时，load 不会用过期的磁盘覆盖它', () async {
    DormElectricityCache.put('2535055309', sample);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    const fresh = DormElectricity(
      dormAddress: '新宿舍 101',
      zmKwh: '1 度',
      zmMoney: '1 元',
      ktKwh: '2 度',
      ktMoney: '2 元',
      hasAirConditioner: false,
    );
    DormElectricityCache.put('2535055309', fresh);

    await DormElectricityCache.load('2535055309');
    expect(DormElectricityCache.dataFor('2535055309')!.dormAddress, '新宿舍 101');
  });
}
