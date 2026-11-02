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

  group('RollcallApi.parseSignResult', () {
    test('成功签到响应', () {
      final res = RollcallApi.parseSignResult(200, '{"status_name":"已签到"}');
      expect(res.success, isTrue);
      expect(res.statusName, '已签到');
    });

    test('200 响应但跟随到登录页判定为失效', () {
      final res = RollcallApi.parseSignResult(
        200,
        '<html>login</html>',
        realUrl: 'https://1906.usst.edu.cn/auth/login',
      );
      expect(res.success, isFalse);
      expect(res.message, contains('登录状态已失效'));
    });

    test('errorCode 触发友好提示', () {
      final res = RollcallApi.parseSignResult(
        400,
        '{"errorCode":"ROLLCALL_RADAR_OUT_OF_SCOPE"}',
      );
      expect(res.success, isFalse);
      expect(res.message, '定位超出签到范围，请靠近上课教室后重试');
    });

    test('error_code（下划线风格）兼容映射', () {
      final res = RollcallApi.parseSignResult(
        400,
        '{"error_code":"ROLLCALL_RADAR_OUT_OF_SCOPE"}',
      );
      expect(res.success, isFalse);
      expect(res.message, '定位超出签到范围，请靠近上课教室后重试');
    });

    test('英文 message/error（如 out of roll scope）转为友好中文', () {
      final res1 = RollcallApi.parseSignResult(
        400,
        '{"message":"out of roll scope"}',
      );
      expect(res1.success, isFalse);
      expect(res1.message, '定位超出签到范围，请靠近上课教室后重试');

      final res2 = RollcallApi.parseSignResult(
        400,
        '{"error":"Position out of scope"}',
      );
      expect(res2.success, isFalse);
      expect(res2.message, '定位超出签到范围，请靠近上课教室后重试');
    });

    test('蓝牙信标缺失错误映射', () {
      final res = RollcallApi.parseSignResult(
        400,
        '{"errorCode":"RADAR_SIGNAL_INVALID_NO_SIGNAL"}',
      );
      expect(res.success, isFalse);
      expect(res.message, '本堂课需要教室蓝牙信标，请在教室内重试');
    });

    test('设备重复签到错误映射', () {
      final res = RollcallApi.parseSignResult(
        400,
        '{"error_code":"ROLLCALL_DEVICE_ALREADY_IN_USE"}',
      );
      expect(res.success, isFalse);
      expect(res.message, '这台设备已经给其他账号签过到了');
    });
  });
}
