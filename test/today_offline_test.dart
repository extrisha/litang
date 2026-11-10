import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/auth/jwgl_auth.dart';
import 'package:project_usst/data/auth/session_store.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/calendar/calendar_service.dart';
import 'package:project_usst/data/jwc/course_api.dart';
import 'package:project_usst/data/jwc/course_repository.dart';
import 'package:project_usst/data/models.dart';
import 'package:project_usst/pages/today/widgets/schedule_grid.dart';
import 'package:project_usst/pages/today_page.dart';

class _Client extends CasClient {
  Completer<bool>? sessionGate;
  Completer<void>? scheduleGate;
  bool sessionValid = false;
  bool offline = true;
  int sessionChecks = 0;
  int scheduleCalls = 0;
  String courseName = '重新联网课程';

  @override
  Future<bool> checkSession() async {
    sessionChecks++;
    return sessionGate?.future ?? sessionValid;
  }

  @override
  Future<bool> silentLogin() async => false;

  @override
  Future<Response<String>> getJson(Uri uri, {Map<String, String>? data}) async {
    final timetable = uri.path.contains('xskbcx');
    if (timetable) {
      scheduleCalls++;
      await scheduleGate?.future;
    }
    if (offline) {
      throw DioException(
        requestOptions: RequestOptions(path: uri.toString()),
        type: DioExceptionType.connectionError,
        error: 'campus network unavailable',
      );
    }
    return Response<String>(
      requestOptions: RequestOptions(path: uri.toString()),
      statusCode: 200,
      data: timetable
          ? jsonEncode({
              'xsxx': {'XNM': '2026', 'XQM': '3'},
              'kbList': [
                {
                  'kcmc': courseName,
                  'xqj': '1',
                  'jcs': '1-2',
                  'cdmc': '一教101',
                  'zcd': '1-20周',
                },
              ],
            })
          : '<html></html>',
    );
  }
}

CourseSnapshot _schedule(String name) => CourseSnapshot(
  termLabel: '已下载学期',
  xnm: '2026',
  xqm: '3',
  currentWeek: 1,
  updatedAt: DateTime.now(),
  courses: [
    Course(
      name: name,
      day: 0,
      start: 0,
      span: 2,
      room: '一教101',
      weeks: List<int>.generate(20, (index) => index + 1),
      weeksText: '1-20周',
    ),
  ],
);

String _indexKey(String username) =>
    'usst_course_v3_${sha256.convert(utf8.encode(username))}';

Future<void> _mount(
  WidgetTester tester,
  JwglAuth auth, {
  Size viewport = const Size(320, 640),
  double textScale = 1,
}) async {
  tester.view.physicalSize = viewport * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: TodayPage(auth: auth),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final stored = <String, String>{};
  String? blockedKey;
  Completer<void>? readGate;
  Completer<void>? readStarted;

  setUp(() async {
    stored.clear();
    blockedKey = null;
    readGate = null;
    readStarted = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final arguments = (call.arguments as Map).cast<String, dynamic>();
          final key = arguments['key'] as String?;
          switch (call.method) {
            case 'read':
              final value = stored[key];
              if (key == blockedKey) {
                blockedKey = null;
                readStarted!.complete();
                await readGate!.future;
              }
              return value;
            case 'write':
              stored[key!] = arguments['value'] as String;
              return null;
            case 'delete':
              stored.remove(key);
              return null;
            default:
              throw StateError(
                'Unexpected secure storage method: ${call.method}',
              );
          }
        });
    CacheStore.clearMemory();
    CalendarService.instance.notifier.value = null;
    await CourseRepository.clear();
  });

  tearDown(() {
    CacheStore.clearMemory();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('冷启动在校园网验证结束前显示旧缓存，离线恢复失败后仍显示', (tester) async {
    await SessionStore().save(CasClient(), username: 'A');
    await CacheStore.write(
      'usst_course_snapshot_v2',
      _schedule('离线高数').toJson(),
      secure: true,
    );
    CacheStore.clearMemory();
    final client = _Client()..sessionGate = Completer<bool>();
    final auth = JwglAuth.forTesting(
      SessionStore(),
      clientFactory: (_) => client,
    );
    var restored = false;
    final restoring = auth.restore().then((_) => restored = true);

    await _mount(tester, auth);

    expect(client.sessionChecks, 1);
    expect(restored, isFalse);
    expect(auth.isLoggedIn, isFalse);
    expect(find.byType(ScheduleGrid), findsOneWidget);
    expect(find.text('离线高数'), findsOneWidget);
    client.sessionGate!.complete(false);
    await restoring;
    await tester.pumpAndSettle();

    expect(auth.isLoggedIn, isFalse);
    expect(auth.savedUsername, 'A');
    expect(find.text('离线高数'), findsOneWidget);
    expect(find.text('登录教务，一键同步课表'), findsNothing);
    expect(client.scheduleCalls, 0);
  });

  testWidgets('联网会话刷新抛异常时保留当前账号课表', (tester) async {
    final client = _Client();
    final auth = JwglAuth.forTesting(SessionStore());
    await auth.adopt(client, 'A', '', remember: false);
    await CourseRepository.save(_schedule('已缓存高数'), username: 'A');
    await _mount(tester, auth);

    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();

    expect(client.scheduleCalls, 1);
    expect(find.text('已缓存高数'), findsOneWidget);
    expect(find.text('课表更新失败，请重试'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    CacheStore.clearMemory();
    expect(
      (await CourseRepository.loadCache(username: 'A'))!.courses.single.name,
      '已缓存高数',
    );
  });

  testWidgets('离线缓存的手动刷新可以重新恢复会话并更新课表', (tester) async {
    await SessionStore().save(CasClient(), username: 'A');
    await CourseRepository.save(_schedule('离线高数'), username: 'A');
    final client = _Client();
    final auth = JwglAuth.forTesting(
      SessionStore(),
      clientFactory: (_) => client,
    );
    await auth.restore();
    await _mount(tester, auth);
    expect(find.text('离线高数'), findsOneWidget);

    client.sessionValid = true;
    client.offline = false;
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    await refresh;
    await tester.pumpAndSettle();

    expect(auth.isLoggedIn, isTrue);
    expect(client.sessionChecks, 2);
    expect(find.text('重新联网课程'), findsOneWidget);
    expect(find.text('离线高数'), findsNothing);
  });

  testWidgets('同账号重新登录后，旧会话迟到响应不能覆盖新课表', (tester) async {
    final old = _Client()
      ..offline = false
      ..courseName = '迟到旧会话课程'
      ..scheduleGate = Completer<void>();
    final auth = JwglAuth.forTesting(SessionStore());
    await auth.adopt(old, 'A', '', remember: false);
    await CourseRepository.save(_schedule('原缓存课程'), username: 'A');
    await _mount(tester, auth);
    final refreshing = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    final renewed = _Client()
      ..offline = false
      ..courseName = '新会话课程';
    await auth.adopt(renewed, 'A', '', remember: false);
    await tester.pumpAndSettle();
    expect(find.text('新会话课程'), findsOneWidget);
    old.scheduleGate!.complete();
    await refreshing;
    await tester.pumpAndSettle();
    expect(find.text('迟到旧会话课程'), findsNothing);
    expect(find.text('新会话课程'), findsOneWidget);
  });

  testWidgets('后台补齐课表缓存时今日页更新教学周而不再次发网络请求', (tester) async {
    final client = _Client();
    final auth = JwglAuth.forTesting(SessionStore());
    await auth.adopt(client, 'A', '', remember: false);
    await CourseRepository.save(_schedule('已缓存课程'), username: 'A');
    await _mount(tester, auth);
    await CourseRepository.save(
      _schedule('已缓存课程').copyWith(currentWeek: 5),
      username: 'A',
    );
    await tester.pumpAndSettle();
    expect(find.text('第5周 (本周)'), findsOneWidget);
    expect(client.scheduleCalls, 0);
  });

  for (final viewport in [const Size(320, 640), const Size(390, 844)]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        '${viewport.width}x${viewport.height} 字号$textScale 完整显示节次时间',
        (tester) async {
          final auth = JwglAuth.forTesting(SessionStore());
          await auth.adopt(_Client(), 'A', '', remember: false);
          await CourseRepository.save(_schedule('离线高数'), username: 'A');
          await _mount(tester, auth, viewport: viewport, textScale: textScale);

          expect(tester.takeException(), isNull);
          expect(find.text('08:00'), findsOneWidget);
          expect(find.text('离线高数'), findsOneWidget);
          final firstTime = tester.getRect(find.text('08:00'));
          final firstPeriod = tester.getRect(find.text('1'));
          final secondPeriod = tester.getRect(find.text('2'));
          expect(firstTime.top, greaterThanOrEqualTo(firstPeriod.bottom));
          expect(firstTime.bottom, lessThan(secondPeriod.top));

          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -1600),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final lastTime = tester.getRect(find.text('20:10'));
          final screen = tester.getRect(find.byType(Scaffold));
          expect(lastTime.top, greaterThan(screen.top));
          expect(lastTime.bottom, lessThanOrEqualTo(screen.bottom));
        },
      );
    }
  }

  for (final logout in [false, true]) {
    final action = logout ? '退出' : '切换账号';
    testWidgets('$action 后迟到的刷新结果不会显示旧账号课程', (tester) async {
      final oldClient = _Client()
        ..offline = false
        ..courseName = '迟到旧课程'
        ..scheduleGate = Completer<void>();
      final auth = JwglAuth.forTesting(SessionStore());
      await auth.adopt(oldClient, 'A', '', remember: false);
      await CourseRepository.save(_schedule('A账号课程'), username: 'A');
      await CourseRepository.save(_schedule('B账号课程'), username: 'B');
      await _mount(tester, auth);
      expect(find.text('A账号课程'), findsOneWidget);
      final refreshing = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();
      expect(oldClient.scheduleCalls, 1);

      if (logout) {
        await auth.logout();
      } else {
        await auth.adopt(_Client(), 'B', '', remember: false);
      }
      await tester.pumpAndSettle();
      expect(find.text('A账号课程'), findsNothing);
      if (logout) {
        expect(find.text('登录教务，一键同步课表'), findsOneWidget);
      } else {
        expect(find.text('B账号课程'), findsOneWidget);
      }

      oldClient.scheduleGate!.complete();
      await refreshing;
      await tester.pumpAndSettle();
      expect(find.text('迟到旧课程'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      if (logout) {
        expect(find.byType(ScheduleGrid), findsNothing);
      } else {
        expect(find.text('B账号课程'), findsOneWidget);
      }
    });

    testWidgets('$action 后迟到的缓存读取不会显示旧账号课程', (tester) async {
      final auth = JwglAuth.forTesting(SessionStore());
      await auth.adopt(_Client(), 'A', '', remember: false);
      await CourseRepository.save(_schedule('A账号课程'), username: 'A');
      await CourseRepository.save(_schedule('B账号课程'), username: 'B');
      CacheStore.clearMemory();
      blockedKey = _indexKey('A');
      readGate = Completer<void>();
      readStarted = Completer<void>();
      await _mount(tester, auth);
      expect(readStarted!.isCompleted, isTrue);

      if (logout) {
        await auth.logout();
      } else {
        await auth.adopt(_Client(), 'B', '', remember: false);
      }
      await tester.pumpAndSettle();
      readGate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('A账号课程'), findsNothing);
      if (logout) {
        expect(find.text('登录教务，一键同步课表'), findsOneWidget);
        expect(find.byType(ScheduleGrid), findsNothing);
      } else {
        expect(find.text('B账号课程'), findsOneWidget);
      }
    });
  }
}
