import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 上理历史建筑思晏堂（校徽核心建筑图案）风格的校园矢量图标
///
/// 视觉规范：
/// - 24x24 矢量栅格
/// - 未选态：1.6px 描边轮廓，与 Material Outlined 系列图标线宽完全一致
/// - 选中态：实心剪影，镂空门窗细节，颜色响应主题与导航栏 IconTheme
class UsstCampusIcon extends StatelessWidget {
  final bool selected;
  final double size;
  final Color? color;

  const UsstCampusIcon({
    super.key,
    required this.selected,
    this.size = 24.0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? IconTheme.of(context).color ?? AppColors.textPrimary;
    return CustomPaint(
      size: Size(size, size),
      painter: _UsstCampusIconPainter(
        selected: selected,
        color: iconColor,
      ),
    );
  }
}

class _UsstCampusIconPainter extends CustomPainter {
  final bool selected;
  final Color color;

  const _UsstCampusIconPainter({
    required this.selected,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24.0;
    final sy = size.height / 24.0;

    // 建筑轮廓外边框
    final buildingPath = Path()
      // 左侧地基底线
      ..moveTo(3.5 * sx, 20.0 * sy)
      // 左侧主墙
      ..lineTo(3.5 * sx, 12.0 * sy)
      // 左侧山墙斜坡屋顶
      ..lineTo(9.5 * sx, 9.5 * sy)
      // 中央钟楼左墙
      ..lineTo(9.5 * sx, 6.0 * sy)
      // 钟楼尖顶 (尖塔山墙)
      ..lineTo(12.0 * sx, 3.2 * sy)
      // 钟楼尖顶右侧
      ..lineTo(14.5 * sx, 6.0 * sy)
      // 中央钟楼右墙
      ..lineTo(14.5 * sx, 9.5 * sy)
      // 右侧山墙斜坡屋顶
      ..lineTo(20.5 * sx, 12.0 * sy)
      // 右侧主墙
      ..lineTo(20.5 * sx, 20.0 * sy)
      ..close();

    // 中央正门拱门
    final doorRect = Rect.fromLTRB(10.5 * sx, 15.5 * sy, 13.5 * sx, 20.0 * sy);
    final doorRRect = RRect.fromRectAndCorners(
      doorRect,
      topLeft: Radius.circular(1.5 * sx),
      topRight: Radius.circular(1.5 * sx),
    );
    final doorPath = Path()..addRRect(doorRRect);

    // 钟楼拱形钟窗
    final bellRect = Rect.fromLTRB(11.0 * sx, 7.5 * sy, 13.0 * sx, 10.5 * sy);
    final bellRRect = RRect.fromRectAndCorners(
      bellRect,
      topLeft: Radius.circular(1.0 * sx),
      topRight: Radius.circular(1.0 * sx),
    );
    final bellPath = Path()..addRRect(bellRRect);

    // 左翼拱窗
    final leftWinRect = Rect.fromLTRB(5.5 * sx, 14.0 * sy, 7.5 * sx, 17.0 * sy);
    final leftWinRRect = RRect.fromRectAndCorners(
      leftWinRect,
      topLeft: Radius.circular(1.0 * sx),
      topRight: Radius.circular(1.0 * sx),
    );
    final leftWinPath = Path()..addRRect(leftWinRRect);

    // 右翼拱窗
    final rightWinRect = Rect.fromLTRB(16.5 * sx, 14.0 * sy, 18.5 * sx, 17.0 * sy);
    final rightWinRRect = RRect.fromRectAndCorners(
      rightWinRect,
      topLeft: Radius.circular(1.0 * sx),
      topRight: Radius.circular(1.0 * sx),
    );
    final rightWinPath = Path()..addRRect(rightWinRRect);

    if (selected) {
      // 选中态：实心剪影，镂空门窗
      final cutouts = Path()
        ..addPath(doorPath, Offset.zero)
        ..addPath(bellPath, Offset.zero)
        ..addPath(leftWinPath, Offset.zero)
        ..addPath(rightWinPath, Offset.zero);

      final solidPath = Path.combine(PathOperation.difference, buildingPath, cutouts);

      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      canvas.drawPath(solidPath, fillPaint);

      // 地平线底座
      final linePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * sx
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;

      canvas.drawLine(Offset(2.0 * sx, 20.0 * sy), Offset(22.0 * sx, 20.0 * sy), linePaint);
    } else {
      // 未选态：精致线框轮廓，与 Material 线性图标一致
      final strokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * sx
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;

      canvas.drawPath(buildingPath, strokePaint);
      canvas.drawPath(doorPath, strokePaint);
      canvas.drawPath(bellPath, strokePaint);
      canvas.drawPath(leftWinPath, strokePaint);
      canvas.drawPath(rightWinPath, strokePaint);

      // 地平线底座
      canvas.drawLine(Offset(2.0 * sx, 20.0 * sy), Offset(22.0 * sx, 20.0 * sy), strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _UsstCampusIconPainter oldDelegate) {
    return oldDelegate.selected != selected || oldDelegate.color != color;
  }
}
