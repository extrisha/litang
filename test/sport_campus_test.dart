import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/app_exception.dart';
import 'package:project_usst/data/auth/sport_campus_store.dart';
import 'package:project_usst/services/sport_campus_service.dart';

/// 高校体育（校园跑）这层最容易坏在两处：
///   1. 签名规则（协议是社区逆向的，厂商一改就全挂）
///   2. 字段解析（goal/surplus 可能是字符串，也可能缺字段）
/// 所以这两块必须有测试兜住。
void main() {
  group('签名', () {
    test('紧凑 JSON 不带空格', () {
      final json = SportCampusService.compactJson(<String, dynamic>{
        'mobile': '13800000000',
        'password': 'pass',
      });
      expect(json, '{"mobile":"13800000000","password":"pass"}');
    });

    test('md5(prefix + data + payload) 与固定向量一致', () {
      const payload =
          '{"info":"00000000-0000-4000-8000-000000000000",'
          '"mobile":"13800000000","password":"pass","type":"iPhone 11"}';
      // 用 Python 的 hashlib.md5 独立算出来的，防止「改了实现还自洽」
      expect(
        SportCampusService.signOf(payload),
        '4b1d59956fd1304d67a8e2b232a71ca6',
      );
    });

    test('payload 变了签名必须变', () {
      expect(
        SportCampusService.signOf('{"a":"1"}'),
        isNot(SportCampusService.signOf('{"a":"2"}')),
      );
    });
  });

  group('解析登录响应', () {
    test('正常响应：goal/surplus 是字符串', () {
      final progress = SportCampusProgress.parse(<String, dynamic>{
        'username': '陈宇喆',
        'school': '上海理工大学',
        'teacher': '王老师',
        'course': '羽毛球',
        'goal': '30',
        'surplus': '18',
        'userid': '123',
        'utoken': 'abc',
      });
      expect(progress, isNotNull);
      expect(progress!.goal, 30);
      expect(progress.surplus, 18);
      expect(progress.done, 12);
      expect(progress.ratio, closeTo(0.4, 1e-9));
      expect(progress.finished, isFalse);
      expect(progress.school, '上海理工大学');
    });

    test('数字类型也能解析', () {
      final progress = SportCampusProgress.parse(<String, dynamic>{
        'goal': 40,
        'surplus': 0,
      });
      expect(progress!.goal, 40);
      expect(progress.done, 40);
      expect(progress.finished, isTrue);
      expect(progress.ratio, 1.0);
    });

    test('缺 goal/surplus 时返回 null（交给调用方报错）', () {
      expect(SportCampusProgress.parse(<String, dynamic>{}), isNull);
      expect(
        SportCampusProgress.parse(<String, dynamic>{'username': '张三'}),
        isNull,
      );
    });

    test('surplus 大于 goal（学校手工调整过）不会算出负数', () {
      final progress = SportCampusProgress.parse(<String, dynamic>{
        'goal': '10',
        'surplus': '12',
      });
      expect(progress!.done, 0);
      expect(progress.ratio, 0.0);
    });

    test('goal 为 0 时不算完成度，避免除零', () {
      final progress = SportCampusProgress.parse(<String, dynamic>{
        'goal': '0',
        'surplus': '0',
      });
      expect(progress!.ratio, isNull);
      expect(progress.done, isNull);
      expect(progress.finished, isTrue);
    });
  });

  group('缓存序列化', () {
    test('往返一致', () {
      final progress = SportCampusProgress.parse(<String, dynamic>{
        'username': '陈宇喆',
        'school': '上海理工大学',
        'teacher': '王老师',
        'course': '羽毛球',
        'goal': '30',
        'surplus': '18',
      })!;
      final restored = SportCampusProgress.fromCacheJson(
        progress.toCacheJson(),
      );
      expect(restored, isNotNull);
      expect(restored!.goal, 30);
      expect(restored.surplus, 18);
      expect(restored.teacher, '王老师');
    });

    test('旧缓存缺字段时返回 null，不会崩', () {
      expect(SportCampusProgress.fromCacheJson(<String, dynamic>{}), isNull);
    });
  });

  group('凭据存储编解码', () {
    SportCampusCredentials roundTrip(SportCampusCredentials credentials) =>
        SportCampusStore.decode(
          jsonDecode(SportCampusStore.encode(credentials))
              as Map<String, dynamic>,
        );

    test('手机号 / 密码 / 设备指纹往返一致', () {
      final restored = roundTrip(
        SportCampusCredentials(
          mobile: '13800000000',
          password: 'secret',
          deviceId: 'AAAA-BBBB',
          savedAt: DateTime(2026, 11, 4, 12, 30),
        ),
      );
      expect(restored.mobile, '13800000000');
      expect(restored.password, 'secret');
      expect(restored.deviceId, 'AAAA-BBBB');
      expect(restored.savedAt, DateTime(2026, 11, 4, 12, 30));
      expect(restored.canAutoLogin, isTrue);
    });

    test('没勾记住密码时不落盘密码，但手机号与设备指纹仍保留', () {
      final restored = roundTrip(
        SportCampusCredentials(
          mobile: '13800000000',
          deviceId: 'AAAA-BBBB',
          savedAt: DateTime(2026, 11, 4),
        ),
      );
      expect(restored.password, isNull);
      expect(restored.canAutoLogin, isFalse);
      expect(restored.mobile, '13800000000');
      expect(restored.deviceId, 'AAAA-BBBB');
    });

    test('空 map 也能容忍，不抛异常', () {
      final restored = SportCampusStore.decode(<String, dynamic>{});
      expect(restored.mobile, '');
      expect(restored.canAutoLogin, isFalse);
    });
  });

  group('异常契约', () {
    test('SportCampusException 是 AppException，页面能统一 catch', () {
      const e = SportCampusException(AppFailure.auth, '手机号没注册');
      expect(e, isA<AppException>());
      expect(e.needsRelogin, isTrue);
      expect(e.message, '手机号没注册');
    });
  });
}
