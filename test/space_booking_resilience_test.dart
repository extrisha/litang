import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/jwc/space_booking_api.dart';

Map<String, dynamic> record(String id) => {
  'id': id,
  'roomId': '101',
  'roomName': '研修间',
  'startTime': '2026-11-06 14:00:00',
  'endTime': '2026-11-06 16:00:00',
  'reservationStatus': 21,
  'type': 0,
};

class _Client extends CasClient {
  dynamic current;
  dynamic submitResponse;
  Completer<void>? submitGate;
  bool disconnect = false;
  int posts = 0;
  final pages = <int>[];
  final historyBodies = <int, dynamic>{};
  Response<String> response(Uri uri, dynamic body) => Response(
    requestOptions: RequestOptions(path: uri.toString()),
    statusCode: 200,
    data: jsonEncode(body),
  );
  @override
  Future<Response<String>> getApi(
    Uri uri, {
    Map<String, String>? headers,
  }) async => response(uri, current);
  @override
  Future<Response<String>> sendJsonWithHeaders(
    Uri uri, {
    String method = 'POST',
    Map<String, dynamic> data = const {},
    Map<String, String> extraHeaders = const {},
  }) async {
    final page = int.parse(uri.queryParameters['page']!);
    pages.add(page);
    return response(uri, historyBodies[page]);
  }

  @override
  Future<Response<String>> postApi(
    Uri uri,
    Map<String, String> data, {
    String? referer,
    Map<String, String> extraHeaders = const {},
  }) async {
    posts++;
    await submitGate?.future;
    if (disconnect) {
      throw DioException(
        requestOptions: RequestOptions(path: uri.toString()),
        type: DioExceptionType.receiveTimeout,
      );
    }
    return response(uri, submitResponse);
  }
}

SpaceBookingApi _api(_Client client) => SpaceBookingApi(client)
  ..accessToken = 'fixture-token'
  ..userId = 'student'
  ..tokenObtainedAt = DateTime.now();

Future<ReservationResult> submit(SpaceBookingApi api) => api.submitReservation(
  roomId: '101',
  startTime: '2026-11-06 14:00:00',
  endTime: '2026-11-06 16:00:00',
  dictId: 1,
);

void main() {
  test('历史分页使用真实页码、页大小及 total 判断末页', () async {
    final client = _Client()
      ..historyBodies[1] = {
        'records': [record('1'), record('2')],
        'total': 3,
      }
      ..historyBodies[2] = {
        'records': [record('3')],
        'total': 3,
      };
    final service = _api(client);
    final first = await service.fetchReservationHistory(size: 2);
    final last = await service.fetchReservationHistory(page: 2, size: 2);
    expect(first.hasMore, isTrue);
    expect(last.hasMore, isFalse);
    expect(last.items.single.id, '3');
    expect(client.pages, [1, 2]);
  });

  test('业务错误或结构变化不能伪装成没有预约', () async {
    final client = _Client()..current = {'code': 503, 'message': 'maintenance'};
    final service = _api(client);
    await expectLater(
      service.fetchCurrentReservations(),
      throwsA(isA<SpaceBookingException>()),
    );
    client.current = {'unexpected': 'format'};
    await expectLater(
      service.fetchCurrentReservations(),
      throwsA(isA<SpaceBookingException>()),
    );
    client.historyBodies[1] = {'items': []};
    await expectLater(
      service.fetchReservationHistory(),
      throwsA(isA<SpaceBookingException>()),
    );
    client.current = {'code': 200, 'data': null};
    expect(await service.fetchCurrentReservations(), isEmpty);
  });

  test('提交超时但当前预约已有订单时确认成功，不重发', () async {
    final client = _Client()
      ..disconnect = true
      ..current = record('confirmed');
    final result = await submit(_api(client));
    expect(result.success, isTrue);
    expect(result.outcomeUnknown, isFalse);
    expect(result.reservationId, 'confirmed');
    expect(client.posts, 1);
  });

  test('结果不明时再次点击只查询，后续出现订单能够确认', () async {
    final client = _Client()..disconnect = true;
    final service = _api(client);
    expect((await submit(service)).outcomeUnknown, isTrue);
    expect((await submit(service)).outcomeUnknown, isTrue);
    expect(client.posts, 1);
    client.current = record('eventually-visible');
    expect((await submit(service)).success, isTrue);
    expect(client.posts, 1);
  });

  test('同时提交同一时段共享请求；明确拒绝可以修正后再试', () async {
    final client = _Client()
      ..submitGate = Completer<void>()
      ..submitResponse = {'code': 409, 'message': '时间冲突'};
    final service = _api(client);
    final first = submit(service);
    final duplicate = submit(service);
    expect(identical(first, duplicate), isTrue);
    client.submitGate!.complete();
    expect((await first).outcomeUnknown, isFalse);
    expect((await duplicate).success, isFalse);
    expect(client.posts, 1);
    client.submitResponse = {
      'code': 200,
      'data': {'id': 'new'},
    };
    expect((await submit(service)).success, isTrue);
    expect(client.posts, 2);
  });
}
