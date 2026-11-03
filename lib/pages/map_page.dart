import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../data/campus_labels.dart';
import '../data/campus_shapes.dart';
import '../data/campus_places.dart';
import '../data/campus_tiles.dart';
import '../data/map_calibration.dart';
import '../data/map_focus.dart';
import '../data/map_trace.dart';
import '../data/walk_graph.dart';
import 'map_diagnostics_page.dart';

/// 是否启用地图功能（置 false 可在发版时整体下线）
const bool kMapFeatureEnabled = true;

/// 校园地图：军工路 516 号校区官方手绘示意图（0.4.0 底图），
/// 已用 36 个 OSM 控制点配准到 WGS-84，支持搜索、GPS 定位与课表联动。
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

const LatLng _campusCenter = LatLng(31.29407, 121.55139);
const double _initialZoom = 17.2;
const double _focusZoom = 18.3;
const double _minZoom = 15.0;
const double _maxZoom = 19.4;

/// 可拖动范围：只框住校区主体，不含海报顶部的标题条和四周留白。
/// 数值由 tools/map/georef_campus_map.py 的变换对图像矩形 (560,400)-(4300,5300) 反算得到。
final LatLngBounds _campusBounds = LatLngBounds(
  const LatLng(31.288508, 121.546787),
  const LatLng(31.299634, 121.555999),
);

/// 相机中心允许移动的范围：比校区大一圈（约 160 m），
/// 这样缩小时能露出一点白边，又不会把整张图拖出屏幕。
final LatLngBounds _panBounds = LatLngBounds(
  const LatLng(31.287008, 121.545387),
  const LatLng(31.301134, 121.557399),
);

/// 整张海报（4500×5350）的经纬度范围，等于所有瓦片 bounds 的外包。
/// 用来把经纬度换算回图像归一化坐标，做「吸附到建筑角点」。
final LatLngBounds _posterBounds = () {
  var south = 90.0, north = -90.0, west = 180.0, east = -180.0;
  for (final tile in kCampusTiles) {
    if (tile.south < south) south = tile.south;
    if (tile.north > north) north = tile.north;
    if (tile.west < west) west = tile.west;
    if (tile.east > east) east = tile.east;
  }
  return LatLngBounds(LatLng(south, west), LatLng(north, east));
}();

/// 顶部搜索栏会盖住地图，适配视野时留出 padding。
const EdgeInsets _fitPadding = EdgeInsets.fromLTRB(16, 128, 16, 40);

/// 低于该缩放不显示任何文字标签，整幅图保持干净。
/// 取值略低于「装下整张图」的默认缩放（约 15.85），保证一打开就能看到地标标签。
const double _labelMinZoom = 15.5;

class _MapPageState extends State<MapPage> with TickerProviderStateMixin {
  static const Distance _distance = Distance();

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  late final List<OverlayImage> _baseOverlays = <OverlayImage>[
    for (final tile in kCampusTiles)
      OverlayImage(
        bounds: tile.bounds,
        imageProvider: AssetImage(tile.asset),
        filterQuality: FilterQuality.medium,
      ),
  ];

  CampusLabel? _selected;
  CampusLabel? _pending;
  String _query = '';
  bool _showLabels = true;

  MapCamera? _camera;
  double _zoom = _initialZoom;

  /// 装下整张图所需的最小缩放，onMapReady 时按实际视口算出来。
  bool _ready = false;

  /// 防止软回弹触发的 move 再次进入 _handlePosition 形成递归。
  bool _clamping = false;
  double? _lastBuildZoom;
  LatLng? _lastBuildCenter;

  LatLng? _userLocation;

  /// 未经校准的原始 GPS 点，用于标定时算偏差。
  LatLng? _rawFix;
  double? _userHeading;

  /// 系统上报的定位精度（米），用来画精度圈。
  double? _accuracyMeters;
  bool _locating = false;

  /// A* 算出的步行路线。
  WalkRoute? _route;

  /// 正在采集的轨迹。
  bool _recording = false;
  final List<LatLng> _trace = <LatLng>[];
  StreamSubscription<Position>? _traceSubscription;
  DateTime? _traceStartedAt;

  AnimationController? _flying;

  @override
  void initState() {
    super.initState();
    MapFocus.target.addListener(_onMapFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onMapFocus());
    MapCalibration.load().then((_) {
      if (mounted) setState(() {});
    });
    // 路网与轨迹在后台加载，加载完不影响既有交互
    WalkGraph.load().then((_) {
      if (mounted) setState(() {});
    });
    MapTraces.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    MapFocus.target.removeListener(_onMapFocus);
    _traceSubscription?.cancel();
    _flying?.dispose();
    _mapController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 焦点

  void _onMapFocus() {
    final place = MapFocus.target.value;
    if (place == null) return;
    MapFocus.consume();
    final label = _resolvePlace(place);
    if (label == null) return;
    if (_ready) {
      _focusLabel(label);
    } else {
      _pending = label;
    }
  }

  CampusLabel? _labelByName(String name) {
    for (final l in kCampusLabels) {
      if (l.name == name) return l;
    }
    return null;
  }

  /// 把课表里的教室 / 地点名解析到某个标签实体。
  CampusLabel? _resolvePlace(CampusPlace place) {
    final direct = _labelByName(place.name);
    if (direct != null) return direct;

    final byRoom = placeForRoom(place.name);
    if (byRoom != null) {
      final hit = _labelByName(byRoom.name);
      if (hit != null) return hit;
    }

    CampusLabel? best;
    var bestDistance = 0.06; // 归一化坐标，约为图幅的 6%
    for (final l in kCampusLabels) {
      final d = (l.anchor - place.anchor).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = l;
      }
    }
    return best;
  }

  // ---------------------------------------------------------------- 相机

  void _handleReady() {
    _ready = true;
    _camera = _mapController.camera;

    final pending = _pending;
    if (pending != null) {
      _pending = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusLabel(pending));
      return;
    }
    // 首帧就要把标签算出来，否则要等用户拖动才出现
    _lastBuildCenter = _camera?.center;
    _lastBuildZoom = _camera?.zoom;
    if (mounted) setState(() {});
  }

  void _handlePosition(MapCamera camera, bool hasGesture) {
    _camera = camera;
    _zoom = camera.zoom;
    if (!_ready) return;

    // 软边界：拖出允许范围就把它拉回来，不加 CameraConstraint（那个会和 rebuild 打架）
    if (hasGesture && !_clamping && !_panBounds.contains(camera.center)) {
      _clamping = true;
      _mapController.move(
        LatLng(
          camera.center.latitude.clamp(_panBounds.south, _panBounds.north),
          camera.center.longitude.clamp(_panBounds.west, _panBounds.east),
        ),
        camera.zoom,
      );
      _clamping = false;
    }

    final moved =
        _lastBuildCenter == null ||
        _distance.as(LengthUnit.Meter, _lastBuildCenter!, camera.center) > 60;
    final zoomed =
        _lastBuildZoom == null || (_lastBuildZoom! - camera.zoom).abs() > 0.12;
    if (!moved && !zoomed) return;

    _lastBuildCenter = camera.center;
    _lastBuildZoom = camera.zoom;
    if (mounted) setState(() {});
  }

  void _flyTo(LatLng destination, double zoom) {
    if (!_ready) return;
    _flying?.dispose();
    final camera = _mapController.camera;
    final latTween = Tween<double>(
      begin: camera.center.latitude,
      end: destination.latitude,
    );
    final lngTween = Tween<double>(
      begin: camera.center.longitude,
      end: destination.longitude,
    );
    final zoomTween = Tween<double>(begin: camera.zoom, end: zoom);

    final controller = AnimationController(
      duration: const Duration(milliseconds: 420),
      vsync: this,
    );
    _flying = controller;
    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        controller.dispose();
        if (identical(_flying, controller)) _flying = null;
      }
    });
    controller.forward();
  }

  void _focusLabel(CampusLabel label) {
    setState(() {
      _selected = label;
      _query = '';
      _searchController.clear();
      _searchFocus.unfocus();
    });
    _flyTo(LatLng(label.lat, label.lng), math.max(_zoom, _focusZoom));
  }

  void _handleMapTap(LatLng point) {
    CampusLabel? best;
    var bestDistance = 32.0;
    for (final l in kCampusLabels) {
      final d = _distance.as(LengthUnit.Meter, point, LatLng(l.lat, l.lng));
      if (d < bestDistance) {
        bestDistance = d;
        best = l;
      }
    }
    if (best != null) {
      _focusLabel(best);
    } else if (_selected != null) {
      setState(() => _selected = null);
    }
  }

  // ---------------------------------------------------------------- 定位

  Future<void> _locateUser() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _toast('定位权限已被永久禁用，请在系统设置中允许');
        await Geolocator.openAppSettings();
        return;
      }
      if (permission == LocationPermission.denied) {
        _toast('未授予位置权限，无法获取实时定位');
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('系统定位服务未开启');
        await Geolocator.openLocationSettings();
        return;
      }

      final last = await Geolocator.getLastKnownPosition();
      final hasLast = last != null && _isUsable(last);
      if (hasLast) {
        // 先把上次的位置画出来，用户立刻能看到点，再等精定位刷新
        _applyFix(
          last.latitude,
          last.longitude,
          last.accuracy,
          last.heading,
          fly: false,
        );
      }

      final fix = await _collectFix();
      if (fix == null) {
        if (hasLast) {
          _flyTo(LatLng(last.latitude, last.longitude), math.max(_zoom, 18.0));
          _toast('只拿到上次的定位记录，精度可能较差');
        } else {
          _toast('暂时拿不到定位，请到室外或稍后再试');
        }
        return;
      }
      _applyFix(fix.$1, fix.$2, fix.$3, fix.$4);
    } catch (_) {
      _toast('获取定位失败，请确认系统定位已开启');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  bool _isUsable(Position p) {
    final age = DateTime.now().difference(p.timestamp);
    return !age.isNegative &&
        age <= const Duration(minutes: 5) &&
        p.accuracy <= 100;
  }

  /// 取一次定位。融合定位优先，`forceGps` 时退回系统 LocationManager（纯 GPS），
  /// 用作没有 GMS / 融合定位超时的兜底。
  Future<Position?> _tryFix({bool forceGps = false, int seconds = 12}) async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: forceGps
            ? AndroidSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: seconds),
                forceLocationManager: true,
              )
            : LocationSettings(
                accuracy: LocationAccuracy.best,
                timeLimit: Duration(seconds: seconds),
              ),
      );
    } catch (_) {
      return null;
    }
  }

  /// 辅助定位：融合定位（GPS + Wi-Fi + 基站）优先，失败再退回纯 GPS；
  /// 精度一般时补采一次做加权平均，抵消随机抖动。
  ///
  /// 超时不能压太短：室内首次定位经常要 10 s 以上，之前 6 s 硬超时会导致直接拿不到点。
  /// 定位预算：在这个时间内尽量拿点，够准就提前结束，避免用户干等。
  static const Duration _fixBudget = Duration(milliseconds: 2500);
  static const Duration _gpsFallbackBudget = Duration(seconds: 5);

  /// 快速定位：订阅定位流（融合定位会先吐一个 Wi-Fi/基站粗定位），
  /// 在 [_fixBudget] 内取精度最好的一批点做加权平均；够准（≤15 m）立刻收工。
  /// 流里完全没点时才退回一次纯 GPS 请求（最多再等 5 s）。
  Future<(double, double, double, double)?> _collectFix() async {
    final samples = <Position>[];
    final completer = Completer<(double, double, double, double)?>();
    StreamSubscription<Position>? sub;
    Timer? timer;

    void finish() {
      if (completer.isCompleted) return;
      timer?.cancel();
      sub?.cancel();
      if (samples.isEmpty) {
        completer.complete(null);
        return;
      }
      var weightSum = 0.0;
      var lat = 0.0;
      var lng = 0.0;
      for (final p in samples) {
        final w = 1.0 / math.max(p.accuracy, 1.0);
        weightSum += w;
        lat += p.latitude * w;
        lng += p.longitude * w;
      }
      final best = samples.map((p) => p.accuracy).reduce(math.min);
      completer.complete((
        lat / weightSum,
        lng / weightSum,
        best,
        samples.last.heading,
      ));
    }

    try {
      sub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
            ),
          ).listen(
            (p) {
              samples.add(p);
              if (p.accuracy <= 15) finish();
            },
            onError: (_) => finish(),
            cancelOnError: false,
          );
      timer = Timer(_fixBudget, finish);
    } catch (_) {
      return null;
    }

    final streamed = await completer.future;
    if (streamed != null) return streamed;

    // 流里一个点都没有：可能是融合定位不可用，退回纯 GPS 再试一次
    final fallback = await _tryFix(
      forceGps: true,
      seconds: _gpsFallbackBudget.inSeconds,
    );
    if (fallback == null) return null;
    return (
      fallback.latitude,
      fallback.longitude,
      fallback.accuracy,
      fallback.heading,
    );
  }

  void _applyFix(
    double latitude,
    double longitude,
    double accuracy,
    double heading, {
    bool fly = true,
  }) {
    final raw = LatLng(latitude, longitude);
    _rawFix = raw;
    final point = MapCalibration.apply(raw);
    setState(() {
      _userLocation = point;
      _accuracyMeters = accuracy;
      _userHeading = heading > 0 ? heading : null;
    });
    if (!fly) return;

    final meters = _distance.as(LengthUnit.Meter, point, _campusCenter);
    final accuracyText = accuracy >= 1 ? '（精度约 ${accuracy.round()} 米）' : '';
    final poor = accuracy > 35;
    final calibrated = MapCalibration.active ? '，已套用校准' : '';
    if (meters <= 2500) {
      _flyTo(point, math.max(_zoom, 18.0));
      _toast(
        '已定位到当前位置$accuracyText$calibrated${poor ? '，建议到室外或开启 Wi-Fi 扫描' : ''}',
      );
    } else {
      // 地图只有校园范围，镜头不做无意义的越界移动
      _toast('当前不在上理主要校区范围内$accuracyText');
    }
  }

  /// 长按地图：把一个已知点存成校准样本（偏差 = 你指的位置 − 系统定位）。
  Future<void> _handleMapLongPress(LatLng point) async {
    final raw = _rawFix;
    final accuracy = _accuracyMeters;
    if (raw == null || accuracy == null) {
      _toast('先点右下角定位，拿到当前位置再校准');
      return;
    }
    if (accuracy > 25) {
      _toast('当前精度约 ${accuracy.round()} m，请到室外再校准');
      return;
    }

    // 吸附到最近的建筑轮廓顶点：角点是明确的几何点，比"门口"这种模糊区域可靠
    final snapped = _snapToBuildingCorner(point);
    final snapMeters = _distance.as(LengthUnit.Meter, point, snapped);
    final offsetMeters = _distance.as(
      LengthUnit.Meter,
      MapCalibration.apply(raw),
      snapped,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('校准定位偏移'),
        content: Text(
          '把这里设为你现在的真实位置？\n\n'
          '${snapMeters >= 0.5 ? '已吸附到最近的建筑角点（偏离你点的位置约 ${snapMeters.round()} 米）。\n\n' : ''}'
          '系统定位与这个点相差约 ${offsetMeters.round()} 米，'
          '校准后所有定位点都会按这个偏差修正。',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('校准'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await MapCalibration.add(
      MapCalibrationSample(
        gpsLat: raw.latitude,
        gpsLng: raw.longitude,
        mapLat: snapped.latitude,
        mapLng: snapped.longitude,
        accuracy: accuracy,
        savedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    setState(() => _userLocation = MapCalibration.apply(raw));
    _toast('已记录第 ${MapCalibration.count} 个校准点：${MapCalibration.describe()}');
  }

  /// 把地图上的点吸附到最近的建筑轮廓顶点（12 m 内），让标定点落在明确的角上。
  LatLng _snapToBuildingCorner(LatLng point) {
    final b = _posterBounds;
    final nx = (point.longitude - b.west) / (b.east - b.west);
    final ny = (b.north - point.latitude) / (b.north - b.south);
    if (nx < 0 || nx > 1 || ny < 0 || ny > 1) return point;

    var bestDistance = 0.012; // 归一化阈值，约 45 px / 11 m
    Offset? best;
    for (final shape in kCampusShapes) {
      for (final vertex in shape.points) {
        final d = (vertex - Offset(nx, ny)).distance;
        if (d < bestDistance) {
          bestDistance = d;
          best = vertex;
        }
      }
    }
    if (best == null) return point;
    return LatLng(
      b.north - best.dy * (b.north - b.south),
      b.west + best.dx * (b.east - b.west),
    );
  }

  // ---------------------------------------------------------------- 步行路线

  /// 从当前位置用 A* 算一条到目标楼的步行路线。
  void _routeTo(CampusLabel label) {
    final start = _userLocation;
    if (start == null) {
      _toast('先点右下角定位，才能从当前位置算路线');
      return;
    }
    if (!WalkGraph.isLoaded) {
      _toast('路网数据还在加载，稍后再试');
      return;
    }
    final target = LatLng(label.lat, label.lng);
    final route = WalkGraph.route(
      start,
      target,
      toNode: WalkGraph.connectorFor(label.name),
    );
    if (route == null) {
      _toast('没找到可走的路线');
      return;
    }
    setState(() => _route = route);
    _flyTo(
      LatLng(
        (start.latitude + target.latitude) / 2,
        (start.longitude + target.longitude) / 2,
      ),
      math.max(_zoom, 17.2),
    );
    _toast('步行 ${route.distanceText} · ${route.durationText}');
  }

  // ---------------------------------------------------------------- 路线采集

  Future<void> _startTrace() async {
    if (_recording) return;
    setState(() {
      _recording = true;
      _trace.clear();
      _traceStartedAt = DateTime.now();
      _route = null;
    });
    try {
      _traceSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 2,
            ),
          ).listen(
            (p) {
              if (!_recording) return;
              final point = LatLng(p.latitude, p.longitude);
              if (_trace.isEmpty ||
                  _distance.as(LengthUnit.Meter, _trace.last, point) > 2) {
                setState(() => _trace.add(point));
              }
            },
            onError: (_) {},
            cancelOnError: false,
          );
      _toast('开始记录路线，走完再点一次停止');
    } catch (_) {
      setState(() => _recording = false);
      _toast('无法开始记录，请检查定位权限');
    }
  }

  Future<void> _stopTrace() async {
    await _traceSubscription?.cancel();
    _traceSubscription = null;
    final points = List<LatLng>.from(_trace);
    final startedAt = _traceStartedAt ?? DateTime.now();
    setState(() {
      _recording = false;
      _trace.clear();
      _traceStartedAt = null;
    });

    if (points.length < 3) {
      _toast('轨迹太短，没有保存');
      return;
    }

    final from = await _pickBuilding('这次从哪里出发？', points.first);
    if (from == null) return;
    final to = await _pickBuilding('走到哪栋楼？', points.last);
    if (to == null) return;

    await MapTraces.add(
      MapTrace(
        fromName: from.name,
        toName: to.name,
        points: points,
        startedAt: startedAt,
      ),
    );
    if (!mounted) return;
    _toast('已保存：${from.name} → ${to.name}（${points.length} 个点）');
  }

  /// 轨迹端点吸附：按距离列出最近的几栋楼，让用户确认起终点。
  Future<CampusLabel?> _pickBuilding(String title, LatLng point) {
    final sorted = <CampusLabel>[...kCampusLabels]
      ..sort(
        (a, b) => _distance
            .as(LengthUnit.Meter, point, LatLng(a.lat, a.lng))
            .compareTo(
              _distance.as(LengthUnit.Meter, point, LatLng(b.lat, b.lng)),
            ),
      );
    final candidates = sorted.take(8).toList();
    if (candidates.isEmpty) return Future<CampusLabel?>.value();

    return showDialog<CampusLabel>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title, style: const TextStyle(fontSize: 15)),
        children: <Widget>[
          for (final label in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(label),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label.name,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                  Text(
                    '${_distance.as(LengthUnit.Meter, point, LatLng(label.lat, label.lng)).round()} m',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 13)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 2200),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
  }

  Future<void> _openExternalNavigation(CampusLabel label) async {
    final name = Uri.encodeComponent(label.name);
    final geoUri = Uri.parse(
      'geo:${label.lat},${label.lng}?q=${label.lat},${label.lng}($name)',
    );
    final amapUri = Uri.parse(
      'https://uri.amap.com/marker?position=${label.lng},${label.lat}&name=$name',
    );
    try {
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri);
      } else {
        await launchUrl(amapUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      _toast('无法拉起外部地图应用');
    }
  }

  // ---------------------------------------------------------------- 搜索

  bool _matches(String name, String query) {
    final n = name.replaceAll(RegExp(r'\s'), '');
    final q = query.replaceAll(RegExp(r'\s'), '');
    if (n.contains(q)) return true;

    // 简称：一教 → 第一教学楼，二食 → 第二食堂，三公 → 第三学生公寓
    final short = RegExp(r'^([0-9]{1,2}|[一二三四五六七八九十]{1,3})(教|食|公|宿|操)')
        .firstMatch(q);
    if (short != null) {
      final digit = short.group(1)!;
      final tail = switch (short.group(2)!) {
        '教' => '教学楼',
        '食' => '食堂',
        '公' || '宿' => '学生公寓',
        _ => '运动场',
      };
      final expanded = digit.replaceAllMapped(
        RegExp(r'[一二三四五六七八九十]'),
        (m) =>
            const {
              '一': '1',
              '二': '2',
              '三': '3',
              '四': '4',
              '五': '5',
              '六': '6',
              '七': '7',
              '八': '8',
              '九': '9',
              '十': '10',
            }[m.group(0)] ??
            m.group(0)!,
      );
      if (n.contains('第$expanded$tail') || n.contains('$expanded$tail')) {
        return true;
      }
    }
    return false;
  }

  List<CampusLabel> get _searchResults {
    final query = _query.trim();
    if (query.isEmpty) return const <CampusLabel>[];

    // 同名不同楼（如机械实验中心（二）的两栋）在地图上各留一个标签，
    // 搜索列表里只保留一条，避免出现两行完全一样的条目。
    final seen = <String>{};
    final matches = <CampusLabel>[
      for (final l in kCampusLabels)
        if (_matches(l.name, query) && seen.add(l.name)) l,
    ]..sort((a, b) => a.name.length.compareTo(b.name.length));

    final direct = placeForRoom(query);
    if (direct != null) {
      final hit = _labelByName(direct.name);
      if (hit != null && !matches.any((m) => m.name == hit.name)) {
        matches.insert(0, hit);
      }
    }
    return matches.take(8).toList();
  }

  // ---------------------------------------------------------------- 标签

  /// 校级地标：缩小时优先保住它们。
  static const Set<String> _landmarks = <String>{
    '图文信息中心',
    '大礼堂',
    '第一教学楼',
    '第三教学楼',
    '第四教学楼（逸兴楼）',
    '综合楼',
    '卓越楼',
    '北区运动场',
    '南区运动场',
    '第一食堂',
    '第二食堂',
    '国合楼（中德国际学院）',
    '军工路516号校门（正门）',
    '体育健身中心',
    '音乐堂',
    '思晏堂',
    '大草坪',
    '沪江文化园',
    '红塔（沪江大学水塔）',
    '先进制造大楼',
  };

  static bool _isMajor(String name) =>
      name.contains('教学楼') ||
      name.contains('食堂') ||
      name.contains('公寓') ||
      name.contains('宿舍') ||
      name.contains('校门') ||
      name.contains('运动场') ||
      name.contains('图书馆') ||
      name.contains('图文');

  int _priority(CampusLabel label) {
    if (_landmarks.contains(label.name)) return 0;
    if (_isMajor(label.name)) return 1;
    return 2;
  }

  static bool _isSame(CampusLabel a, CampusLabel b) =>
      a.name == b.name && a.lat == b.lat && a.lng == b.lng;

  /// 只有一套标签样式：低于阈值整体隐藏，之后按重要度贪心避让，能放多少放多少。
  List<Marker> _buildLabelMarkers() {
    final camera = _camera;
    if (!_showLabels || camera == null || _zoom < _labelMinZoom) {
      return const <Marker>[];
    }

    // 刚过阈值时半透明渐显，避免标签突然跳出来
    final fade = ((_zoom - _labelMinZoom) / 0.35).clamp(0.0, 1.0);

    final screen = MediaQuery.sizeOf(context);
    // 顶部搜索栏与底部按钮/详情卡会盖住地图，别在这些区域放标签
    final viewport = Rect.fromLTRB(
      8,
      116,
      screen.width - 8,
      screen.height - 96,
    );
    final candidates =
        <CampusLabel>[
          for (final l in kCampusLabels)
            if (camera.visibleBounds.contains(LatLng(l.lat, l.lng))) l,
        ]..sort((a, b) {
          final p = _priority(a).compareTo(_priority(b));
          if (p != 0) return p;
          return a.name.length.compareTo(b.name.length);
        });

    final gap = _zoom >= 18.2 ? 1.0 : 3.0;
    const chipHeight = 20.0;
    final taken = <Rect>[];
    final markers = <Marker>[];
    for (final label in candidates) {
      final isSelected = _selected != null && _isSame(_selected!, label);
      final point = LatLng(label.lat, label.lng);
      final offset = camera.latLngToScreenOffset(point);
      final width = 14.0 + label.name.length * 9.4;

      // 位置固定钉在锚点上，缩放时绝不上下跳；挤不下就整体让位（宁可少显示一个）
      final rect = Rect.fromCenter(
        center: offset,
        width: width,
        height: chipHeight,
      );
      if (!isSelected) {
        if (!viewport.overlaps(rect)) continue;
        if (taken.any((t) => t.overlaps(rect.inflate(gap)))) continue;
      }
      taken.add(rect);
      markers.add(
        Marker(
          point: point,
          width: width,
          height: chipHeight,
          alignment: Alignment.center,
          child: Opacity(
            opacity: isSelected ? 1 : fade,
            child: _LabelChip(
              label: label,
              selected: isSelected,
              onTap: () => _focusLabel(label),
            ),
          ),
        ),
      );
      if (markers.length >= 90) break;
    }
    return markers;
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    if (!kMapFeatureEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('校园地图'), centerTitle: true),
        body: const Center(child: Text('校园地图功能维护中')),
      );
    }

    final selected = _selected;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: _buildMap()),
            Positioned(left: 0, right: 0, top: 0, child: _buildTopBar()),
            if (_query.isNotEmpty)
              Positioned(
                left: 14,
                right: 14,
                top: 108,
                child: _buildSearchResults(),
              ),
            if (_recording)
              Positioned(
                left: 0,
                right: 0,
                top: 104,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.usstRed.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '记录中 · ${_trace.length} 个点 · 再点一次停止',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 14,
              bottom: selected == null ? 24 : 172,
              child: _buildActionButtons(),
            ),
            if (selected != null)
              Positioned(
                left: 14,
                right: 14,
                bottom: 16,
                child: _buildDetailCard(selected),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        // 同时给 center/zoom 会让 initialCameraFit 失效，这里只用 fit
        initialCameraFit: CameraFit.bounds(
          bounds: _campusBounds,
          padding: _fitPadding,
        ),
        minZoom: _minZoom,
        maxZoom: _maxZoom,
        // 边界用软回弹实现（见 _handlePosition）：不用 CameraConstraint，
        // 那个在每次 rebuild 时都会触发 flutter_map 的 debug 断言。
        backgroundColor: Colors.white,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: _handleReady,
        onPositionChanged: _handlePosition,
        onTap: (_, point) => _handleMapTap(point),
        onLongPress: (_, point) => _handleMapLongPress(point),
      ),
      children: <Widget>[
        OverlayImageLayer(overlayImages: _baseOverlays),
        if (_userLocation != null && (_accuracyMeters ?? 0) > 0)
          CircleLayer(
            circles: <CircleMarker>[
              CircleMarker(
                point: _userLocation!,
                radius: _accuracyMeters!,
                useRadiusInMeter: true,
                color: const Color(0x1A1976D2),
                borderColor: const Color(0x661976D2),
                borderStrokeWidth: 1,
              ),
            ],
          ),
        MarkerLayer(markers: _buildLabelMarkers()),
        if (_route != null)
          PolylineLayer(
            polylines: <Polyline>[
              Polyline(
                points: _route!.points,
                strokeWidth: 4,
                color: AppColors.usstRed,
                borderStrokeWidth: 1.5,
                borderColor: Colors.white,
              ),
            ],
          ),
        if (_trace.length > 1)
          PolylineLayer(
            polylines: <Polyline>[
              Polyline(
                points: _trace,
                strokeWidth: 4,
                color: const Color(0xFF1565C0),
              ),
            ],
          ),
        if (_userLocation != null)
          MarkerLayer(markers: <Marker>[_buildUserMarker()]),
      ],
    );
  }

  Marker _buildUserMarker() {
    final heading = _userHeading;
    return Marker(
      point: _userLocation!,
      width: 34,
      height: 34,
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: Color(0x332196F3),
              shape: BoxShape.circle,
            ),
          ),
          if (heading != null)
            Transform.rotate(
              angle: heading * math.pi / 180,
              child: const Icon(
                Icons.navigation,
                size: 16,
                color: AppColors.info,
              ),
            ),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.info,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Color(0x33000000), blurRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final canPop = Navigator.of(context).canPop();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (canPop) ...<Widget>[
                _roundButton(
                  icon: Icons.arrow_back,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
              ],
              const Text(
                '校园地图',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              _roundButton(
                icon: _showLabels ? Icons.label : Icons.label_off_outlined,
                onTap: () {
                  setState(() => _showLabels = !_showLabels);
                  _toast(_showLabels ? '已显示地点标签' : '已隐藏地点标签');
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildSearchBar(),
        ],
      ),
    );
  }

  Widget _roundButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: '搜索教学楼、食堂、宿舍、教室号…',
          hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          prefixIcon: const Icon(
            Icons.search,
            size: 18,
            color: AppColors.textSecondary,
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
        onChanged: (value) => setState(() => _query = value.trim()),
      ),
    );
  }

  Widget _buildSearchResults() {
    final results = _searchResults;
    if (results.isEmpty) {
      return _panel(
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: Text(
              '没有找到相关地点',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }
    return _panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final label in results)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(
                Icons.place_outlined,
                size: 18,
                color: AppColors.usstRed,
              ),
              title: Text(label.name, style: const TextStyle(fontSize: 13.5)),
              subtitle: Text(
                _categoryOf(label.name),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              onTap: () => _focusLabel(label),
            ),
        ],
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 4,
      child: ClipRRect(borderRadius: BorderRadius.circular(14), child: child),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FloatingActionButton.small(
          heroTag: 'map-record',
          backgroundColor: _recording ? AppColors.usstRed : Colors.white,
          foregroundColor: _recording ? Colors.white : AppColors.textPrimary,
          elevation: 3,
          onPressed: _recording ? _stopTrace : _startTrace,
          child: Icon(
            _recording ? Icons.stop : Icons.radio_button_checked,
            size: 20,
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          // 长按定位键进入定位诊断（隐藏入口，不打扰日常使用）
          onLongPress: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MapDiagnosticsPage()),
          ),
          child: FloatingActionButton.small(
            heroTag: 'map-locate',
            backgroundColor: Colors.white,
            foregroundColor: _userLocation != null
                ? AppColors.usstRed
                : AppColors.textPrimary,
            elevation: 3,
            onPressed: _locateUser,
            child: _locating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.usstRed,
                    ),
                  )
                : const Icon(Icons.my_location, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailCard(CampusLabel label) {
    String? distanceText;
    final user = _userLocation;
    if (user != null) {
      final meters = _distance.as(
        LengthUnit.Meter,
        user,
        LatLng(label.lat, label.lng),
      );
      distanceText = meters >= 1000
          ? '距您约 ${(meters / 1000).toStringAsFixed(1)} km'
          : '距您约 ${meters.toStringAsFixed(0)} 米';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.redTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.place,
                  size: 20,
                  color: AppColors.usstRed,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      distanceText == null
                          ? _categoryOf(label.name)
                          : '${_categoryOf(label.name)} · $distanceText',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _selected = null),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_route != null) ...<Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.directions_walk,
                  size: 15,
                  color: AppColors.usstRed,
                ),
                const SizedBox(width: 6),
                Text(
                  '步行 ${_route!.distanceText} · ${_route!.durationText}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.usstRed,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _route = null),
                  child: const Text(
                    '清除',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _routeTo(label),
                  icon: const Icon(Icons.directions_walk, size: 16),
                  label: const Text('走过去', style: TextStyle(fontSize: 12.5)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.usstRed,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openExternalNavigation(label),
                  icon: const Icon(Icons.directions_outlined, size: 16),
                  label: const Text('导航到此处', style: TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.usstRed,
                    side: const BorderSide(color: AppColors.usstRed, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _categoryOf(String name) {
    if (name.contains('食堂') || name.contains('餐厅')) return '食堂餐饮';
    if (name.contains('宿舍') || name.contains('公寓')) return '宿舍公寓';
    if (name.contains('图文') || name.contains('图书') || name.contains('档案馆')) {
      return '图书自习';
    }
    if (name.contains('运动场') || name.contains('体育') || name.contains('球场')) {
      return '运动场馆';
    }
    if (name.contains('校门') || name.contains('门）') || name.contains('大门')) {
      return '校门';
    }
    if (name.contains('教学楼') || name.contains('学院') || name.contains('实验')) {
      return '教学楼';
    }
    return '校园地点';
  }
}

/// 屏幕空间标签：白底红边小圆角，选中时反色。
class _LabelChip extends StatelessWidget {
  const _LabelChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final CampusLabel label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 20,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.usstRed
                : Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected
                  ? Colors.white
                  : AppColors.usstRed.withValues(alpha: 0.45),
              width: selected ? 1.2 : 0.8,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            label.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              height: 1.1,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
