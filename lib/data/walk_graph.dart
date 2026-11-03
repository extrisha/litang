import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

/// 一条步行路线。
class WalkRoute {
  const WalkRoute({required this.points, required this.meters});

  final List<LatLng> points;

  /// 步行距离（米，已含台阶/道路类型的代价修正）。
  final double meters;

  String get distanceText {
    if (meters < 1000) return '${meters.round()} 米';
    return '${(meters / 1000).toStringAsFixed(1)} 公里';
  }

  /// 按 1.25 m/s 估算步行时间。
  String get durationText {
    final minutes = (meters / 75).ceil();
    if (minutes < 60) return '约 $minutes 分钟';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '约 $h 小时' : '约 $h 小时 $m 分';
  }
}

/// 校园步行路网（由 tools/map/export_walk_graph.py 从 OSM 步道生成，坐标 WGS-84）。
class WalkGraph {
  WalkGraph._();

  static const String _asset = 'assets/map/walk_graph.json';
  static const Distance _distance = Distance();

  static List<LatLng> _nodes = const <LatLng>[];
  static List<List<(int, double)>> _adjacency = const <List<(int, double)>>[];
  static Map<String, int> _connectors = const <String, int>{};
  static bool _loaded = false;
  static bool get isLoaded => _loaded;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString(_asset);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _nodes = <LatLng>[
        for (final n in (data['nodes'] as List))
          LatLng((n[0] as num).toDouble(), (n[1] as num).toDouble()),
      ];
      _adjacency = List<List<(int, double)>>.generate(
        _nodes.length,
        (_) => <(int, double)>[],
      );
      for (final e in (data['edges'] as List)) {
        final a = e[0] as int;
        final b = e[1] as int;
        final w = (e[2] as num).toDouble();
        _adjacency[a].add((b, w));
        _adjacency[b].add((a, w));
      }
      final connectors = data['connectors'] as Map<String, dynamic>;
      _connectors = <String, int>{
        for (final entry in connectors.entries)
          entry.key: (entry.value['node'] as num).toInt(),
      };
      _loaded = true;
    } catch (_) {
      _loaded = false;
    }
  }

  static int nearestNode(LatLng point) {
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < _nodes.length; i++) {
      final d = _distance.as(LengthUnit.Meter, point, _nodes[i]);
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  /// 起点/终点到路网的接入节点：优先用同名的楼栋接入点。
  static int? connectorFor(String name) => _connectors[name];

  /// A* 求最短步行路线；失败返回 null。
  static WalkRoute? route(
    LatLng from,
    LatLng to, {
    int? fromNode,
    int? toNode,
  }) {
    if (!_loaded || _nodes.isEmpty) return null;
    final start = fromNode ?? nearestNode(from);
    final goal = toNode ?? nearestNode(to);
    if (start == goal) {
      return WalkRoute(
        points: <LatLng>[from, to],
        meters: _distance.as(LengthUnit.Meter, from, to),
      );
    }

    final n = _nodes.length;
    final gScore = List<double>.filled(n, double.infinity);
    final fScore = List<double>.filled(n, double.infinity);
    final previous = List<int>.filled(n, -1);
    final open = <int>{start};
    gScore[start] = 0;
    fScore[start] = _distance.as(LengthUnit.Meter, _nodes[start], _nodes[goal]);

    while (open.isNotEmpty) {
      // 节点数不到 1000，线性找最小值足够快
      var current = -1;
      var bestF = double.infinity;
      for (final i in open) {
        if (fScore[i] < bestF) {
          bestF = fScore[i];
          current = i;
        }
      }
      if (current == -1) break;
      if (current == goal) {
        final path = <LatLng>[to];
        var node = goal;
        while (node != -1) {
          path.add(_nodes[node]);
          node = previous[node];
        }
        path.add(from);
        return WalkRoute(points: path.reversed.toList(), meters: gScore[goal]);
      }

      open.remove(current);
      for (final (next, weight) in _adjacency[current]) {
        final tentative = gScore[current] + weight;
        if (tentative < gScore[next]) {
          previous[next] = current;
          gScore[next] = tentative;
          fScore[next] =
              tentative +
              _distance.as(LengthUnit.Meter, _nodes[next], _nodes[goal]);
          open.add(next);
        }
      }
    }
    return null;
  }

  static double straightDistance(LatLng a, LatLng b) =>
      _distance.as(LengthUnit.Meter, a, b);

  /// 调试用：路网规模。
  static String get summary =>
      '${_nodes.length} 节点 / ${_connectors.length} 接地点';

  // 便于测试
  static int get nodeCount => _nodes.length;
  static LatLng nodeAt(int index) => _nodes[index];
  static int get maxNodeIndex => math.max(0, _nodes.length - 1);
}
