import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/campus_places.dart';
import '../data/place_search.dart';
import '../data/map_focus.dart';
import '../data/campus_shapes.dart';

const int _tileSize = 1024;
const int _tileCols = 5;
const int _tileRows = 6;

/// 地图：官方校园地图（4500x5350，分块加载）+ 地点搜索。
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final TransformationController _controller = TransformationController();
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  CampusPlace? _selected;
  bool _showLabels = true;
  bool _initialized = false;
  bool _updating = false;
  Size _viewport = Size.zero;
  double _fitScale = 0.1;
  Set<int> _visible = <int>{};
  CampusPlace? _pendingFocus;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
    MapFocus.target.addListener(_onFocusTarget);
  }

  @override
  void dispose() {
    MapFocus.target.removeListener(_onFocusTarget);
    _controller.removeListener(_onTransform);
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  static Matrix4 _matrix(double scale, double tx, double ty) {
    return Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
  }

  void _onFocusTarget() {
    final place = MapFocus.target.value;
    if (place == null) {
      return;
    }
    if (_initialized && _viewport != Size.zero) {
      _selectPlace(place);
      MapFocus.consume();
    } else {
      _pendingFocus = place;
    }
  }

  void _onTransform() {
    if (_updating || _viewport == Size.zero) {
      return;
    }
    final next = _visibleTiles();
    if (!setEquals(next, _visible)) {
      for (final index in next.difference(_visible)) {
        _precacheTile(index, 'base');
        if (_showLabels) {
          _precacheTile(index, 'labels');
        }
      }
      setState(() => _visible = next);
    }
  }

  Set<int> _visibleTiles() {
    final inverse = Matrix4.inverted(_controller.value);
    final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
    final bottomRight = MatrixUtils.transformPoint(
      inverse,
      Offset(_viewport.width, _viewport.height),
    );
    final rect = Rect.fromPoints(
      topLeft,
      bottomRight,
    ).inflate(_tileSize.toDouble());
    final c0 = (rect.left / _tileSize).floor().clamp(0, _tileCols - 1);
    final c1 = (rect.right / _tileSize).floor().clamp(0, _tileCols - 1);
    final r0 = (rect.top / _tileSize).floor().clamp(0, _tileRows - 1);
    final r1 = (rect.bottom / _tileSize).floor().clamp(0, _tileRows - 1);
    final tiles = <int>{};
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        tiles.add(r * _tileCols + c);
      }
    }
    return tiles;
  }

  void _applyFit() {
    final fit = math.max(
      _viewport.width / kCampusMapWidth,
      _viewport.height / kCampusMapHeight,
    );
    _fitScale = fit;
    _updating = true;
    _controller.value = _matrix(
      fit,
      _viewport.width / 2 - kCampusMapWidth / 2 * fit,
      _viewport.height / 2 - kCampusMapHeight / 2 * fit,
    );
    _updating = false;
    _visible = _visibleTiles();
  }

  void _selectPlace(CampusPlace place) {
    setState(() {
      _selected = place;
      _query = '';
      _searchController.clear();
    });
    if (_viewport == Size.zero) {
      return;
    }
    final scale = _fitScale * 2.4;
    final px = place.anchor.dx * kCampusMapWidth;
    final py = place.anchor.dy * kCampusMapHeight;
    _controller.value = _matrix(
      scale,
      _viewport.width / 2 - px * scale,
      _viewport.height / 2 - py * scale,
    );
  }

  void _reset() {
    setState(() {
      _selected = null;
      _initialized = false;
    });
  }

  void _onTapUp(TapUpDetails details) {
    final normalized = Offset(
      details.localPosition.dx / kCampusMapWidth,
      details.localPosition.dy / kCampusMapHeight,
    );
    final place = placeAt(normalized) ?? nearestPlace(normalized);
    if (place != null) {
      setState(() => _selected = place);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _topBar(),
            _searchBar(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _viewport = Size(constraints.maxWidth, constraints.maxHeight);
                  if (!_initialized) {
                    _applyFit();
                    _initialized = true;
                  }
                  if (_pendingFocus != null) {
                    final pending = _pendingFocus!;
                    _pendingFocus = null;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) {
                        return;
                      }
                      _selectPlace(pending);
                      MapFocus.consume();
                    });
                  }
                  return Stack(
                    children: <Widget>[
                      Positioned.fill(child: _mapCanvas()),
                      if (_query.isNotEmpty) _resultsPanel(),
                      if (_selected != null) _selectedBanner(_selected!),
                      Positioned(
                        right: 12,
                        bottom: _selected == null ? 12 : 104,
                        child: FloatingActionButton.small(
                          heroTag: 'map-reset',
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.usstRed,
                          onPressed: _reset,
                          child: const Icon(Icons.fullscreen_exit, size: 18),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: <Widget>[
          const Text(
            '校园地图',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          const Text(
            '缩放 · 拖动 · 点击楼栋',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          IconButton(
            tooltip: _showLabels ? '隐藏楼名' : '显示楼名',
            icon: Icon(
              _showLabels ? Icons.label : Icons.label_outline,
              size: 20,
            ),
            onPressed: () => setState(() => _showLabels = !_showLabels),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F5F7),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: '搜索楼栋，如「第一教学楼」',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
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
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mapCanvas() {
    return ClipRect(
      child: InteractiveViewer(
        transformationController: _controller,
        constrained: false,
        minScale: _fitScale,
        maxScale: _fitScale * 5,
        boundaryMargin: EdgeInsets.zero,
        child: GestureDetector(
          onTapUp: _onTapUp,
          child: SizedBox(
            width: kCampusMapWidth,
            height: kCampusMapHeight,
            child: Stack(
              children: <Widget>[
                for (final index in _visible) ...<Widget>[
                  _tile(index, 'base'),
                  if (_showLabels) _tile(index, 'labels'),
                ],
                if (_selected != null)
                  Positioned(
                    left: _selected!.anchor.dx * kCampusMapWidth - 18,
                    top: _selected!.anchor.dy * kCampusMapHeight - 18,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.usstRed, width: 3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _precacheTile(int index, String layer) {
    final row = index ~/ _tileCols;
    final col = index % _tileCols;
    final path = 'assets/map/${layer}_r${row}_c$col.webp';
    unawaited(precacheImage(AssetImage(path), context));
  }

  Widget _tile(int index, String layer) {
    final row = index ~/ _tileCols;
    final col = index % _tileCols;
    final left = col * _tileSize;
    final top = row * _tileSize;
    final width = math.min(_tileSize.toDouble(), kCampusMapWidth - left);
    final height = math.min(_tileSize.toDouble(), kCampusMapHeight - top);
    return Positioned(
      left: left.toDouble(),
      top: top.toDouble(),
      width: width,
      height: height,
      child: Image.asset(
        'assets/map/${layer}_r${row}_c$col.webp',
        key: ValueKey<String>('${layer}_${row}_$col'),
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      ),
    );
  }

  Widget _resultsPanel() {
    final results = searchCampusPlaces(_query);
    return Positioned(
      left: 16,
      right: 16,
      top: 6,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: results.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    '没有找到这个地点',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final place = results[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        place.name,
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 16),
                      onTap: () => _selectPlace(place),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _selectedBanner(CampusPlace place) {
    return Positioned(
      left: 16,
      right: 70,
      bottom: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x1F000000), blurRadius: 10),
          ],
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.redTint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.place,
                size: 18,
                color: AppColors.usstRed,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    place.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '军工路校区',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _selected = null),
              child: const Icon(
                Icons.close,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
