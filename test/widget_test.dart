import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/app_theme.dart';
import 'package:project_usst/data/models.dart';
import 'package:project_usst/data/notice_prefs.dart';
import 'package:project_usst/data/notice_source.dart';
import 'package:project_usst/pages/home_page.dart';
import 'package:project_usst/pages/map_page.dart';
import 'package:project_usst/pages/profile_page.dart';
import 'package:project_usst/pages/search_page.dart';
import 'package:project_usst/widgets/course_table.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

void main() {
  test('主题主色是上理红', () {
    expect(AppTheme.light().colorScheme.primary, AppColors.usstRed);
  });

  testWidgets('首页用演示数据源渲染通知流', (tester) async {
    await tester.pumpWidget(_wrap(const HomePage(source: DemoNoticeSource())));
    await tester.pumpAndSettle();

    expect(find.text('搜通知、公告，比如“寒假安排”'), findsOneWidget);
    expect(find.text('关于调整校园上下课铃声的通知'), findsOneWidget);
    expect(find.byType(ListView), findsWidgets);
  });

  testWidgets('点击搜索框进入搜索页', (tester) async {
    await tester.pumpWidget(_wrap(const HomePage(source: DemoNoticeSource())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('搜通知、公告，比如“寒假安排”'));
    await tester.pumpAndSettle();

    expect(find.text('热门搜索'), findsOneWidget);
    expect(find.textContaining('共 '), findsWidgets);
  });

  testWidgets('搜索空结果提示换个关键词', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SearchPage(
          source: const DemoNoticeSource(),
          initialNotices: const <Notice>[
            Notice(dept: '教务处', kind: '通知', title: '关于2026年寒假安排的通知'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '空教室');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('换个关键词试试'), findsOneWidget);
  });

  testWidgets('地图页可搜索楼栋并展示信息', (tester) async {
    await tester.pumpWidget(_wrap(const MapPage()));

    expect(find.text('校园地图'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '第一教学楼');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '第一教学楼'));
    await tester.pumpAndSettle();

    expect(find.text('第一教学楼'), findsWidgets);
    expect(find.textContaining('军工路'), findsWidgets);
  });

  testWidgets('我的页展示学业入口与空间服务', (tester) async {
    await tester.pumpWidget(_wrap(const ProfilePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('学业'), findsOneWidget);
    // 课表已单独抽取为「今日」独立Tab，我的页不再保留课表区块
    expect(find.textContaining('课表'), findsNothing);
    // 空间入口：教室查询 / 学工一体化，旧的「我的课表」已移除
    expect(find.text('空间预约'), findsOneWidget);
    expect(find.text('教室查询'), findsNothing);
    expect(find.text('学工一体化'), findsOneWidget);
    expect(find.text('我的课表'), findsNothing);
    // 个人信息卡：默认头像 + 昵称
    expect(find.text('🎓'), findsOneWidget);
    expect(find.text('同学'), findsOneWidget);
  });

  testWidgets('课表左栏显示每节起止时间', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Scaffold(
          body: SingleChildScrollView(
            child: CourseWeekTable(
              week: 3,
              courses: <Course>[
                Course(
                  name: '大学物理',
                  day: 2,
                  start: 2,
                  span: 3,
                  room: '三教106',
                  weeks: <int>[3, 4, 5],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('第1节'), findsOneWidget);
    expect(find.text('08:00-08:40'), findsOneWidget);
    expect(find.text('第13节'), findsOneWidget);
    expect(find.text('19:30-20:10'), findsOneWidget);
    // 课程块里只留课程名 / 教室 / 教师，不再显示上课时间
    expect(find.textContaining('09:45-11:55'), findsNothing);
    expect(find.text('大学物理'), findsOneWidget);
    expect(find.text('三教106'), findsOneWidget);
  });

  testWidgets('课表组件按节次渲染课程', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Scaffold(
          body: SingleChildScrollView(
            child: CourseWeekTable(
              week: 3,
              courses: <Course>[
                Course(
                  name: '高等数学',
                  day: 0,
                  start: 0,
                  span: 2,
                  room: '三教305',
                  weeks: <int>[3, 4],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('三教305'), findsOneWidget);
  });

  group('首页 + 真实产物', () {
    final file = File('tools/notice-sync/out/notices.json');
    if (!file.existsSync()) {
      test('跳过：本地没有 notices.json', () {}, skip: true);
      return;
    }

    testWidgets('7000+ 条真实数据不溢出，筛选条能用', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(HomePage(source: _FileSource(file))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 筛选条在（分类和「本院」都在）
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('竞赛'), findsWidgets);
      expect(find.text('学院'), findsOneWidget);

      // 点「竞赛」后列表只剩竞赛（至少还能找到竞赛标签）
      await tester.tap(find.text('竞赛').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 往下滚几屏，确认懒加载不会崩
      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -1200));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('首页筛选', () {
    Notice notice(String dept, String kind, String title, DateTime at) =>
        Notice(
          dept: dept,
          kind: kind,
          scope: 'college',
          title: title,
          publishedAt: at,
        );

    NoticeSource source() => _FixedSource(<Notice>[
      notice('A学院', '竞赛', 'A学院的竞赛通知', DateTime.now()),
      notice('B学院', '通知', 'B学院的通知', DateTime.now()),
    ]);

    setUp(() {
      NoticePrefs.debugSkipStorage = true;
    });
    tearDown(() async {
      await NoticePrefs.setSelected(null);
      NoticePrefs.debugReset();
      NoticePrefs.debugSkipStorage = false;
    });

    testWidgets('选了学院就筛选，筛出空结果时筛选条还在', (tester) async {
      await NoticePrefs.setSelected('B学院');
      await tester.pumpWidget(_wrap(HomePage(source: source())));
      await tester.pumpAndSettle();

      // 选了学院之后按钮上显示的就是学院名
      expect(find.text('B学院'), findsWidgets);
      expect(find.text('B学院的通知'), findsOneWidget);
      expect(find.text('A学院的竞赛通知'), findsNothing);

      // 再筛「竞赛」→ 空
      await tester.tap(find.text('竞赛').first);
      await tester.pumpAndSettle();
      expect(find.text('B学院的通知'), findsNothing);

      // 关键：筛选条不能跟着消失，否则回不去
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('B学院'), findsWidgets);
      expect(find.text('清除筛选'), findsOneWidget);

      // 清除后恢复
      await tester.tap(find.text('清除筛选'));
      await tester.pumpAndSettle();
      expect(find.text('B学院的通知'), findsOneWidget);
      expect(find.text('A学院的竞赛通知'), findsOneWidget);
    });

    testWidgets('学院可以反复选，选完标签变成学院名', (tester) async {
      await tester.pumpWidget(_wrap(HomePage(source: source())));
      await tester.pumpAndSettle();

      // 没选的时候按钮写「学院」
      expect(find.text('学院'), findsOneWidget);
      expect(find.text('A学院的竞赛通知'), findsOneWidget);

      // 打开选择框 → 选 A学院
      await tester.tap(find.text('学院'));
      await tester.pumpAndSettle();
      expect(find.text('按学院筛选'), findsOneWidget);
      expect(find.text('全部学院'), findsOneWidget);

      await tester.tap(find.text('A学院').last);
      await tester.pumpAndSettle();
      expect(find.text('A学院的竞赛通知'), findsOneWidget);
      expect(find.text('B学院的通知'), findsNothing);

      // 再改回「全部学院」
      await tester.tap(find.text('A学院').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部学院'));
      await tester.pumpAndSettle();
      expect(find.text('学院'), findsOneWidget);
      expect(find.text('A学院的竞赛通知'), findsOneWidget);
      expect(find.text('B学院的通知'), findsOneWidget);
    });
  });
}

/// 用本地产物当数据源，避免 widget 测试里发网络请求。
class _FileSource implements NoticeSource {
  _FileSource(this.file);

  final File file;

  @override
  Future<NoticeFeed> fetch({bool force = false}) async =>
      RemoteNoticeSource.parseFeed(file.readAsStringSync())!;
}

/// 固定几条数据，用来构造边界场景（比如筛出空结果）。
class _FixedSource implements NoticeSource {
  _FixedSource(this.notices);

  final List<Notice> notices;

  @override
  Future<NoticeFeed> fetch({bool force = false}) async =>
      NoticeFeed(notices: notices);
}
