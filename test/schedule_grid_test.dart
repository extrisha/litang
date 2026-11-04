import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/models.dart';
import 'package:project_usst/pages/today/models/course_theme.dart';
import 'package:project_usst/pages/today/widgets/schedule_grid.dart';

/// 真正上屏的课表组件（`today_page` 用的就是它）。
void main() {
  Future<void> pumpGrid(
    WidgetTester tester, {
    required List<Course> courses,
    int selectedWeek = 1,
    int? activePeriod,
    void Function(Course)? onDoubleTap,
  }) async {
    // 课表网格按「可用高度 / 11」算行高，必须给它一个真实手机尺寸的画布，
    // 否则默认 800x600 会被压扁，行高偏小触发溢出。
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final controller = PageController(initialPage: selectedWeek - 1);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleGrid(
            weekCount: 20,
            pageOf: (week) {
              final weekCourses = courses
                  .where((c) => c.activeInWeek(week))
                  .toList();
              return WeekPage(
                week: week,
                courses: weekCourses,
                themeMap: buildCourseThemeMap(weekCourses),
                isCurrentWeek: week == selectedWeek,
              );
            },
            pageController: controller,
            onPageChanged: (_) {},
            activePeriod: activePeriod,
            displayedWeek: selectedWeek,
            currentWeek: selectedWeek,
            isToday: (_) => false,
            dateForDay: (_, _) => null,
            onRefresh: () async {},
            onCourseTap: (_) {},
            onCourseDoubleTap: onDoubleTap ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('只渲染选中教学周的课程', (tester) async {
    await pumpGrid(
      tester,
      selectedWeek: 4,
      courses: const <Course>[
        Course(
          name: '本周课',
          day: 0,
          start: 0,
          span: 2,
          room: '1',
          weeks: <int>[3, 4],
        ),
        Course(
          name: '下周课',
          day: 1,
          start: 2,
          span: 2,
          room: '2',
          weeks: <int>[5, 6],
        ),
        Course(name: '全学期课', day: 2, start: 4, span: 2, room: '3'),
      ],
    );

    expect(find.text('本周课'), findsOneWidget);
    expect(find.text('全学期课'), findsOneWidget);
    expect(find.text('下周课'), findsNothing);
  });

  testWidgets('左栏渲染 13 节的起止时间', (tester) async {
    await pumpGrid(tester, courses: const <Course>[]);

    expect(find.text('08:00'), findsOneWidget); // 第 1 节开始
    expect(find.text('20:10'), findsOneWidget); // 第 13 节结束
    // 左栏节次序号 1..13 都在
    expect(find.text('1'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
  });

  testWidgets('双击课程触发定位回调', (tester) async {
    Course? tapped;
    await pumpGrid(
      tester,
      courses: const <Course>[
        Course(
          name: '高等数学',
          day: 0,
          start: 0,
          span: 2,
          room: '三教305',
          teacher: '王老师',
        ),
      ],
      onDoubleTap: (c) => tapped = c,
    );

    await tester.tap(find.text('高等数学'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('高等数学'));
    await tester.pumpAndSettle();

    expect(tapped?.name, '高等数学');
  });

  testWidgets('没有周末课时不占位，有周六课才展开周六', (tester) async {
    await pumpGrid(tester, courses: const <Course>[]);
    expect(find.text('周六'), findsNothing);
    expect(find.text('周日'), findsNothing);

    await pumpGrid(
      tester,
      courses: const <Course>[
        Course(name: '周六课', day: 5, start: 0, span: 1, room: '1'),
      ],
    );
    expect(find.text('周六'), findsOneWidget);
    expect(find.text('周日'), findsNothing);
  });

  testWidgets('周末列按「当周」判断：别的周有周六课不影响本周', (tester) async {
    // 周六课只在第 5 周上
    const courses = <Course>[
      Course(
        name: '周六课',
        day: 5,
        start: 0,
        span: 1,
        room: '1',
        weeks: <int>[5],
      ),
    ];

    // 看第 1 周：本周没有周六课，不该占位
    await pumpGrid(tester, courses: courses, selectedWeek: 1);
    expect(find.text('周六'), findsNothing);

    // 看第 5 周：这一周有周六课，展开周六列
    await pumpGrid(tester, courses: courses, selectedWeek: 5);
    expect(find.text('周六'), findsOneWidget);
  });

  testWidgets('当前节次高亮不崩、网格正常绘制', (tester) async {
    await pumpGrid(
      tester,
      activePeriod: 3,
      courses: const <Course>[
        Course(name: '高数', day: 0, start: 0, span: 2, room: '1'),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('高数'), findsOneWidget);
  });
}
