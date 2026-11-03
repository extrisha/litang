import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/jwc/space_booking_api.dart';

/// 并发登录必须**单飞**。
///
/// 现场症状：房间列表和「我的预约」是并发拉取的，token 被服务端判无效时两边
/// 同时触发重登 → 两轮 CAS 授权 + 两次换 token 互相覆盖，用户看到
/// 「刚登录成功却一直提示登录失效」。
class _CountingClient extends CasClient {
  int authorizeCalls = 0;

  @override
  Future<Response<String>> getApi(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    if (uri.path.contains('/oauth/v1/authorize')) {
      authorizeCalls++;
      // 慢一点，确保并发调用都落在同一个在途 Future 上
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return Response<String>(
        requestOptions: RequestOptions(path: uri.toString()),
        statusCode: 200,
        data: '<html>no code here</html>',
      );
    }
    return Response<String>(
      requestOptions: RequestOptions(path: uri.toString()),
      statusCode: 404,
      data: 'Not Found',
    );
  }
}

void main() {
  test('三个并发 login 只发起一轮授权', () async {
    final client = _CountingClient();
    final api = SpaceBookingApi(client);

    final results = await Future.wait(<Future<bool>>[
      api.login(),
      api.login(),
      api.login(),
    ]);

    expect(results, <bool>[false, false, false]);
    expect(client.authorizeCalls, 1, reason: '并发调用应共享同一次登录，而不是各发起一轮');
  });

  test('登录失败后进入冷却，force 可绕过', () async {
    final client = _CountingClient();
    final api = SpaceBookingApi(client);

    expect(await api.login(), isFalse);
    expect(client.authorizeCalls, 1);

    // 冷却期内：直接返回 false，不再打 CAS（避免请求风暴）
    expect(await api.login(), isFalse);
    expect(client.authorizeCalls, 1, reason: '冷却期内不应再次请求授权');

    // 用户主动重试可以绕过冷却
    expect(await api.login(force: true), isFalse);
    expect(client.authorizeCalls, 2);
  });
}
