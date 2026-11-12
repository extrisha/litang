import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/lms/rollcall_api.dart';

void main() {
  group('QrPayload.parse', () {
    test('JSON 格式', () {
      final payload = QrPayload.parse(
        '{"rollcallId":"7","data":"abc","courseId":"9"}',
      );
      expect(payload, isNotNull);
      final qr = payload!;
      expect(qr.rollcallId, 7);
      expect(qr.courseId, 9);
      expect(qr.data, 'abc');
    });

    test('URL 的 _p 参数是 JSON', () {
      final url = Uri(
        scheme: 'https',
        host: '1906.usst.edu.cn',
        path: '/j',
        queryParameters: <String, String>{
          '_p': '{"rollcallId":"7","data":"abc"}',
        },
      ).toString();
      final payload = QrPayload.parse(url);
      expect(payload, isNotNull);
      final qr = payload!;
      expect(qr.rollcallId, 7);
      expect(qr.data, 'abc');
    });

    test('URL 直接带 rollcall_id / data', () {
      final payload = QrPayload.parse(
        'https://1906.usst.edu.cn/scan?rollcall_id=42&data=tok',
      );
      expect(payload, isNotNull);
      final qr = payload!;
      expect(qr.rollcallId, 42);
      expect(qr.data, 'tok');
    });

    test('真实课堂二维码：/j?p= + 42 位 data（2026-11-12 实拍）', () {
      // 教室大屏实拍解码结果：courseId=146144, rollcallId=740927，
      // data = 10 位 unix 秒 + 32 位 md5，共 42 位。
      const url =
          '/j?p=0~\u001034rk!3~17944645864b8bd8fc375fec72aa4f9238b255d4bb'
          '!4~\u0010fvpb';
      final qr = QrPayload.parse(url);
      expect(qr, isNotNull);
      expect(qr!.courseId, 146144);
      expect(qr.rollcallId, 740927);
      expect(qr.data.length, 42);
      expect(qr.data.substring(0, 10), '1794464586');
      expect(qr.data.substring(10), '4b8bd8fc375fec72aa4f9238b255d4bb');
    });

    test('官方 Base36 紧凑编码（带 \\x10 前缀）', () {
      // 4~1x = rollcallId 69；0~2y = courseId 106
      final payload = QrPayload.parse('\u00104~1x!3~tok!0~2y');
      expect(payload, isNotNull);
      final qr = payload!;
      expect(qr.rollcallId, 69);
      expect(qr.courseId, 106);
      expect(qr.data, 'tok');
    });

    test('紧凑编码里的分隔符转义', () {
      final payload = QrPayload.parse('4~1!3~a\u001Eb\u001Fc!0~2');
      expect(payload, isNotNull);
      final qr = payload!;
      expect(qr.data, 'a~b!c');
    });

    test('纯口令当 data', () {
      final payload = QrPayload.parse(' 123456 ');
      expect(payload, isNotNull);
      final qr = payload!;
      expect(qr.rollcallId, isNull);
      expect(qr.data, '123456');
    });

    test('空内容返回 null', () {
      expect(QrPayload.parse('   '), isNull);
    });
  });
}
