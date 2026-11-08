import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/jwc/classroom_api.dart';
import 'package:project_usst/pages/classroom/empty_classroom_tab.dart';

class Pages extends CasClient {
  var calls = 0;
  bool repeated = false;
  bool incomplete = false;
  bool overlapping = false;
  @override
  Future<Response<String>> getApi(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    String body = '{}';
    if (uri.path.endsWith('queryClassSchedule.rst')) {
      calls++;
      final page = int.parse(uri.queryParameters['page']!);
      final data = page == 0 || repeated
          ? List.generate(
              1000,
              (i) => {
                'id': '$i',
                'kcmc': '课程$i',
                'jsdd': '其他楼$i',
                'zj': 1,
                'jc': 1,
              },
            )
          : overlapping
          ? [
              {'id': '999', 'jsdd': '其他楼999', 'zj': 1, 'jc': 1},
            ]
          : incomplete
          ? []
          : [
              {
                'id': '1000',
                'jsdd': '一教201',
                'kcmc': '第二页的课',
                'zj': 1,
                'jc': 1,
              },
            ];
      body = jsonEncode({
        'resultCode': 0,
        'result': {'data': data, 'total': 1001},
      });
    }
    return Response(
      requestOptions: RequestOptions(path: '$uri'),
      data: body,
      statusCode: 200,
    );
  }
}

class DelayedClassrooms extends ClassroomApi {
  DelayedClassrooms() : super(CasClient());
  final requests = <Completer<List<ClassroomInfo>>>[];
  @override
  Future<List<ClassroomInfo>> queryClassrooms({
    required String building,
    required int week,
    required int dayOfWeek,
    required (int, int)? sectionRange,
    String queryJc = '1-2',
    String xn = '',
    String xq = '',
    bool forceRefresh = false,
  }) {
    final c = Completer<List<ClassroomInfo>>();
    requests.add(c);
    return c.future;
  }
}

void main() {
  test('超过1000条时补齐第二页，第二页占用不能当成空闲', () async {
    final client = Pages();
    final api = ClassroomApi(client);
    final rooms = await api.queryClassrooms(
      building: '第一教学楼',
      week: 1,
      dayOfWeek: 1,
      sectionRange: (1, 2),
    );
    final room = rooms.singleWhere((r) => r.name == '一教201');
    expect(room.isFree, isFalse);
    expect(room.occupiedCourse, '第二页的课');
    expect(client.calls, 2);
  });
  test('分页缺失或重复必须报不完整，不推断空闲', () async {
    for (final repeated in [false, true]) {
      final client = Pages()
        ..incomplete = true
        ..repeated = repeated;
      await expectLater(ClassroomApi(client).fetchSchedule(), throwsException);
      expect(client.calls, 2);
    }
  });
  test('部分重叠的分页不能凑够 total 后当成完整结果', () async {
    final client = Pages()..overlapping = true;
    await expectLater(
      ClassroomApi(client).fetchSchedule(),
      throwsA(predicate((error) => error.toString().contains('重叠'))),
    );
    expect(client.calls, 2);
    // The invalid page must not populate the query cache.
    client.overlapping = false;
    expect(await ClassroomApi(client).fetchSchedule(), hasLength(1001));
    expect(client.calls, 4);
  });
  test('同会话合并请求、缓存5分钟；换会话不复用缓存', () async {
    var now = DateTime(2026, 11, 7);
    final client = Pages();
    final api = ClassroomApi(client, now: () => now);
    await Future.wait([api.fetchSchedule(), api.fetchSchedule()]);
    expect(client.calls, 2);
    await api.fetchSchedule();
    expect(client.calls, 2);
    now = now.add(const Duration(minutes: 6));
    await api.fetchSchedule();
    expect(client.calls, 4);
    final other = Pages();
    await ClassroomApi(other).fetchSchedule();
    expect(other.calls, 2);
  });
  testWidgets('未登录教室显示待确认，不能显示可自习', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EmptyClassroomTab())),
    );
    await tester.pump();
    expect(find.text('待确认'), findsWidgets);
    expect(find.text('可自习'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('刷新乱序保留最新结果，离开页面不更新已销毁状态', (tester) async {
    final api = DelayedClassrooms();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EmptyClassroomTab(api: api)),
      ),
    );
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    api.requests[1].complete([
      const ClassroomInfo(name: '新结果', building: '一教', isFree: true),
    ]);
    await refresh;
    await tester.pump();
    api.requests[0].complete([
      const ClassroomInfo(name: '旧结果', building: '一教', isFree: true),
    ]);
    await tester.pump();
    expect(find.text('新结果'), findsOneWidget);
    expect(find.text('旧结果'), findsNothing);
    final last = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpWidget(const SizedBox());
    api.requests[2].complete([]);
    await last;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
