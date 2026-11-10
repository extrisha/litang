import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/app_theme.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/models.dart';
import 'package:project_usst/data/notice_source.dart';
import 'package:project_usst/pages/home_page.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) => respond(options);
  @override
  void close({bool force = false}) {}
}

class _Source implements NoticeSource, NoticeUpdates {
  final controllers = <StreamController<NoticeFeed>>[];
  @override
  Stream<NoticeFeed> fetchUpdates({bool force = false}) {
    final controller = StreamController<NoticeFeed>();
    controllers.add(controller);
    return controller.stream;
  }

  @override
  Future<NoticeFeed> fetch({bool force = false}) => throw UnimplementedError();
}

NoticeFeed _feed(String title) => NoticeFeed(
  notices: [Notice(dept: '教务处', kind: '通知', title: title)],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('litang-notice-refresh-');
    CacheStore.directoryOverride = () async => temp;
    CacheStore.clearMemory();
  });
  tearDown(() async {
    CacheStore.directoryOverride = null;
    CacheStore.clearMemory();
    await temp.delete(recursive: true);
  });

  Future<void> cache(DateTime at) => CacheStore.writeEncoded(
    'notices_feed_v2',
    CacheStore.encode({
      'fetchedAt': at.toIso8601String(),
      'notices': [
        {'dept': '教务处', 'kind': '通知', 'title': '缓存通知'},
      ],
    }, at),
  );

  test('过期通知先返回缓存，并发刷新只访问一次远端', () async {
    await cache(DateTime.now().subtract(const Duration(days: 5)));
    final gate = Completer<void>();
    final requested = Completer<void>();
    var calls = 0;
    final source = RemoteNoticeSource(
      dio: Dio()
        ..httpClientAdapter = _Adapter((_) async {
          calls++;
          if (!requested.isCompleted) requested.complete();
          await gate.future;
          return ResponseBody.fromString(
            jsonEncode({
              'updatedAt': DateTime.now().toIso8601String(),
              'notices': [
                {'dept': '教务处', 'kind': '通知', 'title': '新通知'},
              ],
            }),
            200,
          );
        }),
    );
    final feeds = <NoticeFeed>[];
    final done = source.fetchUpdates().forEach(feeds.add);
    await requested.future;
    expect(feeds.single.notices.single.title, '缓存通知');
    final simultaneous = source.fetch(force: true);
    // 读取缓存也经过 isolate，等 force 请求接到同一在途刷新。
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 1);
    gate.complete();
    await done;
    expect((await simultaneous).notices.single.title, '新通知');
    expect(calls, 1);
    expect(feeds.map((feed) => feed.notices.single.title), ['缓存通知', '新通知']);
    await source.flushCacheWrites();
  });

  test('新鲜缓存不访问远端，强制刷新也不回退到较旧镜像', () async {
    await cache(DateTime.now());
    var calls = 0;
    final source = RemoteNoticeSource(
      dio: Dio()
        ..httpClientAdapter = _Adapter((_) async {
          calls++;
          return ResponseBody.fromString(
            jsonEncode({
              'updatedAt': DateTime.now()
                  .subtract(const Duration(days: 1))
                  .toIso8601String(),
              'notices': [
                {'dept': '教务处', 'title': '旧镜像'},
              ],
            }),
            200,
          );
        }),
    );
    final cached = await source.fetchUpdates().toList();
    expect(cached.single.notices.single.title, '缓存通知');
    expect(calls, 0);
    expect((await source.fetch(force: true)).notices.single.title, '缓存通知');
    expect(calls, 1);
    await source.flushCacheWrites();
  });

  testWidgets('首页在刷新完成前显示缓存，后续数据更新同一列表', (tester) async {
    final source = _Source();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomePage(source: source),
      ),
    );
    source.controllers.single.add(_feed('缓存通知'));
    await tester.pumpAndSettle();
    expect(find.text('缓存通知'), findsOneWidget);
    source.controllers.single.add(_feed('新通知'));
    await tester.pumpAndSettle();
    expect(find.text('新通知'), findsOneWidget);
    expect(find.text('缓存通知'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await source.controllers.single.close();
    expect(tester.takeException(), isNull);
  });

  testWidgets('重复刷新时迟到的旧通知流不能覆盖新数据', (tester) async {
    final source = _Source();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomePage(source: source),
      ),
    );
    source.controllers.single.add(_feed('缓存通知'));
    await tester.pumpAndSettle();
    final refresh = tester.state<RefreshIndicatorState>(
      find.byType(RefreshIndicator),
    );
    final pending = refresh.show();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(source.controllers, hasLength(2));
    source.controllers[1].add(_feed('最新通知'));
    await source.controllers[1].close();
    await tester.pumpAndSettle();
    await pending;
    source.controllers[0].add(_feed('迟到通知'));
    await source.controllers[0].close();
    await tester.pumpAndSettle();
    expect(find.text('最新通知'), findsOneWidget);
    expect(find.text('迟到通知'), findsNothing);
  });
}
