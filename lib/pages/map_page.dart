import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../data/geo/campus_config.dart';
import '../data/illustrated_map/campus_516_buildings.dart';
import '../data/illustrated_map/campus_building.dart';
import '../data/map_focus.dart';
import '../data/vector_map/models.dart';
import '../data/vector_map/vector_campus_repository.dart';
import '../data/vector_map/vector_map_style.dart';
import '../widgets/illustrated_campus_view.dart';
import 'classroom_query_page.dart';

/// 校园地图：军工路 516 号校区融合 2D 平面与 2.5D 鸟瞰双视角高清手绘矢量底图，
/// 1100 号南校区、复兴路与营口路融合轻量几何矢量体系，支持全校建筑精准对焦、
/// 课表双击联动与空教室快捷直达。
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<IllustratedCampusViewState> _illustratedViewKey =
      GlobalKey<IllustratedCampusViewState>();

  Campus _currentCampus = CampusData.jungong516;
  CampusCategory _selectedCategory = CampusCategory.all;
  MapViewMode _mapViewMode = MapViewMode.flat;
  String _query = '';

  CampusPoi? _selectedPoi;
  CampusPoi? _pendingPoi;
  BuildingFeature? _selectedBuilding;
  CampusBuilding? _selectedIllustratedBuilding;

  // 516 校区模式：false 为精细手绘矢量地图，true 为高德街道/实景底图
  bool _useHdOnline = false;
  bool _mapReady = false;
  double _currentZoom = 16.8;

  // 定位状态
  LatLng? _userLocation;
  bool _locating = false;
  double? _userHeading;

  @override
  void initState() {
    super.initState();
    MapFocus.target.addListener(_onFocusTarget);
    _checkInitialFocus();
  }

  @override
  void dispose() {
    MapFocus.target.removeListener(_onFocusTarget);
    _mapController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _checkInitialFocus() {
    final target = MapFocus.target.value;
    if (target != null) {
      _applyFocusTarget(target.name);
      MapFocus.consume();
    }
  }

  void _onFocusTarget() {
    final target = MapFocus.target.value;
    if (target == null) return;
    _applyFocusTarget(target.name);
    MapFocus.consume();
  }

  void _applyFocusTarget(String roomOrBuildingName) {
    // 1. 优先在 516 号校区手绘数据库中查找
    final bld516 = Campus516Data.findBuilding(roomOrBuildingName);
    if (bld516 != null) {
      setState(() {
        _currentCampus = CampusData.jungong516;
        _useHdOnline = false;
      });
      _selectIllustratedBuilding(bld516);
      return;
    }

    // 2. 查找矢量数据库及全校 POI 表
    final bld = VectorCampusRepository.buildingForRoom(roomOrBuildingName);
    final poi = bld?.toPoi() ??
        CampusData.poiForRoom(roomOrBuildingName) ??
        CampusData.search(query: roomOrBuildingName).firstOrNull;

    if (poi != null) {
      if (_currentCampus.id == 'jungong516' && !_useHdOnline) {
        // 尝试反向对应到 516 手绘建筑
        final matchedBld = Campus516Data.findBuilding(poi.name);
        if (matchedBld != null) {
          _selectIllustratedBuilding(matchedBld);
          return;
        }
      }

      if (_mapReady) {
        _selectPoi(poi);
      } else {
        _pendingPoi = poi;
      }
    }
  }

  CampusPoi _buildingToPoi(CampusBuilding b) {
    final existing = CampusData.pois.firstWhere(
      (p) => p.name == b.name && p.campusId == 'jungong516',
      orElse: () => CampusData.pois.firstWhere(
        (p) => p.aliases.contains(b.name) && p.campusId == 'jungong516',
        orElse: () => CampusPoi(
          name: b.name,
          campusId: 'jungong516',
          location: LatLng(
            31.2965 - (b.flatLabel.dy * (31.2965 - 31.2870)),
            121.5470 + (b.flatLabel.dx * (121.5590 - 121.5470)),
          ),
          category: b.campusCategory,
          subtitle: '${b.category} · ${b.floors}层',
          aliases: b.aliases,
        ),
      ),
    );
    return existing;
  }

  void _selectIllustratedBuilding(CampusBuilding b) {
    final poi = _buildingToPoi(b);
    setState(() {
      _selectedIllustratedBuilding = b;
      _selectedPoi = poi;
      _selectedBuilding = VectorCampusRepository.buildingForRoom(b.name);
      _query = '';
      _searchController.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _illustratedViewKey.currentState?.focusBuilding(b, animate: true);
    });
  }

  /// 平滑飞行移动镜头 (FlutterMap 矢量校区)
  void _animatedMapMove(LatLng destLocation, double destZoom) {
    if (!_mapReady) {
      _pendingPoi = _selectedPoi;
      return;
    }

    final camera = _mapController.camera;
    final latTween = Tween<double>(
      begin: camera.center.latitude,
      end: destLocation.latitude,
    );
    final lngTween = Tween<double>(
      begin: camera.center.longitude,
      end: destLocation.longitude,
    );
    final zoomTween = Tween<double>(
      begin: camera.zoom,
      end: destZoom,
    );

    final controller = AnimationController(
      duration: const Duration(milliseconds: 380),
      vsync: this,
    );
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

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  void _selectPoi(CampusPoi poi) {
    setState(() {
      _selectedPoi = poi;
      _selectedBuilding = VectorCampusRepository.buildingForRoom(poi.name);
      _query = '';
      _searchController.clear();
      final matchedCampus = CampusData.allCampuses.firstWhere(
        (c) => c.id == poi.campusId,
        orElse: () => _currentCampus,
      );
      _currentCampus = matchedCampus;
    });

    if (_currentCampus.id == 'jungong516' && !_useHdOnline) {
      final bld516 = Campus516Data.findBuilding(poi.name);
      if (bld516 != null) {
        _selectIllustratedBuilding(bld516);
        return;
      }
    }

    _animatedMapMove(poi.location, 17.5);
  }

  void _selectBuilding(BuildingFeature building) {
    setState(() {
      _selectedBuilding = building;
      _selectedPoi = building.toPoi();
      _query = '';
      _searchController.clear();
      final matchedCampus = CampusData.allCampuses.firstWhere(
        (c) => c.id == building.campusId,
        orElse: () => _currentCampus,
      );
      _currentCampus = matchedCampus;
    });
    _animatedMapMove(building.center, 17.5);
  }

  void _switchCampus(Campus campus) {
    setState(() {
      _currentCampus = campus;
      _selectedPoi = null;
      _selectedBuilding = null;
      _selectedIllustratedBuilding = null;
    });
    if (campus.id != 'jungong516' || _useHdOnline) {
      _animatedMapMove(campus.center, campus.defaultZoom);
    }
  }

  /// 智能申请权限并获取 GPS 实时定位
  Future<void> _locateUser() async {
    if (_locating) return;
    setState(() => _locating = true);

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _toast('定位权限已被永久禁用，请在手机应用设置中允许');
        await Geolocator.openAppSettings();
        return;
      }
      if (permission == LocationPermission.denied) {
        _toast('未授予位置权限，无法获取实时定位');
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('系统 GPS/位置服务未开启，请先打开定位开关');
        await Geolocator.openLocationSettings();
        return;
      }

      try {
        final last = await Geolocator.getLastKnownPosition(
          forceAndroidLocationManager: true,
        );
        if (last != null && _isUsablePosition(last)) {
          _applyPosition(last);
        }
      } catch (_) {}

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 12),
          forceLocationManager: true,
        ),
      );
      _applyPosition(pos);
    } catch (e) {
      _toast('获取定位失败，请确保开启了系统定位服务');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  bool _isUsablePosition(Position p) {
    final age = DateTime.now().difference(p.timestamp);
    return !age.isNegative && age <= const Duration(minutes: 5) && p.accuracy <= 100;
  }

  void _applyPosition(Position pos) {
    final userPos = LatLng(pos.latitude, pos.longitude);
    setState(() {
      _userLocation = userPos;
      _userHeading = pos.heading > 0 ? pos.heading : null;
    });

    final nearby = CampusData.nearestCampus(userPos);
    const distanceCalc = Distance();
    final meters = distanceCalc.as(LengthUnit.Meter, userPos, nearby.center);

    if (meters < 2000) {
      if (_currentCampus.id != nearby.id) {
        _switchCampus(nearby);
      }
      _animatedMapMove(userPos, 17.5);
      _toast('已定位至 ${nearby.shortName}');
    } else {
      _animatedMapMove(userPos, 16.5);
      _toast('当前定位不在上理主要校区范围内');
    }
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
  }

  Future<void> _openExternalNavigation(CampusPoi poi) async {
    final lat = poi.location.latitude;
    final lng = poi.location.longitude;
    final name = Uri.encodeComponent(poi.name);

    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($name)');
    final amapWebUri = Uri.parse(
      'https://uri.amap.com/marker?position=$lng,$lat&name=$name',
    );

    try {
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri);
      } else {
        await launchUrl(amapWebUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      _toast('无法拉起外部地图应用');
    }
  }

  int _lodForZoom(double zoom) {
    if (zoom < 16.3) return 1;
    if (zoom < 17.6) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final is516Illustrated = _currentCampus.id == 'jungong516' && !_useHdOnline;

    final searchResults = _query.isEmpty
        ? const <CampusPoi>[]
        : () {
            if (is516Illustrated) {
              final queryLower = _query.toLowerCase();
              final matches = Campus516Data.buildings.where((b) {
                if (_selectedCategory != CampusCategory.all &&
                    b.campusCategory != _selectedCategory) {
                  return false;
                }
                if (b.name.toLowerCase().contains(queryLower)) return true;
                return b.aliases.any((a) => a.toLowerCase().contains(queryLower));
              }).toList();

              return matches.map((b) => _buildingToPoi(b)).toList();
            }

            final vectorMatches = VectorCampusRepository.search(
              query: _query,
              campusId: _currentCampus.id,
              category: _selectedCategory,
            ).map((b) => b.toPoi()).toList();
            if (vectorMatches.isNotEmpty) return vectorMatches;
            return CampusData.search(
              query: _query,
              campusId: _currentCampus.id,
              category: _selectedCategory,
            );
          }();

    return Scaffold(
      backgroundColor: VectorMapStyle.mapBackground,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            // 1. 核心底图与多边形矢量渲染层
            Positioned.fill(
              child: is516Illustrated
                  ? IllustratedCampusView(
                      key: _illustratedViewKey,
                      mode: _mapViewMode,
                      selectedBuilding: _selectedIllustratedBuilding,
                      activeCategory: _selectedCategory,
                      onBuildingSelected: (b) {
                        if (b != null) {
                          _selectIllustratedBuilding(b);
                        } else {
                          setState(() {
                            _selectedIllustratedBuilding = null;
                            _selectedPoi = null;
                            _selectedBuilding = null;
                          });
                        }
                      },
                    )
                  : _buildMap(),
            ),

            // 2. 顶部综合栏（校区切换、搜索框、分类标签与建筑物横向筛选）
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _buildHeader(is516Illustrated),
                  _buildSearchBar(),
                  _buildCategoryChips(),
                  if (_selectedCategory != CampusCategory.all)
                    _buildBuildingQuickSelector(is516Illustrated),
                ],
              ),
            ),

            // 3. 搜索结果浮层
            if (_query.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                top: 104,
                child: _buildSearchResults(searchResults),
              ),

            // 4. 右下角快捷按钮群（视角切换、定位、复位视角）
            Positioned(
              right: 14,
              bottom: _selectedPoi == null ? 24 : 165,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 516 号专属：2D 平面 / 2.5D 鸟瞰平滑视角切换胶囊
                  if (is516Illustrated) ...<Widget>[
                    FloatingActionButton.extended(
                      heroTag: 'map-view-toggle',
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.usstRed,
                      elevation: 3,
                      icon: Icon(_mapViewMode.icon, size: 18),
                      label: Text(
                        _mapViewMode.label,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () {
                        setState(() {
                          _mapViewMode = _mapViewMode == MapViewMode.flat
                              ? MapViewMode.isometric
                              : MapViewMode.flat;
                        });
                        _toast(_mapViewMode == MapViewMode.flat
                            ? '已切换至 2D 平面手绘图'
                            : '已切换至 2.5D 鸟瞰立体图');
                      },
                    ),
                    const SizedBox(height: 10),
                  ],

                  FloatingActionButton.small(
                    heroTag: 'map-location',
                    backgroundColor: Colors.white,
                    foregroundColor:
                        _userLocation != null ? AppColors.usstRed : AppColors.textPrimary,
                    elevation: 3,
                    onPressed: _locateUser,
                    child: _locating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2, color: AppColors.usstRed),
                          )
                        : const Icon(Icons.my_location, size: 20),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    heroTag: 'map-reset',
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 3,
                    onPressed: () {
                      if (is516Illustrated) {
                        setState(() {
                          _selectedIllustratedBuilding = null;
                          _selectedPoi = null;
                          _selectedBuilding = null;
                        });
                        _toast('已重置回校园全景');
                      } else {
                        _animatedMapMove(_currentCampus.center, _currentCampus.defaultZoom);
                      }
                    },
                    child: const Icon(Icons.center_focus_strong, size: 20),
                  ),
                ],
              ),
            ),

            // 5. 底部选中地点详细卡片
            if (_selectedPoi != null)
              Positioned(
                left: 14,
                right: 14,
                bottom: 16,
                child: _buildPoiDetailCard(_selectedPoi!),
              ),
          ],
        ),
      ),
    );
  }

  /// 地图核心组件：集成地貌多边形、建筑外轮廓、自适应 LOD 矢量标注与点击交互
  Widget _buildMap() {
    final grounds = VectorCampusRepository.groundsForCampus(_currentCampus.id);
    final campusBuildings = VectorCampusRepository.buildingsForCampus(
      _currentCampus.id,
      category: _selectedCategory,
    );

    final lod = _lodForZoom(_currentZoom);
    final markers = <Marker>[];

    final List<BuildingFeature> visibleBuildings;
    if (_selectedCategory != CampusCategory.all) {
      visibleBuildings = campusBuildings;
    } else if (lod == 1) {
      visibleBuildings = campusBuildings
          .where((b) => b.importance >= 2 || b.id == _selectedBuilding?.id)
          .toList();
    } else {
      visibleBuildings = campusBuildings;
    }

    for (final b in visibleBuildings) {
      final isSelected = _selectedBuilding?.id == b.id || _selectedPoi?.name == b.name;
      markers.add(
        Marker(
          point: b.center,
          width: isSelected ? 120 : 105,
          height: 44,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => _selectBuilding(b),
            child: _buildBuildingBadge(b, isSelected, lod),
          ),
        ),
      );
    }

    if (lod == 3 && _selectedBuilding != null && _selectedBuilding!.entrances.isNotEmpty) {
      for (final ent in _selectedBuilding!.entrances) {
        markers.add(
          Marker(
            point: ent.location,
            width: 100,
            height: 28,
            alignment: Alignment.center,
            child: _buildEntranceBadge(ent),
          ),
        );
      }
    }

    if (_userLocation != null) {
      markers.add(
        Marker(
          point: _userLocation!,
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0x332196F3),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFF1976D2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x33000000), blurRadius: 4),
                  ],
                ),
              ),
              if (_userHeading != null)
                Transform.rotate(
                  angle: (_userHeading! * math.pi) / 180,
                  child: const Icon(
                    Icons.navigation,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final initialCenter = _selectedPoi?.location ?? _currentCampus.center;
    final initialZoom = _selectedPoi != null ? 17.5 : _currentCampus.defaultZoom;

    final groundPolygons = <Polygon>[
      for (final g in grounds)
        Polygon(
          points: g.points,
          color: _groundFillColor(g.type),
          borderColor: _groundStrokeColor(g.type),
          borderStrokeWidth: _groundStrokeWidth(g.type),
        ),
    ];

    final buildingPolygons = <Polygon>[
      for (final b in campusBuildings)
        Polygon(
          points: b.points,
          color: _selectedBuilding?.id == b.id || _selectedPoi?.name == b.name
              ? VectorMapStyle.selectedBuildingFill
              : VectorMapStyle.buildingFill(b.category),
          borderColor: _selectedBuilding?.id == b.id || _selectedPoi?.name == b.name
              ? VectorMapStyle.selectedBuildingStroke
              : VectorMapStyle.buildingStroke(b.category),
          borderStrokeWidth: _selectedBuilding?.id == b.id || _selectedPoi?.name == b.name
              ? VectorMapStyle.selectedStrokeWidth
              : VectorMapStyle.defaultStrokeWidth,
        ),
    ];

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: initialZoom,
        minZoom: 13.5,
        maxZoom: 19.5,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onPositionChanged: (camera, hasGesture) {
          if ((camera.zoom - _currentZoom).abs() > 0.4) {
            setState(() {
              _currentZoom = camera.zoom;
            });
          }
        },
        onMapReady: () {
          _mapReady = true;
          if (_pendingPoi != null) {
            final p = _pendingPoi!;
            _pendingPoi = null;
            _selectPoi(p);
          }
        },
        onTap: (_, point) {
          final allBlds = VectorCampusRepository.buildingsForCampus(_currentCampus.id);
          BuildingFeature? hit;
          for (final b in allBlds) {
            if (_isPointInPolygon(point, b.points)) {
              hit = b;
              break;
            }
          }

          if (hit != null) {
            _selectBuilding(hit);
          } else {
            if (_query.isNotEmpty) {
              setState(() => _query = '');
              _searchController.clear();
            }
          }
        },
      ),
      children: <Widget>[
        if (_useHdOnline)
          TileLayer(
            urlTemplate:
                'https://wprd01.is.autonavi.com/appmaptile?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scale=2&style=7',
            tileDimension: 512,
            zoomOffset: -1,
            minZoom: 13.5,
            maxZoom: 19.5,
            maxNativeZoom: 19,
            keepBuffer: 3,
            fallbackUrl: 'assets/tiles/{z}_{x}_{y}.png',
          ),
        PolygonLayer(polygons: groundPolygons),
        PolygonLayer(polygons: buildingPolygons),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Color _groundFillColor(GroundType type) {
    switch (type) {
      case GroundType.campusGround:
        return _useHdOnline ? const Color(0x33F9FAF8) : VectorMapStyle.campusGroundFill;
      case GroundType.water:
        return VectorMapStyle.waterFill;
      case GroundType.lawn:
        return VectorMapStyle.lawnFill;
      case GroundType.sportsTrack:
        return VectorMapStyle.sportsTrackFill;
    }
  }

  Color _groundStrokeColor(GroundType type) {
    switch (type) {
      case GroundType.campusGround:
        return VectorMapStyle.campusGroundStroke;
      case GroundType.water:
        return VectorMapStyle.waterStroke;
      case GroundType.lawn:
        return VectorMapStyle.lawnStroke;
      case GroundType.sportsTrack:
        return VectorMapStyle.sportsTrackStroke;
    }
  }

  double _groundStrokeWidth(GroundType type) {
    switch (type) {
      case GroundType.campusGround:
        return 1.4;
      case GroundType.water:
        return 1.2;
      case GroundType.lawn:
        return 0.8;
      case GroundType.sportsTrack:
        return 1.0;
    }
  }

  Widget _buildBuildingBadge(BuildingFeature b, bool isSelected, int lod) {
    final cat = b.category;
    final isOverview = lod == 1 && _selectedCategory == CampusCategory.all;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isOverview ? 5.0 : 6.0,
            vertical: isOverview ? 2.0 : 3.0,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.usstRed
                : isOverview
                    ? const Color(0xF7FFFFFF)
                    : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? Colors.white
                  : isOverview
                      ? AppColors.usstRed.withValues(alpha: 0.6)
                      : VectorMapStyle.buildingStroke(cat),
              width: isSelected ? 1.4 : 1.0,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x24000000), blurRadius: 4, offset: Offset(0, 1.5)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                cat.icon,
                size: isOverview ? 9.5 : 11,
                color: isSelected ? Colors.white : AppColors.usstRed,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  b.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isOverview ? 9.0 : 10.0,
                    fontWeight: isSelected || isOverview ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.arrow_drop_down,
          size: 13,
          color: isSelected
              ? AppColors.usstRed
              : (isOverview ? const Color(0xF7FFFFFF) : Colors.white),
        ),
      ],
    );
  }

  Widget _buildEntranceBadge(BuildingEntrance ent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: ent.hasStairs ? const Color(0xFFD9381E) : const Color(0xFF137333),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            ent.hasStairs ? Icons.stairs_outlined : Icons.door_front_door_outlined,
            size: 10,
            color: Colors.white,
          ),
          const SizedBox(width: 2),
          Text(
            ent.name.replaceAll(RegExp(r'.*教|.*楼'), ''),
            style: const TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部栏：返回按钮、校区切换选择器与街道/纯净手绘模式切换
  Widget _buildHeader(bool is516Illustrated) {
    final canPop = Navigator.of(context).canPop();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(
        children: <Widget>[
          if (canPop) ...<Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
          ],
          const Text(
            '校园地图',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),

          // 4 大校区自由切换下拉
          PopupMenuButton<Campus>(
            initialValue: _currentCampus,
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: _switchCampus,
            itemBuilder: (context) => CampusData.allCampuses
                .map(
                  (c) => PopupMenuItem<Campus>(
                    value: c,
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.location_city,
                          size: 17,
                          color: c.id == _currentCampus.id
                              ? AppColors.usstRed
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          c.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                c.id == _currentCampus.id ? FontWeight.w700 : FontWeight.normal,
                            color:
                                c.id == _currentCampus.id ? AppColors.usstRed : AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E5E5)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Color(0x10000000), blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _currentCampus.shortName,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          const Spacer(),

          // 516 号专属切换底图：高清手绘 vs 真实街道底图
          if (_currentCampus.id == 'jungong516')
            GestureDetector(
              onTap: () {
                setState(() => _useHdOnline = !_useHdOnline);
                _toast(_useHdOnline ? '已开启周边街道底图' : '已切换至经典手绘图');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _useHdOnline ? const Color(0xFFEBF5FE) : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _useHdOnline ? const Color(0xFF90CAF9) : const Color(0xFFE0E0E0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      _useHdOnline ? Icons.layers_outlined : Icons.brush_outlined,
                      size: 13,
                      color: _useHdOnline ? const Color(0xFF1976D2) : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _useHdOnline ? '街道底图' : '经典手绘',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _useHdOnline ? const Color(0xFF1976D2) : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 搜索框
  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8E8E8)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x0C000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: '搜索${_currentCampus.shortName}建筑、教学楼、教室...',
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
          prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
        onChanged: (val) => setState(() => _query = val.trim()),
      ),
    );
  }

  /// 分类筛选 Chips
  Widget _buildCategoryChips() {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: CampusCategory.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final cat = CampusCategory.values[index];
          final isSelected = _selectedCategory == cat;

          return FilterChip(
            selected: isSelected,
            showCheckmark: false,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  cat.icon,
                  size: 13,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  cat.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            selectedColor: AppColors.usstRed,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isSelected ? AppColors.usstRed : const Color(0xFFE2E2E2),
                width: 0.8,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) {
              setState(() {
                _selectedCategory = cat;
                _selectedPoi = null;
                _selectedBuilding = null;
                _selectedIllustratedBuilding = null;
              });
            },
          );
        },
      ),
    );
  }

  /// 建筑物快捷横向列表（当选中分类时展开）
  Widget _buildBuildingQuickSelector(bool is516Illustrated) {
    if (is516Illustrated) {
      final buildings = Campus516Data.buildings
          .where((b) => b.campusCategory == _selectedCategory && b.name != '未命名建筑')
          .toList();

      if (buildings.isEmpty) return const SizedBox.shrink();

      return Container(
        height: 32,
        margin: const EdgeInsets.only(top: 4),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: buildings.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            final b = buildings[i];
            final isSelected = _selectedIllustratedBuilding?.id == b.id;

            return ActionChip(
              label: Text(
                b.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
              backgroundColor: isSelected ? AppColors.usstRed : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isSelected ? AppColors.usstRed : const Color(0xFFE0E0E0),
                  width: 0.8,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onPressed: () => _selectIllustratedBuilding(b),
            );
          },
        ),
      );
    }

    final buildings = VectorCampusRepository.buildingsForCampus(
      _currentCampus.id,
      category: _selectedCategory,
    );

    if (buildings.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 32,
      margin: const EdgeInsets.only(top: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: buildings.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final b = buildings[i];
          final isSelected = _selectedBuilding?.id == b.id || _selectedPoi?.name == b.name;

          return ActionChip(
            label: Text(
              b.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            backgroundColor: isSelected ? AppColors.usstRed : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: isSelected ? AppColors.usstRed : const Color(0xFFE0E0E0),
                width: 0.8,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onPressed: () => _selectBuilding(b),
          );
        },
      ),
    );
  }

  /// 搜索结果浮层
  Widget _buildSearchResults(List<CampusPoi> results) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: results.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    '未找到匹配地点，请尝试输入简称如「一教」「卓越」「五食」',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: results.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final poi = results[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(poi.category.icon, size: 18, color: AppColors.usstRed),
                    title: Text(
                      poi.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: poi.subtitle != null
                        ? Text(
                            poi.subtitle!,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          )
                        : null,
                    trailing: const Icon(Icons.arrow_forward_ios,
                        size: 12, color: AppColors.textSecondary),
                    onTap: () => _selectPoi(poi),
                  );
                },
              ),
      ),
    );
  }

  /// 选中地点详细卡片（带空教室直达、出入口就近指示与外部导航）
  Widget _buildPoiDetailCard(CampusPoi poi) {
    String? distanceText;
    if (_userLocation != null) {
      const distanceCalc = Distance();
      final meters = distanceCalc.as(LengthUnit.Meter, _userLocation!, poi.location);
      distanceText = meters >= 1000
          ? '距您约 ${(meters / 1000).toStringAsFixed(1)} km'
          : '距您约 ${meters.toStringAsFixed(0)} 米';
    }

    final isTeachingBuilding = poi.category == CampusCategory.teaching;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x24000000), blurRadius: 14, offset: Offset(0, 4)),
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
                child: Icon(poi.category.icon, size: 20, color: AppColors.usstRed),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      poi.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        Text(
                          _currentCampus.shortName,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                        if (distanceText != null) ...<Widget>[
                          const Text(' · ', style: TextStyle(color: AppColors.textSecondary)),
                          Text(
                            distanceText,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.usstRed,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (poi.subtitle != null) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        poi.subtitle!,
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF666666)),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() {
                  _selectedPoi = null;
                  _selectedBuilding = null;
                  _selectedIllustratedBuilding = null;
                }),
              ),
            ],
          ),

          // 建筑出入口与就近教室指引 (若有)
          if (_selectedBuilding != null && _selectedBuilding!.entrances.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      Icon(Icons.door_sliding_outlined, size: 14, color: AppColors.usstRed),
                      SizedBox(width: 4),
                      Text(
                        '出入口与就近教室指引',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final ent in _selectedBuilding!.entrances)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: ent.hasStairs
                                  ? const Color(0xFFFFF0ED)
                                  : const Color(0xFFE6F4EA),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              ent.hasStairs ? '有台阶' : '平地/坡道',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: ent.hasStairs
                                    ? const Color(0xFFD9381E)
                                    : const Color(0xFF137333),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  ent.name,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                if (ent.nearbyRooms.isNotEmpty)
                                  Text(
                                    '适合到达教室: ${ent.nearbyRooms.join("、")}',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          // 功能快捷动作按钮群
          Row(
            children: <Widget>[
              if (isTeachingBuilding) ...<Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.usstRed,
                      side: const BorderSide(color: Color(0xFFE0C4C4)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.meeting_room_outlined, size: 15),
                    label: const Text('查本楼空教室', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ClassroomQueryPage(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.usstRed,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.navigation_outlined, size: 15),
                  label: const Text('外部地图导航', style: TextStyle(fontSize: 12)),
                  onPressed: () => _openExternalNavigation(poi),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].latitude, yi = polygon[i].longitude;
      final xj = polygon[j].latitude, yj = polygon[j].longitude;

      final intersect = ((yi > point.longitude) != (yj > point.longitude)) &&
          (point.latitude < (xj - xi) * (point.longitude - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}
