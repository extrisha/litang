import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/geo/campus_config.dart';
import '../data/illustrated_map/campus_516_buildings.dart';
import '../data/illustrated_map/campus_building.dart';

/// 军工路 516 号校区专属高清手绘矢量地图渲染组件
/// 支持 2D 平面与 2.5D 鸟瞰双视角、毫秒级手势交互、多边形高亮与脉冲对焦
class IllustratedCampusView extends StatefulWidget {
  const IllustratedCampusView({
    super.key,
    required this.mode,
    required this.selectedBuilding,
    required this.activeCategory,
    required this.onBuildingSelected,
    this.transformationController,
  });

  final MapViewMode mode;
  final CampusBuilding? selectedBuilding;
  final CampusCategory activeCategory;
  final ValueChanged<CampusBuilding?> onBuildingSelected;
  final TransformationController? transformationController;

  @override
  State<IllustratedCampusView> createState() => IllustratedCampusViewState();
}

class IllustratedCampusViewState extends State<IllustratedCampusView>
    with TickerProviderStateMixin {
  late TransformationController _controller;
  late AnimationController _pulseController;

  Size _viewportSize = Size.zero;
  bool _initialized = false;

  Size get _mapSize => widget.mode == MapViewMode.flat
      ? const Size(Campus516Data.flatWidth, Campus516Data.flatHeight)
      : const Size(Campus516Data.isoWidth, Campus516Data.isoHeight);

  @override
  void initState() {
    super.initState();
    _controller = widget.transformationController ?? TransformationController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.selectedBuilding != null) {
      _pulseController.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant IllustratedCampusView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.selectedBuilding != null) {
          focusBuilding(widget.selectedBuilding!, animate: true);
        } else {
          _fitToViewport();
        }
      });
    } else if (oldWidget.selectedBuilding != widget.selectedBuilding &&
        widget.selectedBuilding != null) {
      _pulseController.forward(from: 0);
      focusBuilding(widget.selectedBuilding!, animate: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    if (widget.transformationController == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _fitToViewport() {
    if (_viewportSize == Size.zero) return;
    final scale = math.min(
      _viewportSize.width / _mapSize.width,
      _viewportSize.height / _mapSize.height,
    );
    final tx = (_viewportSize.width - _mapSize.width * scale) / 2;
    final ty = (_viewportSize.height - _mapSize.height * scale) / 2;

    _controller.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
    _initialized = true;
  }

  /// 平滑镜头对焦到指定建筑
  void focusBuilding(CampusBuilding building, {bool animate = true}) {
    if (_viewportSize == Size.zero) return;

    final anchor = building.labelFor(widget.mode);
    final targetX = anchor.dx * _mapSize.width;
    final targetY = anchor.dy * _mapSize.height;

    // 缩放到适当清晰度 (0.75 - 1.2)
    const targetScale = 0.95;
    final targetTx = _viewportSize.width / 2 - targetX * targetScale;
    final targetTy = _viewportSize.height / 2 - targetY * targetScale;

    final targetMatrix = Matrix4.identity()
      ..setEntry(0, 0, targetScale)
      ..setEntry(1, 1, targetScale)
      ..setEntry(2, 2, targetScale)
      ..setEntry(0, 3, targetTx)
      ..setEntry(1, 3, targetTy);

    if (!animate) {
      _controller.value = targetMatrix;
      return;
    }

    final startMatrix = _controller.value.clone();
    final animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    final curved = CurvedAnimation(
      parent: animController,
      curve: Curves.easeOutCubic,
    );

    animController.addListener(() {
      final t = curved.value;
      final m = Matrix4.zero();
      for (var i = 0; i < 16; i++) {
        m.storage[i] = startMatrix.storage[i] * (1 - t) + targetMatrix.storage[i] * t;
      }
      _controller.value = m;
    });

    animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        animController.dispose();
      }
    });

    animController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    final localPoint = details.localPosition;
    final scenePoint = _controller.toScene(localPoint);

    // 1. 优先多边形碰撞命中
    for (final b in Campus516Data.buildings) {
      if (b.hitTest(scenePoint, _mapSize, widget.mode)) {
        widget.onBuildingSelected(b);
        return;
      }
    }

    // 2. 锚点容差命中 (半径 45px 内最近建筑)
    CampusBuilding? closest;
    double closestDist = 48.0;
    for (final b in Campus516Data.buildings) {
      final label = b.labelFor(widget.mode);
      final px = label.dx * _mapSize.width;
      final py = label.dy * _mapSize.height;
      final dist = math.sqrt(math.pow(scenePoint.dx - px, 2) + math.pow(scenePoint.dy - py, 2));
      if (dist < closestDist) {
        closestDist = dist;
        closest = b;
      }
    }

    widget.onBuildingSelected(closest);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final newSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (_viewportSize != newSize) {
          _viewportSize = newSize;
          if (!_initialized) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _fitToViewport());
          }
        }

        final assetPath = widget.mode == MapViewMode.flat
            ? 'assets/map/campus_516_flat.webp'
            : 'assets/map/campus_516_iso.webp';

        return GestureDetector(
          onTapUp: _onTapUp,
          child: InteractiveViewer(
            transformationController: _controller,
            minScale: 0.15,
            maxScale: 2.8,
            boundaryMargin: const EdgeInsets.all(800),
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: _mapSize.width,
              height: _mapSize.height,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // 1. 高清底图
                  Image.asset(
                    assetPath,
                    width: _mapSize.width,
                    height: _mapSize.height,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),

                  // 2. 动态矢量高亮绘制层
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return CustomPaint(
                        size: _mapSize,
                        painter: _IllustratedMapPainter(
                          mode: widget.mode,
                          selectedBuilding: widget.selectedBuilding,
                          activeCategory: widget.activeCategory,
                          pulseValue: _pulseController.value,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 矢量高亮、分类标定与脉冲光环绘制
class _IllustratedMapPainter extends CustomPainter {
  const _IllustratedMapPainter({
    required this.mode,
    required this.selectedBuilding,
    required this.activeCategory,
    required this.pulseValue,
  });

  final MapViewMode mode;
  final CampusBuilding? selectedBuilding;
  final CampusCategory activeCategory;
  final double pulseValue;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 若激活了分类筛选，为该分类的建筑画上柔和的标记
    if (activeCategory != CampusCategory.all) {
      final categoryFill = Paint()
        ..color = _categoryColor(activeCategory).withValues(alpha: 0.18)
        ..style = PaintingStyle.fill;
      final categoryStroke = Paint()
        ..color = _categoryColor(activeCategory).withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      for (final b in Campus516Data.buildings) {
        if (b.campusCategory == activeCategory && b != selectedBuilding) {
          final path = b.toPath(size, mode);
          canvas.drawPath(path, categoryFill);
          canvas.drawPath(path, categoryStroke);

          // 绘制分类小圆标
          final label = b.labelFor(mode);
          final center = Offset(label.dx * size.width, label.dy * size.height);
          canvas.drawCircle(
            center,
            4.0,
            Paint()..color = _categoryColor(activeCategory),
          );
        }
      }
    }

    // 2. 选中的建筑进行全特效高亮
    if (selectedBuilding != null) {
      final b = selectedBuilding!;
      final path = b.toPath(size, mode);

      // (1) 建筑发光背景
      final fillPaint = Paint()
        ..color = AppColors.usstRed.withValues(alpha: 0.28)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);

      // (2) 建筑外边框描边
      final strokePaint = Paint()
        ..color = AppColors.usstRed
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, strokePaint);

      // (3) 脉冲呼吸光环
      final anchor = b.labelFor(mode);
      final center = Offset(anchor.dx * size.width, anchor.dy * size.height);

      final pulseRadius = 16.0 + pulseValue * 12.0;
      final pulseAlpha = (1.0 - pulseValue).clamp(0.0, 1.0);
      final ringPaint = Paint()
        ..color = AppColors.usstRed.withValues(alpha: pulseAlpha * 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawCircle(center, pulseRadius, ringPaint);

      // 中心实心红点与白环
      canvas.drawCircle(
        center,
        7.0,
        Paint()..color = AppColors.usstRed,
      );
      canvas.drawCircle(
        center,
        7.0,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );

      // 建筑名称浮动卡片
      _drawLabelBadge(canvas, center, b.name);
    }
  }

  void _drawLabelBadge(Canvas canvas, Offset center, String name) {
    final tp = TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(
          color: Color(0xFF222222),
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const paddingH = 10.0;
    const paddingV = 5.0;
    final badgeWidth = tp.width + paddingH * 2;
    final badgeHeight = tp.height + paddingV * 2;

    final badgeRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - 28),
      width: badgeWidth,
      height: badgeHeight,
    );
    final rrect = RRect.fromRectAndRadius(badgeRect, const Radius.circular(8));

    // 阴影
    canvas.drawRRect(
      rrect.shift(const Offset(0, 2)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // 卡片背景
    canvas.drawRRect(rrect, Paint()..color = Colors.white);
    // 卡片红边
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = AppColors.usstRed
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // 小三角指针
    final arrowPath = Path()
      ..moveTo(center.dx - 5, badgeRect.bottom)
      ..lineTo(center.dx + 5, badgeRect.bottom)
      ..lineTo(center.dx, center.dy - 12)
      ..close();
    canvas.drawPath(arrowPath, Paint()..color = AppColors.usstRed);

    tp.paint(
      canvas,
      Offset(badgeRect.left + paddingH, badgeRect.top + paddingV),
    );
  }

  Color _categoryColor(CampusCategory category) {
    switch (category) {
      case CampusCategory.teaching:
        return AppColors.usstRed;
      case CampusCategory.dorm:
        return const Color(0xFF4A6FA5);
      case CampusCategory.dining:
        return const Color(0xFFE28413);
      case CampusCategory.library:
        return const Color(0xFF2D82B7);
      case CampusCategory.sports:
        return const Color(0xFF2E7D32);
      case CampusCategory.service:
      case CampusCategory.gate:
      default:
        return const Color(0xFF7A6F62);
    }
  }

  @override
  bool shouldRepaint(covariant _IllustratedMapPainter oldDelegate) {
    return oldDelegate.mode != mode ||
        oldDelegate.selectedBuilding != selectedBuilding ||
        oldDelegate.activeCategory != activeCategory ||
        oldDelegate.pulseValue != pulseValue;
  }
}
