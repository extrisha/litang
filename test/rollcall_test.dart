import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/lms/rollcall_api.dart';

void main() {
  group('RollcallApi.parseOngoing', () {
    test('解析进行中的签到（服务端用 is_number / course_title）', () {
      const raw =
          '{"rollcalls": ['
          '{"rollcall_id": 123, "course_title": "电路原理", "is_number": true, '
          '"status": "absent", "created_at": "2026-10-23T10:30:00"}'
          ']}';
      final list = RollcallApi.parseOngoing(raw);
      expect(list.length, 1);
      final rollcall = list.first;
      expect(rollcall.id, '123');
      expect(rollcall.courseName, '电路原理');
      expect(rollcall.isNumberRollcall, isTrue);
      expect(rollcall.typeLabel, '数字口令');
      expect(rollcall.isSignable, isTrue);
      expect(rollcall.timeText, '10:30');
    });

    test('数字口令 / 雷达 / 二维码 / 默认类型', () {
      final raw =
          '{"rollcalls": ['
          '{"id": 1, "is_number": true},'
          '{"id": 2, "is_radar": true},'
          '{"id": 3, "type": "qr_code"},'
          '{"id": 4, "type": "unknown"}'
          ']}';
      final list = RollcallApi.parseOngoing(raw);
      expect(list.map((r) => r.typeLabel).toList(), <String>[
        '数字口令',
        '雷达点名',
        '二维码签到',
        '签到',
      ]);
      expect(list[0].isNumberRollcall, isTrue);
      expect(list[1].isRadarRollcall, isTrue);
      expect(list[2].isQrRollcall, isTrue);
      expect(list[2].isNumberRollcall, isFalse);
    });

    test('已签到 / 已结束不再算可签到', () {
      const raw =
          '{"rollcalls": ['
          '{"id": 1, "is_number": true, "status": "on_call_fine"},'
          '{"id": 2, "is_number": true, "is_expired": true}'
          ']}';
      final list = RollcallApi.parseOngoing(raw);
      expect(list[0].isSigned, isTrue);
      expect(list[0].isSignable, isFalse);
      expect(list[1].isExpired, isTrue);
      expect(list[1].isSignable, isFalse);
    });

    test('空列表 / 非 JSON', () {
      expect(RollcallApi.parseOngoing('{"rollcalls":[]}'), isEmpty);
      expect(RollcallApi.parseOngoing('<html></html>'), isEmpty);
      expect(RollcallApi.parseOngoing(''), isEmpty);
    });

    test('缺 id 的项被跳过', () {
      final raw = '{"rollcalls": [{"course_title": "没有 id"}, {"id": 9}]}';
      final list = RollcallApi.parseOngoing(raw);
      expect(list.length, 1);
      expect(list.first.id, '9');
      expect(list.first.courseName, '未知课程');
    });
  });

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
