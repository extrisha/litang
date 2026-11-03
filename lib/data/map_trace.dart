import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'cache_store.dart';

/// 一条采集到的步行路线（用于后续改善路线推荐/发现捷径）。
class MapTrace {
  const MapTrace({
    required this.fromName,
    required this.toName,
    required this.points,
    required this.startedAt,
  });

  final String fromName;
  final String toName;
  final List<LatLng> points;
  final DateTime startedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'from': fromName,
    'to': toName,
    'at': startedAt.toIso8601String(),
    'points': <List<double>>[
      for (final p in points) <double>[p.latitude, p.longitude],
    ],
  };

  static MapTrace? fromJson(Map<String, dynamic> json) {
    final points = <LatLng>[];
    for (final p in (json['points'] as List? ?? const <dynamic>[])) {
      if (p is List && p.length >= 2) {
        points.add(LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()));
      }
    }
    if (points.isEmpty) return null;
    return MapTrace(
      fromName: json['from'] as String? ?? '未标注',
      toName: json['to'] as String? ?? '未标注',
      points: points,
      startedAt:
          DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// 本地保存的路线采集记录。
class MapTraces {
  MapTraces._();

  static const String _key = 'map.traces.v1';
  static const int _maxTraces = 200;

  static List<MapTrace> _items = <MapTrace>[];

  static List<MapTrace> get items => List.unmodifiable(_items);
  static int get count => _items.length;

  static Future<void> load() async {
    final entry = await CacheStore.read(_key);
    final raw = entry?.data;
    if (raw is! List) {
      _items = <MapTrace>[];
      return;
    }
    _items = raw
        .whereType<Map>()
        .map((e) => MapTrace.fromJson(Map<String, dynamic>.from(e)))
        .whereType<MapTrace>()
        .toList();
  }

  static Future<void> add(MapTrace trace) async {
    _items = <MapTrace>[..._items, trace];
    if (_items.length > _maxTraces) {
      _items = _items.sublist(_items.length - _maxTraces);
    }
    await CacheStore.write(_key, _items.map((t) => t.toJson()).toList());
  }

  static Future<void> clear() async {
    _items = <MapTrace>[];
    await CacheStore.remove(_key);
  }

  /// 导出为 JSONL（每行一条路线），方便直接发回。
  static String exportText() {
    if (_items.isEmpty) return '（还没有路线记录）';
    final buffer = StringBuffer()
      ..writeln('【校园路线记录】共 ${_items.length} 条')
      ..writeln('from,to,at,points');
    for (final t in _items) {
      buffer.writeln(jsonEncode(t.toJson()));
    }
    return buffer.toString();
  }
}
