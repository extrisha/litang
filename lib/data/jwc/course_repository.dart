import 'dart:async';

import '../auth/cas_client.dart';
import '../cache_store.dart';
import 'course_api.dart';
import '../../services/widget_sync_service.dart';

/// 课表本地缓存：走 [CacheStore] 的加密后端（Android Keystore / iOS Keychain），
/// 不用每次联网。
class CourseRepository {
  // v2：旧缓存没有周次字段，会导致课表全量显示，升级 key 让其失效
  static const String _key = 'usst_course_snapshot_v2';

  /// 课表一天多次刷新没必要；留出 TTL 方便以后做后台刷新。
  static const Duration ttl = Duration(hours: 12);

  static Future<CourseSnapshot?> loadCache() async {
    final entry = await CacheStore.read(_key, secure: true);
    final raw = entry?.data;
    if (raw is! Map) {
      return null;
    }
    try {
      final snapshot = CourseSnapshot.fromJson(raw.cast<String, dynamic>());
      // 数据里一条周次都没有，说明是旧版本缓存，直接丢弃等刷新
      if (snapshot.courses.isNotEmpty &&
          snapshot.courses.every((c) => c.weeksText.isEmpty)) {
        return null;
      }
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  /// 缓存是否还在有效期内（页面可以用它决定要不要后台刷新）。
  static Future<bool> isFresh() async {
    final entry = await CacheStore.read(_key, secure: true);
    return entry != null && entry.isFresh(ttl);
  }

  static Future<void> save(CourseSnapshot snapshot) async {
    await CacheStore.write(_key, snapshot.toJson(), secure: true);
    unawaited(WidgetSyncService.instance.syncTodayWidget());
  }

  /// 退出登录时清掉缓存的课表，避免换账号后串数据。
  static Future<void> clear() => CacheStore.remove(_key, secure: true);

  static Future<CourseSnapshot> refresh(CasClient client) async {
    final snapshot = await CourseApi(client).fetchCurrent();
    if (snapshot.courses.isNotEmpty) {
      await save(snapshot);
    }
    return snapshot;
  }
}
