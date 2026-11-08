import 'dart:convert';

import '../auth/cas_client.dart';

/// 成绩分项（平时 / 期末 / 总评…）。
class GradeDetailItem {
  const GradeDetailItem({
    required this.name,
    required this.ratio,
    required this.score,
  });

  final String name;
  final String ratio;
  final String score;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'ratio': ratio,
    'score': score,
  };

  static GradeDetailItem fromJson(Map<String, dynamic> json) => GradeDetailItem(
    name: json['name'] as String? ?? '',
    ratio: json['ratio'] as String? ?? '',
    score: json['score'] as String? ?? '',
  );
}

/// 一门课的成绩。
class Grade {
  const Grade({
    required this.name,
    required this.code,
    required this.termLabel,
    required this.credit,
    required this.gradePoint,
    required this.scoreText,
    required this.scoreValue,
    required this.courseKind,
    required this.teacher,
    required this.key,
    required this.kchId,
    required this.jxbId,
    required this.xnm,
    required this.xqm,
    this.details = const <GradeDetailItem>[],
  });

  final String name;
  final String code;
  final String termLabel;
  final double? credit;
  final double? gradePoint;
  final String scoreText;
  final double? scoreValue;
  final String courseKind;
  final String teacher;

  /// 查询成绩分项需要的信息。
  final String key;
  final String kchId;
  final String jxbId;
  final String xnm;
  final String xqm;

  final List<GradeDetailItem> details;

  bool get hasDetail => details.isNotEmpty;

  /// 平时 / 期末分项（没有返回 null）。
  GradeDetailItem? detailOf(String keyword) {
    for (final d in details) {
      if (d.name.contains(keyword)) {
        return d;
      }
    }
    return null;
  }

  Grade copyWith({List<GradeDetailItem>? details}) => Grade(
    name: name,
    code: code,
    termLabel: termLabel,
    credit: credit,
    gradePoint: gradePoint,
    scoreText: scoreText,
    scoreValue: scoreValue,
    courseKind: courseKind,
    teacher: teacher,
    key: key,
    kchId: kchId,
    jxbId: jxbId,
    xnm: xnm,
    xqm: xqm,
    details: details ?? this.details,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'code': code,
    'termLabel': termLabel,
    'credit': credit,
    'gradePoint': gradePoint,
    'scoreText': scoreText,
    'scoreValue': scoreValue,
    'courseKind': courseKind,
    'teacher': teacher,
    'key': key,
    'kchId': kchId,
    'jxbId': jxbId,
    'xnm': xnm,
    'xqm': xqm,
    'details': details.map((d) => d.toJson()).toList(),
  };

  static Grade fromJson(Map<String, dynamic> json) => Grade(
    name: json['name'] as String? ?? '',
    code: json['code'] as String? ?? '',
    termLabel: json['termLabel'] as String? ?? '',
    credit: (json['credit'] as num?)?.toDouble(),
    gradePoint: (json['gradePoint'] as num?)?.toDouble(),
    scoreText: json['scoreText'] as String? ?? '',
    scoreValue: (json['scoreValue'] as num?)?.toDouble(),
    courseKind: json['courseKind'] as String? ?? '',
    teacher: json['teacher'] as String? ?? '',
    key: json['key'] as String? ?? '',
    kchId: json['kchId'] as String? ?? '',
    jxbId: json['jxbId'] as String? ?? '',
    xnm: json['xnm'] as String? ?? '',
    xqm: json['xqm'] as String? ?? '',
    details: (json['details'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => GradeDetailItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 绩点汇总（按学分加权）。
class GradeSummary {
  const GradeSummary({
    required this.weightedGpa,
    required this.weightedAverage,
    required this.totalCredits,
    required this.courseCount,
  });

  final double? weightedGpa;
  final double? weightedAverage;
  final double totalCredits;
  final int courseCount;

  static const GradeSummary empty = GradeSummary(
    weightedGpa: null,
    weightedAverage: null,
    totalCredits: 0,
    courseCount: 0,
  );

  static GradeSummary compute(List<Grade> grades) {
    var credits = 0.0;
    var gpaSum = 0.0;
    var gpaCredits = 0.0;
    var avgSum = 0.0;
    var avgCredits = 0.0;
    for (final g in grades) {
      final c = g.credit;
      if (c == null || c <= 0) {
        continue;
      }
      credits += c;
      if (g.gradePoint != null) {
        gpaSum += g.gradePoint! * c;
        gpaCredits += c;
      }
      if (g.scoreValue != null) {
        avgSum += g.scoreValue! * c;
        avgCredits += c;
      }
    }
    return GradeSummary(
      weightedGpa: gpaCredits > 0 ? gpaSum / gpaCredits : null,
      weightedAverage: avgCredits > 0 ? avgSum / avgCredits : null,
      totalCredits: credits,
      courseCount: grades.length,
    );
  }
}

/// 一次成绩查询的快照。
class GradeSnapshot {
  const GradeSnapshot({
    required this.grades,
    required this.updatedAt,
    this.studentName = '',
    this.className = '',
  });

  final List<Grade> grades;
  final DateTime updatedAt;
  final String studentName;
  final String className;

  GradeSummary get summary => GradeSummary.compute(grades);

  /// 所有学期（按学期倒序，最新在前）。
  List<String> get terms {
    final set = <String>{};
    for (final g in grades) {
      if (g.termLabel.isNotEmpty) {
        set.add(g.termLabel);
      }
    }
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  List<Grade> gradesInTerm(String term) =>
      grades.where((g) => g.termLabel == term).toList();

  GradeSummary summaryForTerm(String? term) =>
      term == null ? summary : GradeSummary.compute(gradesInTerm(term));

  Map<String, dynamic> toJson() => <String, dynamic>{
    'updatedAt': updatedAt.toIso8601String(),
    'studentName': studentName,
    'className': className,
    'grades': grades.map((g) => g.toJson()).toList(),
  };

  static GradeSnapshot fromJson(Map<String, dynamic> json) => GradeSnapshot(
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    studentName: json['studentName'] as String? ?? '',
    className: json['className'] as String? ?? '',
    grades: (json['grades'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => Grade.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 正方成绩查询接口。
class GradeApi {
  GradeApi(this.client);

  final CasClient client;

  static const String _listPath =
      'https://jwgl.usst.edu.cn/jwglxt/cjcx/cjcx_cxDgXscj.html?doType=query&gnmkdm=N305005';
  static const String _detailPath =
      'https://jwgl.usst.edu.cn/jwglxt/cjcx/cjcx_cxCjxq.html?gnmkdm=N305005';

  /// 学生分项成绩查询（一次返回一学期所有课的期末成绩与占比）。
  static const String _fxcjPath =
      'https://jwgl.usst.edu.cn/jwglxt/cjcx/cjcx_cxXsfxcjIndex.html?gnmkdm=N305004&layout=default&doType=query';

  /// 总评先返回；分项可由 enrich 在后台补齐。
  Future<GradeSnapshot> fetchAll({bool withDetails = false}) async {
    final grades = <Grade>[];
    final seenPages = <String>{};
    var page = 1;
    var total = 0;
    String studentName = '';
    String className = '';
    do {
      final resp = await client.getJson(
        Uri.parse(_listPath),
        data: <String, String>{
          'xnm': '',
          'xqm': '',
          '_search': 'false',
          'queryModel.showCount': '200',
          'queryModel.currentPage': '$page',
          'queryModel.sortName': '',
          'queryModel.sortOrder': 'asc',
        },
      );
      final raw = resp.data ?? '';
      if (!raw.trimLeft().startsWith('{')) {
        throw StateError('成绩接口未返回有效数据，请刷新登录状态');
      }
      final body = jsonDecode(raw);
      if (body is! Map || body['items'] is! List) {
        throw StateError('成绩列表缺失');
      }
      if (!seenPages.add(jsonEncode(body['items']))) {
        throw StateError('成绩分页重复，请稍后重试');
      }
      final parsed = parsePage(raw);
      grades.addAll(parsed.grades);
      studentName = parsed.studentName;
      className = parsed.className;
      total = parsed.totalCount;
      if (parsed.grades.isEmpty && grades.length < total) {
        throw StateError('成绩分页不完整');
      }
      page++;
    } while (grades.length < total && page <= 5);
    if (grades.length < total) throw StateError('成绩分页不完整，请稍后重试');

    final deduped = <String, Grade>{};
    for (final g in grades) {
      deduped['${g.code}|${g.name}|${g.termLabel}'] = g;
    }
    var list = deduped.values.toList()
      ..sort((a, b) {
        final t = b.termLabel.compareTo(a.termLabel);
        return t != 0 ? t : a.name.compareTo(b.name);
      });

    if (withDetails) {
      list = await _fillBreakdowns(list);
    }
    return GradeSnapshot(
      grades: list,
      updatedAt: DateTime.now(),
      studentName: studentName,
      className: className,
    );
  }

  /// 优先用「分项成绩查询」按学期批量拿（每学期 1 个请求）；
  Future<GradeSnapshot> enrich(GradeSnapshot snapshot) async => GradeSnapshot(
    grades: await _fillBreakdowns(snapshot.grades),
    updatedAt: snapshot.updatedAt,
    studentName: snapshot.studentName,
    className: snapshot.className,
  );

  /// 某学期接口没数据时，再退回按课程逐门查明细。
  Future<List<Grade>> _fillBreakdowns(List<Grade> grades) async {
    if (grades.isEmpty) return grades;
    final result = List<Grade>.from(grades);
    final termKeys = <String>{};
    for (final g in grades) {
      if (g.xnm.isNotEmpty && g.xqm.isNotEmpty) {
        termKeys.add('${g.xnm}|${g.xqm}');
      }
    }
    final byJxb = <String, List<GradeDetailItem>>{};
    // 先一次性拉全部学期（1 个请求），失败再按学期补
    try {
      byJxb.addAll(await fetchAllBreakdowns());
    } catch (_) {
      // ignore
    }
    if (byJxb.isEmpty) {
      final terms = termKeys.toList();
      var cursor = 0;
      Future<void> termWorker() async {
        while (cursor < terms.length) {
          final key = terms[cursor++];
          final parts = key.split('|');
          try {
            final map = await fetchTermBreakdowns(parts[0], parts[1]);
            byJxb.addAll(map);
          } catch (_) {
            // 单学期失败忽略
          }
        }
      }

      await Future.wait(<Future<void>>[termWorker(), termWorker()]);
    }

    final missingIndexes = <int>[];
    for (var i = 0; i < result.length; i++) {
      final details = byJxb[result[i].jxbId];
      if (details != null && details.isNotEmpty) {
        result[i] = result[i].copyWith(details: details);
      } else {
        missingIndexes.add(i);
      }
    }
    if (missingIndexes.isNotEmpty) {
      final fallback = await _fillDetails(
        missingIndexes.map((i) => result[i]).toList(),
      );
      for (var k = 0; k < missingIndexes.length; k++) {
        if (fallback[k].hasDetail) {
          result[missingIndexes[k]] = fallback[k];
        }
      }
    }
    return result;
  }

  /// 拉所有学期的分项成绩（一次拿全，按教学班 id 分组）。
  ///
  /// 注意：这个接口只认 jqGrid 的 queryModel.* 分页参数；
  /// 用 page/rows 会走默认分页（每页 10 条），导致部分课程拿不到。
  Future<Map<String, List<GradeDetailItem>>> fetchAllBreakdowns() async {
    final resp = await client.getJson(
      Uri.parse(_fxcjPath),
      data: <String, String>{
        'xnm': '',
        'xqm': '',
        '_search': 'false',
        'queryModel.showCount': '500',
        'queryModel.currentPage': '1',
        'queryModel.sortName': '',
        'queryModel.sortOrder': 'asc',
      },
    );
    return parseBreakdowns(resp.data ?? '');
  }

  /// 拉一学期的分项成绩，按教学班 id 分组。
  Future<Map<String, List<GradeDetailItem>>> fetchTermBreakdowns(
    String xnm,
    String xqm,
  ) async {
    final resp = await client.getJson(
      Uri.parse(_fxcjPath),
      data: <String, String>{
        'xnm': xnm,
        'xqm': xqm,
        '_search': 'false',
        'queryModel.showCount': '500',
        'queryModel.currentPage': '1',
        'queryModel.sortName': '',
        'queryModel.sortOrder': 'asc',
      },
    );
    return parseBreakdowns(resp.data ?? '');
  }

  /// 解析分项成绩 JSON。
  ///
  /// 教务只公开「期末成绩」和「期末占比」，平时分不直接返回；
  /// 这里用 总评 = 平时*(1-占比) + 期末*占比 反推，名字带 * 号标记为推算值。
  static Map<String, List<GradeDetailItem>> parseBreakdowns(String raw) {
    final out = <String, List<GradeDetailItem>>{};
    if (!raw.trimLeft().startsWith('{')) {
      return out;
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    for (final item in (map['items'] as List<dynamic>? ?? <dynamic>[])) {
      final it = (item as Map<dynamic, dynamic>).cast<String, dynamic>();
      final jxbId = it['jxb_id']?.toString() ?? '';
      if (jxbId.isEmpty) {
        continue;
      }
      final total = _toDouble(it['bfzcj']);
      final finalScore = _toDouble(it['qmcj']);
      // 期末占比：接口里叫 qmbl，老字段 qmxmbl 兜底
      final finalRatio = _toDouble(it['qmbl']) ?? _toDouble(it['qmxmbl']);
      // 平时分与平时占比是接口直接返回的官方字段
      var daily = _toDouble(it['pscj']);
      final dailyRatio = _toDouble(it['psbl']);
      var dailyName = '平时';

      // 极少数情况下接口没给平时分，用 总评/期末/占比 反推并加 * 标记
      if (daily == null &&
          total != null &&
          finalScore != null &&
          finalRatio != null &&
          finalRatio > 0 &&
          finalRatio < 100) {
        final w = finalRatio / 100;
        final derived = (total - finalScore * w) / (1 - w);
        if (derived >= 0 && derived <= 100) {
          daily = (derived * 10).round() / 10;
          dailyName = '平时*';
        }
      }

      final details = <GradeDetailItem>[];
      // 推算平时分时没有 psbl，用 100 - 期末占比 补上平时占比
      final effectiveDailyRatio =
          dailyRatio ?? (finalRatio == null ? null : 100 - finalRatio);
      if (daily != null) {
        details.add(
          GradeDetailItem(
            name: dailyName,
            ratio: effectiveDailyRatio == null
                ? ''
                : '${effectiveDailyRatio.round()}%',
            score: _formatScore(daily),
          ),
        );
      }
      if (finalScore != null) {
        details.add(
          GradeDetailItem(
            name: '期末',
            ratio: finalRatio == null ? '' : '${finalRatio.round()}%',
            score: _formatScore(finalScore),
          ),
        );
      }
      if (total != null) {
        details.add(
          GradeDetailItem(name: '总评', ratio: '', score: _formatScore(total)),
        );
      }
      if (details.isNotEmpty) {
        out[jxbId] = details;
      }
    }
    return out;
  }

  static double? _toDouble(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString().trim());
  }

  static String _formatScore(double value) {
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
  }

  /// 并发抓分项（3 路），单门失败不影响其它。
  Future<List<Grade>> _fillDetails(List<Grade> grades) async {
    final result = List<Grade>.from(grades);
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < result.length) {
        final index = cursor++;
        final grade = result[index];
        if (grade.kchId.isEmpty || grade.jxbId.isEmpty) {
          continue;
        }
        try {
          final items = await fetchDetail(grade);
          if (items.isNotEmpty) {
            result[index] = grade.copyWith(details: items);
          }
        } catch (_) {
          // 忽略单门失败
        }
      }
    }

    await Future.wait(<Future<void>>[worker(), worker(), worker()]);
    return result;
  }

  Future<List<GradeDetailItem>> fetchDetail(Grade grade) async {
    final uri = Uri.parse(
      '$_detailPath&kch_id=${Uri.encodeQueryComponent(grade.kchId)}'
      '&jxb_id=${Uri.encodeQueryComponent(grade.jxbId)}'
      '&xnm=${Uri.encodeQueryComponent(grade.xnm)}'
      '&xqm=${Uri.encodeQueryComponent(grade.xqm)}',
    );
    final resp = await client.getJson(uri);
    return parseDetail(resp.data ?? '');
  }

  /// 解析成绩分项 HTML（<td>分项</td><td>比例</td><td>成绩</td>）。
  static List<GradeDetailItem> parseDetail(String html) {
    final items = <GradeDetailItem>[];
    final rowRe = RegExp(
      r'<td[^>]*>\s*(?:【\s*)?([^<【】]{1,20}?)(?:\s*】)?\s*</td>\s*'
      r'<td[^>]*>([^<]*)</td>\s*'
      r'<td[^>]*>([^<]*)</td>',
      multiLine: true,
    );
    for (final m in rowRe.allMatches(html)) {
      final name = _clean(m.group(1));
      final ratio = _clean(m.group(2));
      final score = _clean(m.group(3));
      if (name.isEmpty || name.contains('成绩分项')) {
        continue;
      }
      items.add(GradeDetailItem(name: name, ratio: ratio, score: score));
    }
    return items;
  }

  static String _clean(String? raw) {
    if (raw == null) {
      return '';
    }
    return raw.replaceAll('&nbsp;', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 解析一页成绩 JSON（字段名来自 2026-10 实测抓包）。
  static ({
    List<Grade> grades,
    int totalCount,
    String studentName,
    String className,
  })
  parsePage(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final items = (map['items'] as List<dynamic>? ?? <dynamic>[]);
    final grades = <Grade>[];
    var studentName = '';
    var className = '';
    for (final item in items) {
      final it = (item as Map<dynamic, dynamic>).cast<String, dynamic>();
      final name = it['kcmc']?.toString().trim() ?? '';
      if (name.isEmpty) {
        continue;
      }
      studentName = it['xm']?.toString() ?? studentName;
      className = it['bj']?.toString() ?? className;
      final xnmmc = it['xnmmc']?.toString() ?? '';
      final xqmmc = it['xqmmc']?.toString() ?? '';
      final termLabel = xnmmc.isEmpty ? '' : '$xnmmc 第$xqmmc学期';
      final scoreText = (it['cj']?.toString() ?? '').trim();
      grades.add(
        Grade(
          name: name,
          code: it['kch']?.toString() ?? '',
          termLabel: termLabel,
          credit: double.tryParse('${it['xf']}'),
          gradePoint: double.tryParse('${it['jd']}'),
          scoreText: scoreText,
          scoreValue: double.tryParse('${it['bfzcj']}'),
          courseKind: it['kcxzmc']?.toString() ?? '',
          teacher: it['jsxm']?.toString() ?? '',
          key: it['key']?.toString() ?? '',
          kchId: it['kch_id']?.toString() ?? '',
          jxbId: it['jxb_id']?.toString() ?? '',
          xnm: it['xnm']?.toString() ?? '',
          xqm: it['xqm']?.toString() ?? '',
        ),
      );
    }
    final total =
        int.tryParse('${map['totalCount']}') ??
        int.tryParse('${map['totalResult']}') ??
        0;
    return (
      grades: grades,
      totalCount: total,
      studentName: studentName,
      className: className,
    );
  }
}
