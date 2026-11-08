import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/jwc/space_booking_api.dart';
import 'package:project_usst/pages/space_booking_page.dart';

SpaceReservation reservation(String id, {int status = 0}) => SpaceReservation(
  id: id,
  roomId: id,
  roomName: '房间$id',
  date: '2026-11-06',
  beginTime: '14:00',
  endTime: '16:00',
  status: status,
  statusDesc: status == 0 ? '已预约' : '已结束',
  isLeader: true,
  qrCode: '',
);

SpaceRoom room(String name) => SpaceRoom(
  id: name,
  name: name,
  floor: '1F',
  roomType: '研修间',
  minNum: 1,
  maxNum: 1,
  devices: '',
  status: 0,
  allTime: 1,
);

class _Api extends SpaceBookingApi {
  final auth = Completer<bool>();
  final rooms = <String, Completer<List<SpaceRoom>>>{};
  final current = Completer<List<SpaceReservation>>();
  final history = <Completer<SpaceReservationPage>>[];
  final pages = <int>[];
  @override
  Future<bool> ensureAuthenticated({bool force = false}) => auth.future;
  @override
  Future<List<SpaceRoom>> fetchRooms({String? date}) =>
      rooms.putIfAbsent(date!, Completer.new).future;
  @override
  Future<List<SpaceReservation>> fetchCurrentReservations() => current.future;
  @override
  Future<SpaceReservationPage> fetchReservationHistory({
    int page = 1,
    int size = 20,
  }) {
    pages.add(page);
    final completer = Completer<SpaceReservationPage>();
    history.add(completer);
    return completer.future;
  }
}

Future<void> frame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('慢历史不阻塞房间和当前预约，失败可重试，分页去重且连点只请求一次', (tester) async {
    final api = _Api()..auth.complete(true);
    await tester.pumpWidget(MaterialApp(home: SpaceBookingPage(api: api)));
    await frame(tester);
    api.rooms.values.first.complete([room('快速到达的研修间')]);
    await frame(tester);
    expect(find.text('快速到达的研修间'), findsOneWidget);
    await tester.tap(find.text('我的预约'));
    await frame(tester);
    api.current.complete([reservation('active')]);
    await frame(tester);
    expect(find.textContaining('房间active'), findsWidgets);
    api.history[0].completeError(SpaceBookingException('历史网络中断'));
    await frame(tester);
    expect(find.textContaining('历史网络中断'), findsOneWidget);
    expect(find.textContaining('房间active'), findsWidgets);
    await tester.tap(find.text('重试'));
    await frame(tester);
    expect(api.pages, [1, 1]);
    api.history[1].complete(
      SpaceReservationPage(
        items: [
          reservation('active', status: 2),
          reservation('old1', status: 2),
        ],
        page: 1,
        hasMore: true,
      ),
    );
    await frame(tester);
    expect(find.text('全部 (2)'), findsOneWidget);
    expect(find.text('进行中 (1)'), findsOneWidget);
    final loadMore = find.byKey(const ValueKey('load-more-reservations'));
    await tester.tap(loadMore);
    await tester.tap(loadMore);
    await frame(tester);
    expect(api.pages, [1, 1, 2]);
    api.history[2].completeError(SpaceBookingException('第二页中断'));
    await frame(tester);
    await tester.tap(find.text('重试'));
    await frame(tester);
    expect(api.pages, [1, 1, 2, 2]);
    api.history[3].complete(
      SpaceReservationPage(
        items: [reservation('old1', status: 2), reservation('old2', status: 2)],
        page: 2,
        hasMore: false,
      ),
    );
    await frame(tester);
    expect(find.text('全部 (3)'), findsOneWidget);
    expect(loadMore, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('页面销毁后认证失败不更新页面，也不抛出未处理异常', (tester) async {
    final api = _Api();
    await tester.pumpWidget(MaterialApp(home: SpaceBookingPage(api: api)));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    api.auth.completeError(Exception('offline'));
    await frame(tester);
    expect(tester.takeException(), isNull);
    expect(api.pages, isEmpty);
  });

  testWidgets('连续切日期时只显示最后一天，空预约能点击返回空间列表', (tester) async {
    final api = _Api()..auth.complete(true);
    await tester.pumpWidget(MaterialApp(home: SpaceBookingPage(api: api)));
    await frame(tester);
    final todayRequest = api.rooms.values.first;
    await tester.tap(find.textContaining('今天').first);
    await frame(tester);
    await tester.tap(find.textContaining('明天').first);
    await frame(tester);
    final tomorrowRequest = api.rooms.values.last;
    await tester.tap(find.textContaining('明天').first);
    await frame(tester);
    await tester.tap(find.textContaining('后天').first);
    await frame(tester);
    api.rooms.values.last.complete([room('最后一天')]);
    await frame(tester);
    tomorrowRequest.complete([room('过期响应')]);
    todayRequest.complete([room('首日旧响应')]);
    api.current.complete([]);
    api.history.first.complete(
      const SpaceReservationPage(items: [], page: 1, hasMore: false),
    );
    await frame(tester);
    expect(find.text('最后一天'), findsOneWidget);
    expect(find.text('过期响应'), findsNothing);
    expect(find.text('首日旧响应'), findsNothing);
    await tester.tap(find.text('我的预约'));
    await frame(tester);
    await tester.tap(find.text('去挑选研修空间'));
    await frame(tester);
    expect(find.text('最后一天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
