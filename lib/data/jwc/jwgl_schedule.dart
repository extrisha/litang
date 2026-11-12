/// 上理 13 节课表作息（2026-2027 学期，用户提供的教务处时刻）。
///
/// 每节 40 分钟，小课间 5 分钟，大课间 20 分钟。
/// 上午 1-5 节、下午 6-10 节、晚上 11-13 节。
class JwglSchedule {
  const JwglSchedule._();

  static const int periodCount = 13;

  /// 每节的起止时间（period 从 1 开始）。
  static const List<({int period, String start, String end})> periods =
      <({int period, String start, String end})>[
        (period: 1, start: '08:00', end: '08:40'),
        (period: 2, start: '08:45', end: '09:25'),
        (period: 3, start: '09:45', end: '10:25'),
        (period: 4, start: '10:30', end: '11:10'),
        (period: 5, start: '11:15', end: '11:55'),
        (period: 6, start: '13:00', end: '13:40'),
        (period: 7, start: '13:45', end: '14:25'),
        (period: 8, start: '14:45', end: '15:25'),
        (period: 9, start: '15:30', end: '16:10'),
        (period: 10, start: '16:15', end: '16:55'),
        (period: 11, start: '18:00', end: '18:40'),
        (period: 12, start: '18:45', end: '19:25'),
        (period: 13, start: '19:30', end: '20:10'),
      ];

  /// 给 Android 小组件用的作息数组（`semester_period_times_json` 的内容）。
  ///
  /// 原生层只认这个格式（`HH:mm-HH:mm`，13 条），改作息只改本文件的 [periods]，
  /// 不要再去 `TodayScheduleWidgetProvider.kt` 里维护第二份。
  static List<String> get periodStrings => <String>[
    for (final p in periods) '${p.start}-${p.end}',
  ];

  static ({int period, String start, String end})? periodAt(int period) {
    for (final p in periods) {
      if (p.period == period) {
        return p;
      }
    }
    return null;
  }

  /// 某节的完整时间区间，如 "08:00-08:40"。
  static String? timeOfPeriod(int period) {
    final p = periodAt(period);
    return p == null ? null : '${p.start}-${p.end}';
  }

  /// 第 start 节起、连续 span 节的时间区间文本（start 从 0 开始，与 Course 一致）。
  static String? rangeOf(int start, int span) {
    final from = periodAt(start + 1);
    final to = periodAt(start + span.clamp(1, periodCount));
    if (from == null || to == null) {
      return null;
    }
    return '${from.start}-${to.end}';
  }

  /// 时段名称：上午 / 下午 / 晚上。
  static String sessionOf(int period) {
    if (period <= 5) {
      return '上午';
    }
    if (period <= 10) {
      return '下午';
    }
    return '晚上';
  }
}

/// 解析正方课表的周次文本，如：
/// "3-18周"、"1-2周"、"6-9周,14-17周"、"1-16周(单)"、"2-16周(双)"。
/// 解析不到返回 null（视为每周都上）。
List<int>? parseCourseWeeks(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  final weeks = <int>{};
  for (final part in text.split(RegExp(r'[，,;、]'))) {
    final match = RegExp(r'(\d+)\s*(?:-\s*(\d+))?').firstMatch(part);
    if (match == null) {
      continue;
    }
    final from = int.parse(match.group(1)!);
    final to = int.tryParse(match.group(2) ?? '') ?? from;
    for (var w = from; w <= to && w <= 30; w++) {
      weeks.add(w);
    }
  }
  if (text.contains('单') && !text.contains('双')) {
    weeks.removeWhere((w) => w.isEven);
  } else if (text.contains('双') && !text.contains('单')) {
    weeks.removeWhere((w) => w.isOdd);
  }
  if (weeks.isEmpty) {
    return null;
  }
  return weeks.toList()..sort();
}
