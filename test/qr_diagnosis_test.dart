import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/lms/qr_diagnosis.dart';

void main() {
  // 2026-11-12 14:23:06（UTC+8）教室实拍解出来的真实载荷。
  const realPayload =
      '/j?p=0~34rk!3~17944645864b8bd8fc375fec72aa4f9238b255d4bb!4~fvpb';
  final capturedAt = DateTime.fromMillisecondsSinceEpoch(1794464586 * 1000);

  group('QrSample.analyze', () {
    test('真实载荷：渠道 id、时间戳、校验段都对得上', () {
      final sample = QrSample.analyze(realPayload, capturedAt);
      expect(sample.kind, 'URL');
      expect(sample.courseId, 146144);
      expect(sample.rollcallId, 740927);
      expect(sample.data, '17944645864b8bd8fc375fec72aa4f9238b255d4bb');
      expect(sample.data!.length, 42);
      expect(sample.ts, 1794464586);
      expect(sample.hash, '4b8bd8fc375fec72aa4f9238b255d4bb');
      // 同一秒扫描 → 时间差 0，不报异常
      expect(sample.ageSeconds, 0);
      expect(sample.notes, isEmpty);
    });

    test('落后设备时钟会算成「二维码比本机慢」', () {
      final sample = QrSample.analyze(
        realPayload,
        capturedAt.add(const Duration(seconds: 90)),
      );
      expect(sample.ageSeconds, 90);
      final rows = sample.rows();
      final clock = rows.firstWhere((row) => row.$1 == '与设备时钟');
      expect(clock.$2, contains('慢 90s'));
      expect(clock.$3, isFalse); // 120 秒以内不算异常
    });

    test('相邻两枚给出 Δts 与 Δ扫码', () {
      final first = QrSample.analyze(realPayload, capturedAt);
      final second = QrSample.analyze(
        '/j?p=0~34rk!3~1794464511a084d0a0ca90e2553c8b291383ebe014!4~fvpb',
        capturedAt.subtract(const Duration(seconds: 75)),
      );
      final rows = second.rows(previous: first);
      final delta = rows.firstWhere((row) => row.$1 == '与上一枚');
      expect(delta.$2, contains('Δts=-75s'));
      expect(delta.$2, contains('Δ扫码=-75.0s'));
    });

    test('长度不对会给出提示并标红', () {
      final sample = QrSample.analyze(
        'https://1906.usst.edu.cn/j?p=3~1794464586abc',
        capturedAt,
      );
      expect(sample.data!.length, lessThan(42));
      expect(
        sample.notes.any((note) => note.contains('长度')),
        isTrue,
      );
      final rows = sample.rows();
      final dataRow = rows.firstWhere((row) => row.$1 == 'data');
      expect(dataRow.$3, isTrue);
    });

    test('前 10 位不是数字时不解析成时间戳', () {
      final sample = QrSample.analyze(
        '/j?p=3~abcdefghij0123456789abcdef0123456789!4~fvpb',
        capturedAt,
      );
      expect(sample.ts, isNull);
      expect(sample.notes.any((note) => note.contains('unix 秒')), isTrue);
    });

    test('控制字符会被识别为官方紧凑编码', () {
      final sample = QrSample.analyze(
        '\u00104~1x!3~tok!0~2y',
        capturedAt,
      );
      expect(sample.kind, '紧凑载荷');
      expect(
        sample.notes.any((note) => note.contains('控制字符')),
        isTrue,
      );
    });

    test('裸 token 也能诊断', () {
      final sample = QrSample.analyze(
        '17944645864b8bd8fc375fec72aa4f9238b255d4bb',
        capturedAt,
      );
      expect(sample.kind, '裸 token');
      expect(sample.ts, 1794464586);
      expect(sample.data!.length, 42);
    });

    test('无法解析的文本不会抛异常', () {
      final sample = QrSample.analyze('随便一段文字', capturedAt);
      expect(sample.kind, '未知');
      expect(sample.notes, isNotEmpty);
      expect(sample.rows(), isNotEmpty);
    });

    test('JSON 往返保留关键字段', () {
      final sample = QrSample.analyze(realPayload, capturedAt);
      final restored = QrSample.fromJson(sample.toJson());
      expect(restored, isNotNull);
      expect(restored!.rollcallId, sample.rollcallId);
      expect(restored.courseId, sample.courseId);
      expect(restored.ts, sample.ts);
      expect(restored.data, sample.data);
      expect(restored.scannedAt, sample.scannedAt);
    });

    test('rows 永远带格式与 data 两行', () {
      final sample = QrSample.analyze(realPayload, capturedAt);
      final labels = sample.rows().map((row) => row.$1).toList();
      expect(labels, contains('格式'));
      expect(labels, contains('data'));
      expect(labels, contains('rollcallId'));
    });
  });
}
