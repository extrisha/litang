import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 底部导航栏「今日」专属日历矢量图标
///
/// 特性：
/// - 中间动态填充当天的公历日期（如 29），消除大面积空白
/// - 未选态：1.6px 矢量日历线框，居中粗体显示当日日期
/// - 选中态：上部横梁实心着色，精细饱满，与 Material NavigationBar 动效完美契合
class UsstTodayNavIcon extends StatelessWidget {
  final bool selected;
  final double size;
  final Color? color;

  const UsstTodayNavIcon({
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
      painter: _UsstTodayNavIconPainter(
        selected: selected,
        color: iconColor,
        day: DateTime.now().day,
      ),
    );
  }
}

class _UsstTodayNavIconPainter extends CustomPainter {
  final bool selected;
  final Color color;
  final int day;

  const _UsstTodayNavIconPainter({
    required this.selected,
    required this.color,
    required this.day,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24.0;
    final sy = size.height / 24.0;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * sx
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 1. 日历外框 (圆角矩形，留出上方挂环空间)
    final calendarRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(3.5 * sx, 4.5 * sy, 20.5 * sx, 20.5 * sy),
      Radius.circular(3.5 * sx),
    );

    if (selected) {
      // 选中态：绘制外框描边
      canvas.drawRRect(calendarRect, strokePaint);

      // 选中态：顶部标题栏实心填充
      final headerPath = Path();
      headerPath.addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(3.5 * sx, 4.5 * sy, 20.5 * sx, 9.0 * sy),
          topLeft: Radius.circular(3.5 * sx),
          topRight: Radius.circular(3.5 * sx),
        ),
      );
      canvas.drawPath(headerPath, fillPaint);
    } else {
      // 未选态：仅描边外框
      canvas.drawRRect(calendarRect, strokePaint);
      // 未选态：顶部水平分隔细线
      canvas.drawLine(
        Offset(3.5 * sx, 9.0 * sy),
        Offset(20.5 * sx, 9.0 * sy),
        strokePaint..strokeWidth = 1.3 * sx,
      );
    }

    // 2. 两个日历装订环 (顶部挂钩)
    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * sx
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(7.5 * sx, 2.5 * sy), Offset(7.5 * sx, 5.5 * sy), ringPaint);
    canvas.drawLine(Offset(16.5 * sx, 2.5 * sy), Offset(16.5 * sx, 5.5 * sy), ringPaint);

    // 3. 中间绘制当天的日期数字 (如 29)
    final dayStr = '$day';
    final fontSize = (dayStr.length > 1 ? 8.5 : 9.5) * sx;
    final textPainter = TextPainter(
      text: TextSpan(
        text: dayStr,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          fontFamily: 'sans-serif',
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // 将日期文本精准居中放置在日历下半部书写区 (y 从 9.0 到 20.5)
    final textX = (12.0 * sx) - (textPainter.width / 2.0);
    final textY = (14.5 * sy) - (textPainter.height / 2.0);
    textPainter.paint(canvas, Offset(textX, textY));
  }

  @override
  bool shouldRepaint(covariant _UsstTodayNavIconPainter oldDelegate) {
    return oldDelegate.selected != selected ||
        oldDelegate.color != color ||
        oldDelegate.day != day;
  }
}
