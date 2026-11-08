import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/app_exception.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/lms/rollcall_api.dart';

class _Client extends CasClient {
  String body = '';
  int status = 200;
  @override
  Future<Response<String>> getApi(
    Uri uri, {
    Map<String, String>? headers,
  }) async => Response(
    requestOptions: RequestOptions(path: '$uri'),
    statusCode: status,
    data: body,
  );
}

void main() {
  test('明确空签到和列表、对象两种有效结构都保持兼容', () async {
    final client = _Client();
    final api = RollcallApi(client);
    for (final raw in ['[]', '{"rollcalls":[]}']) {
      client.body = raw;
      expect(await api.fetchOngoing(), isEmpty);
    }
    final items = [
      {
        'id': 1,
        'course': {'name': '课程一'},
      },
      {'rollcall_id': '2', 'course_title': '课程二'},
      {'rollcallId': '3', 'course_name': '课程三'},
      {'uuid': '4', 'courseName': '课程四'},
    ];
    for (final value in [
      items,
      {'rollcalls': items},
    ]) {
      client.body = jsonEncode(value);
      final records = await api.fetchOngoing();
      expect(records.map((r) => r.id), ['1', '2', '3', '4']);
      expect(records.map((r) => r.courseName), ['课程一', '课程二', '课程三', '课程四']);
    }
  });

  test('错误响应、字段缺失、破损 JSON 和缺失记录不能清空旧签到', () async {
    final client = _Client();
    final api = RollcallApi(client);
    for (final body in [
      '',
      '{',
      '[',
      'null',
      '{}',
      '{"message":"session expired"}',
      '{"rollcalls":null}',
      '{"rollcalls":{}}',
      '[null]',
      '[{}]',
      '{"rollcalls":[{"id":1},{}]}',
      '{"rollcalls":[],"success":false}',
    ]) {
      client.body = body;
      await expectLater(
        api.fetchOngoing(),
        throwsA(
          isA<AppException>().having(
            (e) => e.failure,
            'failure',
            AppFailure.parse,
          ),
        ),
        reason: body,
      );
    }
  });

  test('HTTP 401/403 和登录 HTML 表达登录失效，其他 HTTP 错误不当成空列表', () async {
    final client = _Client()..body = '{"rollcalls":[]}';
    final api = RollcallApi(client);
    for (final status in [401, 403, 404, 500]) {
      client.status = status;
      await expectLater(
        api.fetchOngoing(),
        throwsA(
          isA<AppException>().having(
            (e) => e.failure,
            'failure',
            status == 401 || status == 403
                ? AppFailure.auth
                : AppFailure.server,
          ),
        ),
      );
    }
    client
      ..status = 200
      ..body = '<html>请登录</html>';
    await expectLater(
      api.fetchOngoing(),
      throwsA(isA<AppException>().having((e) => e.needsRelogin, 'auth', true)),
    );
  });
}
