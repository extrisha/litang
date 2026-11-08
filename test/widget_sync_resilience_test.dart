import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/auth/session_store.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/life_cache.dart';
import 'package:project_usst/data/lms/todo_api.dart';
import 'package:project_usst/services/widget_sync_service.dart';
import 'package:project_usst/services/weather_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    CacheStore.clearMemory();
    temp = await Directory.systemTemp.createTemp('litang-widget-test-');
    CacheStore.directoryOverride = () async => temp;
    for (final user in ['A', 'B']) {
      await LifeCache.writeTodos([
        LmsTodo(
          id: 1,
          courseId: 1,
          title: '$user 的作业',
          courseName: '课程',
          type: 'homework',
          deadline: DateTime(2027),
        ),
      ], username: user);
    }
  });
  tearDown(() async {
    CacheStore.clearMemory();
    CacheStore.directoryOverride = null;
    await temp.delete(recursive: true);
  });

  test('冷启动仅凭本地账号读待办；慢天气不阻塞，重复同步不重复天气请求', () async {
    await SessionStore().save(CasClient(), username: 'A');
    final weather = Completer<WeatherSummary>();
    final writes = <String, Object?>{};
    var weatherCalls = 0;
    final service = WidgetSyncService(
      weatherLoader: (_) {
        weatherCalls++;
        return weather.future;
      },
      saveData: (key, value) async {
        writes[key] = value;
      },
      notifyWidget: () async {},
    );
    await service.syncTodayWidget();
    expect(writes['todos_json'], contains('A 的作业'));
    expect(writes.containsKey('weather_icon_type'), isFalse);
    await Future.wait([service.syncTodayWidget(), service.syncTodayWidget()]);
    expect(weatherCalls, 1);
    weather.complete(WeatherSummary.fallback());
    await service.syncTodayWidget(awaitWeather: true);
    expect(writes['weather_icon_type'], 'cloudy');
  });

  test('账号在写入中切换时旧快照中止，最终只发布新账号待办', () async {
    var username = 'A';
    final blocked = Completer<void>();
    final firstWrite = Completer<void>();
    final writes = <String, Object?>{};
    final service = WidgetSyncService(
      identityLoader: () async => username,
      weatherLoader: (_) async => WeatherSummary.fallback(),
      saveData: (key, value) async {
        if (!firstWrite.isCompleted) {
          firstWrite.complete();
          await blocked.future;
        }
        writes[key] = value;
      },
      notifyWidget: () async {},
    );
    final first = service.syncTodayWidget();
    await firstWrite.future;
    username = 'B';
    final second = service.syncTodayWidget(awaitWeather: true);
    blocked.complete();
    await Future.wait([first, second]);
    final items = jsonDecode(writes['todos_json'] as String) as List;
    expect(items.single['name'], 'B 的作业');
  });

  test('本地身份读取失败时保留已经发布的待办', () async {
    final writes = <String, Object?>{'todos_json': 'previous'};
    final service = WidgetSyncService(
      identityLoader: () async => throw StateError('storage unavailable'),
      weatherLoader: (_) async => WeatherSummary.fallback(),
      saveData: (key, value) async {
        writes[key] = value;
      },
      notifyWidget: () async {},
    );
    await service.syncTodayWidget(awaitWeather: true);
    expect(writes['todos_json'], 'previous');
  });
}
