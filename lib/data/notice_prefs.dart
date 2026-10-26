import 'package:flutter/foundation.dart';

import 'cache_store.dart';
import 'jwc/course_repository.dart';

/// 首页通知流的学院偏好。
///
/// 两个不同的东西，别混：
///   - [detected]：从教务课表缓存里读到的学院（`CourseSnapshot.collegeName`），
///     只用来做「本院优先」排序，以及在选择框里置顶；
///   - [selected]：用户手动选的学院，用来**筛选**通知流；null 表示「全部学院」。
///
/// 存到加密存储里，因为检测值是从教务账号推出来的个人信息。
class NoticePrefs {
  NoticePrefs._();

  // v2：语义变了（以前是「本院优先 / 只看本院」），换 key 让旧值失效，
  // 免得升级后用户突然发现通知被筛掉一半。
  static const String _key = 'notice_prefs_v2';

  static String? _selected;
  static bool _selectedLoaded = false;

  static String? _detected;
  static bool _detectedLoaded = false;

  /// 测试用：widget 测试里没有平台通道，flutter_secure_storage 的 Future
  /// 在 FakeAsync 下永远不会完成（会把 await 卡死），所以测试里只走内存。
  @visibleForTesting
  static bool debugSkipStorage = false;

  /// 教务里读到的学院（已对齐到 notices.json 的 dept）。读不到返回 null。
  static Future<String?> detected(Iterable<String> known) async {
    if (_detectedLoaded) return _detected;
    final jw = await _fromCourseCache();
    _detected = jw == null ? null : matchCollege(jw, known);
    _detectedLoaded = true;
    return _detected;
  }

  /// 用户选的学院；null = 全部学院。
  static Future<String?> selected() async {
    if (_selectedLoaded) return _selected;
    _selectedLoaded = true;
    if (debugSkipStorage) return _selected;
    try {
      final entry = await CacheStore.read(_key, secure: true);
      final data = entry?.data;
      if (data is Map) {
        final v = data['college'];
        if (v is String && v.isNotEmpty) _selected = v;
      }
    } catch (_) {
      // 读不出来就当没选
    }
    return _selected;
  }

  static Future<void> setSelected(String? college) async {
    _selected = (college == null || college.isEmpty) ? null : college;
    _selectedLoaded = true;
    if (debugSkipStorage) return;
    await CacheStore.write(
      _key,
      <String, dynamic>{'college': _selected ?? ''},
      secure: true,
    );
  }

  /// 测试用：把内存里的状态清干净。
  @visibleForTesting
  static void debugReset() {
    _selected = null;
    _selectedLoaded = false;
    _detected = null;
    _detectedLoaded = false;
  }

  /// 教务课表缓存里的学院名，比如「健康科学与工程学院」。
  static Future<String?> _fromCourseCache() async {
    if (debugSkipStorage) return null;
    try {
      final snapshot = await CourseRepository.loadCache();
      final name = snapshot?.collegeName.trim() ?? '';
      return name.isEmpty ? null : name;
    } catch (_) {
      return null;
    }
  }

  /// 把教务给的学院名对上 notices.json 里的部门名。
  ///
  /// 大部分是精确相等；少数对不上（比如教务写「出版印刷与艺术设计学院」，
  /// 站点现在叫「出版学院」），就靠「开头两个字一样」这种弱规则兜一下，
  /// 但并列第一的时候宁可返回 null，也不要乱认。
  static String? matchCollege(String raw, Iterable<String> known) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final scores = <String, int>{};
    for (final k in known) {
      if (k.isEmpty) continue;
      int score = 0;
      if (k == text) {
        score = 100;
      } else if (k.contains(text) || text.contains(k)) {
        score = 50;
      } else if (text.length >= 2 &&
          k.length >= 2 &&
          text.startsWith(k.substring(0, 2))) {
        score = 10;
      }
      if (score > 0) scores[k] = score;
    }
    if (scores.isEmpty) return null;

    final best = scores.values.reduce((a, b) => a > b ? a : b);
    final winners = scores.entries.where((e) => e.value == best).toList();
    if (winners.length != 1) return null;
    return winners.single.key;
  }
}
