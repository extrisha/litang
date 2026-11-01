import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/cache_store.dart';

void main() {
  group('CacheEntry', () {
    test('TTL 判断', () {
      final fresh = CacheEntry(data: 1, savedAt: DateTime.now());
      expect(fresh.isFresh(const Duration(minutes: 5)), isTrue);
      expect(fresh.isStale(const Duration(minutes: 5)), isFalse);

      final old = CacheEntry(
        data: 1,
        savedAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(old.isFresh(const Duration(hours: 1)), isFalse);
      expect(old.isStale(const Duration(hours: 1)), isTrue);
    });
  });

  group('CacheStore 序列化', () {
    test('新格式带时间戳', () {
      final savedAt = DateTime(2026, 10, 25, 12, 30);
      final entry = CacheStore.decode(
        CacheStore.encode(<String, dynamic>{'a': 1}, savedAt),
      );
      expect(entry, isNotNull);
      expect(entry!.savedAt, savedAt);
      expect((entry.data as Map)['a'], 1);
    });

    test('旧格式（整个 JSON 就是数据）也能读，但一定算过期', () {
      final entry = CacheStore.decode('[{"id":"1","name":"高等数学"}]');
      expect(entry, isNotNull);
      expect(entry!.data, isA<List<dynamic>>());
      expect(entry.isFresh(const Duration(days: 3650)), isFalse);
    });

    test('坏数据返回 null 而不是抛异常', () {
      expect(CacheStore.decode('not json'), isNull);
      expect(CacheStore.decode(''), isNull);
    });
  });

  group('CacheStore 文件后端', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('litang_cache_test');
      CacheStore.directoryOverride = () async => tempDir;
      CacheStore.clearMemory();
    });

    tearDown(() async {
      CacheStore.directoryOverride = null;
      CacheStore.clearMemory();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('写入后清掉内存也能从磁盘读回', () async {
      await CacheStore.write('demo_key', <String, dynamic>{'x': 2});

      CacheStore.clearMemory();
      final entry = await CacheStore.read('demo_key');

      expect(entry, isNotNull);
      expect((entry!.data as Map)['x'], 2);
      expect(entry.isFresh(const Duration(minutes: 1)), isTrue);
    });

    test('删除后读不到', () async {
      await CacheStore.write('gone', <String>['a']);
      await CacheStore.remove('gone');
      CacheStore.clearMemory();
      expect(await CacheStore.read('gone'), isNull);
    });

    test('没写过的 key 返回 null', () async {
      expect(await CacheStore.read('never'), isNull);
    });

    test('LRU 内存容量限制生效，超出时淘汰最久未访问条目', () async {
      final oldLimit = CacheStore.maxMemoryEntries;
      CacheStore.maxMemoryEntries = 2;
      CacheStore.clearMemory();
      try {
        await CacheStore.write('k1', 'val1');
        await CacheStore.write('k2', 'val2');
        // 访问 k1 使其变为最近使用
        await CacheStore.read('k1');
        // 写入 k3，容量为 2 时应淘汰 k2
        await CacheStore.write('k3', 'val3');

        // 删除磁盘上的 k2 文件，以验证其是否已从内存驱逐
        final dir = tempDir;
        final fileK2 = File('${dir.path}/cache/k2.json');
        if (await fileK2.exists()) {
          await fileK2.delete();
        }
        // 因为 k2 已被内存淘汰且磁盘文件被删，应该读不到
        expect(await CacheStore.read('k2'), isNull);

        // 而 k1 仍在内存中（即使删除磁盘文件也能读到）
        final fileK1 = File('${dir.path}/cache/k1.json');
        if (await fileK1.exists()) {
          await fileK1.delete();
        }
        final entryK1 = await CacheStore.read('k1');
        expect(entryK1?.data, 'val1');
      } finally {
        CacheStore.maxMemoryEntries = oldLimit;
        CacheStore.clearMemory();
      }
    });
  });
}
