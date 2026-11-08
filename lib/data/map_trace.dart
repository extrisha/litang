import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:latlong2/latlong.dart';

import 'cache_store.dart';

/// 采集方式：步行 / 骑行。两者的路线偏好不同（骑行会绕开台阶、走坡道）。
enum TraceMode {
  walk('步行', 'walk'),
  bike('骑行', 'bike');

  const TraceMode(this.label, this.value);

  final String label;
  final String value;

  static TraceMode fromValue(String? value) =>
      value == 'bike' ? TraceMode.bike : TraceMode.walk;
}

/// 一条采集到的路线（用于后续改善路线推荐/发现捷径）。
class MapTrace {
  const MapTrace({
    required this.fromName,
    required this.toName,
    required this.points,
    required this.startedAt,
    this.mode = TraceMode.walk,
    this.samples = const [],
  });

  final String fromName;
  final String toName;
  final List<LatLng> points;
  final DateTime startedAt;
  final TraceMode mode;
  final List<({DateTime at, double accuracy})?> samples;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'from': fromName,
    'to': toName,
    'mode': mode.value,
    'at': startedAt.toIso8601String(),
    'coordinateSystem': 'WGS84',
    'points': <List<num>>[
      for (var i = 0; i < points.length; i++)
        <num>[
          points[i].latitude,
          points[i].longitude,
          if (i < samples.length && samples[i] != null) ...[
            samples[i]!.at.millisecondsSinceEpoch,
            samples[i]!.accuracy,
          ],
        ],
    ],
  };

  static MapTrace? fromJson(Map<String, dynamic> json) {
    final points = <LatLng>[];
    final samples = <({DateTime at, double accuracy})?>[];
    final raw = json['points'];
    if (raw is! List) return null;
    for (final p in raw) {
      if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
        final lat = (p[0] as num).toDouble();
        final lng = (p[1] as num).toDouble();
        if (lat.isFinite &&
            lng.isFinite &&
            lat.abs() <= 90 &&
            lng.abs() <= 180) {
          points.add(LatLng(lat, lng));
          samples.add(
            p.length >= 4 &&
                    p[2] is num &&
                    p[3] is num &&
                    (p[2] as num).isFinite &&
                    (p[2] as num).abs() < 8640000000000000 &&
                    (p[3] as num).isFinite &&
                    (p[3] as num) >= 0
                ? (
                    at: DateTime.fromMillisecondsSinceEpoch(
                      (p[2] as num).toInt(),
                      isUtc: true,
                    ),
                    accuracy: (p[3] as num).toDouble(),
                  )
                : null,
          );
        }
      }
    }
    if (points.isEmpty) return null;
    return MapTrace(
      fromName: json['from']?.toString() ?? '未标注',
      toName: json['to']?.toString() ?? '未标注',
      points: points,
      samples: samples,
      startedAt:
          DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime.now(),
      mode: TraceMode.fromValue(json['mode']?.toString()),
    );
  }
}

/// 本地保存的路线采集记录。
class MapTraces {
  MapTraces._();

  static const String _key = 'map.traces.v1';
  static const int _maxTraces = 200;
  static const String _indexKey = 'map.traces.index.v2';
  static List<Map<String, dynamic>> _records = [];
  static Future<void>? _historyQueue;
  @visibleForTesting
  static bool memoryOnlyForTesting = false;
  static const String _draftKey = 'map.trace.draft.v1';
  static Future<void>? _draftQueue;

  static int get count => _records.length;

  static Future<MapTrace?> loadDraft() async {
    final pending = _draftQueue;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // Failed saves must not prevent recovery of the previous durable draft.
      }
    }
    final raw = (await CacheStore.read(_draftKey))?.data;
    return raw is Map ? MapTrace.fromJson(raw.cast<String, dynamic>()) : null;
  }

  static Future<void> saveDraft(MapTrace draft) {
    final data = draft.toJson();
    return _queueDraftWrite(
      () => CacheStore.write(
        _draftKey,
        data,
        requirePersistence: !memoryOnlyForTesting,
      ),
    );
  }

  static Future<void> clearDraft() => _queueDraftWrite(
    () =>
        CacheStore.remove(_draftKey, requirePersistence: !memoryOnlyForTesting),
  );

  static Future<void> _queueDraftWrite(Future<void> Function() write) {
    late Future<void> future;
    future = (_draftQueue ?? Future<void>.value())
        .then((_) => write(), onError: (Object _) => write())
        .whenComplete(() {
          if (identical(_draftQueue, future)) _draftQueue = null;
        });
    _draftQueue = future;
    return future;
  }

  static Future<void> _history(Future<void> Function() operation) {
    late final Future<void> future;
    future = (_historyQueue ?? Future<void>.value())
        .then((_) => operation(), onError: (Object _) => operation())
        .whenComplete(() {
          if (identical(_historyQueue, future)) _historyQueue = null;
        });
    _historyQueue = future;
    return future;
  }

  static String _traceKey(MapTrace trace) =>
      'map.trace.v2.${sha256.convert(utf8.encode(jsonEncode(trace.toJson())))}';

  static Map<String, dynamic> _record(MapTrace trace, String key) => {
    'key': key,
    'from': trace.fromName,
    'to': trace.toName,
    'mode': trace.mode.value,
    'at': trace.startedAt.toIso8601String(),
    'pointCount': trace.points.length,
  };

  /// Load only the small index. Historical point arrays are read on export.
  static Future<void> load() => _history(_loadIndex);
  static Future<void> _loadIndex() async {
    final data = (await CacheStore.read(_indexKey))?.data;
    if (data is List) {
      _records = data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => e['key'] is String)
          .toList();
      return;
    }
    final legacy = (await CacheStore.read(_key))?.data;
    if (legacy is! List) {
      _records = [];
      return;
    }
    final records = <String, Map<String, dynamic>>{};
    for (final raw in legacy.whereType<Map>()) {
      final trace = MapTrace.fromJson(Map<String, dynamic>.from(raw));
      if (trace == null) continue;
      final key = _traceKey(trace);
      await CacheStore.write(
        key,
        trace.toJson(),
        requirePersistence: !memoryOnlyForTesting,
      );
      records[key] = _record(trace, key);
    }
    // Only remove the legacy archive after all routes and the index are durable.
    await CacheStore.write(
      _indexKey,
      records.values.toList(),
      requirePersistence: !memoryOnlyForTesting,
    );
    _records = records.values.toList();
    await CacheStore.remove(_key, requirePersistence: !memoryOnlyForTesting);
  }

  static Future<void> add(MapTrace trace) => _history(() async {
    if (trace.points.isEmpty || trace.points.length > 20000) {
      throw StateError('路线点数不合法');
    }
    await _loadIndex();
    final key = _traceKey(trace);
    await CacheStore.write(
      key,
      trace.toJson(),
      requirePersistence: !memoryOnlyForTesting,
    );
    final records = [
      ..._records.where((e) => e['key'] != key),
      _record(trace, key),
    ];
    final dropped = records.length > _maxTraces
        ? records.sublist(0, records.length - _maxTraces)
        : <Map<String, dynamic>>[];
    final kept = records.length > _maxTraces
        ? records.sublist(records.length - _maxTraces)
        : records;
    await CacheStore.write(
      _indexKey,
      kept,
      requirePersistence: !memoryOnlyForTesting,
    );
    _records = kept;
    for (final record in dropped) {
      await CacheStore.remove(record['key'] as String);
    }
  });

  static Future<void> clear() => _history(() async {
    await _loadIndex();
    final records = _records;
    // Commit the empty history before removing files, so interruption cannot
    // leave a published index pointing to already deleted routes.
    await CacheStore.write(
      _indexKey,
      <Map<String, dynamic>>[],
      requirePersistence: !memoryOnlyForTesting,
    );
    _records = [];
    for (final record in records) {
      await CacheStore.remove(
        record['key'] as String,
        requirePersistence: !memoryOnlyForTesting,
      );
    }
    await CacheStore.remove(_key, requirePersistence: !memoryOnlyForTesting);
  });

  /// JSONL is assembled only for an explicit export, not on map startup/save.
  static Future<String> exportText() async {
    var result = '（还没有路线记录）';
    await _history(() async {
      await _loadIndex();
      if (_records.isEmpty) return;
      final walk = _records.where((t) => t['mode'] == 'walk').length;
      final buffer = StringBuffer()
        ..writeln(
          '【校园路线记录】共 ${_records.length} 条（步行 $walk / 骑行 ${_records.length - walk}）',
        )
        ..writeln('from,to,mode,at,points');
      for (final record in _records) {
        final data = (await CacheStore.read(record['key'] as String))?.data;
        if (data is! Map ||
            MapTrace.fromJson(Map<String, dynamic>.from(data)) == null) {
          throw StateError('路线记录读取失败，请检查本地存储后重试');
        }
        buffer.writeln(jsonEncode(data));
      }
      result = buffer.toString();
    });
    return result;
  }
}

/// 过滤过期、精度差、重复点和不符合步行/骑行速度的 GPS 跳点。
class TraceSampler {
  TraceSampler(this.mode);
  final TraceMode mode;
  LatLng? _last;
  DateTime? _at;
  static const _distance = Distance();

  bool accept(LatLng point, DateTime at, double accuracy, {DateTime? now}) {
    final age = (now ?? DateTime.now()).difference(at);
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude.abs() > 90 ||
        point.longitude.abs() > 180 ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > 50 ||
        age.isNegative ||
        age > const Duration(seconds: 30)) {
      return false;
    }
    if (_last != null) {
      final seconds = at.difference(_at!).inMilliseconds / 1000;
      final meters = _distance.as(LengthUnit.Meter, _last!, point);
      if (seconds <= 0 ||
          meters < 2 ||
          meters / seconds > (mode == TraceMode.bike ? 20 : 8)) {
        return false;
      }
    }
    _last = point;
    _at = at;
    return true;
  }
}
