import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/lms/course_visit_history.dart';
import 'package:project_usst/data/lms/todo_api.dart';
import 'package:project_usst/pages/life/widgets/life_course_card.dart';

const _courses = <LmsCourseInfo>[
  LmsCourseInfo(id: 'math', name: '高等数学', teacher: '张老师', termCode: ''),
  LmsCourseInfo(id: 'physics', name: '大学物理', teacher: '李老师', termCode: ''),
];

void main() {
  testWidgets('点击课程后立即排到第一位，来源切换可反复操作', (tester) async {
    var courses = _courses;
    var recent = <String>[];
    var chaoxing = false;
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => LifeCourseCard(
              courseInfos: courses,
              coursesLoading: false,
              coursesError: null,
              showChaoxingCourses: chaoxing,
              onToggleSource: () => setState(() => chaoxing = !chaoxing),
              onRetry: () {},
              onLoginChaoxing: () {},
              onOpenCourse: (course) => setState(() {
                opened.add(course.id);
                recent = CourseVisitHistory.promote(recent, course.id);
                courses = CourseVisitHistory.sort(courses, recent);
              }),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('大学物理'));
    await tester.pump();
    expect(opened, ['physics']);
    expect(
      tester.getTopLeft(find.text('大学物理')).dx,
      lessThan(tester.getTopLeft(find.text('高等数学')).dx),
    );
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byIcon(Icons.swap_horiz));
      await tester.pump();
    }
    expect(chaoxing, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320 宽度和双倍字体不溢出，空课程有明确提示', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget view(List<LmsCourseInfo> courses) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: LifeCourseCard(
            courseInfos: courses,
            coursesLoading: false,
            coursesError: null,
            showChaoxingCourses: false,
            onOpenCourse: (_) {},
            onToggleSource: () {},
            onRetry: () {},
            onLoginChaoxing: () {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(view(_courses));
    expect(tester.takeException(), isNull);
    final title = tester.renderObject<RenderParagraph>(find.text('课程信息'));
    expect(title.size.width, greaterThan(0));
    expect(title.didExceedMaxLines, isFalse, reason: '课程标题必须完整可见，不能被来源开关挤掉');
    await tester.pumpWidget(view([]));
    expect(find.text('本学期暂无课程'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
