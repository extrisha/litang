import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:project_usst/app_theme.dart';
import 'package:project_usst/data/attachment_cache.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/auth/jwgl_auth.dart';
import 'package:project_usst/data/auth/session_store.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/jwc/course_api.dart';
import 'package:project_usst/data/jwc/course_repository.dart';
import 'package:project_usst/data/profile_store.dart';
import 'package:project_usst/pages/login_page.dart';
import 'package:project_usst/pages/profile_page.dart';

class _Client extends CasClient {
  Completer<bool>? sessionGate;
  Completer<void>? scheduleGate;
  bool sessionValid = false;
  bool offline = true;
  int sessionChecks = 0;
  int scheduleCalls = 0;
  String studentName = '联网姓名';

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
              'xsxx': {'XNM': '2026', 'XQM': '3', 'XM': studentName},
              'kbList': [],
            })
          : uri.path.contains('Yhxx')
          ? '<p>工程学院 工程一班</p>'
          : '<html></html>',
    );
  }
}

CourseSnapshot _snapshot(String name, {String college = '工程学院'}) =>
    CourseSnapshot(
      termLabel: '已下载学期',
      xnm: '2026',
      xqm: '3',
      courses: const [],
      updatedAt: DateTime.now(),
      studentName: name,
      collegeName: college,
    );

String _indexKey(String username) =>
    'usst_course_v3_${sha256.convert(utf8.encode(username))}';

Future<void> _mount(WidgetTester tester, JwglAuth auth) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(AttachmentCache.refreshSize);
    auth.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: ProfilePage(auth: auth),
    ),
  );
  await tester.runAsync(AttachmentCache.refreshSize);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final stored = <String, String>{};
  late Directory directory;
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
                'Unexpected secure storage call: ${call.method}',
              );
          }
        });
    PackageInfo.setMockInitialValues(
      appName: '理堂',
      packageName: 'com.example.project_usst',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    directory = await Directory.systemTemp.createTemp(
      'litang-profile-identity-',
    );
    await Directory('${directory.path}/downloads').create();
    AttachmentCache.directoryOverride = () async => directory;
    CacheStore.clearMemory();
    await CourseRepository.clear(username: '');
  });

  tearDown(() async {
    AttachmentCache.directoryOverride = null;
    CacheStore.clearMemory();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  testWidgets('先显示本地姓名，校园网恢复失败后仍保留', (tester) async {
    await SessionStore().save(CasClient(), username: 'A');
    await CourseRepository.save(_snapshot('离线姓名'), username: 'A');
    CacheStore.clearMemory();
    final client = _Client()..sessionGate = Completer<bool>();
    final auth = JwglAuth.forTesting(
      SessionStore(),
      clientFactory: (_) => client,
    );

    await _mount(tester, auth);

    expect(client.sessionChecks, 1);
    expect(auth.isLoggedIn, isFalse);
    expect(find.text('离线姓名'), findsOneWidget);
    client.sessionGate!.complete(false);
    await tester.pumpAndSettle();

    expect(auth.isLoggedIn, isFalse);
    expect(auth.savedUsername, 'A');
    expect(find.text('离线姓名'), findsOneWidget);
    expect(find.text('同学'), findsNothing);
    expect(client.scheduleCalls, 0);
  });

  testWidgets('今日页保存新课表后立即更新同账号姓名，不触发再次同步', (tester) async {
    final client = _Client();
    final auth = JwglAuth.forTesting(SessionStore());
    await auth.adopt(client, 'A', '', remember: false);
    await CourseRepository.save(_snapshot('旧姓名'), username: 'A');
    await _mount(tester, auth);
    expect(find.text('旧姓名'), findsOneWidget);

    await CourseRepository.save(_snapshot('更新姓名'), username: 'A');
    await tester.pumpAndSettle();

    expect(find.text('更新姓名'), findsOneWidget);
    expect(find.text('旧姓名'), findsNothing);
    expect(client.scheduleCalls, 0);
  });

  testWidgets('姓名缺失但学院完整时也补拉，成功空课表保留姓名', (tester) async {
    final client = _Client()..offline = false;
    final auth = JwglAuth.forTesting(SessionStore());
    await auth.adopt(client, 'A', '', remember: false);
    await CourseRepository.save(_snapshot(''), username: 'A');
    await _mount(tester, auth);

    expect(client.scheduleCalls, 1);
    expect(find.text('联网姓名'), findsOneWidget);
    expect(find.text('没取到课表，请稍后重试'), findsNothing);
    expect(find.text('课表更新失败，请检查网络后重试'), findsNothing);
    expect((await CourseRepository.loadCache(username: 'A'))!.courses, isEmpty);
  });

  testWidgets('同账号恢复联网会话后补齐姓名', (tester) async {
    await SessionStore().save(CasClient(), username: 'A');
    await CourseRepository.save(_snapshot(''), username: 'A');
    final auth = JwglAuth.forTesting(
      SessionStore(),
      clientFactory: (_) => _Client(),
    );
    await _mount(tester, auth);
    expect(auth.isLoggedIn, isFalse);
    expect(find.text('同学'), findsOneWidget);

    final client = _Client()..offline = false;
    await auth.adopt(client, 'A', '', remember: false);
    await tester.pumpAndSettle();

    expect(client.scheduleCalls, 1);
    expect(find.text('联网姓名'), findsOneWidget);
  });

  testWidgets('自定义昵称继续优先于真实姓名，按账号隔离', (tester) async {
    final auth = JwglAuth.forTesting(SessionStore());
    await auth.adopt(_Client(), 'A', '', remember: false);
    await CourseRepository.save(_snapshot('A真实姓名'), username: 'A');
    await CourseRepository.save(_snapshot('B真实姓名'), username: 'B');
    await ProfileStore.save(
      const UserProfile(nickname: 'A昵称', avatar: '🐱'),
      username: 'A',
    );
    await _mount(tester, auth);
    expect(find.text('A昵称'), findsOneWidget);

    await auth.adopt(_Client(), 'B', '', remember: false);
    await tester.pumpAndSettle();

    expect(find.text('B真实姓名'), findsOneWidget);
    expect(find.text('A昵称'), findsNothing);
    expect(find.text('🐱'), findsNothing);
  });

  for (final logout in [false, true]) {
    final action = logout ? '退出' : '切换账号';
    testWidgets('$action 后旧网络响应不会覆盖姓名，新账号不被旧加载阻塞', (tester) async {
      final oldClient = _Client()
        ..offline = false
        ..studentName = '迟到旧姓名'
        ..scheduleGate = Completer<void>();
      final auth = JwglAuth.forTesting(SessionStore());
      await auth.adopt(oldClient, 'A', '', remember: false);
      await _mount(tester, auth);
      expect(oldClient.scheduleCalls, 1);

      final newClient = _Client()
        ..offline = false
        ..studentName = 'B真实姓名';
      if (logout) {
        await auth.logout();
      } else {
        await auth.adopt(newClient, 'B', '', remember: false);
      }
      await tester.pumpAndSettle();
      if (!logout) {
        expect(newClient.scheduleCalls, 1);
        expect(find.text('B真实姓名'), findsOneWidget);
      }

      oldClient.scheduleGate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('迟到旧姓名'), findsNothing);
      expect(find.text(logout ? '同学' : 'B真实姓名'), findsOneWidget);
    });

    testWidgets('$action 后旧缓存读取不会覆盖当前姓名', (tester) async {
      final auth = JwglAuth.forTesting(SessionStore());
      await auth.adopt(_Client(), 'A', '', remember: false);
      await CourseRepository.save(_snapshot('A真实姓名'), username: 'A');
      await CourseRepository.save(_snapshot('B真实姓名'), username: 'B');
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

      expect(find.text('A真实姓名'), findsNothing);
      expect(find.text(logout ? '同学' : 'B真实姓名'), findsOneWidget);
    });
  }

  testWidgets('同账号换会话后旧响应也不能经仓库通知覆盖新姓名', (tester) async {
    final oldClient = _Client()
      ..offline = false
      ..studentName = '旧会话姓名'
      ..scheduleGate = Completer<void>();
    final auth = JwglAuth.forTesting(SessionStore());
    await auth.adopt(oldClient, 'A', '', remember: false);
    await _mount(tester, auth);
    expect(oldClient.scheduleCalls, 1);

    final newClient = _Client()
      ..offline = false
      ..studentName = '新会话姓名';
    await auth.adopt(newClient, 'A', '', remember: false);
    await tester.pumpAndSettle();
    expect(find.text('新会话姓名'), findsOneWidget);

    oldClient.scheduleGate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('旧会话姓名'), findsNothing);
    expect(find.text('新会话姓名'), findsOneWidget);
    expect(
      (await CourseRepository.loadCache(username: 'A'))!.studentName,
      '新会话姓名',
    );
  });

  testWidgets('登录页返回成功时保留 adopt 通知已同步的姓名与缓存', (tester) async {
    final auth = JwglAuth.forTesting(SessionStore());
    await _mount(tester, auth);
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);

    final client = _Client()..offline = false;
    await auth.adopt(client, 'A', '', remember: false);
    await tester.pumpAndSettle();
    expect(client.scheduleCalls, 1);
    expect(
      (await CourseRepository.loadCache(username: 'A'))!.studentName,
      '联网姓名',
    );
    client.offline = true;
    Navigator.of(tester.element(find.byType(LoginPage))).pop(true);
    await tester.pumpAndSettle();

    expect(find.text('联网姓名'), findsOneWidget);
    expect(client.scheduleCalls, 1);
    CacheStore.clearMemory();
    expect(
      (await CourseRepository.loadCache(username: 'A'))!.studentName,
      '联网姓名',
    );
    expect(tester.takeException(), isNull);
  });
}
