import 'package:flutter/foundation.dart';

import '../cache_store.dart';

/// 本机对某个点名的处理状态。
///
/// 和参考项目 `RollcallSubmissionStore` 一个意思：一条点名只允许提交一次，
/// 失败也不自动重试，避免把服务端的出错次数烧光。
enum RollcallWatchState {
  /// 只发了通知，没有提交。
  notified,

  /// 提交了，但结果未知（网络断开 / 超时）。
  unknown,

  /// 提交成功。
  confirmed,

  /// 服务端明确拒绝（超范围、已结束等）。
  rejected,
}

/// 已处理的点名记录（按点名 id）。
class RollcallWatchStore {
  RollcallWatchStore._();

  static final RollcallWatchStore instance = RollcallWatchStore._();

  static const String storageKey = 'usst_rollcall_watch_v1';

  /// 最多记这么多条，超了丢最旧的，避免文件无限长。
  static const int maxEntries = 300;

  /// id -> (状态, 时间)。懒加载。
  Map<String, RollcallWatchState>? _states;
  Map<String, DateTime>? _times;
  Future<void>? _loading;

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final states = <String, RollcallWatchState>{};
    final times = <String, DateTime>{};
    try {
      final entry = await CacheStore.read(storageKey);
      final data = entry?.data;
      if (data is Map && data['items'] is Map) {
        (data['items'] as Map).forEach((key, value) {
          if (value is! Map) return;
          final state = _stateFromName('${value['s'] ?? ''}');
          if (state == null) return;
          states['$key'] = state;
          final at = DateTime.tryParse('${value['at'] ?? ''}');
          if (at != null) times['$key'] = at;
        });
      }
    } catch (_) {
      // 读不出来当没有记录，宁可多处理一次也不要卡住
    }
    _states = states;
    _times = times;
  }

  static RollcallWatchState? _stateFromName(String name) {
    for (final state in RollcallWatchState.values) {
      if (state.name == name) return state;
    }
    return null;
  }

  /// 已经处理过的点名状态；没处理过返回 null。
  Future<RollcallWatchState?> stateOf(String rollcallId) async {
    await _ensureLoaded();
    return _states![rollcallId];
  }

  /// 这条点名是否已经被处理过（通知过或提交过）。
  Future<bool> isHandled(String rollcallId) async =>
      (await stateOf(rollcallId)) != null;

  Future<void> record(String rollcallId, RollcallWatchState state) async {
    await _ensureLoaded();
    final states = _states!;
    final times = _times!;
    states[rollcallId] = state;
    times[rollcallId] = DateTime.now();
    _trim(states, times);
    await _persist(states, times);
  }

  /// 清掉「只通知过、现在已经不在列表里」的记录。
  ///
  /// 提交过的记录（confirmed / rejected / unknown）永久保留：列表偶尔抖动
  /// 或缺一条时，绝不能因为「忘了处理过」而重复提交。
  Future<void> prune(Set<String> keepIds) async {
    await _ensureLoaded();
    final states = _states!;
    final times = _times!;
    states.removeWhere(
      (id, state) =>
          state == RollcallWatchState.notified && !keepIds.contains(id),
    );
    times.removeWhere((id, _) => !states.containsKey(id));
    _trim(states, times);
    await _persist(states, times);
  }

  Future<void> clear() async {
    _states = <String, RollcallWatchState>{};
    _times = <String, DateTime>{};
    await _persist(_states!, _times!);
  }

  void _trim(
    Map<String, RollcallWatchState> states,
    Map<String, DateTime> times,
  ) {
    final overflow = states.length - maxEntries;
    if (overflow <= 0) return;
    // Map 本身保持插入顺序，最早记进来的就是最旧的
    final drop = states.keys.take(overflow).toList();
    for (final id in drop) {
      states.remove(id);
      times.remove(id);
    }
  }

  Future<void> _persist(
    Map<String, RollcallWatchState> states,
    Map<String, DateTime> times,
  ) async {
    try {
      await CacheStore.write(storageKey, <String, dynamic>{
        'items': <String, dynamic>{
          for (final entry in states.entries)
            entry.key: <String, dynamic>{
              's': entry.value.name,
              'at': times[entry.key]?.toIso8601String(),
            },
        },
      });
    } catch (_) {
      // 存不下来只会导致下次可能重复处理，不阻塞监控
    }
  }

  @visibleForTesting
  Future<void> debugReset() async {
    _states = <String, RollcallWatchState>{};
    _times = <String, DateTime>{};
    _loading = null;
  }
}
