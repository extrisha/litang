import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../cache_store.dart';
import '../geo/campus_buildings.dart';
import '../lms/radar_target.dart' show RadarLocationMode;

RadarLocationMode _modeFromName(String? name) {
  for (final mode in RadarLocationMode.values) {
    if (mode.name == name) return mode;
  }
  return RadarLocationMode.auto;
}

/// 内部模式配置。
///
/// 普通用户走不到这里：只有「我的 → 关于 → 长按检查更新」才打开。
@immutable
class InternalSettings {
  const InternalSettings({
    this.enabled = false,
    this.monitor = false,
    this.autoSign = false,
    this.autoNumber = false,
    this.dryRun = true,
    this.waitForMajority = true,
    this.notify = true,
    this.intervalSeconds = 20,
    this.radarMode = RadarLocationMode.auto,
    this.buildingId,
  });

  /// 内部模式总开关。
  final bool enabled;

  /// 前台轮询签到。
  final bool monitor;

  /// 自动提交雷达签到（关掉就只通知）。
  final bool autoSign;

  /// 自动提交数字口令签到（从花名册读码；读不到仍退回通知）。
  final bool autoNumber;

  /// 演练：只通知、不提交。默认开，避免刚打开就误提交。
  final bool dryRun;

  /// 自动提交前先等「已签人数过半」。
  ///
  /// 两个作用：不会第一个签（不扎眼），也顺带等到班里有人签上、
  /// 数字口令出现在花名册里。
  final bool waitForMajority;

  /// 以本地通知提醒。
  final bool notify;

  /// 轮询间隔（秒）。
  final int intervalSeconds;

  /// 雷达取点方式。
  final RadarLocationMode radarMode;

  /// 锁定使用的教学楼 id（[RadarLocationMode.building] 生效）。
  final String? buildingId;

  static const List<int> allowedIntervals = <int>[10, 20, 30, 60];

  /// 雷达是不是真的会提交：开了自动签到、开了雷达、且不是演练。
  bool get submitsInsteadOfNotify => enabled && autoSign && !dryRun;

  /// 数字口令是不是真的会提交。
  bool get submitsNumberInsteadOfNotify =>
      enabled && autoSign && autoNumber && !dryRun;

  CampusBuilding? get building {
    final id = buildingId;
    if (id == null) return null;
    for (final building in kUsstBuildings) {
      if (building.id == id) return building;
    }
    return null;
  }

  InternalSettings copyWith({
    bool? enabled,
    bool? monitor,
    bool? autoSign,
    bool? autoNumber,
    bool? dryRun,
    bool? waitForMajority,
    bool? notify,
    int? intervalSeconds,
    RadarLocationMode? radarMode,
    Object? buildingId = _unset,
  }) {
    return InternalSettings(
      enabled: enabled ?? this.enabled,
      monitor: monitor ?? this.monitor,
      autoSign: autoSign ?? this.autoSign,
      autoNumber: autoNumber ?? this.autoNumber,
      dryRun: dryRun ?? this.dryRun,
      waitForMajority: waitForMajority ?? this.waitForMajority,
      notify: notify ?? this.notify,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      radarMode: radarMode ?? this.radarMode,
      buildingId: identical(buildingId, _unset)
          ? this.buildingId
          : buildingId as String?,
    );
  }

  static const Object _unset = Object();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'monitor': monitor,
    'autoSign': autoSign,
    'autoNumber': autoNumber,
    'dryRun': dryRun,
    'waitForMajority': waitForMajority,
    'notify': notify,
    'intervalSeconds': intervalSeconds,
    'radarMode': radarMode.name,
    'buildingId': buildingId,
  };

  static InternalSettings fromJson(Map<String, dynamic> json) {
    final rawInterval = switch (json['intervalSeconds']) {
      final num value => value.toInt(),
      final String value => int.tryParse(value) ?? 20,
      _ => 20,
    };
    final interval = allowedIntervals.contains(rawInterval) ? rawInterval : 20;
    final rawBuilding = '${json['buildingId'] ?? ''}'.trim();
    final buildingId = kUsstBuildings.any((b) => b.id == rawBuilding)
        ? rawBuilding
        : null;
    return InternalSettings(
      enabled: json['enabled'] == true,
      monitor: json['monitor'] == true,
      autoSign: json['autoSign'] == true,
      autoNumber: json['autoNumber'] == true,
      dryRun: json['dryRun'] != false,
      waitForMajority: json['waitForMajority'] != false,
      notify: json['notify'] != false,
      intervalSeconds: interval,
      radarMode: _modeFromName(json['radarMode'] as String?),
      buildingId: buildingId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is InternalSettings &&
      other.enabled == enabled &&
      other.monitor == monitor &&
      other.autoSign == autoSign &&
      other.autoNumber == autoNumber &&
      other.dryRun == dryRun &&
      other.waitForMajority == waitForMajority &&
      other.notify == notify &&
      other.intervalSeconds == intervalSeconds &&
      other.radarMode == radarMode &&
      other.buildingId == buildingId;

  @override
  int get hashCode => Object.hash(
    enabled,
    monitor,
    autoSign,
    autoNumber,
    dryRun,
    waitForMajority,
    notify,
    intervalSeconds,
    radarMode,
    buildingId,
  );
}

/// 内部模式开关与配置的全局入口。
class InternalMode {
  InternalMode._();

  static final InternalMode instance = InternalMode._();

  static const String storageKey = 'usst_internal_mode_v1';

  /// 配置变化后通知 UI / 监控。
  final ValueNotifier<InternalSettings> settings =
      ValueNotifier<InternalSettings>(const InternalSettings());

  Future<void>? _loading;

  /// 读一次配置；重复调用复用同一个 Future。
  Future<void> ensureLoaded() {
    if (_loading != null) return _loading!;
    final future = _load();
    _loading = future;
    return future;
  }

  Future<void> _load() async {
    try {
      final entry = await CacheStore.read(storageKey, secure: true);
      final data = entry?.data;
      if (data is Map) {
        settings.value = InternalSettings.fromJson(
          data.map((key, value) => MapEntry('$key', value)),
        );
      }
    } catch (_) {
      // 读失败就用默认值（内部模式关闭），不影响正常使用
    }
  }

  Future<void> save(InternalSettings value) async {
    settings.value = value;
    try {
      await CacheStore.write(storageKey, value.toJson(), secure: true);
    } catch (_) {
      // 存不下来只影响下次启动，本次会话仍然生效
    }
  }

  Future<void> update(InternalSettings Function(InternalSettings) change) =>
      save(change(settings.value));

  Future<void> setEnabled(bool enabled) => update(
    (value) => enabled
        ? value.copyWith(enabled: true)
        : value.copyWith(enabled: false, monitor: false, autoSign: false),
  );

  /// 单测用：直接改内存值，不落盘。
  @visibleForTesting
  void debugSet(InternalSettings value) {
    settings.value = value;
  }

  @visibleForTesting
  void debugReset() {
    _loading = null;
    settings.value = const InternalSettings();
  }

  /// 导出当前配置的 JSON（内部模式页「复制配置」用）。
  String exportJson() =>
      const JsonEncoder.withIndent('  ').convert(settings.value.toJson());
}
