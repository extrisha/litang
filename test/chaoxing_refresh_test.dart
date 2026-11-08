import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/bounded_requests.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/chaoxing/chaoxing_cache.dart';
import 'package:project_usst/data/chaoxing/chaoxing_client.dart';

class FixtureAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions r,
    Stream<Uint8List>? data,
    Future<void>? cancel,
  ) async {
    final id = r.uri.queryParameters['courseId'];
    return ResponseBody.fromString(
      id == '1' ? '{"result":1,"data":{"activeList":[]}}' : '<html>登录过期</html>',
      200,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('litang-deadline-test-');
    CacheStore.directoryOverride = () async => temp;
    CacheStore.clearMemory();
  });
  tearDown(() async {
    CacheStore.clearMemory();
    CacheStore.directoryOverride = null;
    await temp.delete(recursive: true);
  });

  const course = ChaoxingCourse(
    courseId: '1',
    classId: 'a',
    cpi: 'x',
    name: '课程一',
  );
  const html =
      '<li onclick="goTask(this);" data="https://example.test/work?workId=1&amp;courseId=1&amp;classId=a" aria-label="题目 ; 未交">'
      '<div class="time notOver">剩余 2 小时</div></li>';

  test('抓取时固定相对截止时间，缓存重读、分数补齐和通知序列化不漂移', () async {
    final fetchedAt = DateTime(2026, 11, 7, 10);
    final work = ChaoxingClient.parseWorkListHtml(
      html,
      course,
      fetchedAt: fetchedAt,
    ).single;
    expect(work.dueAt, DateTime(2026, 11, 7, 12));
    await ChaoxingCache.writeWorks('A', [work]);
    CacheStore.clearMemory();
    final loaded = (await ChaoxingCache.read('A'))!.works.single;
    expect(loaded.dueAt, work.dueAt);
    expect(loaded.withScore('90').dueAt, work.dueAt);
    expect(ChaoxingWork.fromCacheJson(loaded.toCacheJson())!.dueAt, work.dueAt);
    expect(loaded.courseKey, '1:a');
  });

  test('旧缓存按 savedAt 迁移；缺少可信时间戳的相对文本保持未知', () async {
    final fetchedAt = DateTime(2026, 11, 7, 10);
    final raw =
        ChaoxingClient.parseWorkListHtml(html, course).single.toCacheJson()
          ..remove('fetchedAt')
          ..remove('deadlineAt');
    final cache = Directory('${temp.path}/cache');
    await cache.create();
    await File('${cache.path}/chaoxing_works_v1_old.json')
        .writeAsString(CacheStore.encode([raw], fetchedAt));
    final loaded = (await ChaoxingCache.read('old'))!.works.single;
    expect(loaded.dueAt, DateTime(2026, 11, 7, 12));
    expect(ChaoxingWork.fromCacheJson(raw)!.dueAt, isNull);
  });

  test('成功空课程清空旧值，失败课程保留旧值，完整刷新时间不被部分失败推进', () async {
    final work = ChaoxingClient.parseWorkListHtml(html, course).single;
    await ChaoxingCache.writeWorks('A', [work]);
    final completeAt = (await ChaoxingCache.read('A'))!.savedAt;
    final batch = CourseBatch<ChaoxingWork>({'2:b': []}, {'1:a': '课程一'});
    final merged = batch.merge([work], (w) => w.courseKey);
    await ChaoxingCache.writeWorks(
      'A',
      merged,
      failedCourses: batch.failed.values.toList(),
    );
    CacheStore.clearMemory();
    final partial = (await ChaoxingCache.read('A'))!;
    expect(partial.works.single.dueAt, work.dueAt);
    expect(partial.savedAt, completeAt);
    expect(partial.failedCourses, ['课程一']);
    expect(
      CourseBatch<ChaoxingWork>({
        '1:a': [],
      }, {}).merge([work], (w) => w.courseKey),
      isEmpty,
    );
  });

  test('学习通 HTML 登录页不能作为成功空活动列表', () async {
    final dio = Dio(BaseOptions(responseType: ResponseType.plain))
      ..httpClientAdapter = FixtureAdapter();
    final client = ChaoxingClient(dio: dio);
    final result = await client.fetchActivitiesBatch([
      course,
      const ChaoxingCourse(courseId: '2', classId: 'b', cpi: '', name: '课程二'),
    ]);
    expect(result.successful['1:a'], isEmpty);
    expect(result.failed, {'2:b': '课程二'});
    expect(result.requireComplete, throwsStateError);
  });

  test('并发有上限且单项失败不跳过剩余请求', () async {
    var active = 0, peak = 0, completed = 0;
    final result = mapWithConcurrency(List.generate(10, (i) => i), (i) async {
      active++;
      if (active > peak) peak = active;
      await Future<void>.delayed(const Duration(milliseconds: 1));
      active--;
      completed++;
      if (i == 0) throw StateError('first failed');
      return i;
    });
    await expectLater(result, throwsStateError);
    expect(completed, 10);
    expect(peak, lessThanOrEqualTo(3));
  });
}
