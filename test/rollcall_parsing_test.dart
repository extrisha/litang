import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/lms/rollcall_api.dart';
void main() {
  group('RollcallApi.buildRadarPayload（对齐 usst-jwgl-client）', () {
    test('字段固定：accuracy 默认 15、altitude 10.0、radarSignal null', () {
      final body = RollcallApi.buildRadarPayload(
        deviceId: 'uuid',
        latitude: 31.29464,
        longitude: 121.55350,
      );
      expect(body['deviceId'], 'uuid');
      expect(body['latitude'], 31.29464);
      expect(body['longitude'], 121.55350);
      expect(body['accuracy'], 15.0);
      expect(body['altitude'], 10.0);
      expect(body.containsKey('radarSignal'), isTrue);
      expect(body['radarSignal'], isNull);
      expect(body.containsKey('altitudeAccuracy'), isFalse);
      expect(body.containsKey('heading'), isFalse);
      expect(body.containsKey('speed'), isFalse);
    });

    test('传入精度时使用实际精度，不改变其它字段', () {
      final body = RollcallApi.buildRadarPayload(
        deviceId: 'uuid',
        latitude: 31.0,
        longitude: 121.0,
        accuracy: 8.5,
      );
      expect(body['accuracy'], 8.5);
      expect(body['altitude'], 10.0);
      expect(body['radarSignal'], isNull);
    });
  });

  group('RollcallApi.parseNumberCode', () {
    test('从花名册数组里读口令', () {
      const body =
          '{"student_rollcalls":[{"user_no":"2023001","number_code":"1234"}]}';
      final lookup = RollcallApi.parseNumberCode(body);
      expect(lookup.found, isTrue);
      expect(lookup.code, '1234');
    });

    test('整型口令补零：123 应为 0123', () {
      expect(RollcallApi.parseNumberCode('{"number_code":123}').code, '0123');
      expect(RollcallApi.parseNumberCode('{"number_code":7}').code, '0007');
    });

    test('字符串口令也补零', () {
      expect(RollcallApi.parseNumberCode('{"number_code":"42"}').code, '0042');
    });

    test('详情里的 rollcall 子对象也认', () {
      const body =
          '{"rollcall":{"id":9,"number_code":"5678"},"is_expired":false}';
      expect(RollcallApi.parseNumberCode(body).code, '5678');
    });

    test('多行同一个口令只算一个', () {
      const body =
          '{"student_rollcalls":['
          '{"number_code":"1234"},{"number_code":1234,"user_no":"2"}'
          ']}';
      expect(RollcallApi.parseNumberCode(body).code, '1234');
    });

    test('多行不同口令时拒绝自动签', () {
      const body =
          '{"student_rollcalls":['
          '{"number_code":"1234"},{"number_code":"5678"}'
          ']}';
      final lookup = RollcallApi.parseNumberCode(body);
      expect(lookup.found, isFalse);
      expect(lookup.message, contains('多个'));
    });

    test('没有口令时给出可读原因', () {
      final lookup = RollcallApi.parseNumberCode('{"student_rollcalls":[]}');
      expect(lookup.found, isFalse);
      expect(lookup.message, contains('手动输入'));
    });

    test('非 JSON 不会崩', () {
      expect(RollcallApi.parseNumberCode('<html></html>').found, isFalse);
      expect(RollcallApi.parseNumberCode('').found, isFalse);
    });
  });

  group('RollcallApi.parseAttendance', () {
    const body =
        '{"student_rollcalls":['
        '{"user_no":"2023001","status":"on_call_fine"},'
        '{"user_no":"2023002","status":"absent"}'
        ']}';

    test('本人 on_call_fine 算已签到', () {
      expect(RollcallApi.parseAttendance(body, '2023001'), isTrue);
    });

    test('别人签到不算自己', () {
      expect(RollcallApi.parseAttendance(body, '2023002'), isFalse);
    });

    test('名单里没有自己返回 false', () {
      expect(RollcallApi.parseAttendance(body, '9999999'), isFalse);
    });

    test('响应看不懂返回 null', () {
      expect(RollcallApi.parseAttendance('<html></html>', '2023001'), isNull);
      expect(RollcallApi.parseAttendance(body, ''), isNull);
    });
  });

  group('RollcallApi.parseRoster（自动签到的过半闸门）', () {
    String rosterBody(List<String> statuses) =>
        '{"student_rollcalls":[${statuses.map((s) => '{"status":"$s"}').join(',')}]}';

    test('统计总人数与已签人数', () {
      final roster = RollcallApi.parseRoster(
        rosterBody(<String>[
          'on_call_fine',
          'on_call_fine',
          'absent',
          'absent',
        ]),
      )!;
      expect(roster.total, 4);
      expect(roster.signed, 2);
      // 正好一半不算「过半」
      expect(roster.isMajoritySigned, isFalse);
    });

    test('过半判定：3/4 算，2/3 算，1/3 不算', () {
      expect(
        RollcallApi.parseRoster(
          rosterBody(<String>['on_call_fine', 'late', 'present', 'absent']),
        )!.isMajoritySigned,
        isTrue,
      );
      expect(
        RollcallApi.parseRoster(
          rosterBody(<String>['on_call_fine', 'attended', 'absent']),
        )!.isMajoritySigned,
        isTrue,
      );
      expect(
        RollcallApi.parseRoster(
          rosterBody(<String>['on_call_fine', 'absent', 'absent']),
        )!.isMajoritySigned,
        isFalse,
      );
    });

    test('空名单不算过半，避免除零', () {
      final roster = RollcallApi.parseRoster(rosterBody(<String>[]))!;
      expect(roster.total, 0);
      expect(roster.isMajoritySigned, isFalse);
    });

    test('读人数时顺带把数字口令带出来', () {
      const body =
          '{"student_rollcalls":['
          '{"status":"on_call_fine","number_code":1234},'
          '{"status":"absent"}'
          ']}';
      final roster = RollcallApi.parseRoster(body)!;
      expect(roster.signed, 1);
      expect(roster.numberCode, '1234');
    });

    test('结构不认识返回 null（不能当成 0 人）', () {
      expect(RollcallApi.parseRoster('{}'), isNull);
      expect(RollcallApi.parseRoster('<html></html>'), isNull);
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

    test('401/403 提示重新登录，404 提示点名已结束', () {
      final unauth = RollcallApi.parseSignResult(401, '');
      expect(unauth.success, isFalse);
      expect(unauth.message, contains('重新登录'));

      final forbidden = RollcallApi.parseSignResult(403, '');
      expect(forbidden.message, contains('重新登录'));

      final gone = RollcallApi.parseSignResult(404, '');
      expect(gone.success, isFalse);
      expect(gone.message, contains('已结束'));
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
      expect(res.message, contains('蓝牙信标验证'));
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
