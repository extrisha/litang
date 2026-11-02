import 'dart:convert';

import 'package:dio/dio.dart';

import '../auth/cas_client.dart';
import '../models.dart';
import 'jwgl_schedule.dart';

/// 一次课表查询的快照。
class CourseSnapshot {
  const CourseSnapshot({
    required this.termLabel,
    required this.xnm,
    required this.xqm,
    required this.courses,
    required this.updatedAt,
    this.studentName = '',
    this.className = '',
    this.majorName = '',
    this.collegeName = '',
    this.currentWeek,
  });

  final String termLabel;
  final String xnm;
  final String xqm;
  final List<Course> courses;
  final DateTime updatedAt;

  /// 学籍信息（登录后展示「我的」卡片用）。
  final String studentName;
  final String className;

  /// 专业名（「我的」卡片副标题用）。
  final String majorName;

  /// 学院名（来自教务首页用户信息）。
  final String collegeName;

  /// 教务首页给出的当前教学周（1 起）。
  final int? currentWeek;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'termLabel': termLabel,
    'xnm': xnm,
    'xqm': xqm,
    'updatedAt': updatedAt.toIso8601String(),
    'studentName': studentName,
    'className': className,
    'majorName': majorName,
    'collegeName': collegeName,
    'currentWeek': currentWeek,
    'courses': courses
        .map(
          (c) => <String, dynamic>{
            'name': c.name,
            'day': c.day,
            'start': c.start,
            'span': c.span,
            'room': c.room,
            'teacher': c.teacher,
            'weeks': c.weeks,
            'weeksText': c.weeksText,
          },
        )
        .toList(),
  };

  CourseSnapshot copyWith({int? currentWeek, String? collegeName}) =>
      CourseSnapshot(
        termLabel: termLabel,
        xnm: xnm,
        xqm: xqm,
        courses: courses,
        updatedAt: updatedAt,
        studentName: studentName,
        className: className,
        majorName: majorName,
        collegeName: collegeName ?? this.collegeName,
        currentWeek: currentWeek ?? this.currentWeek,
      );

  static CourseSnapshot fromJson(Map<String, dynamic> json) {
    final list = (json['courses'] as List<dynamic>? ?? <dynamic>[]).map((e) {
      final m = e as Map<String, dynamic>;
      return Course(
        name: m['name'] as String? ?? '',
        day: (m['day'] as num?)?.toInt() ?? 0,
        start: (m['start'] as num?)?.toInt() ?? 0,
        span: (m['span'] as num?)?.toInt() ?? 1,
        room: m['room'] as String? ?? '',
        teacher: m['teacher'] as String?,
        weeks: (m['weeks'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .toList(),
        weeksText: m['weeksText'] as String? ?? '',
      );
    }).toList();
    return CourseSnapshot(
      termLabel: json['termLabel'] as String? ?? '',
      xnm: json['xnm'] as String? ?? '',
      xqm: json['xqm'] as String? ?? '',
      courses: list,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      studentName: json['studentName'] as String? ?? '',
      className: json['className'] as String? ?? '',
      majorName: json['majorName'] as String? ?? '',
      collegeName: json['collegeName'] as String? ?? '',
      currentWeek: (json['currentWeek'] as num?)?.toInt(),
    );
  }
}

/// 正方 jwglxt 课表接口。
class CourseApi {
  CourseApi(this.client);

  final CasClient client;

  static const String _kbPath =
      'https://jwgl.usst.edu.cn/jwglxt/kbcx/xskbcx_cxXsKb.html?gnmkdm=N2151';

  /// 抓当前学期课表；先不传学期参数让教务返回默认学期，
  /// 拿不到再按当前日期推算的学年学期兜底。
  /// 从教务首页用户信息里取学院/班级，如「健康科学与工程学院 康复25291002班」。
  static ({String college, String className})? parseUserInfo(String html) {
    final match = RegExp(r'<p>([^<]*(?:学院|学部|教学部))\s*([^<]*)</p>')
        .firstMatch(html);
    if (match == null) {
      return null;
    }
    final college = (match.group(1) ?? '').trim();
    if (college.isEmpty) {
      return null;
    }
    return (college: college, className: (match.group(2) ?? '').trim());
  }

  Future<({String college, String className})?> _fetchUserInfo() async {
    try {
      final resp = await client.getJson(
        Uri.parse(
          'https://jwgl.usst.edu.cn/jwglxt/xtgl/index_cxYhxxIndex.html?xt=jw&localeKey=zh_CN&gnmkdm=index',
        ),
      );
      return parseUserInfo(resp.data ?? '');
    } catch (_) {
      return null;
    }
  }

  /// 教务首页会带当前教学周（id="dqzc"）。
  Future<int?> fetchCurrentWeek() async {
    try {
      final resp = await client.getJson(
        Uri.parse(
          'https://jwgl.usst.edu.cn/jwglxt/xtgl/index_cxAreaOne.html?gnmkdm=N2151',
        ),
      );
      final html = resp.data ?? '';
      final match = RegExp(r'<input[^>]*dqzc[^>]*value="(\d+)"')
          .firstMatch(html);
      return match == null ? null : int.parse(match.group(1)!);
    } catch (_) {
      return null;
    }
  }

  Future<CourseSnapshot> fetchCurrent() async {
    final currentWeek = await fetchCurrentWeek();
    final userInfo = await _fetchUserInfo();
    final now = DateTime.now();
    final year = now.month >= 8 ? now.year : now.year - 1;
    final term = (now.month >= 8 || now.month <= 1) ? '3' : '12';
    final attempts = <Map<String, String>>[
      <String, String>{'xnm': '', 'xqm': '', 'kzlx': 'ck'},
      <String, String>{'xnm': '$year', 'xqm': term, 'kzlx': 'ck'},
      <String, String>{'xnm': '$year', 'xqm': '3', 'kzlx': 'ck'},
      <String, String>{'xnm': '$year', 'xqm': '12', 'kzlx': 'ck'},
      <String, String>{'xnm': '${year - 1}', 'xqm': '12', 'kzlx': 'ck'},
    ];

    CourseSnapshot? last;
    for (final params in attempts) {
      final resp = await _post(_kbPath, params);
      final raw = resp.data ?? '';
      if (!raw.trimLeft().startsWith('{')) {
        continue;
      }
      final snapshot = parseKb(raw).copyWith(
        currentWeek: currentWeek,
        collegeName: userInfo?.college ?? '',
      );
      last = snapshot;
      if (snapshot.courses.isNotEmpty) {
        return snapshot;
      }
    }
    return (last ?? _empty()).copyWith(
      currentWeek: currentWeek,
      collegeName: userInfo?.college ?? '',
    );
  }

  Future<Response<String>> _post(String url, Map<String, String> data) {
    return client.getJson(Uri.parse(url), data: data);
  }

  static CourseSnapshot _empty() => CourseSnapshot(
    termLabel: '',
    xnm: '',
    xqm: '',
    courses: const <Course>[],
    updatedAt: DateTime.now(),
  );

  /// 解析正方课表 JSON（字段名来自 2026-10 实测抓包）。
  static CourseSnapshot parseKb(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final xsxx =
        (map['xsxx'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final xnm = xsxx['XNM']?.toString() ?? '';
    final xqm = xsxx['XQM']?.toString() ?? '';
    final xnmc = xsxx['XNMC']?.toString() ?? '';
    final xqmmc = xsxx['XQMMC']?.toString() ?? '';
    final termLabel = xnmc.isEmpty ? '当前学期' : '$xnmc 第$xqmmc学期';

    final courses = <Course>[];
    final seen = <String>{};
    for (final item in (map['kbList'] as List<dynamic>? ?? <dynamic>[])) {
      final it = (item as Map<dynamic, dynamic>).cast<String, dynamic>();
      final name = it['kcmc']?.toString().trim() ?? '';
      if (name.isEmpty) {
        continue;
      }
      final day = (int.tryParse(it['xqj']?.toString() ?? '') ?? 0) - 1;
      if (day < 0 || day > 6) {
        continue;
      }
      final jcs = it['jcs']?.toString() ?? '';
      final match = RegExp(r'(\d+)(?:\s*-\s*(\d+))?').firstMatch(jcs);
      final start = match == null ? 0 : int.parse(match.group(1)!) - 1;
      final end = match?.group(2) == null
          ? start + 1
          : int.parse(match!.group(2)!);
      final span = end - start < 1 ? 1 : end - start;
      final room = it['cdmc']?.toString().trim() ?? '';
      final teacher = it['xm']?.toString().trim();
      final weeksText = it['zcd']?.toString().trim() ?? '';
      final weeks = parseCourseWeeks(weeksText);
      final key = '$name|$day|$start|$span|$room';
      if (!seen.add(key)) {
        continue;
      }
      if (start < 0 || start + span > 13) {
        continue;
      }
      courses.add(
        Course(
          name: name,
          day: day,
          start: start,
          span: span,
          room: room,
          teacher: (teacher == null || teacher.isEmpty) ? null : teacher,
          weeks: weeks,
          weeksText: weeksText,
        ),
      );
    }
    courses.sort((a, b) {
      final d = a.day.compareTo(b.day);
      return d != 0 ? d : a.start.compareTo(b.start);
    });
    return CourseSnapshot(
      termLabel: termLabel,
      xnm: xnm,
      xqm: xqm,
      courses: courses,
      updatedAt: DateTime.now(),
      studentName: xsxx['XM']?.toString() ?? '',
      className: xsxx['BJMC']?.toString() ?? '',
      majorName: xsxx['ZYMC']?.toString() ?? '',
    );
  }
}
