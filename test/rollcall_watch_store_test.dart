import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/internal/rollcall_watch_store.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('rollcall_watch_store');
    CacheStore.directoryOverride = () async => temp;
    CacheStore.clearMemory();
    await RollcallWatchStore.instance.debugReset();
  });

  tearDown(() async {
    CacheStore.directoryOverride = null;
    CacheStore.clearMemory();
    await RollcallWatchStore.instance.debugReset();
    try {
      await temp.delete(recursive: true);
    } catch (_) {
      // Windows 上偶发删不掉，测试目录留着也没关系
    }
  });

  test('没处理过的点名返回 null', () async {
    final store = RollcallWatchStore.instance;
    expect(await store.stateOf('100'), isNull);
    expect(await store.isHandled('100'), isFalse);
  });

  test('记录状态后能读回来', () async {
    final store = RollcallWatchStore.instance;
    await store.record('100', RollcallWatchState.confirmed);
    expect(await store.stateOf('100'), RollcallWatchState.confirmed);
    expect(await store.isHandled('100'), isTrue);
  });

  test('状态会落盘，重启后还在', () async {
    await RollcallWatchStore.instance.record(
      '200',
      RollcallWatchState.notified,
    );
    // 模拟进程重启：清掉内存缓存，重新从磁盘读
    CacheStore.clearMemory();
    await RollcallWatchStore.instance.debugReset();
    expect(
      await RollcallWatchStore.instance.stateOf('200'),
      RollcallWatchState.notified,
    );
  });

  test('prune 只清掉通知过的旧记录，提交过的永久保留', () async {
    final store = RollcallWatchStore.instance;
    await store.record('1', RollcallWatchState.notified);
    await store.record('2', RollcallWatchState.confirmed);
    await store.prune(<String>{'3'});
    // 1 只通知过、已不在列表 → 清掉；2 提交过 → 必须保留，避免重复提交
    expect(await store.stateOf('1'), isNull);
    expect(await store.stateOf('2'), RollcallWatchState.confirmed);
  });

  test('clear 清空所有记录', () async {
    final store = RollcallWatchStore.instance;
    await store.record('1', RollcallWatchState.notified);
    await store.clear();
    expect(await store.stateOf('1'), isNull);
  });

  test('超过上限时丢最旧的', () async {
    final store = RollcallWatchStore.instance;
    for (var i = 0; i < RollcallWatchStore.maxEntries + 5; i++) {
      await store.record('id-$i', RollcallWatchState.notified);
    }
    expect(await store.stateOf('id-0'), isNull);
    expect(await store.stateOf('id-4'), isNull);
    expect(
      await store.stateOf('id-${RollcallWatchStore.maxEntries + 4}'),
      RollcallWatchState.notified,
    );
  });
}
