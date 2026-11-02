import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../data/auth/jwgl_auth.dart';
import '../data/calendar/calendar_service.dart';
import '../data/chaoxing/chaoxing_cache.dart';
import '../data/date_format.dart';
import '../data/jwc/course_repository.dart';
import '../data/jwc/jwgl_schedule.dart';
import '../data/life_cache.dart';
import '../data/lms/todo_api.dart';
import '../data/models.dart';
import '../pages/life/widgets/life_todo_card.dart';
import '../pages/today/models/course_theme.dart';
import 'weather_service.dart';

/// 桌面小组件课表与天气数据同步服务
class WidgetSyncService {
  WidgetSyncService._();
  static final WidgetSyncService instance = WidgetSyncService._();

  static const String androidWidgetProvider = 'TodayScheduleWidgetProvider';

  static const List<String> _weekdays = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  /// 同步刷新桌面小组件（获取最新天气、课表/明日预告与待办，并通知 Android RemoteViews 更新）
  Future<void> syncTodayWidget({bool forceWeather = false}) async {
    try {
      final now = DateTime.now();

      // 1. 获取当前学期与教学周
      if (CalendarService.instance.calendar == null) {
        await CalendarService.instance.load();
      }
      final currentWeek = CalendarService.instance.currentWeek ?? 1;

      // 2. 计算日期与周次文本
      final weekText = '第 $currentWeek 周';
      final dateText = DateFmt.mdCn(now);
      final weekdayIndex = now.weekday - 1; // 0 = 周一 ... 6 = 周日
      final weekdayText = _weekdays[weekdayIndex.clamp(0, 6)];

      // 3. 读取本地课表并筛选今日课程
      final snapshot = await CourseRepository.loadCache();
      final allCourses = snapshot?.courses ?? <Course>[];
      final themeMap = buildCourseThemeMap(allCourses);

      final todayCourses = allCourses.where((c) {
        return c.day == weekdayIndex && c.activeInWeek(currentWeek);
      }).toList()..sort((a, b) => a.start.compareTo(b.start));

      // 4. 智能判断：今天没课（或今天课程全部已结束）时，自动转为展示下一次上课那天的课程
      int daysAhead = 0;
      List<Course> displayCourses = todayCourses;

      final allPastToday =
          todayCourses.isNotEmpty &&
          todayCourses.every(
            (c) => _computeStatus(now, c.start, c.span).status == 'past',
          );

      if (todayCourses.isEmpty || allPastToday) {
        for (int offset = 1; offset <= 14; offset++) {
          final targetDate = now.add(Duration(days: offset));
          final targetWeekdayIndex = targetDate.weekday - 1; // 0..6
          final targetWeek =
              CalendarService.instance.calendar?.currentTerm?.weekFor(
                targetDate,
              ) ??
              (currentWeek +
                  ((targetDate.difference(now).inDays + now.weekday - 1) ~/ 7));

          final targetCourses = allCourses.where((c) {
            return c.day == targetWeekdayIndex && c.activeInWeek(targetWeek);
          }).toList()..sort((a, b) => a.start.compareTo(b.start));

          if (targetCourses.isNotEmpty) {
            daysAhead = offset;
            displayCourses = targetCourses;
            break;
          }
        }
      }

      final scheduleTitle = daysAhead == 0
          ? '今日课表'
          : (daysAhead == 1 ? '明日' : '$daysAhead天后');

      // 5. 解析课程状态与时间区间
      final courseListJson = <Map<String, dynamic>>[];
      for (final c in displayCourses) {
        final theme = themeMap[c.name] ?? themeForCourse(c.name);
        final startSection = c.start + 1;
        final endSection = c.start + c.span;
        final periodText =
            '第 $startSection${c.span > 1 ? "-$endSection" : ""} 节';
        final timeRange = JwglSchedule.rangeOf(c.start, c.span) ?? '';

        String status;
        String statusTag;

        if (daysAhead > 0) {
          status = 'upcoming';
          statusTag = '';
        } else {
          final statusInfo = _computeStatus(now, c.start, c.span);
          status = statusInfo.status;
          statusTag = statusInfo.tag;
        }

        final linkUri = Uri(scheme: 'litang', host: 'schedule').toString();

        courseListJson.add(<String, dynamic>{
          'name': c.name,
          'period': periodText,
          'time': timeRange,
          'room': c.room.isEmpty ? '待定教室' : c.room,
          'teacher': c.teacher ?? '',
          'accentColor':
              '#${theme.accent.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
          'bgColor':
              '#${theme.bg.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
          'textColor':
              '#${theme.text.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
          'status': status,
          'statusTag': statusTag,
          'linkUri': linkUri,
        });
      }

      // 6. 整合待办事项（一网畅学待办 + 学习通作业）
      final username = JwglAuth.instance.savedUsername;
      final todos =
          await LifeCache.readTodos(username: username) ??
          await LifeCache.readTodos(username: '') ??
          <LmsTodo>[];

      final cxData =
          await ChaoxingCache.read(username) ??
          await ChaoxingCache.read('') ??
          const ChaoxingCacheData(courses: [], works: [], activities: []);

      final activeCxWorks = cxData.works
          .where((w) => !w.finished && !w.expired)
          .toList();

      final todoListJson = <Map<String, dynamic>>[];

      // 转换一网畅学待办
      for (final t in todos) {
        final ddl = t.deadline;
        final diff = ddl?.difference(now);
        final isPast = diff != null && diff.isNegative;
        final isUrgent = diff != null && !isPast && diff.inHours < 24;
        final isNear = diff != null && !isPast && diff.inDays < 3;
        final ddlText = formatDeadlineText(ddl, now);

        final linkUri = Uri(
          scheme: 'litang',
          host: 'todo',
          queryParameters: <String, String>{
            'kind': 'tron',
            'id': t.id.toString(),
            'courseId': t.courseId.toString(),
            'title': t.title,
            'courseName': t.courseName,
            'type': t.type,
          },
        ).toString();

        todoListJson.add(<String, dynamic>{
          'name': t.title,
          'period': ddlText,
          'time': ddlText,
          'room': LifeTodoCard.cleanCourseName(t.courseName),
          'teacher': '一网畅学 · ${t.typeLabel}',
          'accentColor': '#1967D2', // 一网畅学经典蓝
          'status': isPast
              ? 'past'
              : (isUrgent ? 'urgent' : (isNear ? 'near' : 'normal')),
          'statusTag': '',
          'deadlineMs': ddl?.millisecondsSinceEpoch ?? 9999999999999,
          'linkUri': linkUri,
        });
      }

      // 转换学习通作业
      for (final w in activeCxWorks) {
        final ddl = LifeTodoCard.parseTaskDeadline(w.deadline);
        final diff = ddl?.difference(now);
        final isPast = (diff != null && diff.isNegative) || w.expired;
        final isUrgent = diff != null && !isPast && diff.inHours < 24;
        final isNear = diff != null && !isPast && diff.inDays < 3;
        final ddlText = formatDeadlineText(ddl, now, raw: w.deadline);

        final linkUri = Uri(
          scheme: 'litang',
          host: 'todo',
          queryParameters: <String, String>{
            'kind': 'cx',
            'workId': w.workId,
            'title': w.title,
            'courseName': w.courseName,
            'taskUrl': w.taskUrl,
            'deadline': w.deadline,
            'statusText': w.statusText,
            'expired': w.expired.toString(),
          },
        ).toString();

        todoListJson.add(<String, dynamic>{
          'name': w.title,
          'period': ddlText,
          'time': ddlText,
          'room': LifeTodoCard.cleanCourseName(w.courseName),
          'teacher': '学习通 · 作业',
          'accentColor': '#A31C1C', // 学习通 / 上理红
          'status': isPast
              ? 'past'
              : (isUrgent ? 'urgent' : (isNear ? 'near' : 'normal')),
          'statusTag': '',
          'deadlineMs': ddl?.millisecondsSinceEpoch ?? 9999999999999,
          'linkUri': linkUri,
        });
      }

      // 待办按截止时间升序排序（最紧急的排在最前）
      todoListJson.sort(
        (a, b) => (a['deadlineMs'] as int).compareTo(b['deadlineMs'] as int),
      );

      // 7. 获取今日天气与降雨时间段
      final weather = await WeatherService.instance.getTodayWeather(
        forceRefresh: forceWeather,
      );

      // 8. 保存数据至 SharedPreferences 供 Android AppWidget 读取
      await HomeWidget.saveWidgetData<String>('today_week_text', weekText);
      await HomeWidget.saveWidgetData<String>('today_date_text', dateText);
      await HomeWidget.saveWidgetData<String>(
        'today_weekday_text',
        weekdayText,
      );

      await HomeWidget.saveWidgetData<bool>(
        'weather_has_rain',
        weather.hasRainOrSnow,
      );
      await HomeWidget.saveWidgetData<String>(
        'weather_time_window',
        weather.rainTimeWindow,
      );
      await HomeWidget.saveWidgetData<String>(
        'weather_probability',
        weather.probabilityText,
      );
      await HomeWidget.saveWidgetData<String>(
        'weather_umbrella_advice',
        weather.umbrellaAdvice,
      );
      await HomeWidget.saveWidgetData<String>(
        'weather_temp_range',
        weather.tempRange,
      );
      await HomeWidget.saveWidgetData<String>(
        'weather_icon_type',
        weather.iconType,
      );

      // 准备全学期课程数据供 Android 原生层离线跨天推演
      final currentTerm = CalendarService.instance.calendar?.currentTerm;
      final week1MondayStr = currentTerm != null
          ? DateFmt.ymd(currentTerm.week1Monday)
          : '';
      final totalWeeks = currentTerm?.totalWeeks ?? 20;

      final semesterAllCoursesList = <Map<String, dynamic>>[];
      for (final c in allCourses) {
        final theme = themeMap[c.name] ?? themeForCourse(c.name);
        semesterAllCoursesList.add(<String, dynamic>{
          'name': c.name,
          'day': c.day,
          'start': c.start,
          'span': c.span,
          'room': c.room,
          'teacher': c.teacher ?? '',
          'weeks': c.weeks,
          'accentColor':
              '#${theme.accent.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
          'bgColor':
              '#${theme.bg.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
          'textColor':
              '#${theme.text.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
        });
      }

      // 课表与下一次上课预告
      await HomeWidget.saveWidgetData<bool>(
        'schedule_is_tomorrow',
        daysAhead == 1,
      );
      await HomeWidget.saveWidgetData<int>('schedule_days_ahead', daysAhead);
      await HomeWidget.saveWidgetData<String>(
        'schedule_title_text',
        scheduleTitle,
      );
      await HomeWidget.saveWidgetData<int>(
        'schedule_count',
        displayCourses.length,
      );
      await HomeWidget.saveWidgetData<String>(
        'courses_json',
        jsonEncode(courseListJson),
      );

      // 原生离线跨天推演数据
      if (week1MondayStr.isNotEmpty) {
        await HomeWidget.saveWidgetData<String>(
          'semester_week1_monday',
          week1MondayStr,
        );
        await HomeWidget.saveWidgetData<int>(
          'semester_total_weeks',
          totalWeeks,
        );
        await HomeWidget.saveWidgetData<String>(
          'semester_all_courses_json',
          jsonEncode(semesterAllCoursesList),
        );
      }

      // 待办作业
      await HomeWidget.saveWidgetData<int>('todo_count', todoListJson.length);
      await HomeWidget.saveWidgetData<String>(
        'todos_json',
        jsonEncode(todoListJson),
      );

      // 9. 通知原生组件更新
      await HomeWidget.updateWidget(
        name: androidWidgetProvider,
        androidName: androidWidgetProvider,
      );

      debugPrint(
        '[WidgetSyncService] 桌面小组件已同步刷新 (课表数: ${displayCourses.length}, 标题: $scheduleTitle, 待办数: ${todoListJson.length})',
      );
    } catch (e, stack) {
      debugPrint('[WidgetSyncService] 刷新小组件失败: $e\n$stack');
    }
  }

  static ({String status, String tag}) _computeStatus(
    DateTime now,
    int start,
    int span,
  ) {
    final startInfo = JwglSchedule.periodAt(start + 1);
    final endInfo = JwglSchedule.periodAt(start + span);
    if (startInfo == null || endInfo == null) {
      return (status: 'upcoming', tag: '');
    }

    final startParts = startInfo.start.split(':').map(int.parse).toList();
    final endParts = endInfo.end.split(':').map(int.parse).toList();

    final startTime = DateTime(
      now.year,
      now.month,
      now.day,
      startParts[0],
      startParts[1],
    );
    final endTime = DateTime(
      now.year,
      now.month,
      now.day,
      endParts[0],
      endParts[1],
    );

    if (now.isAfter(endTime)) {
      return (status: 'past', tag: '已结课');
    }

    if (now.isAfter(startTime) && now.isBefore(endTime)) {
      final remaining = endTime.difference(now).inMinutes;
      return (status: 'ongoing', tag: '进行中 (剩${remaining}m)');
    }

    final diffToStart = startTime.difference(now).inMinutes;
    if (diffToStart <= 45 && diffToStart > 0) {
      return (status: 'upcoming', tag: '距上课${diffToStart}m');
    }

    return (status: 'upcoming', tag: '');
  }

  /// 统一将待办截止时间转换为倒计时文本（如“剩 5 小时”、“剩 3 天”），避免显示绝对日期
  static String formatDeadlineText(
    DateTime? ddl,
    DateTime now, {
    String raw = '',
  }) {
    if (ddl == null) {
      if (raw.isNotEmpty) {
        if (raw.contains('已截止') || raw.contains('已逾期') || raw.contains('已结束')) {
          return '已截止';
        }
        return raw;
      }
      return '暂无截止';
    }

    final diff = ddl.difference(now);
    if (diff.isNegative) {
      return '已截止';
    }
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '剩 ${m <= 0 ? 1 : m} 分钟';
    }
    if (diff.inHours < 24) {
      return '剩 ${diff.inHours} 小时';
    }
    return '剩 ${diff.inDays} 天';
  }
}
