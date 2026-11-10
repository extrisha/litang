/// Parse once against the fetch time; persist the resulting absolute deadline.
class TaskDeadline {
  static DateTime? parse(
    String raw, {
    DateTime? now,
    bool allowRelative = true,
  }) {
    final current = now ?? DateTime.now();
    var s = raw
        .replaceAll(RegExp(r'^(?:提交)?截[止至](?:时间)?[:：]\s*'), '')
        .replaceAll(RegExp(r'^有效时间[:：]\s*'), '')
        .replaceAll('/', '-')
        .replaceAll('.', '-')
        .trim();
    if (s.isEmpty) return null;
    if (!allowRelative && !RegExp(r'^\d{4}[-年]').hasMatch(s)) return null;
    final direct = DateTime.tryParse(s);
    if (direct != null) {
      // 纯日期（2026-03-05）要按当天 23:59 算，否则截止日当天 00:01 就被判
      // 「已逾期」。带时间的写法（含 T 或 HH:mm）保持不变。
      final hasTime = s.contains('T') || RegExp(r'\d{1,2}:\d{2}').hasMatch(s);
      if (hasTime) return direct;
      return DateTime(direct.year, direct.month, direct.day, 23, 59);
    }

    // YYYY年MM月DD日 [HH:mm]
    final ymdCn = RegExp(
      r'^(\d{4})年(\d{1,2})月(\d{1,2})日(?:\s+(\d{1,2}):(\d{2}))?',
    ).firstMatch(s);
    if (ymdCn != null) {
      final y = int.parse(ymdCn.group(1)!);
      final m = int.parse(ymdCn.group(2)!);
      final d = int.parse(ymdCn.group(3)!);
      final h = ymdCn.group(4) != null ? int.parse(ymdCn.group(4)!) : 23;
      final min = ymdCn.group(5) != null ? int.parse(ymdCn.group(5)!) : 59;
      return DateTime(y, m, d, h, min);
    }

    // MM月DD日 [HH:mm]
    final mdCn = RegExp(r'^(\d{1,2})月(\d{1,2})日(?:\s+(\d{1,2}):(\d{2}))?')
        .firstMatch(s);
    if (mdCn != null) {
      final m = int.parse(mdCn.group(1)!);
      final d = int.parse(mdCn.group(2)!);
      final h = mdCn.group(3) != null ? int.parse(mdCn.group(3)!) : 23;
      final min = mdCn.group(4) != null ? int.parse(mdCn.group(4)!) : 59;
      return _withYearRollover(current, m, d, h, min);
    }

    // YYYY-MM-DD [HH:mm]
    final ymd = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{2}))?')
        .firstMatch(s);
    if (ymd != null) {
      final y = int.parse(ymd.group(1)!);
      final m = int.parse(ymd.group(2)!);
      final d = int.parse(ymd.group(3)!);
      final h = ymd.group(4) != null ? int.parse(ymd.group(4)!) : 23;
      final min = ymd.group(5) != null ? int.parse(ymd.group(5)!) : 59;
      return DateTime(y, m, d, h, min);
    }

    // MM-DD [HH:mm]
    final md = RegExp(r'^(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{2}))?')
        .firstMatch(s);
    if (md != null) {
      final m = int.parse(md.group(1)!);
      final d = int.parse(md.group(2)!);
      final h = md.group(3) != null ? int.parse(md.group(3)!) : 23;
      final min = md.group(4) != null ? int.parse(md.group(4)!) : 59;
      return _withYearRollover(current, m, d, h, min);
    }

    final dur = parseRemaining(s);
    if (dur != null) {
      return current.add(dur);
    }
    return null;
  }

  /// 只有「月日」时按最近的一次理解：12 月看到「1月5日」是明年 1 月 5 日，
  /// 而不是今年已经过去的那个 1 月 5 日（否则会被判成「已逾期」标红）。
  ///
  /// 只回卷过去超过 30 天的日期：上个月的截止时间大概率是真的过期了，
  /// 盲目 +1 年会让早已截止的作业重新变成「还有 300 天」。
  static DateTime _withYearRollover(
    DateTime current,
    int month,
    int day,
    int hour,
    int minute,
  ) {
    final thisYear = DateTime(current.year, month, day, hour, minute);
    if (current.difference(thisYear) > const Duration(days: 30)) {
      return DateTime(current.year + 1, month, day, hour, minute);
    }
    return thisYear;
  }

  static Duration? parseRemaining(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final day = RegExp(r'(\d+)\s*天').firstMatch(text);
    final hour = RegExp(r'(\d+)\s*小时').firstMatch(text);
    final minute = RegExp(r'(\d+)\s*分钟').firstMatch(text);
    if (day == null && hour == null && minute == null) return null;
    final days = int.tryParse(day?.group(1) ?? '') ?? 0;
    final hours = int.tryParse(hour?.group(1) ?? '') ?? 0;
    final minutes = int.tryParse(minute?.group(1) ?? '') ?? 0;
    return Duration(days: days, hours: hours, minutes: minutes);
  }
}
