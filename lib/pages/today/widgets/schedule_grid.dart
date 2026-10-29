import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../data/models.dart';
import '../../../data/jwc/jwgl_schedule.dart';
import '../models/course_theme.dart';

/// 课表主网格（包含吸顶星期表头、左侧节次列、以及网格线与课程卡片）
class ScheduleGrid extends StatelessWidget {
  const ScheduleGrid({
    super.key,
    required this.courses,
    required this.selectedWeek,
    required this.themeMap,
    required this.activePeriod,
    required this.isToday,
    required this.dateForDay,
    required this.onRefresh,
    required this.onCourseTap,
    required this.onCourseDoubleTap,
    this.periodWidth = 34.0,
    this.headerHeight = 38.0,
  });

  final List<Course> courses;
  final int selectedWeek;
  final Map<String, CourseTheme> themeMap;
  final int? activePeriod;
  final bool Function(int dayIndex) isToday;
  final DateTime? Function(int week, int dayIndex) dateForDay;
  final RefreshCallback onRefresh;
  final void Function(Course course) onCourseTap;
  final void Function(Course course) onCourseDoubleTap;
  final double periodWidth;
  final double headerHeight;

  static const List<String> dayNames = <String>['一', '二', '三', '四', '五', '六', '日'];

  static String formatTeacher(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final trimmed = raw.trim();
    final parts = trimmed
        .split(RegExp(r'[,，;；/、\s]+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first;
    return '${parts.first}等';
  }

  @override
  Widget build(BuildContext context) {
    final shown = courses.where((c) => c.activeInWeek(selectedWeek)).toList();

    // 默认隐藏周末；若检测到周六有课则在右侧展开周六；若周日有课则在周一左侧展开周日
    final hasSaturday = shown.any((c) => c.day == 5);
    final hasSunday = shown.any((c) => c.day == 6);

    final visibleDays = <int>[];
    if (hasSunday) visibleDays.add(6); // 周日置于周一左侧
    visibleDays.addAll(<int>[0, 1, 2, 3, 4]); // 周一至周五
    if (hasSaturday) visibleDays.add(5); // 周六置于周五右侧

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;

        // 单元格横向宽度均分（根据可见星期数 5~7 动态伸缩，充满屏幕）
        final dayWidth = (availableWidth - periodWidth) / visibleDays.length;

        // 课表视口净高度（扣除顶部固定星期栏高度）
        final viewportHeight = availableHeight - headerHeight;

        // 让第十一节课与第十二节课的分界线与底部导航栏齐平：rowHeight * 11 = viewportHeight
        final rowHeight = math.max((viewportHeight - 1.0) / 11.0, 40.0);

        // 总高度刚好等于 13 节课的高度，下滑到底时第 13 节下边线恰好停在导航栏顶端
        final totalGridHeight = 13 * rowHeight;

        return Column(
          children: <Widget>[
            // 顶部固定星期表头 (吸顶固定，横向与每一列精确对齐)
            Row(
              children: <Widget>[
                Container(
                  width: periodWidth,
                  height: headerHeight,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFAFAFA),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFEDEDED)),
                      right: BorderSide(color: Color(0xFFEDEDED), width: 0.6),
                    ),
                  ),
                  child: const Text(
                    '节次',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                for (final dayIndex in visibleDays)
                  _buildDayHeaderCell(dayIndex, dayWidth),
              ],
            ),
            // 垂直滚动区域：左侧节次列与右侧课程网格同属同一垂直滚动视图，彻底修复节次不同步bug
            Expanded(
              child: RefreshIndicator(
                color: AppColors.usstRed,
                onRefresh: onRefresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // 左侧节次时间列 (随课表整体上下滚动)
                      _buildPeriodNumbersColumn(activePeriod, rowHeight, totalGridHeight),
                      // 右侧课程网格
                      SizedBox(
                        width: dayWidth * visibleDays.length,
                        height: totalGridHeight,
                        child: Stack(
                          children: <Widget>[
                            // 网格底图
                            Positioned.fill(
                              child: CustomPaint(
                                painter: GridPainter(
                                  periods: JwglSchedule.periodCount,
                                  activePeriod: activePeriod,
                                  visibleDays: visibleDays,
                                  isTodayCol: (d) => isToday(d),
                                  dayWidth: dayWidth,
                                  rowHeight: rowHeight,
                                ),
                              ),
                            ),
                            // 课程色块
                            for (final course in shown)
                              if (visibleDays.contains(course.day))
                                _buildCourseCard(
                                  course,
                                  dayWidth,
                                  rowHeight,
                                  visibleDays.indexOf(course.day),
                                  themeMap[course.name] ?? themeForCourse(course.name),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDayHeaderCell(int dayIndex, double dayWidth) {
    final isT = isToday(dayIndex);
    final date = dateForDay(selectedWeek, dayIndex);
    final dateStr = date != null ? '${date.month}/${date.day}' : '';

    return Container(
      width: dayWidth,
      height: headerHeight,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isT ? const Color(0xFFFFECEB) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isT ? AppColors.usstRed : const Color(0xFFEDEDED),
            width: isT ? 2.5 : 1,
          ),
          right: const BorderSide(color: Color(0xFFF2F2F2), width: 0.5),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            padding: EdgeInsets.symmetric(horizontal: isT ? 6 : 0, vertical: 1),
            decoration: isT
                ? BoxDecoration(
                    color: AppColors.usstRed,
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            child: Text(
              '周${dayNames[dayIndex]}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isT ? FontWeight.w700 : FontWeight.w600,
                color: isT ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
          if (dateStr.isNotEmpty) ...<Widget>[
            Text(
              dateStr,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isT ? FontWeight.w600 : FontWeight.w400,
                color: isT ? AppColors.usstRed : AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodNumbersColumn(int? activePeriod, double rowHeight, double totalHeight) {
    return Container(
      width: periodWidth,
      height: totalHeight,
      color: const Color(0xFFFAFAFA),
      child: Column(
        children: <Widget>[
          for (var p = 1; p <= JwglSchedule.periodCount; p++)
            _buildPeriodCell(p, activePeriod == p, rowHeight),
        ],
      ),
    );
  }

  Widget _buildPeriodCell(int period, bool isActive, double rowHeight) {
    final timeStr = JwglSchedule.periodAt(period);
    return Container(
      width: periodWidth,
      height: rowHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFFF1F0) : const Color(0xFFFAFAFA),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFEDEDED), width: 0.5),
          right: BorderSide(color: Color(0xFFEDEDED), width: 0.6),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
            decoration: isActive
                ? BoxDecoration(
                    color: AppColors.usstRed,
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
            child: Text(
              '$period',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: isActive ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
          if (timeStr != null) ...<Widget>[
            const SizedBox(height: 1),
            Text(
              timeStr.start,
              style: TextStyle(
                fontSize: 7.5,
                color: isActive ? AppColors.usstRed : AppColors.textSecondary,
              ),
            ),
            Text(
              timeStr.end,
              style: TextStyle(
                fontSize: 7.5,
                color: isActive ? AppColors.usstRed : AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCourseCard(
    Course course,
    double dayWidth,
    double rowHeight,
    int colIndex,
    CourseTheme theme,
  ) {
    final cardHeight = rowHeight * course.span - 3.5;
    final compact = course.span <= 1;
    final teacher = formatTeacher(course.teacher);

    return Positioned(
      left: colIndex * dayWidth + 1.5,
      top: course.start * rowHeight + 1.5,
      width: dayWidth - 3.0,
      height: cardHeight,
      child: GestureDetector(
        onTap: () {
          unawaited(HapticFeedback.lightImpact());
          onCourseTap(course);
        },
        onDoubleTap: () {
          unawaited(HapticFeedback.mediumImpact());
          onCourseDoubleTap(course);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3.0, vertical: 3.0),
          decoration: BoxDecoration(
            color: theme.bg,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: theme.border, width: 0.7),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x08000000),
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                course.name,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 9.5 : 10.5,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: theme.text,
                ),
              ),
              if (course.room.isNotEmpty || teacher.isNotEmpty) ...<Widget>[
                const Spacer(),
                if (!compact && teacher.isNotEmpty) ...<Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.person_outline_rounded,
                        size: 8.5,
                        color: theme.subText,
                      ),
                      const SizedBox(width: 1),
                      Expanded(
                        child: Text(
                          teacher,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 8.5,
                            height: 1.1,
                            color: theme.subText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1.5),
                ],
                if (course.room.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.location_on_rounded,
                        size: 8.5,
                        color: theme.subText,
                      ),
                      const SizedBox(width: 1),
                      Expanded(
                        child: Text(
                          course.room,
                          maxLines: compact ? 1 : 2,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 8.5,
                            height: 1.1,
                            fontWeight: FontWeight.w600,
                            color: theme.subText,
                          ),
                        ),
                      ),
                    ],
                  )
                else if (compact && teacher.isNotEmpty)
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.person_outline_rounded,
                        size: 8.5,
                        color: theme.subText,
                      ),
                      const SizedBox(width: 1),
                      Expanded(
                        child: Text(
                          teacher,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 8.5,
                            height: 1.1,
                            color: theme.subText,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  GridPainter({
    required this.periods,
    required this.activePeriod,
    required this.visibleDays,
    required this.isTodayCol,
    required this.dayWidth,
    required this.rowHeight,
  });

  final int periods;
  final int? activePeriod;
  final List<int> visibleDays;
  final bool Function(int dayIndex) isTodayCol;
  final double dayWidth;
  final double rowHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFFEDEDED)
      ..strokeWidth = 0.6;

    // 统一日期列与节次行微红高亮底色 (约 6.3% 透明度)，保持色相与深度完全一致
    const highlightColor = Color(0x10A31C1C);

    // 今天所在的列涂微红背景
    for (var c = 0; c < visibleDays.length; c++) {
      if (isTodayCol(visibleDays[c])) {
        final todayBg = Paint()..color = highlightColor;
        canvas.drawRect(
          Rect.fromLTWH(c * dayWidth, 0, dayWidth, size.height),
          todayBg,
        );
        break;
      }
    }

    // 如果当前正处于某一节次 (activePeriod != null)，整行使用与日期列完全一致的高亮底色
    if (activePeriod != null && activePeriod! >= 1 && activePeriod! <= periods) {
      final activeY = (activePeriod! - 1) * rowHeight;
      final activeRowPaint = Paint()..color = highlightColor;
      canvas.drawRect(Rect.fromLTWH(0, activeY, size.width, rowHeight), activeRowPaint);
    }

    // 横向网格线 (13节) 与时段红线分割 (第5节底上午下午、第10节底下 cruise 晚上)
    final sessionDividerPaint = Paint()
      ..color = const Color(0x70A31C1C)
      ..strokeWidth = 1.5;

    for (var i = 0; i <= periods; i++) {
      final y = i * rowHeight;
      if (i == 5 || i == 10) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), sessionDividerPaint);
      } else {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      }
    }

    // 纵向网格线
    for (var c = 0; c <= visibleDays.length; c++) {
      final x = c * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return oldDelegate.periods != periods ||
        oldDelegate.activePeriod != activePeriod ||
        oldDelegate.visibleDays != visibleDays ||
        oldDelegate.dayWidth != dayWidth ||
        oldDelegate.rowHeight != rowHeight;
  }
}
