import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/campus_tiles.dart';
import 'package:project_usst/data/map_trace.dart';
import 'package:project_usst/pages/map_diagnostics_page.dart';
import 'package:project_usst/pages/map_page.dart';
import 'package:project_usst/widgets/campus_tile_layer.dart';

class _Location extends GeolocatorPlatform {
  late final points = StreamController<Position>.broadcast();
  LocationPermission permission = LocationPermission.whileInUse;
  int subscriptions = 0;
  Completer<LocationPermission>? permissionCheck;
  @override
  Future<LocationPermission> checkPermission() async =>
      permissionCheck == null ? permission : await permissionCheck!.future;
  @override
  Future<LocationPermission> requestPermission() async => permission;
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    subscriptions++;
    return points.stream;
  }

  void emitRoute() {
    final now = DateTime.now();
    for (var i = 0; i < 3; i++) {
      points.add(
        Position(
          longitude: 121.552,
          latitude: 31.294 + i * 0.00003,
          timestamp: now.subtract(Duration(seconds: 3 - i)),
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 3,
          speedAccuracy: 0,
        ),
      );
    }
  }
}

Future<void> frame(WidgetTester tester) async {
  await tester.pump();
  // Stream.cancel may complete on the real event loop, outside Flutter's fake clock.
  await tester.runAsync(() async {});
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GeolocatorPlatform previous;
  late _Location location;
  setUp(() async {
    MapTraces.memoryOnlyForTesting = true;
    previous = GeolocatorPlatform.instance;
    location = _Location();
    GeolocatorPlatform.instance = location;
    // Widget 测试使用内存后端；落盘恢复由 map_recording_data_test 单独验证。
    CacheStore.directoryOverride = () async =>
        throw StateError('memory-only widget fixture');
    CacheStore.clearMemory();
    await CacheStore.write('map.traces.v1', []);
    await CacheStore.write('map.calibration.v1', []);
    await MapTraces.clearDraft();
  });
  tearDown(() async {
    MapTraces.memoryOnlyForTesting = false;
    GeolocatorPlatform.instance = previous;
    await location.points.close();
    CacheStore.directoryOverride = null;
    CacheStore.clearMemory();
  });

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapPage()));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FloatingActionButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is FloatingActionButton &&
                  widget.heroTag == 'map-record',
            ),
          )
          .onPressed,
      isNotNull,
      reason: '草稿读取完成后应启用录制',
    );
    await tester.tap(find.byTooltip('记录或恢复路线'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('步行'));
    await frame(tester);
  }

  testWidgets('高缩放拖到海报外时回到有底图区域，非手势移动不受限', (tester) async {
    tester.view.physicalSize = const Size(960, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: MapPage()));
    await tester.pumpAndSettle();
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final controller = map.mapController!;
    for (final outside in const [
      LatLng(31.29407, 121.5573),
      LatLng(31.2871, 121.55139),
    ]) {
      controller.move(outside, 19.4);
      await tester.pumpAndSettle();
      expect(controller.camera.center, outside, reason: '定位、搜索等非手势移动仍可指向海报外');
      expect(
        CampusTileLayer.visibleTiles(controller.camera.visibleBounds),
        isEmpty,
        reason: '重现高缩放下整屏无底图的实际边缘位置',
      );
      map.options.onPositionChanged!(controller.camera, true);
      await tester.pumpAndSettle();
      expect(
        kCampusTiles.any(
          (tile) => tile.bounds.contains(controller.camera.center),
        ),
        isTrue,
        reason: '手势回弹后相机中心必须位于底图内',
      );
      expect(
        CampusTileLayer.visibleTiles(controller.camera.visibleBounds),
        isNotEmpty,
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('取消端点选择仍保留草稿，离开重进可以继续保存', (tester) async {
    await start(tester);
    location.emitRoute();
    await frame(tester);
    expect(find.textContaining('3 个点'), findsOneWidget);
    await tester.tap(find.byTooltip('停止并保存路线'));
    await frame(tester);
    await tester.pumpAndSettle();
    expect(find.text('这次从哪里出发？'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect((await MapTraces.loadDraft())!.points, hasLength(3));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(const MaterialApp(home: MapPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('已暂停 · 3 个点'), findsOneWidget);
    await tester.tap(find.byTooltip('记录或恢复路线'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存这一段'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SimpleDialogOption).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SimpleDialogOption).first);
    await tester.pumpAndSettle();
    expect(MapTraces.count, 1);
    expect(await MapTraces.loadDraft(), isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('定位中断显示原因并保存草稿，后台暂停不继续采点', (tester) async {
    await start(tester);
    location.emitRoute();
    await frame(tester);
    location.points.addError(Exception('location disabled'));
    await frame(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('定位中断'), findsOneWidget);
    expect(find.byTooltip('记录或恢复路线'), findsOneWidget);
    expect((await MapTraces.loadDraft())!.points, hasLength(3));
    await tester.tap(find.byTooltip('记录或恢复路线'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续记录'));
    await frame(tester);
    expect(location.subscriptions, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await frame(tester);
    location.emitRoute();
    await frame(tester);
    expect((await MapTraces.loadDraft())!.points, hasLength(3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await frame(tester);
    expect(find.byTooltip('记录或恢复路线'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('拒绝定位权限时不订阅定位流，也不进入假录制状态', (tester) async {
    location.permission = LocationPermission.deniedForever;
    await start(tester);
    expect(location.subscriptions, 0);
    expect(find.textContaining('未授予定位权限'), findsOneWidget);
    expect(find.byTooltip('记录或恢复路线'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('诊断页等待定位权限期间退出，不会订阅流或更新已销毁页面', (tester) async {
    location.permissionCheck = Completer<LocationPermission>();
    await tester.pumpWidget(const MaterialApp(home: MapDiagnosticsPage()));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    location.permissionCheck!.complete(LocationPermission.whileInUse);
    await tester.pumpAndSettle();
    expect(location.subscriptions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('上页草稿保存失败期间重进地图，录制按钮仍恢复可用', (tester) async {
    await CacheStore.write('map.traces.index.v2', []);
    final writeGate = Completer<void>();
    CacheStore.directoryOverride = () async {
      await writeGate.future;
      throw StateError('disk unavailable');
    };
    MapTraces.memoryOnlyForTesting = false;
    final save = MapTraces.saveDraft(
      MapTrace(
        fromName: '',
        toName: '',
        points: const [LatLng(31.294, 121.552)],
        startedAt: DateTime(2026, 11, 5),
      ),
    );
    final failedSave = expectLater(save, throwsStateError);
    await tester.pumpWidget(const MaterialApp(home: MapPage()));
    await tester.pump();
    writeGate.complete();
    await tester.pumpAndSettle();
    await failedSave;
    final recordButton = tester.widget<FloatingActionButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is FloatingActionButton && widget.heroTag == 'map-record',
      ),
    );
    expect(recordButton.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });
}
