import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../data/geo/campus_config.dart';
import '../data/geo/campus_tile_provider.dart';
import '../data/map_focus.dart';
import 'classroom_query_page.dart';

/// 校园地图：基于 flutter_map 与内置开源离线瓦片
/// 支持全校区统一呈现（军工路 516/1100、复兴路、营口路）、离线秒开、分类筛选、GPS 定位与业务联动。
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  Campus _currentCampus = CampusData.jungong;
  CampusCategory _selectedCategory = CampusCategory.all;
  String _query = '';
  CampusPoi? _selectedPoi;

  // 定位状态
  LatLng? _userLocation;
  bool _locating = false;
  double? _userHeading;

  @override
  void initState() {
    super.initState();
    MapFocus.target.addListener(_onFocusTarget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialFocus();
    });
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
      _onFocusTarget();
    }
  }

  void _onFocusTarget() {
    final target = MapFocus.target.value;
    if (target == null) return;

    final poi = CampusData.poiForRoom(target.name) ??
        CampusData.search(query: target.name).firstOrNull;

    if (poi != null) {
      _selectPoi(poi);
      MapFocus.consume();
    }
  }

  /// 平滑飞行移动镜头
  void _animatedMapMove(LatLng destLocation, double destZoom) {
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
      duration: const Duration(milliseconds: 450),
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
      _query = '';
      _searchController.clear();
      // 切换校区
      final matchedCampus = CampusData.allCampuses.firstWhere(
        (c) => c.id == poi.campusId,
        orElse: () => _currentCampus,
      );
      _currentCampus = matchedCampus;
    });

    _animatedMapMove(poi.location, 17.5);
  }

  void _switchCampus(Campus campus) {
    setState(() {
      _currentCampus = campus;
      _selectedPoi = null;
    });
    _animatedMapMove(campus.center, campus.defaultZoom);
  }

  /// 获取当前 GPS 位置并在地图上标定
  Future<void> _locateUser() async {
    if (_locating) return;
    setState(() => _locating = true);

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('请先开启手机 GPS/位置服务');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _toast('未授予位置权限，无法获取实时定位');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final userPos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _userLocation = userPos;
        _userHeading = pos.heading > 0 ? pos.heading : null;
      });

      // 判断用户是否在某个校区附近（以 3 公里为界）
      const distanceCalc = Distance();
      Campus? nearby;
      double minD = double.infinity;
      for (final c in CampusData.allCampuses) {
        final d = distanceCalc.as(LengthUnit.Meter, userPos, c.center);
        if (d < minD) {
          minD = d;
          nearby = c;
        }
      }

      if (minD <= 2500 && nearby != null) {
        setState(() => _currentCampus = nearby!);
        _animatedMapMove(userPos, 17.2);
        _toast('已定位到您所在的校区');
      } else {
        _animatedMapMove(userPos, 16.0);
        final km = (minD / 1000).toStringAsFixed(1);
        _toast('当前距离最近校区约 $km km');
      }
    } catch (e) {
      _toast('获取定位失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 唤起第三方地图外部导航
  Future<void> _openExternalNavigation(CampusPoi poi) async {
    final name = Uri.encodeComponent('上海理工大学-${poi.name}');
    final lat = poi.location.latitude;
    final lng = poi.location.longitude;

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

  @override
  Widget build(BuildContext context) {
    final searchResults = _query.isEmpty
        ? const <CampusPoi>[]
        : CampusData.search(
            query: _query,
            campusId: _currentCampus.id,
            category: _selectedCategory,
          );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            // 1. 底图层：FlutterMap
            Positioned.fill(child: _buildMap()),

            // 2. 顶部综合栏（校区切换、搜索框、分类标签）
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _buildHeader(),
                  _buildSearchBar(),
                  _buildCategoryChips(),
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

            // 4. 右下角快捷按钮群（定位、复位视角）
            Positioned(
              right: 14,
              bottom: _selectedPoi == null ? 24 : 150,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FloatingActionButton.small(
                    heroTag: 'map-location',
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.usstRed,
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
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    heroTag: 'map-reset-view',
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 3,
                    onPressed: () {
                      setState(() => _selectedPoi = null);
                      _animatedMapMove(_currentCampus.center, _currentCampus.defaultZoom);
                    },
                    child: const Icon(Icons.center_focus_strong, size: 20),
                  ),
                ],
              ),
            ),

            // 5. 选中地点详细信息浮窗
            if (_selectedPoi != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _buildPoiDetailCard(_selectedPoi!),
              ),
          ],
        ),
      ),
    );
  }

  /// 地图核心组件
  Widget _buildMap() {
    final markers = <Marker>[];

    // 当前选中的 POI 标记
    if (_selectedPoi != null) {
      markers.add(
        Marker(
          point: _selectedPoi!.location,
          width: 44,
          height: 44,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.usstRed,
                  shape: BoxShape.circle,
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
                  ],
                ),
                child: const Icon(Icons.location_on, size: 20, color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    // 用户 GPS 定位蓝点
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
                decoration: BoxDecoration(
                  color: const Color(0x332196F3),
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

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentCampus.center,
        initialZoom: _currentCampus.defaultZoom,
        minZoom: _currentCampus.minZoom,
        maxZoom: _currentCampus.maxZoom,
        cameraConstraint: CameraConstraint.contain(bounds: _currentCampus.bounds),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate, // 锁定正北朝向，方便高校浏览
        ),
        onTap: (_, _) {
          if (_query.isNotEmpty) {
            setState(() => _query = '');
            _searchController.clear();
          }
        },
      ),
      children: <Widget>[
        // 离线内置瓦片图层（优先秒开本地 assets/tiles/{z}_{x}_{y}.png）
        TileLayer(
          urlTemplate: 'assets/tiles/{z}_{x}_{y}.png',
          tileProvider: CampusOfflineTileProvider(),
          maxZoom: 18.5,
          maxNativeZoom: 18,
          keepBuffer: 3,
        ),

        // 标记层
        MarkerLayer(markers: markers),
      ],
    );
  }

  /// 顶部栏：返回按钮与校区切换选择器
  Widget _buildHeader() {
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

          // 校区切换下拉
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
                          color: c.id == _currentCampus.id ? AppColors.usstRed : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          c.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: c.id == _currentCampus.id ? FontWeight.w700 : FontWeight.normal,
                            color: c.id == _currentCampus.id ? AppColors.usstRed : AppColors.textPrimary,
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
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _currentCampus.id == 'jungong' ? '校区切换' : _currentCampus.shortName,
                    style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xCCFFFFFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '离线地图 · 开源高精',
              style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索栏
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(21),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x18000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: '搜索地点，如「第一教学楼」「二食」',
                  hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  border: InputBorder.none,
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (_query.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
                child: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }

  /// 分类快捷筛选标签横向滚动条
  Widget _buildCategoryChips() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: CampusCategory.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final cat = CampusCategory.values[index];
          final isSelected = cat == _selectedCategory;
          return FilterChip(
            selected: isSelected,
            showCheckmark: false,
            avatar: Icon(
              cat.icon,
              size: 13,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            label: Text(
              cat.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            backgroundColor: Colors.white,
            selectedColor: AppColors.usstRed,
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: BorderSide.none,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (val) {
              setState(() => _selectedCategory = cat);
            },
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
                    '未在当前校区找到相关地点',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
                    trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: AppColors.textSecondary),
                    onTap: () => _selectPoi(poi),
                  );
                },
              ),
      ),
    );
  }

  /// 选中地点详细卡片（带空教室直达与外部导航）
  Widget _buildPoiDetailCard(CampusPoi poi) {
    // 计算离用户的距离
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
                            style: const TextStyle(fontSize: 11, color: AppColors.usstRed, fontWeight: FontWeight.w600),
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
                onPressed: () => setState(() => _selectedPoi = null),
              ),
            ],
          ),
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
                        MaterialPageRoute<void>(builder: (_) => const ClassroomQueryPage()),
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
}
