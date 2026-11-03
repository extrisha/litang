import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:project_usst/data/walk_graph.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('路网能从资源加载并算出一条路线', () async {
    await WalkGraph.load();
    expect(WalkGraph.isLoaded, isTrue, reason: 'assets/map/walk_graph.json 应能解析');
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
}
