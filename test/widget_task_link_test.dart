import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/chaoxing/chaoxing_cache.dart';
import 'package:project_usst/data/chaoxing/chaoxing_client.dart';
import 'package:project_usst/main.dart';
import 'package:project_usst/services/weather_service.dart';
import 'package:project_usst/services/widget_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('桌面待办生成的链接进入详情后保留抓取时间与绝对截止时间', () async {
    final directory = await Directory.systemTemp.createTemp(
      'litang-link-test-',
    );
    CacheStore.directoryOverride = () async => directory;
    CacheStore.clearMemory();
    FlutterSecureStorage.setMockInitialValues({});
    addTearDown(() async {
      CacheStore.clearMemory();
      CacheStore.directoryOverride = null;
      await directory.delete(recursive: true);
    });

    final fetchedAt = DateTime(2026, 11, 7, 10);
    final deadlineAt = fetchedAt.add(const Duration(hours: 2));
    await ChaoxingCache.writeWorks('A', [
      ChaoxingWork(
        workId: 'work-1',
        title: '作业',
        courseName: '课程',
        statusText: '未交',
        deadline: '剩余 2 小时',
        fetchedAt: fetchedAt,
        deadlineAt: deadlineAt,
        expired: false,
        taskUrl: 'https://example.test/work?id=1',
      ),
    ]);
    final writes = <String, Object?>{};
    await WidgetSyncService(
      identityLoader: () async => 'A',
      weatherLoader: (_) async => WeatherSummary.fallback(),
      saveData: (key, value) async => writes[key] = value,
      notifyWidget: () async {},
    ).syncTodayWidget(awaitWeather: true);

    final items = jsonDecode(writes['todos_json'] as String) as List;
    final uri = Uri.parse((items.single as Map)['linkUri'] as String);
    final target = todoTargetFromWidgetUri(uri);
    final work = ChaoxingWork.fromCacheJson(target)!;
    expect(work.fetchedAt, fetchedAt);
    expect(work.dueAt, deadlineAt);
    expect(work.taskUrl, 'https://example.test/work?id=1');
    expect(work.expired, isFalse);
  });

  test('旧待办链接保留整数 ID 默认值，过期布尔字符串正确转换', () {
    final tron = todoTargetFromWidgetUri(Uri.parse('litang://todo?id=12'));
    expect(tron['kind'], 'tron');
    expect(tron['id'], 12);
    expect(tron['courseId'], 0);
    expect(tron['type'], 'homework');
    final cx = todoTargetFromWidgetUri(
      Uri.parse('litang://todo?kind=cx&expired=true'),
    );
    expect(cx['expired'], isTrue);
  });
}
