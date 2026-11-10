import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/auth/jwgl_auth.dart';
import 'package:project_usst/data/auth/session_store.dart';
import 'package:project_usst/pages/login_page.dart';

class _Store extends SessionStore {
  StoredSession? value;
  @override
  Future<StoredSession?> load() async => value;
  @override
  Future<void> save(
    CasClient client, {
    required String username,
    String? password,
  }) async {
    value = StoredSession(
      cookies: List.of(client.jar.cookies),
      username: username,
      password: password,
      savedAt: DateTime.now(),
    );
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _LoginTransport implements HttpClientAdapter {
  final firstResponse = Completer<ResponseBody>();
  int entryRequests = 0;
  int passwordPosts = 0;
  bool firstCancelled = false;
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? body,
    Future<void>? cancelled,
  ) async {
    if (request.uri.toString() == CasClient.entryUrl) {
      entryRequests++;
      if (entryRequests == 1) {
        cancelled!.then((_) => firstCancelled = true);
        return firstResponse.future;
      }
      return ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['https://ids6.usst.edu.cn/authserver/login'],
        },
      );
    }
    if (request.uri.path.endsWith('needCaptcha.html')) {
      return ResponseBody.fromString('false', 200);
    }
    if (request.uri.host == 'ids6.usst.edu.cn') {
      if (request.method == 'GET') {
        return ResponseBody.fromString(
          '<input type="hidden" name="lt" value="LT-test"/>'
          '<input type="hidden" name="execution" value="e1s1"/>',
          200,
        );
      }
      passwordPosts++;
      final form = Uri.splitQueryString(await utf8.decoder.bind(body!).join());
      expect(form['username'], 'B');
      expect(form['password'], 'password');
      return ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': [CasClient.indexUrl],
        },
      );
    }
    return ResponseBody.fromString('<html>教务菜单</html>', 200);
  }

  @override
  void close({bool force = false}) => closed = true;
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var frame = 0; frame < 100; frame++) {
    await tester.pump(const Duration(milliseconds: 1));
    if (done()) return;
  }
  fail('Login transport did not reach the expected state within 100 frames');
}

void main() {
  testWidgets('真实登录页忙时禁重复提交，超时恢复按钮并可成功重试', (tester) async {
    final store = _Store();
    final auth = JwglAuth.forTesting(store);
    final transport = _LoginTransport();
    final client = CasClient(
      dio: Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = transport,
      authenticationTimeout: const Duration(seconds: 1),
    );
    bool? result;
    addTearDown(() async {
      client.cancelAuthentication();
      if (!transport.firstResponse.isCompleted) {
        transport.firstResponse.complete(ResponseBody.fromString('', 200));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => LoginPage(auth: auth, client: client),
                  ),
                );
              },
              child: const Text('打开登录'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开登录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '学号'), 'B');
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'password');
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await _pumpUntil(tester, () => transport.entryRequests == 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    tester.widget<TextField>(find.widgetWithText(TextField, '密码')).onSubmitted!(
      'password',
    );
    await tester.pump();
    expect(transport.entryRequests, 1);

    await tester.pump(const Duration(milliseconds: 1010));
    expect(find.textContaining('响应超时'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(transport.firstCancelled, isTrue);
    expect(auth.isLoggedIn, isFalse);
    expect(store.value, isNull);

    transport.firstResponse.complete(
      ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['https://ids6.usst.edu.cn/authserver/login'],
          'set-cookie': ['LATE=invalid; Path=/'],
        },
      ),
    );
    await tester.pump();
    expect(client.jar.cookies, isEmpty);
    expect(result, isNull);
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await _pumpUntil(tester, () => result == true);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsNothing);
    expect(result, isTrue);
    expect(auth.studentId, 'B');
    expect(store.value!.username, 'B');
    expect(store.value!.password, 'password');
    expect(transport.entryRequests, 2);
    expect(transport.passwordPosts, 1);
    expect(transport.closed, isFalse);
    expect(tester.takeException(), isNull);
  });
}
