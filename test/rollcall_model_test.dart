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

    test('解析雷达点名的教师基准点 / 教室 / 范围', () {
      const raw =
          '{"rollcalls": [{'
          '"id": 9, "course_title": "大学物理", "is_radar": true,'
          '"classroom": "三教101", "scope": 50,'
          '"latitude": 31.294512, "longitude": "121.555612"'
          '}]}';
      final rollcall = RollcallApi.parseOngoing(raw).single;
      expect(rollcall.isRadarRollcall, isTrue);
      expect(rollcall.classroom, '三教101');
      expect(rollcall.scope, 50);
      expect(rollcall.latitude, closeTo(31.294512, 1e-9));
      expect(rollcall.longitude, closeTo(121.555612, 1e-9));
      expect(rollcall.hasTeacherReference, isTrue);
    });

    test('没下发坐标时 hasTeacherReference 为 false', () {
      const raw =
          '{"rollcalls": [{"id": 10, "is_radar": true, "latitude": 0, "longitude": 0}]}';
      final rollcall = RollcallApi.parseOngoing(raw).single;
      expect(rollcall.latitude, 0);
      expect(rollcall.hasTeacherReference, isFalse);
    });

    test('雷达字段能往返本地缓存', () {
      const raw =
          '{"rollcalls": [{'
          '"id": 11, "is_radar": true, "classroom": "四教205", "scope": 30,'
          '"latitude": 31.286636, "longitude": 121.557302'
          '}]}';
      final rollcall = RollcallApi.parseOngoing(raw).single;
      final restored = Rollcall.fromCacheJson(rollcall.toCacheJson())!;
      expect(restored.classroom, '四教205');
      expect(restored.scope, 30);
      expect(restored.latitude, closeTo(31.286636, 1e-9));
      expect(restored.longitude, closeTo(121.557302, 1e-9));
    });

    test('自主签到：布尔标记或 type 都能认出来', () {
      const raw =
          '{"rollcalls": ['
          '{"id": 1, "is_self_registration": true},'
          '{"id": 2, "type": "self_registration"}'
          ']}';
      final list = RollcallApi.parseOngoing(raw);
      expect(list[0].isSelfRollcall, isTrue);
      expect(list[0].typeLabel, '自主签到');
      expect(list[1].isSelfRollcall, isTrue);
      expect(list[1].isNumberRollcall, isFalse);
      expect(list[1].isRadarRollcall, isFalse);
    });

    test('自主签名的标记能往返本地缓存', () {
      const raw = '{"rollcalls": [{"id": 3, "is_self_registration": true}]}';
      final rollcall = RollcallApi.parseOngoing(raw).single;
      final restored = Rollcall.fromCacheJson(rollcall.toCacheJson())!;
      expect(restored.isSelfRollcall, isTrue);
    });

    test('UTC 时间（带 Z）显示成本地时间', () {
      const raw =
          '{"rollcalls":[{"id": 1, "created_at": "2026-10-23T02:30:00Z"}]}';
      final local = DateTime.parse('2026-10-23T02:30:00Z').toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      final list = RollcallApi.parseOngoing(raw);
      expect(list.single.timeText, '${two(local.hour)}:${two(local.minute)}');
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
}
