import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/jwc/space_booking_api.dart';

/// 模拟「网关把过期 token 判成 400」：第一次拉房间返回 400，
/// 重新登录之后的第二次返回正常数据。
class _SequencedCasClient extends CasClient {
  int roomsCalls = 0;
  int authorizeCalls = 0;
  int tokenCalls = 0;

  Response<String> _json(Uri uri, int status, Object body) => Response<String>(
    requestOptions: RequestOptions(path: uri.toString()),
    statusCode: status,
    data: body is String ? body : jsonEncode(body),
  );

  @override
  Future<Response<String>> getApi(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final key = uri.toString();

    if (key.contains('oauth/v1/authorize')) {
      authorizeCalls++;
      return Response<String>(
        requestOptions: RequestOptions(
          path:
              'https://libspace.usst.edu.cn/student/studentIndex?code=code-$authorizeCalls',
        ),
        statusCode: 200,
        data: '<html>redirect</html>',
      );
    }
    if (key.contains('userAccount/accessToken')) {
      tokenCalls++;
      return _json(uri, 200, <String, dynamic>{
        'accessToken': 'token-$tokenCalls',
        'expires': 7200,
      });
    }
    if (key.contains('room/mRooms')) {
      roomsCalls++;
      if (roomsCalls == 1) {
        return _json(uri, 400, <String, dynamic>{'message': 'token invalid'});
      }
      return _json(uri, 200, <String, dynamic>{'data': <dynamic>[]});
    }
    return _json(uri, 404, '');
  }

  @override
  Future<Response<String>> postApi(
    Uri uri,
    Map<String, String> data, {
    String? referer,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    if (uri.toString().contains('oauth/v1/user')) {
      return _json(uri, 200, <String, dynamic>{'userId': 'student-1'});
    }
    return _json(uri, 404, '');
  }
}

void main() {
  test('房间接口返回 400 时会作废 token、重登并重试一次', () async {
    final client = _SequencedCasClient();
    final api = SpaceBookingApi(client);

    final rooms = await api.fetchRooms();

    expect(rooms, isEmpty, reason: '重试后拿到的是空列表，不是异常');
    expect(client.roomsCalls, 2, reason: '400 之后必须重试一次');
    expect(client.authorizeCalls, 2, reason: '首次登录 + 被拒后重登');
    expect(api.accessToken, 'token-2', reason: '第二次拿到的应该是新 token');
  });

  test('作废 token 后 isTokenValid 变 false', () async {
    final client = _SequencedCasClient();
    final api = SpaceBookingApi(client);
    await api.fetchRooms();
    expect(api.isTokenValid, isTrue);

    api.invalidateToken();
    expect(api.accessToken, isNull);
    expect(api.isTokenValid, isFalse);
  });
}
