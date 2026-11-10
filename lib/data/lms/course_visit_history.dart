import '../cache_store.dart';
import 'todo_api.dart';

/// 最近访问顺序与服务器课程列表分开保存，刷新课程不会重置顺序。
class CourseVisitHistory {
  CourseVisitHistory._();

  static const int limit = 100;
  static Future<void> _writes = Future<void>.value();

  static String _key(String username, String source) =>
      'course_visits_v1_${source}_${username.trim()}';

  static Future<List<String>> load(String username, String source) async {
    final data = (await CacheStore.read(_key(username, source)))?.data;
    return data is List
        ? data
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet()
              .take(limit)
              .toList()
        : <String>[];
  }

  static List<String> promote(List<String> recent, String courseId) => <String>[
    courseId,
    ...recent.where((id) => id != courseId),
  ].where((id) => id.isNotEmpty).take(limit).toList();

  static Future<void> record(String username, String source, String courseId) {
    if (username.trim().isEmpty || courseId.isEmpty) {
      return Future<void>.value();
    }
    // 连续点击必须按点击顺序落盘，不能让先发的读改写覆盖后一次点击。
    final write = _writes.then((_) async {
      final recent = await load(username, source);
      await CacheStore.write(_key(username, source), promote(recent, courseId));
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  static List<LmsCourseInfo> sort(
    List<LmsCourseInfo> courses,
    List<String> recent,
  ) {
    final ranks = <String, int>{
      for (var i = 0; i < recent.length; i++) recent[i]: i,
    };
    final indexed = courses.indexed.toList();
    indexed.sort((a, b) {
      final rank = (ranks[a.$2.id] ?? recent.length).compareTo(
        ranks[b.$2.id] ?? recent.length,
      );
      return rank != 0 ? rank : a.$1.compareTo(b.$1);
    });
    return indexed.map((entry) => entry.$2).toList();
  }
}
