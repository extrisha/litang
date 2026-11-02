import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/app_exception.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/lms/rollcall_api.dart';

/// 契约回归：签到列表拿到 HTML（登录页/错误页）时必须抛 [AppException]，
/// 不能返回空列表——否则页面会显示「当前没有进行中的签到」，
/// 把「登录失效」伪装成「没有签到」。
class _FakeCasClient extends CasClient {
  _FakeCasClient(this.body);

  final String body;

  @override
  Future<Response<String>> getApi(
    Uri uri, {
    Map<String, String>? headers,
  }) async => Response<String>(
    requestOptions: RequestOptions(path: uri.toString()),
    statusCode: 200,
    data: body,
  );
}

void main() {
  test('拿到 HTML 登录页时抛 auth 异常', () async {
    final api = RollcallApi(
      _FakeCasClient('<html><body>请登录 <a href="/login">登录</a></body></html>'),
    );
    await expectLater(
      api.fetchOngoing(),
      throwsA(
        isA<AppException>().having(
          (e) => e.failure,
          'failure',
          AppFailure.auth,
        ),
      ),
    );
  });

  test('正常 JSON 空列表照常返回（不误判为失败）', () async {
    final api = RollcallApi(_FakeCasClient('{"rollcalls": []}'));
    final list = await api.fetchOngoing();
    expect(list, isEmpty);
  });
}
