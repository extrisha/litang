import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/services/weather_service.dart';

/// 构造一天 24 小时的逐小时数据；[codesByHour] / [probsByHour] 只覆盖需要的那几小时。
WeatherSummary summarize({
  required int nowHour,
  Map<int, int> codesByHour = const <int, int>{},
  Map<int, int> probsByHour = const <int, int>{},
  Map<int, int> precipByHour = const <int, int>{},
}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final times = <String>[
    for (var h = 0; h < 24; h++) '2026-11-12T${two(h)}:00',
  ];
  return WeatherService.summarize(
    times: times,
    temps: List<num>.generate(24, (h) => 10 + (h % 10)),
    precipProbs: List<num>.generate(24, (h) => probsByHour[h] ?? 0),
    precips: List<num>.generate(24, (h) => precipByHour[h] ?? 0),
    codes: List<int>.generate(24, (h) => codesByHour[h] ?? 0),
    now: DateTime(2026, 11, 12, nowHour),
  );
}

void main() {
  group('小组件带伞提示', () {
    test('当前正在下雨：短提示 + 时间行给出结束时间', () {
      final summary = summarize(
        nowHour: 10,
        codesByHour: <int, int>{10: 61, 11: 61},
        probsByHour: <int, int>{10: 85, 11: 80},
      );
      expect(summary.hasRainOrSnow, isTrue);
      expect(summary.umbrellaAdvice, '出门带伞 ☔');
      expect(summary.rainTimeWindow, '正在降雨 · 至 12:00');
      // 两行不能再说同一句话
      expect(summary.rainTimeWindow.contains('带伞'), isFalse);
      expect(summary.umbrellaAdvice.contains('正在'), isFalse);
    });

    test('稍后有雨：提示“稍后带伞”，并给出时间段', () {
      final summary = summarize(
        nowHour: 10,
        codesByHour: <int, int>{15: 61},
        probsByHour: <int, int>{15: 80},
      );
      expect(summary.hasRainOrSnow, isTrue);
      expect(summary.umbrellaAdvice, '稍后带伞 🌂');
      expect(summary.rainTimeWindow, '15:00 起降雨');
    });

    test('早间下过、之后没雨：不提示带伞', () {
      final summary = summarize(
        nowHour: 10,
        codesByHour: <int, int>{8: 61},
        probsByHour: <int, int>{8: 90},
      );
      expect(summary.hasRainOrSnow, isFalse);
      expect(summary.umbrellaAdvice, isEmpty);
      expect(summary.rainTimeWindow, '今日后续无雨');
    });

    test('全天无雨：不提示带伞', () {
      final summary = summarize(nowHour: 10);
      expect(summary.hasRainOrSnow, isFalse);
      expect(summary.umbrellaAdvice, isEmpty);
      expect(summary.iconType, 'sunny');
    });

    test('降雪：提示里带雪花而不是雨伞', () {
      final summary = summarize(
        nowHour: 10,
        codesByHour: <int, int>{15: 71},
        probsByHour: <int, int>{15: 80},
      );
      expect(summary.iconType, 'snow');
      expect(summary.umbrellaAdvice, contains('❄️'));
      expect(summary.rainTimeWindow, contains('降雪'));
    });

    test('降水概率达到阈值也算（不要求气象码）', () {
      final summary = summarize(nowHour: 10, probsByHour: <int, int>{16: 45});
      expect(summary.hasRainOrSnow, isTrue);
      expect(summary.umbrellaAdvice, '稍后带伞 🌂');
    });

    test('提示文案保持短：不超过小组件胶囊宽度', () {
      for (final summary in <WeatherSummary>[
        summarize(
          nowHour: 10,
          codesByHour: <int, int>{10: 61},
          probsByHour: <int, int>{10: 80},
        ),
        summarize(
          nowHour: 10,
          codesByHour: <int, int>{15: 61},
          probsByHour: <int, int>{15: 80},
        ),
        summarize(nowHour: 10),
      ]) {
        expect(summary.umbrellaAdvice.length, lessThanOrEqualTo(8));
      }
    });
  });

  group('Open-Meteo 响应解析', () {
    test('precipitation_probability 里的 null 不会让整次抓取失败', () {
      // 上海一带这个字段经常是 null，以前会抛
      // type 'Null' is not a subtype of type 'num'
      final summary = WeatherService.parseOpenMeteo(<String, dynamic>{
        'hourly': <String, dynamic>{
          'time': <String>[
            for (var h = 0; h < 24; h++)
              '2026-11-12T${h.toString().padLeft(2, '0')}:00',
          ],
          'temperature_2m': <dynamic>[for (var h = 0; h < 24; h++) 10 + h % 5],
          'precipitation_probability': <dynamic>[
            for (var h = 0; h < 24; h++) null,
          ],
          'precipitation': <dynamic>[for (var h = 0; h < 24; h++) null],
          'weather_code': <dynamic>[for (var h = 0; h < 24; h++) 0],
        },
      });
      expect(summary.isFallback, isFalse);
      expect(summary.tempRange, contains('°'));
      expect(summary.rainTimeWindow, isNotEmpty);
    });

    test('逐小时数据为空时抛错，让调用方保留上一次的天气', () {
      expect(
        () => WeatherService.parseOpenMeteo(<String, dynamic>{
          'hourly': <String, dynamic>{
            'time': <String>[],
            'temperature_2m': <num>[],
          },
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('缺少 hourly 字段时抛错', () {
      expect(
        () => WeatherService.parseOpenMeteo(<String, dynamic>{}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
