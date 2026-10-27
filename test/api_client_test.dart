import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/http/api_client.dart';

/// 用本地 HttpServer 验证统一客户端的三个行为：
/// 1. 正常请求能通
/// 2. 5xx 会重试（GET），且最终成功
/// 3. POST 不重试（避免重复提交）
void main() {
  late HttpServer server;
  late String base;
  var hits = 0;

  setUp(() async {
    hits = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      hits++;
      if (req.uri.path == '/flaky') {
        // 前两次 500，第三次 200
        if (hits < 3) {
          req.response.statusCode = 500;
        } else {
          req.response.statusCode = 200;
        }
      } else {
        req.response.statusCode = 200;
      }
      req.response.write('ok');
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('普通 GET 能拿到 200', () async {
    final resp = await ApiClient.dio.get<String>('$base/ok');
    expect(resp.statusCode, 200);
    expect(hits, 1);
  });

  test('GET 遇到 5xx 会重试并最终成功', () async {
    final resp = await ApiClient.dio.get<String>('$base/flaky');
    expect(resp.statusCode, 200);
    expect(hits, 3); // 1 次原始 + 2 次重试
  });

  test('POST 遇到 5xx 不重试', () async {
    await expectLater(
      ApiClient.dio.post<String>('$base/flaky'),
      throwsA(isA<DioException>()),
    );
    expect(hits, 1);
  });

  test('lib 下不应新增明文 http:// 地址', () {
    // Android 的 network_security_config 已设置 cleartextTrafficPermitted=false，
    // 明文地址在真机上会直接连接失败，这里做一道静态防回归。
    final offenders = <String>[];
    final pattern = RegExp(r"""['"]http://[a-zA-Z0-9]""");
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}  ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: '发现明文 HTTP 地址：\n${offenders.join('\n')}');
  });
}
