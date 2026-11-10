import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/map_trace.dart';
import 'package:project_usst/data/map_calibration.dart';
import 'package:project_usst/widgets/campus_tile_layer.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('litang-map-test-');
    CacheStore.directoryOverride = () async => directory;
    CacheStore.clearMemory();
    await MapTraces.load();
    await MapTraces.clearDraft();
    await MapCalibration.clear();
  });
  tearDown(() async {
    CacheStore.directoryOverride = () async => directory;
    await MapTraces.load();
    await MapTraces.clearDraft();
    await MapCalibration.clear();
    CacheStore.directoryOverride = null;
    CacheStore.clearMemory();
    for (var attempt = 0; ; attempt++) {
      try {
        await directory.delete(recursive: true);
        break;
      } on FileSystemException catch (error) {
        // Windows can briefly retain a sharing lock on the now-empty test folder.
        if (!Platform.isWindows ||
            error.osError?.errorCode != 32 ||
            attempt >= 2) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      }
    }
  });

  test('草稿写入磁盘后可恢复，排队保存与清除不会使已完成草稿复活', () async {
    final trace = MapTrace(
      fromName: '',
      toName: '',
      points: const [LatLng(31.29, 121.55), LatLng(31.291, 121.551)],
      startedAt: DateTime(2026, 11, 5),
      mode: TraceMode.bike,
    );
    await MapTraces.saveDraft(trace);
    CacheStore.clearMemory();
    final restored = (await MapTraces.loadDraft())!;
    expect(restored.mode, TraceMode.bike);
    expect(restored.points, trace.points);
    expect(restored.startedAt, trace.startedAt);
    final pending = MapTraces.saveDraft(trace);
    final clear = MapTraces.clearDraft();
    await Future.wait([pending, clear]);
    CacheStore.clearMemory();
    expect(await MapTraces.loadDraft(), isNull);
  });

  MapTrace route(int offset) => MapTrace(
    fromName: '第三教学楼',
    toName: '图文信息中心',
    points: [LatLng(31.29 + offset * 0.00001, 121.55)],
    startedAt: DateTime(2026, 11, 5, 12),
    samples: [(at: DateTime.utc(2026, 11, 5, 4), accuracy: 5)],
  );

  test('新草稿保存失败时并发恢复仍取得上一份磁盘草稿', () async {
    await MapTraces.saveDraft(route(0));
    final writeGate = Completer<void>();
    var requests = 0;
    CacheStore.directoryOverride = () async {
      if (++requests == 1) {
        await writeGate.future;
        throw FileSystemException('write refused');
      }
      return directory;
    };
    final save = MapTraces.saveDraft(route(1));
    final failedSave = expectLater(save, throwsA(isA<FileSystemException>()));
    final restored = MapTraces.loadDraft();
    writeGate.complete();
    await failedSave;
    expect((await restored)!.points, route(0).points);
  });

  test('清空索引写入失败时不删除路线并保留上一份历史', () async {
    await MapTraces.add(route(0));
    var requests = 0;
    CacheStore.directoryOverride = () async {
      if (++requests == 1) throw FileSystemException('index write refused');
      return directory;
    };
    await expectLater(MapTraces.clear(), throwsA(isA<FileSystemException>()));
    expect(MapTraces.count, 1);
    CacheStore.clearMemory();
    expect((await MapTraces.exportText()).trim().split('\n'), hasLength(3));
  });

  test('清空时路线删除失败会报错，已持久化空索引不再引用残余路线', () async {
    await MapTraces.add(route(0));
    final index = (await CacheStore.read('map.traces.index.v2'))!.data as List;
    var requests = 0;
    CacheStore.directoryOverride = () async {
      if (++requests == 2) throw FileSystemException('route deletion refused');
      return directory;
    };
    await expectLater(MapTraces.clear(), throwsA(isA<FileSystemException>()));
    CacheStore.clearMemory();
    await MapTraces.load();
    expect(MapTraces.count, 0);
    expect(await MapTraces.exportText(), '（还没有路线记录）');
    expect(
      await File('${directory.path}/cache/${index[0]['key']}.json').exists(),
      isTrue,
    );
  });

  test('旧路线迁移为小索引与独立文件，相同时间但不同点的记录不会互相覆盖', () async {
    final first = route(0);
    final second = route(1);
    await CacheStore.write('map.traces.v1', [first.toJson(), second.toJson()]);
    CacheStore.clearMemory();
    await MapTraces.load();
    expect(MapTraces.count, 2);
    expect(await CacheStore.read('map.traces.v1'), isNull);
    final index = (await CacheStore.read('map.traces.index.v2'))!.data as List;
    expect(index, hasLength(2));
    expect(
      index.every((record) => !(record as Map).containsKey('points')),
      isTrue,
    );
    final exported = (await MapTraces.exportText()).trim().split('\n');
    expect(exported, hasLength(4));
    expect(jsonDecode(exported[2]), first.toJson());
    expect(jsonDecode(exported[3]), second.toJson());
    // 已迁移的启动只读取索引，不需要解码任何历史点数组。
    CacheStore.clearMemory();
    await File('${directory.path}/cache/${index[0]['key']}.json')
        .writeAsString('broken route');
    await MapTraces.load();
    expect(MapTraces.count, 2);
    await expectLater(MapTraces.exportText(), throwsStateError);
  });

  test('迁移索引写入失败保留旧档，恢复存储后可直接重试且队列继续工作', () async {
    await CacheStore.write('map.traces.v1', [route(0).toJson()]);
    final blockedIndex = Directory(
      '${directory.path}/cache/map.traces.index.v2.json',
    );
    await blockedIndex.create();
    await expectLater(MapTraces.load(), throwsA(isA<FileSystemException>()));
    expect(
      await File('${directory.path}/cache/map.traces.v1.json').exists(),
      isTrue,
    );
    await blockedIndex.delete();
    // 不清内存重试，验证失败索引不会被当作已持久化成功。
    await MapTraces.load();
    CacheStore.clearMemory();
    expect(MapTraces.count, 1);
    expect((await MapTraces.exportText()).trim().split('\n'), hasLength(3));
    expect(
      await File('${directory.path}/cache/map.traces.v1.json').exists(),
      isFalse,
    );
  });

  test('并发保存不丢索引，重复保存幂等，导出在清空前取得完整快照', () async {
    await Future.wait([MapTraces.add(route(0)), MapTraces.add(route(1))]);
    await MapTraces.add(route(0));
    CacheStore.clearMemory();
    await MapTraces.load();
    expect(MapTraces.count, 2);
    final export = MapTraces.exportText();
    final clear = MapTraces.clear();
    final exported = await export;
    await clear;
    expect(exported.trim().split('\n'), hasLength(4));
    CacheStore.clearMemory();
    await MapTraces.load();
    expect(MapTraces.count, 0);
    expect(await MapTraces.exportText(), '（还没有路线记录）');
  });

  test('新增路线仅写当前点文件，历史文件保持原内容和修改时间', () async {
    await MapTraces.add(route(0));
    final index = (await CacheStore.read('map.traces.index.v2'))!.data as List;
    final firstFile = File(
      '${directory.path}/cache/${index.first['key']}.json',
    );
    final originalBytes = await firstFile.readAsBytes();
    final modified = DateTime(2020);
    await firstFile.setLastModified(modified);
    await MapTraces.add(route(1));
    expect(await firstFile.readAsBytes(), originalBytes);
    expect(await firstFile.lastModified(), modified);
  });

  test('坏点不会破坏整个轨迹，定位质量过滤不会接受瞬移或旧点', () {
    final parsed = MapTrace.fromJson({
      'points': [
        [31.29, 121.55],
        ['bad', 4],
        [91, 0],
        [double.nan, 0],
      ],
    });
    expect(parsed!.points, hasLength(1));
    final now = DateTime(2026, 11, 5, 12);
    final sampler = TraceSampler(TraceMode.walk);
    expect(
      sampler.accept(
        const LatLng(31.29, 121.55),
        now.subtract(const Duration(seconds: 5)),
        10,
        now: now,
      ),
      isTrue,
    );
    expect(
      sampler.accept(const LatLng(31.3, 121.55), now, 10, now: now),
      isFalse,
    );
    expect(
      sampler.accept(const LatLng(31.29003, 121.55), now, 80, now: now),
      isFalse,
    );
    expect(
      sampler.accept(const LatLng(31.29003, 121.55), now, 10, now: now),
      isTrue,
    );
    expect(
      sampler.accept(const LatLng(31.29003, 121.55), now, 10, now: now),
      isFalse,
    );
  });

  test('重复位置校准替换旧测量，恢复保持一致，损坏样本不会产生 NaN', () async {
    MapCalibrationSample sample(double mapLat) => MapCalibrationSample(
      gpsLat: 31.29,
      gpsLng: 121.55,
      mapLat: mapLat,
      mapLng: 121.5501,
      accuracy: 5,
      savedAt: DateTime(2026, 11, 5),
    );
    await MapCalibration.add(sample(31.2901));
    await MapCalibration.add(sample(31.2902));
    expect(MapCalibration.count, 1);
    CacheStore.clearMemory();
    await MapCalibration.load();
    expect(
      MapCalibration.apply(const LatLng(31.29, 121.55)).latitude,
      closeTo(31.2902, 1e-8),
    );
    expect(MapCalibrationSample.fromJson({'gpsLat': 'bad'}), isNull);
    expect(
      MapCalibrationSample.fromJson({
        ...sample(31.2902).toJson(),
        'mapLng': double.infinity,
      }),
      isNull,
    );
  });

  test('标定读取与变更按序执行，磁盘写失败不改变已生效标定且允许重试', () async {
    MapCalibrationSample sample(double lat) => MapCalibrationSample(
      gpsLat: lat,
      gpsLng: 121.55,
      mapLat: lat + 0.0001,
      mapLng: 121.5501,
      accuracy: 5,
      savedAt: DateTime(2026, 11, 5),
    );
    await Future.wait([
      MapCalibration.load(),
      MapCalibration.add(sample(31.29)),
    ]);
    expect(MapCalibration.count, 1);
    CacheStore.directoryOverride = () async =>
        throw FileSystemException('disk unavailable');
    await expectLater(
      MapCalibration.add(sample(31.291)),
      throwsA(isA<FileSystemException>()),
    );
    expect(MapCalibration.count, 1);
    CacheStore.directoryOverride = () async => directory;
    CacheStore.clearMemory();
    await MapCalibration.load();
    expect(MapCalibration.count, 1);
    await MapCalibration.add(sample(31.291));
    expect(MapCalibration.count, 2);
  });

  test('局部视口仅选附近瓦片，解码尺寸随实际像素分级并封顶', () {
    final tiles = CampusTileLayer.visibleTiles(
      LatLngBounds(
        const LatLng(31.2937, 121.551),
        const LatLng(31.2943, 121.5517),
      ),
    );
    expect(tiles.length, inInclusiveRange(1, 6));
    expect(CampusTileLayer.decodeWidth(120), 256);
    expect(CampusTileLayer.decodeWidth(400), 512);
    expect(CampusTileLayer.decodeWidth(600), 1024);
    expect(CampusTileLayer.decodeWidth(3000), 1024);
  });
}
