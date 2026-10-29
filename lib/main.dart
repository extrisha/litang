import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'data/calendar/calendar_service.dart';
import 'data/chaoxing/chaoxing_client.dart';
import 'data/lms/todo_api.dart';
import 'data/map_focus.dart';
import 'data/notice_source.dart';
import 'pages/chaoxing_homework_page.dart';
import 'pages/home_page.dart';
import 'pages/homework_page.dart';
import 'pages/update_page.dart';
import 'services/reminder_service.dart';
import 'services/update_service.dart';
import 'pages/life_page.dart';
import 'pages/map_page.dart';
import 'pages/forum_page.dart';
import 'pages/profile_page.dart';
import 'pages/today_page.dart';
import 'widgets/usst_campus_icon.dart';
import 'widgets/usst_today_icon.dart';

/// 全局导航 key：点通知时要能从任意位置跳转。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CalendarService.instance.load();
  runApp(const CampusApp());
  // 启动后在后台静默同步一次作业提醒（不阻塞首屏，6 小时内不会重复跑）
  unawaited(ReminderService.instance.syncInBackground());
}

class CampusApp extends StatelessWidget {
  const CampusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '理堂',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: AppTheme.light(),
      home: const RootScaffold(),
    );
  }
}

/// 底部五 Tab 骨架：信息 / 校园 / 今日 / 理评 / 我的
class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> with WidgetsBindingObserver {
  int _index = 2;

  static bool _checkedUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MapFocus.target.addListener(_onMapFocus);
    ReminderService.pendingTarget.addListener(_onReminderTap);
    // App 是被通知点开的：首帧之后补一次跳转
    if (ReminderService.pendingTarget.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onReminderTap());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_checkedUpdate || !mounted) return;
      _checkedUpdate = true;
      final info = await UpdateService.check();
      if (info != null && mounted) {
        await showUpdateDialog(
          context,
          info,
          startup: true,
          mandatory: info.mandatory,
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MapFocus.target.removeListener(_onMapFocus);
    ReminderService.pendingTarget.removeListener(_onReminderTap);
    super.dispose();
  }

  void _onMapFocus() {
    final target = MapFocus.target.value;
    if (target != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const MapPage()),
      );
    }
  }

  /// 点了提醒通知：直接跳到对应作业详情。
  void _onReminderTap() {
    final target = ReminderService.pendingTarget.value;
    if (target == null || !mounted) return;
    ReminderService.pendingTarget.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final page = _pageForReminder(target);
      if (page == null) return;
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    });
  }

  Widget? _pageForReminder(Map<String, dynamic> target) {
    switch ('${target['kind']}') {
      case 'tron':
        final id = (target['id'] as num?)?.toInt() ?? 0;
        if (id <= 0) return null;
        return HomeworkPage(
          todo: LmsTodo(
            id: id,
            courseId: (target['courseId'] as num?)?.toInt() ?? 0,
            title: '${target['title'] ?? ''}',
            courseName: '${target['courseName'] ?? ''}',
            type: 'homework',
            deadline: null,
          ),
        );
      case 'cx':
        final taskUrl = '${target['taskUrl'] ?? ''}';
        if (taskUrl.isEmpty) return null;
        return ChaoxingHomeworkPage(
          work: ChaoxingWork(
            workId: '${target['workId'] ?? ''}',
            title: '${target['title'] ?? ''}',
            courseName: '${target['courseName'] ?? ''}',
            statusText: '${target['statusText'] ?? ''}',
            deadline: '${target['deadline'] ?? ''}',
            expired: target['expired'] == true,
            taskUrl: taskUrl,
          ),
        );
      default:
        return null;
    }
  }

  /// 页面只构建一次；首页在这里注入真实数据源，页面本身仍可单独注入演示数据。
  static final List<Widget> _pages = [
    HomePage(source: RemoteNoticeSource()),
    const LifePage(),
    const TodayPage(),
    const ForumPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.feed_outlined),
            selectedIcon: Icon(Icons.feed),
            label: '信息',
          ),
          const NavigationDestination(
            icon: UsstCampusIcon(selected: false),
            selectedIcon: UsstCampusIcon(selected: true),
            label: '校园',
          ),
          const NavigationDestination(
            icon: UsstTodayNavIcon(selected: false),
            selectedIcon: UsstTodayNavIcon(selected: true),
            label: '今日',
          ),
          const NavigationDestination(
            icon: Icon(Icons.rate_review_outlined),
            selectedIcon: Icon(Icons.rate_review),
            label: '理评',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
