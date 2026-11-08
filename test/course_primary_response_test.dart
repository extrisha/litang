import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/auth/jwgl_auth.dart';
import 'package:project_usst/data/auth/session_store.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/jwc/course_repository.dart';

class _Client extends CasClient {
  _Client() {
    studentId = 'A';
  }
  final extras = Completer<void>();
  Completer<void>? timetableGate;
  Completer<void>? loginGate;
  final requested = <Map<String, String>>[];
  bool invalidDefaultTerm = false;
  bool expired = false;
  bool repairSilently = false;
  bool withExtras = false;
  @override
  Future<bool> silentLogin() async {
    if (!repairSilently) return false;
    expired = false;
    return true;
  }

  @override
  Future<void> login(String username, String password) async {
    if (loginGate != null) await loginGate!.future;
  }

  @override
  Future<Response<String>> getJson(Uri uri, {Map<String, String>? data}) async {
    final timetable = uri.path.contains('xskbcx');
    if (timetable) {
      requested.add(Map.of(data!));
      if (timetableGate != null) await timetableGate!.future;
      if (expired) {
        return Response(
          requestOptions: RequestOptions(path: uri.toString()),
          statusCode: 200,
          data: '<form action="login_slogin.html">用户登录</form>',
        );
      }
      return Response(
        requestOptions: RequestOptions(path: uri.toString()),
        statusCode: 200,
        data: invalidDefaultTerm && data['xnm'] == ''
            ? '<html>请先选择学年学期</html>'
            : '{"xsxx":{"XNM":"2026","XQM":"3","XM":"真实姓名"},"kbList":[{"kcmc":"数学","xqj":"1","jcs":"1-2","zcd":"1-20周"}]}',
      );
    }
    await extras.future;
    return Response(
      requestOptions: RequestOptions(path: uri.toString()),
      statusCode: 200,
      data: withExtras
          ? (uri.path.contains('AreaOne')
                ? '<input id="dqzc" value="5">'
                : '<p>健康科学与工程学院 康复25291002班</p>')
          : '<html></html>',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    CacheStore.clearMemory();
    await CourseRepository.clear(username: 'A');
  });
  test('教学周和学院接口未返回时，课表及姓名先完成并缓存', () async {
    final client = _Client();
    var finished = false;
    final loading = CourseRepository.refresh(client).then((value) {
      finished = true;
      return value;
    });
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final primaryFinished = finished;
    client.extras.complete();
    final snapshot = await loading;
    expect(primaryFinished, isTrue);
    expect(snapshot.studentName, '真实姓名');
    expect(
      (await CourseRepository.loadCache(username: 'A'))!.studentName,
      '真实姓名',
    );
  });
  test('默认学期响应为选择页时仍尝试明确的当前学期，不请求历史学期', () async {
    final client = _Client()..invalidDefaultTerm = true;
    client.extras.complete();
    final snapshot = await CourseRepository.refresh(client);
    expect(snapshot.courses.single.name, '数学');
    expect(client.requested, hasLength(2));
    expect(client.requested.last['xnm'], isNotEmpty);
    expect(client.requested.last['xqm'], isNotEmpty);
  });

  test('失效课表会话仅恢复一次，换client后新结果正常持久化', () async {
    final old = _Client()..expired = true;
    final renewed = _Client();
    old.extras.complete();
    renewed.extras.complete();
    var clients = 0;
    final auth = JwglAuth.forTesting(
      SessionStore(),
      clientFactory: (_) {
        clients++;
        return renewed;
      },
    );
    await auth.adopt(old, 'A', 'saved');
    final snapshot = await CourseRepository.refresh(old, auth: auth);
    expect(snapshot.studentName, '真实姓名');
    expect(auth.client, same(renewed));
    expect(clients, 1);
    expect(
      (await CourseRepository.loadCache(username: 'A'))!.studentName,
      '真实姓名',
    );
    auth.dispose();
  });

  test('静默恢复复用同client时直接重试，不等待自身在途请求', () async {
    final client = _Client()
      ..expired = true
      ..repairSilently = true;
    client.extras.complete();
    final auth = JwglAuth.forTesting(SessionStore());
    await auth.adopt(client, 'A', 'saved');
    final snapshot = await CourseRepository.refresh(client, auth: auth);
    expect(snapshot.courses.single.name, '数学');
    expect(client.requested, hasLength(2));
    expect(auth.client, same(client));
    auth.dispose();
  });

  test('恢复后课表仍失效就返回失败，不无限重复登录或覆盖缓存', () async {
    final old = _Client()..expired = true;
    final renewed = _Client()..expired = true;
    old.extras.complete();
    renewed.extras.complete();
    var clients = 0;
    final auth = JwglAuth.forTesting(
      SessionStore(),
      clientFactory: (_) {
        clients++;
        return renewed;
      },
    );
    await auth.adopt(old, 'A', 'saved');
    await expectLater(
      CourseRepository.refresh(old, auth: auth),
      throwsException,
    );
    expect(clients, 1);
    expect(renewed.requested, hasLength(1));
    expect(await CourseRepository.loadCache(username: 'A'), isNull);
    auth.dispose();
  });

  test('课表先完成，附加信息返回后再写入同账号缓存', () async {
    final client = _Client()..withExtras = true;
    await CourseRepository.refresh(client);
    expect(
      (await CourseRepository.loadCache(username: 'A'))!.currentWeek,
      isNull,
    );
    client.extras.complete();
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final enriched = (await CourseRepository.loadCache(username: 'A'))!;
    expect(enriched.currentWeek, 5);
    expect(enriched.collegeName, '健康科学与工程学院');
    expect(enriched.className, '康复25291002班');
  });

  testWidgets('课表超时后的迟到登录页不再启动认证恢复或写缓存', (tester) async {
    final old = _Client()
      ..expired = true
      ..timetableGate = Completer<void>();
    final renewed = _Client();
    old.extras.complete();
    renewed.extras.complete();
    var clients = 0;
    final auth = JwglAuth.forTesting(
      SessionStore(),
      clientFactory: (_) {
        clients++;
        return renewed;
      },
    );
    addTearDown(() async {
      if (!old.timetableGate!.isCompleted) old.timetableGate!.complete();
      await tester.pump();
      auth.dispose();
    });
    await auth.adopt(old, 'A', 'saved');
    final loading = CourseRepository.refresh(old, auth: auth);
    final rejected = expectLater(loading, throwsException);
    await tester.pump();
    expect(old.requested, hasLength(1));
    await tester.pump(const Duration(seconds: 21));
    await rejected;
    old.timetableGate!.complete();
    await tester.pump();
    expect(clients, 0);
    expect(renewed.requested, isEmpty);
    expect(auth.client, same(old));
    expect(await CourseRepository.loadCache(username: 'A'), isNull);
  });

  testWidgets('换client重试和并发查询共用原20秒期限，迟到结果不缓存', (tester) async {
    final old = _Client()..expired = true;
    final renewed = _Client()
      ..loginGate = Completer<void>()
      ..timetableGate = Completer<void>();
    old.extras.complete();
    renewed.extras.complete();
    final auth = JwglAuth.forTesting(
      SessionStore(),
      clientFactory: (_) => renewed,
    );
    addTearDown(() async {
      if (!renewed.loginGate!.isCompleted) renewed.loginGate!.complete();
      if (!renewed.timetableGate!.isCompleted) {
        renewed.timetableGate!.complete();
      }
      await tester.pump();
      auth.dispose();
    });
    await auth.adopt(old, 'A', 'saved');
    final loading = CourseRepository.refresh(old, auth: auth);
    final rejected = expectLater(loading, throwsException);
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));
    renewed.loginGate!.complete();
    await tester.pump();
    expect(auth.client, same(renewed));
    expect(renewed.requested, hasLength(1));
    final joined = CourseRepository.refresh(renewed, auth: auth);
    expect(joined, same(loading));
    await tester.pump(const Duration(seconds: 9));
    await rejected;
    renewed.timetableGate!.complete();
    await tester.pump();
    expect(renewed.requested, hasLength(1));
    expect(await CourseRepository.loadCache(username: 'A'), isNull);
  });
}
