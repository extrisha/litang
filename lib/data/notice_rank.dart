import 'models.dart';

/// 通知排序：把 7000+ 条通知排成"学生最该先看到"的顺序。
///
/// 不是简单按时间倒序 —— 那样竞赛通知会被海量学院新闻淹没；
/// 也不是简单按分类权重 —— 那样一个月前的通知会压过今天的。
///
/// 打分 = 分类权重 + 新鲜度衰减 + 本院加成 + 校级加成
class NoticeRanker {
  const NoticeRanker._();

  /// 分类基础分（和 tools/notice-sync/build-sources.mjs 里的权重保持一致）
  static const Map<String, double> kindScore = <String, double>{
    '竞赛': 9.5,
    '教学': 9.0,
    '通知': 8.8,
    '讲座': 8.5,
    '学工': 8.0,
    '就业': 7.5,
    '科研': 6.0,
    '招生': 5.5,
    '新闻': 4.5,
    '党群': 2.5,
  };

  /// 不属于"通知流"的分类：默认不显示，用「新闻」这个筛选项才看得到党群。
  static const Set<String> offFeedKinds = <String>{'新闻', '党群'};

  static double score(Notice n, {String? college, DateTime? now}) {
    final at = now ?? DateTime.now();
    var s = kindScore[n.kind] ?? 6.0;

    final date = n.publishedAt;
    if (date == null) {
      s -= 4; // 没日期的不该霸屏
    } else {
      final days = at.difference(date).inHours / 24.0;
      // 今天 12 分，三天前 6 分，一周前 3.6 分，一个月前 1.1 分
      final age = days < 0 ? 0.0 : days;
      s += 12 / (1 + age / 3);
    }

    // 本院优先：同学院的通知 +2.5
    if (college != null && college.isNotEmpty && n.dept == college) s += 2.5;
    // 校级通知普遍更通用
    if (n.scope == 'school') s += 0.5;

    return s;
  }

  /// 筛选 + 排序。[kind] 为 null / '全部' 表示全部（但仍然排除新闻/党群）。
  static List<Notice> rank(
    List<Notice> all, {
    String? college,
    String? filterCollege,
    String? kind,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    Iterable<Notice> list = all;
    if (filterCollege != null && filterCollege.isNotEmpty) {
      list = list.where((n) => n.dept == filterCollege);
    }
    if (kind == null || kind == '全部') {
      list = list.where((n) => !offFeedKinds.contains(n.kind));
    } else if (kind == '新闻') {
      list = list.where((n) => n.kind == '新闻' || n.kind == '党群');
    } else {
      list = list.where((n) => n.kind == kind);
    }

    final out = list.toList();
    out.sort((a, b) {
      final d = score(b, college: college, now: at)
          .compareTo(score(a, college: college, now: at));
      if (d != 0) return d;
      return b.title.compareTo(a.title);
    });
    return out;
  }

  /// 数据里出现过的分类，按权重排（给筛选栏用）。
  static List<String> kindsIn(Iterable<Notice> all) {
    final present = <String>{for (final n in all) n.kind};
    const order = <String>[
      '竞赛',
      '教学',
      '通知',
      '讲座',
      '学工',
      '就业',
      '科研',
      '招生',
      '新闻',
    ];
    final out = <String>[
      for (final k in order)
        if (present.contains(k)) k,
      // 云端将来加了新分类也不会漏
      for (final k in present)
        if (!order.contains(k)) k,
    ];
    return out;
  }
}
