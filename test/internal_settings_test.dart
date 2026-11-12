import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/internal/internal_settings.dart';
import 'package:project_usst/data/lms/radar_target.dart';

void main() {
  test('默认值：内部模式关、演练开、自动取点', () {
    const settings = InternalSettings();
    expect(settings.enabled, isFalse);
    expect(settings.monitor, isFalse);
    expect(settings.autoSign, isFalse);
    expect(settings.dryRun, isTrue);
    expect(settings.intervalSeconds, 20);
    expect(settings.radarMode, RadarLocationMode.auto);
    expect(settings.submitsInsteadOfNotify, isFalse);
  });

  test('默认等签到人数过半，且能关掉', () {
    const settings = InternalSettings();
    expect(settings.waitForMajority, isTrue);
    expect(settings.copyWith(waitForMajority: false).waitForMajority, isFalse);
    final restored = InternalSettings.fromJson(
      settings.copyWith(waitForMajority: false).toJson(),
    );
    expect(restored.waitForMajority, isFalse);
  });

  test('JSON 往返不丢字段', () {
    const original = InternalSettings(
      enabled: true,
      monitor: true,
      autoSign: true,
      autoNumber: true,
      dryRun: false,
      notify: false,
      intervalSeconds: 60,
      radarMode: RadarLocationMode.building,
      buildingId: 'b_516_3j_e',
    );
    final restored = InternalSettings.fromJson(original.toJson());
    expect(restored, original);
  });

  test('非法值回退到默认', () {
    final settings = InternalSettings.fromJson(<String, dynamic>{
      'intervalSeconds': 7,
      'radarMode': 'not-a-mode',
      'buildingId': 'not-a-building',
    });
    expect(settings.intervalSeconds, 20);
    expect(settings.radarMode, RadarLocationMode.auto);
    expect(settings.buildingId, isNull);
  });

  test('buildingId 能解析成教学楼', () {
    final settings = InternalSettings.fromJson(<String, dynamic>{
      'buildingId': 'b_516_3j_e',
    });
    expect(settings.building?.name, '三教');
    expect(settings.building?.campus, '本部北校区');
  });

  test('只有「开了自动签到且不是演练」才真的提交', () {
    const settings = InternalSettings(enabled: true, autoSign: true);
    expect(settings.submitsInsteadOfNotify, isFalse);
    expect(settings.copyWith(dryRun: false).submitsInsteadOfNotify, isTrue);
    expect(
      settings.copyWith(dryRun: false, enabled: false).submitsInsteadOfNotify,
      isFalse,
    );
    expect(
      settings.copyWith(dryRun: false, autoSign: false).submitsInsteadOfNotify,
      isFalse,
    );
  });

  test('数字口令默认不自动提交，单开也不越过演练', () {
    const settings = InternalSettings(enabled: true, autoSign: true);
    expect(settings.autoNumber, isFalse);
    expect(settings.submitsNumberInsteadOfNotify, isFalse);

    final numberOn = settings.copyWith(autoNumber: true);
    expect(numberOn.submitsNumberInsteadOfNotify, isFalse);
    expect(
      numberOn.copyWith(dryRun: false).submitsNumberInsteadOfNotify,
      isTrue,
    );
    expect(
      numberOn
          .copyWith(dryRun: false, autoSign: false)
          .submitsNumberInsteadOfNotify,
      isFalse,
    );
  });

  test('copyWith 能清空 buildingId，也能保持其它字段', () {
    const settings = InternalSettings(buildingId: 'b_516_3j_e');
    expect(settings.copyWith(buildingId: null).buildingId, isNull);
    expect(settings.copyWith(monitor: true).buildingId, 'b_516_3j_e');
  });

  test('关闭内部模式同时停监控和自动签到', () {
    const settings = InternalSettings(
      enabled: true,
      monitor: true,
      autoSign: true,
    );
    final off = settings.copyWith(
      enabled: false,
      monitor: false,
      autoSign: false,
    );
    expect(off.enabled, isFalse);
    expect(off.monitor, isFalse);
    expect(off.autoSign, isFalse);
  });

  test('间隔只允许白名单里的值', () {
    expect(InternalSettings.allowedIntervals, <int>[10, 20, 30, 60]);
  });
}
