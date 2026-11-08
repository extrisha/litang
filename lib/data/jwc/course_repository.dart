import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../auth/cas_client.dart';
import '../auth/jwgl_auth.dart';
import '../auth/session_store.dart';
import '../cache_store.dart';
import '../app_exception.dart';
import 'course_api.dart';

/// 课表本地缓存：走 [CacheStore] 的加密后端（Android Keystore / iOS Keychain），
/// 不用每次联网。
class CourseRepository {
  static final changes = ValueNotifier<int>(0);
  static const _legacyKey = 'usst_course_snapshot_v2';
  static String _accountKey(String username) =>
      'usst_course_v3_${sha256.convert(utf8.encode(username))}';
  static Future<String> _account(String? username) async =>
      username ??
      (JwglAuth.instance.savedUsername.isNotEmpty
          ? JwglAuth.instance.savedUsername
          : await SessionStore().loadUsername());
  static Expando<Future<CourseSnapshot>> _inFlight =
      Expando<Future<CourseSnapshot>>();
  static int _generation = 0;
  static final Map<String, Future<void>> _writes = {};
  static final Map<String, int> _requests = {};

  /// 课表一天多次刷新没必要；留出 TTL 方便以后做后台刷新。
  static const Duration ttl = Duration(hours: 12);

  static Future<CourseSnapshot?> loadCache({String? username}) async {
    final account = await _account(username);
    if (account.isEmpty) return null;
    await _writes[account];
    final index = (await CacheStore.read(
      _accountKey(account),
      secure: true,
    ))?.data;
    if (index == null) return _migrateLegacy(account);
    if (index is! Map || index['active'] is! String) return null;
    final entry = await CacheStore.read(
      index['active'] as String,
      secure: true,
    );
    return _decode(entry?.data);
  }

  static CourseSnapshot? _decode(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    try {
      final snapshot = CourseSnapshot.fromJson(raw.cast<String, dynamic>());
      // 数据里一条周次都没有，说明是旧版本缓存，直接丢弃等刷新
      if (snapshot.courses.isNotEmpty &&
          snapshot.courses.every(
            (c) => c.weeksText.isEmpty && (c.weeks?.isEmpty ?? true),
          )) {
        return null;
      }
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  static Future<CourseSnapshot?> _migrateLegacy(String account) async {
    final generation = _generation;
    // The old global key belongs only to the locally persisted account.
    try {
      if (await SessionStore().loadUsername() != account) return null;
    } catch (_) {
      return null;
    }
    final legacy = await CacheStore.read(_legacyKey, secure: true);
    final snapshot = _decode(legacy?.data);
    if (snapshot == null || generation != _generation) return null;
    try {
      await _save(snapshot, username: account, requirePersistence: true);
      if (generation != _generation) return null;
      await CacheStore.remove(_legacyKey, secure: true);
    } catch (_) {
      // Keep the original readable if migration cannot be persisted.
    }
    return generation == _generation ? snapshot : null;
  }

  /// 缓存是否还在有效期内（页面可以用它决定要不要后台刷新）。
  static Future<bool> isFresh({String? username}) async {
    final snapshot = await loadCache(username: username);
    return snapshot != null &&
        DateTime.now().difference(snapshot.updatedAt) < ttl;
  }

  static Future<void> save(CourseSnapshot snapshot, {String? username}) =>
      _save(snapshot, username: username);

  static Future<void> _save(
    CourseSnapshot snapshot, {
    String? username,
    bool requirePersistence = false,
  }) async {
    final account = await _account(username);
    if (account.isEmpty) return;
    final indexKey = _accountKey(account);
    final key = '${indexKey}_${snapshot.xnm}_${snapshot.xqm}';
    final generation = _generation;
    late final Future<void> operation;
    operation = (_writes[account] ?? Future<void>.value())
        .then((_) async {
          if (generation != _generation) return;
          final old = (await CacheStore.read(indexKey, secure: true))?.data;
          final active = old is Map ? old['active'] as String? : null;
          final previous = old is Map ? old['previous'] as String? : null;
          await CacheStore.write(
            key,
            snapshot.toJson(),
            secure: true,
            requirePersistence: requirePersistence,
          );
          await CacheStore.write(
            indexKey,
            {'active': key, 'previous': active == key ? previous : active},
            secure: true,
            requirePersistence: requirePersistence,
          );
          if (active != key &&
              previous != null &&
              previous != key &&
              previous != active) {
            await CacheStore.remove(previous, secure: true);
          }
        })
        .whenComplete(() {
          if (identical(_writes[account], operation)) _writes.remove(account);
        });
    _writes[account] = operation;
    await operation;
    changes.value++;
  }

  /// 退出登录时清掉缓存的课表，避免换账号后串数据。
  static Future<void> clear({String? username}) async {
    _generation++;
    _inFlight = Expando<Future<CourseSnapshot>>();
    final account = await _account(username);
    await _writes[account];
    final key = _accountKey(account);
    final index = (await CacheStore.read(key, secure: true))?.data;
    if (index is Map) {
      for (final value in [index['active'], index['previous']]) {
        if (value is String) await CacheStore.remove(value, secure: true);
      }
    }
    await CacheStore.remove(key, secure: true);
    await CacheStore.remove('usst_course_snapshot_v2', secure: true);
    changes.value++;
  }

  static Future<CourseSnapshot> refresh(CasClient client, {JwglAuth? auth}) =>
      _refresh(client, auth ?? JwglAuth.instance);

  static Future<CourseSnapshot> _refresh(CasClient client, JwglAuth auth) {
    final pending = _inFlight[client];
    if (pending != null) return pending;
    final generation = _generation;
    final account = client.studentId ?? '';
    final sequence = (_requests[account] ?? 0) + 1;
    _requests[account] = sequence;
    final managed = identical(auth.client, client);
    final authGeneration = auth.generation;
    var active = true;
    var activeClient = client;
    bool isCurrent() =>
        active &&
        generation == _generation &&
        _requests[account] == sequence &&
        activeClient.studentId == account &&
        (!managed ||
            (auth.generation == authGeneration &&
                identical(auth.client, activeClient)));
    var api = CourseApi(client);
    late final Future<CourseSnapshot> request;
    Future<CourseSnapshot> fetch() async {
      try {
        return await api.fetchCurrent(includeExtras: false);
      } on AppException catch (error) {
        if (!error.needsRelogin || !managed || !isCurrent()) rethrow;
        if (!await auth.reauthenticate()) rethrow;
        final renewed = auth.client;
        if (renewed == null) rethrow;
        activeClient = renewed;
        if (!isCurrent()) rethrow;
        // Renewed clients share this request and its remaining network budget.
        _inFlight[renewed] = request;
        api = CourseApi(renewed);
        return api.fetchCurrent(includeExtras: false);
      }
    }

    // Only primary fetch, recovery and its single retry share this deadline;
    // local cache IO and successful metadata enrichment remain independent.
    request = fetch()
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            active = false;
            throw const AppException(AppFailure.network, '课表请求超时，已保留本地课表，请重试');
          },
        )
        .then((snapshot) async {
          if (isCurrent()) {
            final cached = await loadCache(username: account);
            if (!isCurrent()) return snapshot;
            snapshot = snapshot.copyWith(
              studentName: snapshot.studentName.isEmpty
                  ? cached?.studentName
                  : null,
              collegeName: snapshot.collegeName.isEmpty
                  ? cached?.collegeName
                  : null,
              className: snapshot.className.isEmpty ? cached?.className : null,
              majorName: snapshot.majorName.isEmpty ? cached?.majorName : null,
              currentWeek: snapshot.currentWeek ?? cached?.currentWeek,
            );
            await save(snapshot, username: account);
            if (isCurrent()) {
              unawaited(
                api
                    .enrich(snapshot)
                    .then((enriched) async {
                      if (isCurrent() && !identical(snapshot, enriched)) {
                        await save(enriched, username: account);
                      }
                    })
                    .catchError((Object _) {}),
              );
            }
          }
          return snapshot;
        })
        .whenComplete(() {
          if (identical(_inFlight[client], request)) _inFlight[client] = null;
          if (identical(_inFlight[activeClient], request)) {
            _inFlight[activeClient] = null;
          }
        });
    _inFlight[client] = request;
    return request;
  }
}
