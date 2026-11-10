import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

/// 一条步行路线。
class WalkRoute {
  const WalkRoute({
    required this.points,
    required this.meters,
    this.routingCost = 0,
  });

  final List<LatLng> points;

  /// 路线折线的实际长度（米），含起终点到路网的连接段。
  final double meters;

  /// 选路代价（含道路偏好），不能作为实际米数展示。
  final double routingCost;

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

/// 校园步行路网（已有 WGS-84 快照，原始导出器未随仓库提供）。
/// 已知漏边由 tools/map/repair_walk_connector.ps1 根据原始 OSM 修复。
class WalkGraph {
  WalkGraph._();

  static const String _asset = 'assets/map/walk_graph.json';
  static const Distance _distance = Distance();

  static List<LatLng> _nodes = const <LatLng>[];
  static List<List<(int, double)>> _adjacency = const <List<(int, double)>>[];
  static Map<String, int> _connectors = const <String, int>{};
  static bool _loaded = false;
  static Future<void>? _loading;
  static Set<int> _mainComponent = {};
  static double _heuristicScale = 1;
  static bool get isLoaded => _loaded;

  static Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load().whenComplete(() {
      _loading = null;
    });
  }

  static Future<void> _load() async {
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
      _heuristicScale = 1;
      for (var a = 0; a < _nodes.length; a++) {
        for (final (b, cost) in _adjacency[a]) {
          final meters = straightDistance(_nodes[a], _nodes[b]);
          if (meters > 0) {
            _heuristicScale = math.min(_heuristicScale, cost / meters);
          }
        }
      }
      // 只向主路网接入；孤立建筑点不能成为默认路线起点。
      final seen = <int>{};
      _mainComponent = {};
      for (var node = 0; node < _nodes.length; node++) {
        if (seen.contains(node)) continue;
        final component = <int>{node};
        final queue = [node];
        seen.add(node);
        for (var i = 0; i < queue.length; i++) {
          for (final (next, _) in _adjacency[queue[i]]) {
            if (seen.add(next)) {
              queue.add(next);
              component.add(next);
            }
          }
        }
        if (component.length > _mainComponent.length) {
          _mainComponent = component;
        }
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
    var best = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < _nodes.length; i++) {
      if (!_mainComponent.contains(i)) continue;
      final d = _distance.as(LengthUnit.Meter, point, _nodes[i]);
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  /// 起点/终点到路网的接入节点：优先用同名的楼栋接入点。
  static int? connectorFor(String name) {
    final node = _connectors[name];
    if (node == null) return null;
    if (_mainComponent.contains(node)) return node;
    final nearby = nearestNode(_nodes[node]);
    if (nearby < 0 || straightDistance(_nodes[node], _nodes[nearby]) > 50) {
      return null;
    }
    return nearby;
  }

  /// 只导航到附近已知道路，不凭空生成穿越建筑/围墙的连线。
  static bool hasApproximateConnector(String name) =>
      _connectors.containsKey(name) &&
      !_mainComponent.contains(_connectors[name]);

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
    if (start < 0 ||
        goal < 0 ||
        start >= _nodes.length ||
        goal >= _nodes.length) {
      return null;
    }
    if (start == goal) {
      final points = <LatLng>[from, _nodes[start], to];
      return WalkRoute(points: points, meters: pathLength(points));
    }

    final n = _nodes.length;
    final gScore = List<double>.filled(n, double.infinity);
    final fScore = List<double>.filled(n, double.infinity);
    final previous = List<int>.filled(n, -1);
    final open = <int>{start};
    gScore[start] = 0;
    fScore[start] =
        _heuristicScale * straightDistance(_nodes[start], _nodes[goal]);

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
        final points = path.reversed.toList();
        return WalkRoute(
          points: points,
          meters: pathLength(points),
          routingCost: gScore[goal],
        );
      }

      open.remove(current);
      for (final (next, weight) in _adjacency[current]) {
        final tentative = gScore[current] + weight;
        if (tentative < gScore[next]) {
          previous[next] = current;
          gScore[next] = tentative;
          fScore[next] =
              tentative +
              _heuristicScale * straightDistance(_nodes[next], _nodes[goal]);
          open.add(next);
        }
      }
    }
    return null;
  }

  static double straightDistance(LatLng a, LatLng b) =>
      _distance.as(LengthUnit.Meter, a, b);

  static double pathLength(List<LatLng> points) {
    var meters = 0.0;
    for (var i = 1; i < points.length; i++) {
      meters += straightDistance(points[i - 1], points[i]);
    }
    return meters;
  }

  /// 调试用：路网规模。
  static String get summary =>
      '${_nodes.length} 节点 / ${_connectors.length} 接地点';

  // 便于测试
  static int get nodeCount => _nodes.length;
  static LatLng nodeAt(int index) => _nodes[index];
  static int get maxNodeIndex => math.max(0, _nodes.length - 1);
}
