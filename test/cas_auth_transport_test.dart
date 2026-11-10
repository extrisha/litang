import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';

const _authUrl = 'https://ids6.usst.edu.cn/authserver/login';
const _form =
    '<form><input type="hidden" name="lt" value="LT-test"/>'
    '<input type="hidden" name="execution" value="e1s1"/>'
    '<input type="hidden" name="_eventId" value="submit"/></form>';
// Synthetic compatible menu; no undocumented school-specific CSS is required.
const _menu = '<html><body>本科教务菜单</body></html>';

ResponseBody _html(
  String body, {
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  body,
  200,
  headers: {
    Headers.contentTypeHeader: ['text/html; charset=utf-8'],
    ...headers,
  },
);

ResponseBody _redirect(String location, {String? cookie}) =>
    ResponseBody.fromString(
      '',
      302,
      headers: {
        'location': [location],
        if (cookie != null) 'set-cookie': [cookie],
      },
    );

class _Transport implements HttpClientAdapter {
  _Transport(this.respond);
  final FutureOr<ResponseBody> Function(
    RequestOptions options,
    String body,
    Future<void>? cancelled,
  )
  respond;
  final requests = <RequestOptions>[];
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = requestStream == null
        ? ''
        : await utf8.decoder.bind(requestStream).join();
    return respond(options, body, cancelFuture);
  }

  @override
  void close({bool force = false}) => closed = true;
}

CasClient _client(
  _Transport transport, {
  Duration authenticationTimeout = const Duration(seconds: 2),
  Duration sessionCheckTimeout = const Duration(seconds: 2),
}) => CasClient(
  dio: Dio(BaseOptions(validateStatus: (_) => true))
    ..httpClientAdapter = transport,
  authenticationTimeout: authenticationTimeout,
  sessionCheckTimeout: sessionCheckTimeout,
);

void main() {
  test('真实Dio传输保留跨域跳转cookie并提交CAS表单', () async {
    final transport = _Transport((request, body, cancelled) {
      expect(request.followRedirects, isFalse);
      expect(cancelled, isNotNull);
      if (request.uri.toString() == CasClient.entryUrl) {
        return _redirect('http://ehall.usst.edu.cn/adapter');
      }
      if (request.uri.host == 'ehall.usst.edu.cn') {
        expect(request.uri.scheme, 'https');
        return _redirect(_authUrl);
      }
      if (request.uri.path.endsWith('needCaptcha.html')) {
        expect(request.headers['Cookie'], contains('CASID=session'));
        return _html('false');
      }
      if (request.uri.toString() == _authUrl) {
        if (request.method == 'GET') {
          return _html(
            _form,
            headers: {
              'set-cookie': ['CASID=session; Path=/authserver'],
            },
          );
        }
        expect(request.headers['Cookie'], contains('CASID=session'));
        expect(Uri.splitQueryString(body), containsPair('username', 'student'));
        expect(Uri.splitQueryString(body), containsPair('password', 'p&=word'));
        expect(Uri.splitQueryString(body), containsPair('execution', 'e1s1'));
        return _redirect(CasClient.indexUrl, cookie: 'CASTGC=TGT; Path=/');
      }
      expect(request.uri.toString(), CasClient.indexUrl);
      return _html(
        _menu,
        headers: {
          'set-cookie': ['JSESSIONID=school; Path=/jwglxt'],
        },
      );
    });
    final client = _client(transport);
    await client.login(' student ', 'p&=word');
    expect(client.studentId, 'student');
    expect(
      client.jar.headerFor(Uri.parse(CasClient.indexUrl)),
      contains('JSESSIONID=school'),
    );
    expect(transport.closed, isFalse);
  });

  for (final entry in {
    '空白页': ' \n ',
    '教务登录页': '<title>用户登录</title>',
    '教务脚本登录页': '<script>location="login_slogin.html";</script>',
    'CAS原地返回的登录表单': _form,
    '无隐藏字段的英文登录表单':
        '<form><input name="username"/>'
        '<input type="password" name="password"/></form>',
    '校内IP限制': '当前 IP 并非校内地址，该信息仅允许校内地址访问',
    '校外IP限制': '校外 IP 无访问权限',
    '网关错误': '<title>502 Bad Gateway</title>',
    '服务暂不可用': '<title>503 Service Unavailable</title>',
  }.entries) {
    test('会话检测拒绝HTTP200的${entry.key}', () async {
      final client = _client(
        _Transport((_, body, cancelled) => _html(entry.value)),
      );
      expect(await client.checkSession(), isFalse);
      expect(client.studentId, isNull);
    });
  }

  test('会话检测拒绝跳到CAS后的HTTP200，即使没有旧中文登录字串', () async {
    final client = _client(
      _Transport(
        (request, body, cancelled) =>
            request.uri.toString() == CasClient.indexUrl
            ? _redirect(_authUrl)
            : _html('<form><input name="username"/></form>'),
      ),
    );
    expect(await client.checkSession(), isFalse);
  });

  test('兼容菜单端点原有成功页面，不猜测额外CSS标记', () async {
    final client = _client(_Transport((_, body, cancelled) => _html(_menu)));
    expect(await client.checkSession(), isTrue);
  });

  test('总截止时间取消底层传输，迟到响应不能写cookie或studentId', () async {
    final response = Completer<ResponseBody>();
    final started = Completer<void>();
    final cancelled = Completer<void>();
    final transport = _Transport((request, body, cancelFuture) {
      cancelFuture!.then((_) => cancelled.complete());
      started.complete();
      return response.future;
    });
    final client = _client(
      transport,
      authenticationTimeout: const Duration(milliseconds: 100),
    );
    final login = client.login('student', 'password');
    final rejected = expectLater(
      login,
      throwsA(
        isA<CasLoginException>().having(
          (error) => error.message,
          'message',
          contains('超时'),
        ),
      ),
    );
    await started.future;
    await rejected;
    await cancelled.future;
    expect(transport.requests, hasLength(1));
    response.complete(_redirect(_authUrl, cookie: 'LATE=bad; Path=/'));
    await Future<void>.delayed(Duration.zero);
    expect(client.jar.cookies, isEmpty);
    expect(client.studentId, isNull);
    expect(transport.requests, hasLength(1));
  });

  test('总截止时间包含网络错误后的重试间隔，不启动迟到重试', () async {
    final transport = _Transport(
      (request, body, cancelled) => throw DioException.connectionError(
        requestOptions: request,
        reason: 'network interrupted',
      ),
    );
    final client = _client(
      transport,
      authenticationTimeout: const Duration(milliseconds: 80),
    );
    await expectLater(
      client.login('student', 'password'),
      throwsA(isA<CasLoginException>()),
    );
    expect(transport.requests, hasLength(1));
    // The old operation is still waiting for its retry delay; cancellation
    // must also prevent that delayed work from resetting a newer session.
    client.studentId = 'newer-session';
    await Future<void>.delayed(const Duration(milliseconds: 2050));
    expect(transport.requests, hasLength(1));
    expect(client.studentId, 'newer-session');
  });

  test('会话检测截止时间涵盖整条多跳链路', () async {
    final transport = _Transport((request, body, cancelled) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return _redirect(
        '/jwglxt/xtgl/index_initMenu.html?hop=next',
        cookie: 'hop=received; Path=/jwglxt',
      );
    });
    final client = _client(
      transport,
      sessionCheckTimeout: const Duration(milliseconds: 75),
    );
    expect(await client.checkSession(), isFalse);
    expect(transport.requests.length, inInclusiveRange(1, 8));
    final count = transport.requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(transport.requests, hasLength(count));
  });

  test('验证码挑战和重试使用同一个CAS会话与隐藏字段', () async {
    var passwordPosts = 0;
    final transport = _Transport((request, body, cancelled) {
      if (request.uri.toString() == CasClient.entryUrl) {
        return _redirect(_authUrl);
      }
      if (request.uri.path.endsWith('needCaptcha.html')) {
        return _html('true');
      }
      if (request.uri.path.endsWith('captcha.html')) {
        expect(request.headers['Cookie'], contains('CASID=challenge'));
        return ResponseBody.fromBytes([1, 2, 3], 200);
      }
      if (request.uri.toString() == _authUrl) {
        if (request.method == 'GET') {
          return _html(
            '$_form<img id="captchaImg"/>',
            headers: {
              'set-cookie': ['CASID=challenge; Path=/authserver'],
            },
          );
        }
        passwordPosts++;
        expect(request.headers['Cookie'], contains('CASID=challenge'));
        final fields = Uri.splitQueryString(body);
        expect(fields['captchaResponse'], '1234');
        expect(fields['lt'], 'LT-test');
        expect(fields['execution'], 'e1s1');
        return _redirect(CasClient.indexUrl);
      }
      return _html(_menu);
    });
    final client = _client(transport);
    CasCaptchaRequired? challenge;
    try {
      await client.login('student', 'password');
      fail('Expected captcha before password submission');
    } on CasCaptchaRequired catch (error) {
      challenge = error;
    }
    expect(passwordPosts, 0);
    expect(challenge.image, [1, 2, 3]);
    await client.loginWithCaptcha(
      username: 'student',
      password: 'password',
      challenge: challenge,
      code: ' 1234 ',
    );
    expect(passwordPosts, 1);
    expect(client.studentId, 'student');
  });

  test('外部取消认证不关闭共享Dio，也不取消业务请求', () async {
    final authResponse = Completer<ResponseBody>();
    final businessResponse = Completer<ResponseBody>();
    final authStarted = Completer<void>();
    final businessStarted = Completer<void>();
    final authCancelled = Completer<void>();
    final transport = _Transport((request, body, cancelled) {
      if (request.uri.toString() == CasClient.indexUrl) {
        cancelled!.then((_) => authCancelled.complete());
        authStarted.complete();
        return authResponse.future;
      }
      expect(cancelled, isNull);
      businessStarted.complete();
      return businessResponse.future;
    });
    final client = _client(transport);
    final auth = client.checkSession();
    final business = client.getJson(Uri.parse('https://jwgl.usst.edu.cn/api'));
    await Future.wait([authStarted.future, businessStarted.future]);
    client.cancelAuthentication();
    expect(await auth, isFalse);
    await authCancelled.future;
    businessResponse.complete(_html('{"ok":true}'));
    expect((await business).data, '{"ok":true}');
    expect(transport.closed, isFalse);
    authResponse.complete(
      _html(
        _menu,
        headers: {
          'set-cookie': ['LATE=bad; Path=/jwglxt'],
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(client.jar.cookies, isEmpty);
  });
}
