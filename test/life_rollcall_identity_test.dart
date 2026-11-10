import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/auth/jwgl_auth.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/pages/life/widgets/rollcall_card.dart';
import 'package:project_usst/pages/life_page.dart';

class _Client extends CasClient {
  _Client()
    : super(
        initialCookies: const [
          CasCookie(
            name: 'session',
            value: 'fixture',
            domain: '1906.usst.edu.cn',
            path: '/',
          ),
        ],
      );

  Completer<String>? pendingRollcalls;
  final started = Completer<void>();

  Response<String> response(Uri uri, String body) => Response(
    requestOptions: RequestOptions(path: '$uri'),
    statusCode: 200,
    data: body,
  );

  @override
  Future<Response<String>> getApi(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    if (uri.path.contains('/radar/rollcalls')) {
      final gate = pendingRollcalls;
      if (gate != null) {
        if (!started.isCompleted) started.complete();
        return response(uri, await gate.future);
      }
      return response(uri, '{"rollcalls":[]}');
    }
    if (uri.path == '/user/index') {
      return response(uri, '<input id="userId" value="fixture-user">');
    }
    if (uri.path.endsWith('/courses')) return response(uri, '{"courses":[]}');
    if (uri.path == '/api/todos') return response(uri, '{"todo_list":[]}');
    return response(uri, '{}');
  }

  @override
  Future<Response<String>> getJson(
    Uri uri, {
    Map<String, String>? data,
  }) async => response(
    uri,
    uri.path.contains('kscx') ? '{"items":[]}' : '{"kbList":[]}',
  );
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() async {});
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    CacheStore.clearMemory();
    CacheStore.directoryOverride = () async =>
        throw StateError('memory fixture');
    await JwglAuth.instance.logout();
  });
  tearDown(() async {
    await JwglAuth.instance.logout();
    CacheStore.clearMemory();
    CacheStore.directoryOverride = null;
  });

  for (final fails in [false, true]) {
    testWidgets('退出账号后迟到的签到${fails ? '错误' : '结果'}不覆盖新状态', (tester) async {
      final client = _Client();
      await tester.runAsync(
        () => JwglAuth.instance.adopt(client, 'A', '', remember: false),
      );
      await tester.pumpWidget(const MaterialApp(home: LifePage()));
      for (var i = 0; i < 8; i++) {
        await _drain(tester);
      }
      var card = tester.widget<RollcallCard>(find.byType(RollcallCard));
      expect(card.refreshing, isFalse);

      final gate = Completer<String>();
      client.pendingRollcalls = gate;
      card.onRefresh();
      await _drain(tester);
      expect(client.started.isCompleted, isTrue);
      await tester.runAsync(() => JwglAuth.instance.logout());
      await _drain(tester);
      card = tester.widget<RollcallCard>(find.byType(RollcallCard));
      expect(card.refreshing, isFalse);
      final errorAfterLogout = card.error;

      if (fails) {
        gate.completeError(StateError('old account request failed'));
      } else {
        gate.complete(
          jsonEncode({
            'rollcalls': [
              {'id': 'old-A', 'course_name': '旧账号课程'},
            ],
          }),
        );
      }
      await _drain(tester);
      card = tester.widget<RollcallCard>(find.byType(RollcallCard));
      expect(card.rollcalls, isEmpty);
      expect(card.error, errorAfterLogout);
      expect(card.refreshing, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
