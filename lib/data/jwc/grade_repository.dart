import '../auth/cas_client.dart';
import '../cache_store.dart';
import 'grade_api.dart';

/// 成绩本地缓存（加密存储），打开成绩页先用缓存再后台更新。
class GradeRepository {
  static const String _key = 'usst_grade_snapshot_v1';
  static int _generation = 0;
  static int _revision = 0;
  static final _snapshotRevisions = Expando<int>();
  static var _pending = Expando<Future<GradeSnapshot>>();

  static Future<GradeSnapshot?> loadCache() async {
    final entry = await CacheStore.read(_key, secure: true);
    final raw = entry?.data;
    if (raw is! Map) {
      return null;
    }
    try {
      return GradeSnapshot.fromJson(raw.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(GradeSnapshot snapshot) {
    _snapshotRevisions[snapshot] = ++_revision;
    return CacheStore.write(_key, snapshot.toJson(), secure: true);
  }

  static Future<void> clear() {
    _generation++;
    _revision++;
    _pending = Expando<Future<GradeSnapshot>>();
    return CacheStore.remove(_key, secure: true);
  }

  static Future<GradeSnapshot> refresh(CasClient client) {
    if (_pending[client] != null) return _pending[client]!;
    final generation = _generation;
    late final Future<GradeSnapshot> operation;
    operation = GradeApi(client)
        .fetchAll()
        .then((snapshot) async {
          if (generation == _generation) await save(snapshot);
          return snapshot;
        })
        .whenComplete(() {
          if (identical(_pending[client], operation)) _pending[client] = null;
        });
    _pending[client] = operation;
    return operation;
  }

  static Future<GradeSnapshot> enrich(
    CasClient client,
    GradeSnapshot snapshot,
  ) async {
    final generation = _generation;
    final revision = _snapshotRevisions[snapshot];
    final enriched = await GradeApi(client).enrich(snapshot);
    // Windows clock ticks can give two different snapshots the same timestamp.
    if (generation == _generation &&
        revision != null &&
        revision == _revision) {
      await save(enriched);
    }
    return enriched;
  }
}
