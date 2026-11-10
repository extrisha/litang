import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:project_usst/data/walk_graph.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('路网能从资源加载并算出一条路线', () async {
    await WalkGraph.load();
    expect(
      WalkGraph.isLoaded,
      isTrue,
      reason: 'assets/map/walk_graph.json 应能解析',
    );
    expect(WalkGraph.nodeCount, greaterThan(500));

    final route = WalkGraph.route(
      const LatLng(31.292891, 121.553390), // 第二学生公寓三号楼附近
      const LatLng(31.293200, 121.554000), // 第一教学楼附近
    );
    expect(route, isNotNull);
    expect(route!.meters, greaterThan(0));
    expect(route.points.length, greaterThan(1));
  });

  test('楼栋接地点能命中已命名地点', () async {
    await WalkGraph.load();
    expect(WalkGraph.connectorFor('第三教学楼'), isNotNull);
    expect(WalkGraph.connectorFor('图文信息中心'), isNotNull);
    expect(WalkGraph.connectorFor('不存在的楼'), isNull);
  });

  test('所有命名接点均可从主路网到达，思伊堂使用 OSM 修复后的真实连接', () async {
    await WalkGraph.load();
    final data = jsonDecode(
      await rootBundle.loadString('assets/map/walk_graph.json'),
    ) as Map;
    final startNode = WalkGraph.connectorFor('第三教学楼')!;
    for (final name in (data['connectors'] as Map).keys.cast<String>()) {
      final node = WalkGraph.connectorFor(name);
      expect(node, isNotNull, reason: name);
      final route = WalkGraph.route(
        WalkGraph.nodeAt(startNode),
        WalkGraph.nodeAt(node!),
        fromNode: startNode,
        toNode: node,
      );
      expect(route, isNotNull, reason: name);
      expect(route!.meters, closeTo(WalkGraph.pathLength(route.points), 0.001));
    }
    expect(WalkGraph.connectorFor('思伊堂（第四学生宿舍）'), 599);
    expect(WalkGraph.hasApproximateConnector('思伊堂（第四学生宿舍）'), isFalse);
  });

  test('距离包含连接段；选择同一接点也不能把折线路径伪装成直线', () async {
    await WalkGraph.load();
    final node = WalkGraph.connectorFor('第三教学楼')!;
    final origin = WalkGraph.nodeAt(node);
    final from = LatLng(origin.latitude + 0.0001, origin.longitude);
    final to = LatLng(origin.latitude, origin.longitude + 0.0001);
    final route = WalkGraph.route(from, to, fromNode: node, toNode: node)!;
    expect(route.points, [from, origin, to]);
    expect(route.meters, greaterThan(WalkGraph.straightDistance(from, to)));
    expect(WalkGraph.route(from, to, fromNode: -1), isNull);
  });
}
