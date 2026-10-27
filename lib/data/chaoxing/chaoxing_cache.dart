import '../cache_store.dart';
import 'chaoxing_client.dart';

/// 学习通课程 / 作业 / 活动的本地缓存。
///
/// 学习通没有一网畅学那样的整页 JSON 接口，课程、作业都要逐门课请求；
/// 先把上次结果贴到界面，再后台刷新，切换「学习通」待办时就不会空白很久。
class ChaoxingCacheData {
  const ChaoxingCacheData({
    required this.courses,
    required this.works,
    required this.activities,
    this.savedAt,
  });

  final List<ChaoxingCourse> courses;
  final List<ChaoxingWork> works;
  final List<ChaoxingActivity> activities;
  final DateTime? savedAt;

  bool get isEmpty => courses.isEmpty && works.isEmpty && activities.isEmpty;
}

class ChaoxingCache {
  ChaoxingCache._();

  static const String _coursesKey = 'chaoxing_courses_v1';
  static const String _worksKey = 'chaoxing_works_v1';
  static const String _activitiesKey = 'chaoxing_activities_v1';

  static String _key(String base, String username) {
    final user = username.trim();
    return user.isEmpty ? base : '${base}_$user';
  }

  static Future<ChaoxingCacheData?> read(String username) async {
    final courses = await _readList(
      _key(_coursesKey, username),
      ChaoxingCourse.fromCacheJson,
    );
    final works = await _readList(
      _key(_worksKey, username),
      ChaoxingWork.fromCacheJson,
    );
    final activities = await _readList(
      _key(_activitiesKey, username),
      ChaoxingActivity.fromCacheJson,
    );
    if (courses == null && works == null && activities == null) {
      return null;
    }
    return ChaoxingCacheData(
      courses: courses ?? const <ChaoxingCourse>[],
      works: works ?? const <ChaoxingWork>[],
      activities: activities ?? const <ChaoxingActivity>[],
    );
  }

  static Future<void> writeCourses(
    String username,
    List<ChaoxingCourse> value,
  ) => _writeList(
    _key(_coursesKey, username),
    value.map((e) => e.toCacheJson()).toList(),
  );

  static Future<void> writeWorks(String username, List<ChaoxingWork> value) =>
      _writeList(
        _key(_worksKey, username),
        value.map((e) => e.toCacheJson()).toList(),
      );

  static Future<void> writeActivities(
    String username,
    List<ChaoxingActivity> value,
  ) => _writeList(
    _key(_activitiesKey, username),
    value.map((e) => e.toCacheJson()).toList(),
  );

  static Future<List<T>?> _readList<T>(
    String key,
    T? Function(Map<String, dynamic>) parse,
  ) async {
    final entry = await CacheStore.read(key);
    final data = entry?.data;
    if (data is! List) return null;
    final out = <T>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      final parsed = parse(Map<String, dynamic>.from(raw));
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  static Future<void> _writeList(
    String key,
    List<Map<String, dynamic>> value,
  ) => CacheStore.write(key, value);
}
