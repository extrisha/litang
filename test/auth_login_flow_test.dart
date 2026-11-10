import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/auth/jwgl_auth.dart';
import 'package:project_usst/data/auth/session_store.dart';

class _Store extends SessionStore {
  _Store({bool empty = false})
    : value = empty
          ? null
          : StoredSession(
              cookies: const [],
              username: 'A',
              password: 'saved-password',
              savedAt: DateTime(2026),
            );
  StoredSession? value;
  int saves = 0;
  int clears = 0;
  Completer<void>? saveGate;
  Completer<void>? saveStarted;
  @override
  Future<StoredSession?> load() async => value;
  @override
  Future<void> save(
    CasClient client, {
    required String username,
    String? password,
  }) async {
    saves++;
    if (saveStarted != null && !saveStarted!.isCompleted) {
      saveStarted!.complete();
    }
    await saveGate?.future;
    value = StoredSession(
      cookies: const [],
      username: username,
      password: password,
      savedAt: DateTime(2026),
    );
  }

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}

class _Client extends CasClient {
  _Client({this.name = '', this.events});
  final String name;
  final List<String>? events;
  final check = Completer<bool>();
  final loginResult = Completer<void>();
  final loginStarted = Completer<void>();
  int logins = 0;
  int cancellations = 0;
  @override
  Future<bool> checkSession() => check.future;
  @override
  Future<bool> silentLogin() async => false;
  @override
  Future<void> login(String username, String password) {
    events?.add('$name login');
    logins++;
    if (!loginStarted.isCompleted) loginStarted.complete();
    return loginResult.future;
  }

  @override
  void cancelAuthentication() {
    events?.add('$name cancel');
    cancellations++;
  }

  void release() {
    if (!check.isCompleted) check.complete(false);
    if (!loginResult.isCompleted) loginResult.complete();
  }
}

void _cleanUp(JwglAuth auth, List<_Client> clients, {_Store? store}) {
  addTearDown(() async {
    if (store?.saveGate != null && !store!.saveGate!.isCompleted) {
      store.saveGate!.complete();
    }
    for (final client in clients) {
      client.release();
    }
    await Future<void>.delayed(Duration.zero);
    auth.dispose();
  });
}

void main() {
  test('会话校验与强制恢复等待在途启动恢复，不额外提交密码', () async {
    final client = _Client();
    var clients = 0;
    final auth = JwglAuth.forTesting(
      _Store(),
      clientFactory: (_) {
        clients++;
        return client;
      },
    );
    _cleanUp(auth, [client]);
    final restoring = auth.restore();
    await Future<void>.delayed(Duration.zero);
    final ensuring = auth.ensureSession();
    final reauthenticating = auth.reauthenticate();
    await Future<void>.delayed(Duration.zero);
    final createdBeforeRelease = clients;
    final loginsBeforeRelease = client.logins;
    client.check.complete(true);
    client.loginResult.complete();
    await restoring;
    await Future.wait([ensuring, reauthenticating]);
    expect(createdBeforeRelease, 1);
    expect(loginsBeforeRelease, 0);
    expect(auth.studentId, 'A');
  });

  test('手动登录先取消旧启动恢复，旧会话迟到不会覆盖新账号', () async {
    final events = <String>[];
    final oldClient = _Client(name: 'old', events: events);
    final manualClient = _Client(name: 'manual', events: events);
    final store = _Store();
    final auth = JwglAuth.forTesting(store, clientFactory: (_) => oldClient);
    _cleanUp(auth, [oldClient, manualClient]);
    final restoring = auth.restore();
    await Future<void>.delayed(Duration.zero);
    final manual = auth.login('B', 'new-password', client: manualClient);
    await manualClient.loginStarted.future.timeout(const Duration(seconds: 2));
    expect(events, ['old cancel', 'manual login']);
    manualClient.loginResult.complete();
    await manual;
    oldClient.check.complete(true);
    await restoring;
    expect(auth.client, same(manualClient));
    expect(auth.studentId, 'B');
    expect(auth.savedUsername, 'B');
    expect(auth.savedPassword, 'new-password');
    expect(store.value!.username, 'B');
    expect(store.saves, 1);
    expect(oldClient.logins, 0);
  });

  test('手动登录期间会话校验和强制恢复共用manual，不截断其登录预算', () async {
    final client = _Client();
    final store = _Store(empty: true);
    var factoryCalls = 0;
    final auth = JwglAuth.forTesting(
      store,
      recoveryTimeout: const Duration(milliseconds: 40),
      clientFactory: (_) {
        factoryCalls++;
        return client;
      },
    );
    _cleanUp(auth, [client]);
    final manual = auth.login('B', 'password', client: client);
    var ensureFinished = false;
    var reauthFinished = false;
    final ensuring = auth.ensureSession().then((value) {
      ensureFinished = true;
      return value;
    });
    final reauthenticating = auth.reauthenticate().then((value) {
      reauthFinished = true;
      return value;
    });
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(ensureFinished, isFalse);
    expect(reauthFinished, isFalse);
    expect(client.cancellations, 0);
    expect(client.logins, 1);
    expect(factoryCalls, 0);
    client.loginResult.complete();
    await manual;
    expect(await ensuring, isTrue);
    expect(await reauthenticating, isTrue);
    expect(auth.client, same(client));
  });

  test('启动恢复截止取消请求并保留本地身份和密码，迟到成功不写入', () async {
    final client = _Client();
    final store = _Store();
    final auth = JwglAuth.forTesting(
      store,
      clientFactory: (_) => client,
      recoveryTimeout: const Duration(milliseconds: 60),
    );
    _cleanUp(auth, [client]);
    await auth.restore();
    expect(client.cancellations, 1);
    expect(auth.isLoggedIn, isFalse);
    expect(auth.studentId, 'A');
    expect(auth.savedUsername, 'A');
    expect(auth.savedPassword, 'saved-password');
    expect(store.clears, 0);
    client.check.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(auth.isLoggedIn, isFalse);
    expect(auth.savedUsername, 'A');
    expect(auth.savedPassword, 'saved-password');
    expect(store.saves, 0);
  });

  test('恢复总截止同样覆盖自动密码登录，迟到密码成功不恢复会话', () async {
    final checking = _Client()..check.complete(false);
    final autoLogin = _Client();
    var clients = 0;
    final store = _Store();
    final auth = JwglAuth.forTesting(
      store,
      recoveryTimeout: const Duration(milliseconds: 75),
      clientFactory: (_) => clients++ == 0 ? checking : autoLogin,
    );
    _cleanUp(auth, [checking, autoLogin]);
    final restoring = auth.restore();
    await autoLogin.loginStarted.future.timeout(const Duration(seconds: 2));
    await restoring;
    expect(autoLogin.cancellations, 1);
    expect(auth.isLoggedIn, isFalse);
    expect(auth.savedUsername, 'A');
    expect(auth.savedPassword, 'saved-password');
    autoLogin.loginResult.complete();
    await Future<void>.delayed(Duration.zero);
    expect(auth.isLoggedIn, isFalse);
    expect(store.saves, 0);
    expect(store.clears, 0);
  });

  test('退出取消在途手动登录，迟到结果不恢复身份或保存会话', () async {
    final client = _Client();
    final store = _Store(empty: true);
    final auth = JwglAuth.forTesting(store);
    _cleanUp(auth, [client]);
    final manual = auth.login('B', 'password', client: client);
    final rejected = expectLater(manual, throwsA(isA<CasLoginException>()));
    await client.loginStarted.future.timeout(const Duration(seconds: 2));
    await auth.logout();
    expect(client.cancellations, 1);
    client.loginResult.complete();
    await rejected;
    expect(auth.isLoggedIn, isFalse);
    expect(auth.studentId, isNull);
    expect(auth.savedUsername, isEmpty);
    expect(auth.savedPassword, isNull);
    expect(store.value, isNull);
    expect(store.saves, 0);
  });

  test('登录保存期间退出会使旧登录返回取消，而非虚报登录成功', () async {
    final client = _Client()..loginResult.complete();
    final store = _Store(empty: true)
      ..saveStarted = Completer<void>()
      ..saveGate = Completer<void>();
    final auth = JwglAuth.forTesting(store);
    _cleanUp(auth, [client], store: store);
    final manual = auth.login('B', 'password', client: client);
    final outcome = manual.then((_) => true, onError: (Object _) => false);
    await store.saveStarted!.future.timeout(const Duration(seconds: 2));
    final logout = auth.logout();
    store.saveGate!.complete();
    final succeeded = await outcome;
    await logout;
    expect(auth.isLoggedIn, isFalse);
    expect(store.value, isNull);
    expect(succeeded, isFalse);
  });
}
