import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/http/api_client.dart';

/// 校园气象概况（专门供桌面小组件决策出行与雨具）
class WeatherSummary {
  const WeatherSummary({
    required this.hasRainOrSnow,
    required this.weatherStatus,
    required this.rainTimeWindow,
    required this.probabilityText,
    required this.umbrellaAdvice,
    required this.tempRange,
    required this.iconType,
    required this.updatedAt,
  });

  /// 是否有雨或雪
  final bool hasRainOrSnow;

  /// 天气基本状况（如 "阴转小雨"、"晴朗"、"多云"、"雷阵雨"）
  final String weatherStatus;

  /// 降雨/雪发生的时间窗口（如 "14:00~17:00 阵雨"、"夜间 19:00 起降雨"、"全天无雨"）
  final String rainTimeWindow;

  /// 降水概率或状态描述（如 "降雨概率 85%"、"全天干爽"）
  final String probabilityText;

  /// 伞具建议（如 "出门记得带伞 ☔"、"无需带伞 🌤"）
  final String umbrellaAdvice;

  /// 当日温度范围（如 "16° ~ 25°C"）
  final String tempRange;

  /// 图标类型: "rain" | "snow" | "cloudy" | "sunny"
  final String iconType;

  final DateTime updatedAt;

  /// 离线或默认兜底数据
  factory WeatherSummary.fallback() {
    return WeatherSummary(
      hasRainOrSnow: false,
      weatherStatus: '多云',
      rainTimeWindow: '暂无气象信息',
      probabilityText: '网络未连接',
      umbrellaAdvice: '适宜出行 🌤',
      tempRange: '--° ~ --°C',
      iconType: 'cloudy',
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'hasRainOrSnow': hasRainOrSnow,
        'weatherStatus': weatherStatus,
        'rainTimeWindow': rainTimeWindow,
        'probabilityText': probabilityText,
        'umbrellaAdvice': umbrellaAdvice,
        'tempRange': tempRange,
        'iconType': iconType,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

/// 上理军工路校区气象与降水预报服务 (基于 Open-Meteo 免费高精度开源气象 API)
class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  // 上理军工路 516 校区坐标 (纬度 31.2917, 经度 121.5517)
  static const double usstLat = 31.2917;
  static const double usstLon = 121.5517;

  WeatherSummary? _cachedSummary;
  DateTime? _lastFetchTime;

  /// 获取今日天气概况（带 30 分钟内存缓存）
  Future<WeatherSummary> getTodayWeather({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedSummary != null &&
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!).inMinutes < 30) {
      return _cachedSummary!;
    }

    try {
      final summary = await _fetchFromOpenMeteo();
      _cachedSummary = summary;
      _lastFetchTime = now;
      return summary;
    } catch (e, stack) {
      debugPrint('[WeatherService] 天气抓取失败: $e\n$stack');
      return _cachedSummary ?? WeatherSummary.fallback();
    }
  }

  Future<WeatherSummary> _fetchFromOpenMeteo() async {
    final url =
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$usstLat&longitude=$usstLon'
        '&hourly=temperature_2m,precipitation_probability,precipitation,weather_code'
        '&timezone=Asia%2FShanghai&forecast_days=1';

    final resp = await ApiClient.dio.get<Map<String, dynamic>>(url);
    final data = resp.data;
    if (data == null || data['hourly'] == null) {
      throw Exception('Open-Meteo 数据格式异常');
    }

    final hourly = data['hourly'] as Map<String, dynamic>;
    final times = List<String>.from(hourly['time'] as List);
    final temps = List<num>.from(hourly['temperature_2m'] as List);
    final precipProbs =
        List<num>.from(hourly['precipitation_probability'] as List);
    final precips = List<num>.from(hourly['precipitation'] as List);
    final codes = List<int>.from(hourly['weather_code'] as List);

    if (times.isEmpty) {
      return WeatherSummary.fallback();
    }

    // 1. 计算今日温差范围
    num minTemp = 100;
    num maxTemp = -100;
    for (final t in temps) {
      if (t < minTemp) minTemp = t;
      if (t > maxTemp) maxTemp = t;
    }
    final tempRange = '${minTemp.round()}° ~ ${maxTemp.round()}°C';

    // 2. 识别降水/下雪区间与最高概率
    // 聚焦日间活跃时段 (06:00 ~ 23:00)
    int maxProb = 0;
    double totalPrecip = 0.0;
    final rainHours = <int>[];
    bool isSnow = false;

    for (int i = 0; i < times.length; i++) {
      final hourStr = times[i]; // e.g. "2026-11-01T14:00"
      final parsed = DateTime.tryParse(hourStr);
      final hour = parsed?.hour ?? i;

      final prob = (precipProbs.length > i) ? precipProbs[i].toInt() : 0;
      final precip = (precips.length > i) ? precips[i].toDouble() : 0.0;
      final code = (codes.length > i) ? codes[i] : 0;

      if (prob > maxProb) maxProb = prob;
      totalPrecip += precip;

      final isRainCode = _isRainOrSnowCode(code);
      if (code == 71 || code == 73 || code == 75 || code == 77 || code == 85 || code == 86) {
        isSnow = true;
      }

      // 当降雨概率 >= 40% 或 降水量 >= 0.1mm 或 气象码为降水
      if (prob >= 40 || precip >= 0.1 || isRainCode) {
        rainHours.add(hour);
      }
    }

    final hasRainOrSnow = rainHours.isNotEmpty || maxProb >= 50 || totalPrecip >= 0.2;

    // 3. 构造降雨时间段文本与提醒
    String rainTimeWindow;
    String umbrellaAdvice;
    String probabilityText;
    String iconType;
    String weatherStatus;

    if (hasRainOrSnow) {
      iconType = isSnow ? 'snow' : 'rain';
      weatherStatus = isSnow ? '有降雪' : (maxProb > 70 ? '有降雨' : '可能有阵雨');
      probabilityText = '降水概率 $maxProb%';
      umbrellaAdvice = isSnow ? '出门防寒带伞 ❄️' : '出门记得带伞 ☔';

      if (rainHours.isNotEmpty) {
        // 合并连续时间段
        final ranges = _groupContinuousHours(rainHours);
        final firstRange = ranges.first;
        final typeName = isSnow ? '降雪' : '降雨';
        rainTimeWindow = '${firstRange.start}:00~${firstRange.end + 1}:00 $typeName';
        if (ranges.length > 1) {
          rainTimeWindow += '等';
        }
      } else {
        rainTimeWindow = isSnow ? '今日有零星降雪' : '今日局部零星小雨';
      }
    } else {
      // 无降水
      final midDayCode = codes.length > 12 ? codes[12] : (codes.isNotEmpty ? codes.first : 0);
      if (midDayCode == 0) {
        iconType = 'sunny';
        weatherStatus = '晴天';
      } else {
        iconType = 'cloudy';
        weatherStatus = '多云';
      }
      rainTimeWindow = '今日全天无雨';
      probabilityText = maxProb > 0 ? '降水概率 $maxProb%' : '全天干爽';
      umbrellaAdvice = '无需带伞 🌤';
    }

    return WeatherSummary(
      hasRainOrSnow: hasRainOrSnow,
      weatherStatus: weatherStatus,
      rainTimeWindow: rainTimeWindow,
      probabilityText: probabilityText,
      umbrellaAdvice: umbrellaAdvice,
      tempRange: tempRange,
      iconType: iconType,
      updatedAt: DateTime.now(),
    );
  }

  static bool _isRainOrSnowCode(int code) {
    // 51~67: 雨/冻雨; 71~77: 雪; 80~82: 阵雨; 85~86: 阵雪; 95~99: 雷雨/冰雹
    return (code >= 51 && code <= 67) ||
        (code >= 71 && code <= 86) ||
        (code >= 95 && code <= 99);
  }

  static List<({int start, int end})> _groupContinuousHours(List<int> hours) {
    final sorted = hours.toSet().toList()..sort();
    final result = <({int start, int end})>[];
    if (sorted.isEmpty) return result;

    int curStart = sorted.first;
    int curEnd = sorted.first;

    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i] == curEnd + 1) {
        curEnd = sorted[i];
      } else {
        result.add((start: curStart, end: curEnd));
        curStart = sorted[i];
        curEnd = sorted[i];
      }
    }
    result.add((start: curStart, end: curEnd));
    return result;
  }
}
