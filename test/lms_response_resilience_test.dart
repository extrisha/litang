import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/app_exception.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/lms/todo_api.dart';

class _Client extends CasClient {
  String body = '';
  int status = 200;

  Response<String> response(Uri uri) => Response(
    requestOptions: RequestOptions(path: uri.toString()),
    statusCode: status,
    data: body,
  );

  @override
  Future<Response<String>> getApi(
    Uri uri, {
    Map<String, String>? headers,
  }) async => uri.path == '/user/index'
      ? Response(
          requestOptions: RequestOptions(path: uri.toString()),
          statusCode: 200,
          data: '<input id="userId" value="fixture-user">',
        )
      : response(uri);

  @override
  Future<Response<String>> getJson(
    Uri uri, {
    Map<String, String>? data,
  }) async => response(uri);
}

void main() {
  final endpoints = [
    (
      label: '待办',
      key: 'todo_list',
      fetch: (LmsApi api) => api.fetchTodos(),
      item: {'id': 1, 'title': 'fixture todo'},
    ),
    (
      label: '考试',
      key: 'items',
      fetch: (LmsApi api) => api.fetchExams(),
      item: {'kcmc': 'fixture exam'},
    ),
    (
      label: '课程',
      key: 'courses',
      fetch: (LmsApi api) => api.fetchCourseInfos(),
      item: {'id': 1, 'name': 'fixture course'},
    ),
  ];
  for (final endpoint in endpoints) {
    test('${endpoint.label}明确空列表可以清空旧值，非空列表正常解析', () async {
      final client = _Client()..body = jsonEncode({endpoint.key: []});
      final api = LmsApi(client);
      expect(await endpoint.fetch(api), isEmpty);
      client.body = jsonEncode({
        endpoint.key: [endpoint.item],
      });
      expect(await endpoint.fetch(api), hasLength(1));
    });

    test('${endpoint.label}空响应、错误 JSON、列表缺失和不完整不能当成没有数据', () async {
      final client = _Client();
      final api = LmsApi(client);
      for (final body in [
        '',
        '{',
        '[]',
        '{}',
        '{"message":"session expired"}',
        jsonEncode({endpoint.key: null}),
        jsonEncode({endpoint.key: {}}),
        jsonEncode({
          endpoint.key: [null],
        }),
        jsonEncode({endpoint.key: [], 'success': false}),
      ]) {
        client.body = body;
        await expectLater(
          endpoint.fetch(api),
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

    test('${endpoint.label}HTTP 错误和登录页不能覆盖旧缓存', () async {
      final client = _Client()..body = jsonEncode({endpoint.key: []});
      final api = LmsApi(client);
      for (final status in [401, 403, 404, 500]) {
        client.status = status;
        await expectLater(
          endpoint.fetch(api),
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
        endpoint.fetch(api),
        throwsA(
          isA<AppException>().having((e) => e.needsRelogin, 'auth', true),
        ),
      );
    });
  }
}
