import 'cache_store.dart';
import 'lms/rollcall_api.dart';
import 'lms/todo_api.dart';

/// 生活页数据的本地缓存：冷启动先显示上次的内容，再后台刷新。
///
/// 这是 stale-while-revalidate 模式——用户打开 App 立刻看到东西，
/// 网络慢或断网时至少还有旧数据可用，不至于整页空白。
///
/// 只缓存"非敏感、可重建"的列表（待办、考试、签到），
/// 不做增量合并，整份覆盖写入。
class LifeCache {
  LifeCache._();

  static const String _todosKey = 'life_todos_v1';
  static const String _examsKey = 'life_exams_v1';
  static const String _rollcallsKey = 'life_rollcalls_v1';

  static String _key(String base, String username) {
    final user = username.trim();
    return user.isEmpty ? base : '${base}_$user';
  }

  /// 超过这个时间的数据仍然显示，但会立刻触发后台刷新。
  static const Duration ttl = Duration(hours: 6);

  // ------------------------------------------------------------------ 待办

  static Future<List<LmsTodo>?> readTodos({String username = ''}) =>
      _readList(_key(_todosKey, username), LmsTodo.fromCacheJson);

  static Future<void> writeTodos(List<LmsTodo> items, {String username = ''}) =>
      _writeList(
        _key(_todosKey, username),
        items.map((e) => e.toCacheJson()).toList(),
      );

  // ------------------------------------------------------------------ 考试

  static Future<List<LmsExam>?> readExams({String username = ''}) =>
      _readList(_key(_examsKey, username), LmsExam.fromCacheJson);

  static Future<void> writeExams(List<LmsExam> items, {String username = ''}) =>
      _writeList(
        _key(_examsKey, username),
        items.map((e) => e.toCacheJson()).toList(),
      );

  // ------------------------------------------------------------------ 签到

  static Future<List<Rollcall>?> readRollcalls({String username = ''}) =>
      _readList(_key(_rollcallsKey, username), Rollcall.fromCacheJson);

  static Future<void> writeRollcalls(
    List<Rollcall> items, {
    String username = '',
  }) => _writeList(
    _key(_rollcallsKey, username),
    items.map((e) => e.toCacheJson()).toList(),
  );

  // ------------------------------------------------------------------ 内部

  static Future<List<T>?> _readList<T>(
    String key,
    T? Function(Map<String, dynamic>) parse,
  ) async {
    final entry = await CacheStore.read(key);
    final data = entry?.data;
    if (data is! List) {
      return null;
    }
    final items = <T>[];
    for (final raw in data) {
      if (raw is! Map) {
        continue;
      }
      final parsed = parse(Map<String, dynamic>.from(raw));
      if (parsed != null) {
        items.add(parsed);
      }
    }
    return items;
  }

  static Future<void> _writeList(
    String key,
    List<Map<String, dynamic>> items,
  ) => CacheStore.write(key, items);
}
