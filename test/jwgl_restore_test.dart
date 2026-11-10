import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/jwgl_auth.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/auth/session_store.dart';

class _Store extends SessionStore {
  final result = Completer<StoredSession?>();
  int reads = 0;
  @override
  Future<StoredSession?> load() {
    reads++;
    return result.future;
  }

  @override
  Future<void> clear() async {}
  @override
  Future<void> save(
    CasClient client, {
    required String username,
    String? password,
  }) async {}
}

class _PersistedStore extends SessionStore {
  _PersistedStore(this.stored);
  StoredSession? stored;
  int clears = 0;
  int reads = 0;

  @override
  Future<StoredSession?> load() async {
    reads++;
    return stored;
  }

  @override
  Future<void> clear() async {
    clears++;
    stored = null;
  }

  @override
  Future<void> save(
    CasClient client, {
    required String username,
    String? password,
  }) async {
    stored = StoredSession(
      cookies: List.of(client.jar.cookies),
      username: username,
      password: password,
      savedAt: DateTime.now(),
    );
  }
}

class _OfflineAdapter implements HttpClientAdapter {
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: StateError('campus network unavailable'),
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Client extends CasClient {
  _Client({this.valid = false, this.loginError});
  final bool valid;
  final Object? loginError;

  @override
  Future<bool> checkSession() async => valid;

  @override
  Future<bool> silentLogin() async => false;

  @override
  Future<void> login(String username, String password) async {
    if (loginError != null) throw loginError!;
  }
}

StoredSession _session({String? password}) => StoredSession(
  cookies: const [
    CasCookie(
      name: 'JSESSIONID',
      value: 'saved-session',
      domain: 'jwgl.usst.edu.cn',
      path: '/',
    ),
  ],
  username: 'A',
  password: password,
  savedAt: DateTime(2026, 11, 7),
);

void main() {
  test('离校冷启动网络失败保留本地身份和会话，联网后可重试恢复', () async {
    final stored = _session();
    final store = _PersistedStore(stored);
    final adapter = _OfflineAdapter();
    var offline = true;
    final auth = JwglAuth.forTesting(
      store,
      clientFactory: (cookies) {
        if (!offline) return _Client(valid: true);
        return CasClient(
          dio: Dio()..httpClientAdapter = adapter,
          initialCookies: cookies,
        );
      },
    );

    await auth.restore();
    expect(adapter.requests, 2);
    expect(auth.isLoggedIn, isFalse);
    expect(auth.client, isNull);
    expect(auth.studentId, 'A');
    expect(auth.savedUsername, 'A');
    expect(store.stored, same(stored));
    expect(store.clears, 0);

    offline = false;
    await auth.restore();
    expect(store.reads, 2);
    expect(auth.isLoggedIn, isTrue);
    expect(auth.client?.studentId, 'A');
    await auth.logout();
    expect(auth.studentId, isNull);
    expect(auth.savedUsername, isEmpty);
    expect(store.stored, isNull);
    expect(store.clears, 1);
    auth.dispose();
  });

  test('离线自动登录失败仍保留记住的密码且不冒充在线登录', () async {
    final stored = _session(password: 'remembered');
    final store = _PersistedStore(stored);
    final auth = JwglAuth.forTesting(
      store,
      clientFactory: (_) =>
          _Client(loginError: const CasLoginException('网络不稳定，登录失败，请稍后重试')),
    );
    await auth.restore();
    expect(auth.isLoggedIn, isFalse);
    expect(auth.savedPassword, 'remembered');
    expect(auth.savedUsername, 'A');
    expect(store.stored, same(stored));
    expect(store.clears, 0);
    auth.dispose();
  });

  test('泛化登录提示不是明确密码拒绝，不能因此清掉本地身份', () async {
    final stored = _session(password: 'remembered');
    final store = _PersistedStore(stored);
    final auth = JwglAuth.forTesting(
      store,
      clientFactory: (_) =>
          _Client(loginError: const CasLoginException('登录失败，请检查学号和密码')),
    );
    await auth.restore();
    expect(auth.isLoggedIn, isFalse);
    expect(auth.savedUsername, 'A');
    expect(auth.savedPassword, 'remembered');
    expect(store.clears, 0);
    auth.dispose();
  });

  test('明确凭据错误仍清掉身份，不自动恢复错误会话', () async {
    final store = _PersistedStore(_session(password: 'rejected'));
    final auth = JwglAuth.forTesting(
      store,
      clientFactory: (_) =>
          _Client(loginError: const CasLoginException('用户名或密码错误')),
    );
    await auth.restore();
    expect(auth.isLoggedIn, isFalse);
    expect(auth.studentId, isNull);
    expect(auth.savedUsername, isEmpty);
    expect(store.stored, isNull);
    expect(store.clears, 1);
    auth.dispose();
  });

  test('旧恢复返回不能清掉期间新登录的账号', () async {
    final store = _Store();
    final auth = JwglAuth.forTesting(store);
    final restoring = auth.restore();
    await Future<void>.delayed(Duration.zero);
    final client = CasClient();
    await auth.adopt(client, 'B', '', remember: false);
    store.result.complete(null);
    await restoring;
    expect(auth.studentId, 'B');
    expect(client.studentId, 'B');
    expect(auth.client, same(client));
    auth.dispose();
  });
  test('退出后迟到的本地会话不能重新恢复账号', () async {
    final store = _Store();
    final auth = JwglAuth.forTesting(store);
    final restoring = auth.restore();
    await Future<void>.delayed(Duration.zero);
    await auth.logout();
    store.result.complete(
      StoredSession(cookies: [], username: 'A', savedAt: DateTime.now()),
    );
    await restoring;
    expect(auth.studentId, isNull);
    expect(auth.isLoggedIn, isFalse);
    auth.dispose();
  });
  test('并发恢复均等待同一份本地会话读取', () async {
    final store = _Store();
    final auth = JwglAuth.forTesting(store);
    final first = auth.restore();
    final second = auth.restore();
    var finished = false;
    second.then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(identical(first, second), isTrue);
    expect(store.reads, 1);
    expect(finished, isFalse);
    store.result.complete(null);
    await Future.wait([first, second]);
    expect(finished, isTrue);
    expect(auth.isLoggedIn, isFalse);
    await auth.restore();
    expect(store.reads, 1);
    auth.dispose();
  });
}
