import 'dart:convert';

import '../auth/cas_client.dart';

/// 一网畅学待办（作业/任务）。
class LmsTodo {
  const LmsTodo({
    required this.id,
    required this.courseId,
    required this.title,
    required this.courseName,
    required this.type,
    required this.deadline,
  });

  final int id;
  final int courseId;
  final String title;
  final String courseName;
  final String type;
  final DateTime? deadline;

  bool get isHomework => type == 'homework';

  String get typeLabel => switch (type) {
    'homework' => '作业',
    'exam' => '考试',
    _ => '任务',
  };

  static int _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  static LmsTodo? fromJson(Map<String, dynamic> json) {
    final title = (json['title'] ?? '').toString().trim();
    if (title.isEmpty) {
      return null;
    }
    DateTime? deadline;
    final raw = (json['end_time'] ?? json['deadline'] ?? '').toString();
    if (raw.isNotEmpty) {
      deadline = DateTime.tryParse(raw)?.toLocal();
    }
    var courseId = _asInt(json['course_id']);
    if (courseId == 0 && json['course'] is Map) {
      courseId = _asInt((json['course'] as Map)['id']);
    }
    if (courseId == 0 && json['courseId'] != null) {
      courseId = _asInt(json['courseId']);
    }

    var courseName = (json['course_name'] ?? '').toString().trim();
    if (courseName.isEmpty && json['course'] is Map) {
      courseName = ((json['course'] as Map)['name'] ?? '').toString().trim();
    }
    if (courseName.isEmpty && json['courseName'] != null) {
      courseName = (json['courseName'] ?? '').toString().trim();
    }

    final type = (json['type'] ?? json['activity_type'] ?? '').toString().trim();

    return LmsTodo(
      id: _asInt(json['id']),
      courseId: courseId,
      title: title,
      courseName: courseName,
      type: type,
      deadline: deadline,
    );
  }

  /// 本地缓存用（与上游字段名解耦，上游改字段不影响旧缓存）。
  Map<String, dynamic> toCacheJson() => <String, dynamic>{
    'id': id,
    'courseId': courseId,
    'title': title,
    'courseName': courseName,
    'type': type,
    'deadline': deadline?.toIso8601String(),
  };

  static LmsTodo? fromCacheJson(Map<String, dynamic> json) {
    final title = (json['title'] ?? '').toString();
    if (title.isEmpty) {
      return null;
    }
    final raw = json['deadline']?.toString() ?? '';
    return LmsTodo(
      id: _asInt(json['id']),
      courseId: _asInt(json['courseId']),
      title: title,
      courseName: (json['courseName'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      deadline: raw.isEmpty ? null : DateTime.tryParse(raw),
    );
  }
}

/// 一网畅学课程信息。
class LmsCourseInfo {
  const LmsCourseInfo({
    required this.id,
    required this.name,
    required this.teacher,
    required this.termCode,
  });

  final String id;
  final String name;
  final String teacher;
  final String termCode;
}

/// 教务考试安排。
class LmsExam {
  const LmsExam({
    required this.courseName,
    required this.examName,
    required this.termLabel,
    required this.timeText,
    required this.location,
    required this.teacher,
  });

  final String courseName;
  final String examName;
  final String termLabel;
  final String timeText;
  final String location;
  final String teacher;

  bool get timePending => timeText.isEmpty || timeText.contains('未放开');

  static LmsExam? fromJson(Map<String, dynamic> json) {
    final course = (json['kcmc'] ?? '').toString().trim();
    if (course.isEmpty) {
      return null;
    }
    final xnmc = (json['xnmc'] ?? '').toString().trim();
    final xqmmc = (json['xqmmc'] ?? '').toString().trim();
    var location = (json['jxdd'] ?? '').toString().trim();
    if (location.contains(';')) {
      location = location.split(';').first;
    }
    return LmsExam(
      courseName: course,
      examName: (json['ksmc'] ?? '').toString().trim(),
      termLabel: '$xnmc 第$xqmmc学期'.trim(),
      timeText: (json['kssj'] ?? '').toString().trim(),
      location: location,
      teacher: (json['jsxx'] ?? '').toString().trim(),
    );
  }

  /// 本地缓存用。
  Map<String, dynamic> toCacheJson() => <String, dynamic>{
    'courseName': courseName,
    'examName': examName,
    'termLabel': termLabel,
    'timeText': timeText,
    'location': location,
    'teacher': teacher,
  };

  static LmsExam? fromCacheJson(Map<String, dynamic> json) {
    final course = (json['courseName'] ?? '').toString();
    if (course.isEmpty) {
      return null;
    }
    return LmsExam(
      courseName: course,
      examName: (json['examName'] ?? '').toString(),
      termLabel: (json['termLabel'] ?? '').toString(),
      timeText: (json['timeText'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      teacher: (json['teacher'] ?? '').toString(),
    );
  }
}

/// 一网畅学 + 教务的学习类数据。
class LmsApi {
  LmsApi(this.client);

  final CasClient client;

  /// 1906 的数值 user id 不会变，缓存住就不用每次刷新都拉
  /// /user/index —— 那个页面有 800KB+，纯为了正则抠一个 id。
  static String? _uidCache;

  static const String _todosUrl = 'https://1906.usst.edu.cn/api/todos';
  static const String _examsUrl =
      'https://jwgl.usst.edu.cn/jwglxt/kwgl/kscx_cxXsksxxIndex.html?doType=query&gnmkdm=N358105';

  /// 一网畅学课程列表（含教师、学期）。
  Future<List<LmsCourseInfo>> fetchCourseInfos() async {
    var uid = _uidCache;
    if (uid == null || uid.isEmpty) {
      final index = await client.getApi(
        Uri.parse('https://1906.usst.edu.cn/user/index'),
      );
      uid = RegExp(r'id="userId"[^>]*value="([^"]+)"')
          .firstMatch(index.data ?? '')
          ?.group(1);
      if (uid == null || uid.isEmpty) {
        return const <LmsCourseInfo>[];
      }
      _uidCache = uid;
    }
    final response = await client.getApi(
      Uri.parse(
        'https://1906.usst.edu.cn/api/users/$uid/courses?page=1&page_size=100',
      ),
    );
    final raw = response.data ?? '';
    if (!raw.trim().startsWith('{')) {
      return const <LmsCourseInfo>[];
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final list = (map['courses'] as List<dynamic>? ?? <dynamic>[]);
    final out = <LmsCourseInfo>[];
    for (final item in list) {
      if (item is! Map) continue;
      final course = item.cast<String, dynamic>();
      final code = (course['course_code'] ?? '').toString();
      final rawName = (course['name'] ?? '').toString().trim();
      if (rawName.isEmpty) continue;
      final name = rawName
          .replaceAll('（', '(')
          .replaceAll('）', ')')
          .replaceAll(RegExp(r'\(\d{4}-\d{4}-\d\)-.*$'), '')
          .trim();
      final instructors =
          (course['instructors'] as List<dynamic>? ?? <dynamic>[])
              .whereType<Map>()
              .map((e) => (e['name'] ?? '').toString().trim())
              .where((e) => e.isNotEmpty)
              .join('、');
      final term =
          RegExp(r'\(([^)]+)\)').firstMatch(code)?.group(1) ??
          (course['semester'] as Map?)?['code']?.toString() ??
          '';
      out.add(
        LmsCourseInfo(
          id: (course['id'] ?? '').toString(),
          name: name,
          teacher: instructors,
          termCode: term,
        ),
      );
    }
    return out;
  }

  /// 待办（作业/任务），按截止时间升序。
  Future<List<LmsTodo>> fetchTodos() async {
    final resp = await client.getApi(Uri.parse(_todosUrl));
    final raw = resp.data ?? '';
    if (raw.trim().isNotEmpty && !raw.trim().startsWith('{')) {
      throw Exception('一网畅学待办返回异常，可能登录已失效');
    }
    final list = parseTodos(raw);
    list.sort((a, b) {
      final da = a.deadline;
      final db = b.deadline;
      if (da == null && db == null) {
        return 0;
      }
      if (da == null) {
        return 1;
      }
      if (db == null) {
        return -1;
      }
      return da.compareTo(db);
    });
    return list;
  }

  /// 考试安排（教务）。
  Future<List<LmsExam>> fetchExams() async {
    final resp = await client.getJson(
      Uri.parse(_examsUrl),
      data: <String, String>{
        'xnm': '',
        'xqm': '',
        '_search': 'false',
        'queryModel.showCount': '200',
        'queryModel.currentPage': '1',
        'queryModel.sortName': '',
        'queryModel.sortOrder': 'asc',
      },
    );
    return parseExams(resp.data ?? '');
  }

  static List<LmsTodo> parseTodos(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) {
      return const <LmsTodo>[];
    }
    final map = jsonDecode(trimmed) as Map<String, dynamic>;
    final list = (map['todo_list'] as List<dynamic>? ?? <dynamic>[]);
    final out = <LmsTodo>[];
    for (final item in list) {
      if (item is Map) {
        final todo = LmsTodo.fromJson(item.cast<String, dynamic>());
        if (todo != null) {
          out.add(todo);
        }
      }
    }
    return out;
  }

  static List<LmsExam> parseExams(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) {
      return const <LmsExam>[];
    }
    final map = jsonDecode(trimmed) as Map<String, dynamic>;
    final items = (map['items'] as List<dynamic>? ?? <dynamic>[]);
    final out = <LmsExam>[];
    for (final item in items) {
      if (item is Map) {
        final exam = LmsExam.fromJson(item.cast<String, dynamic>());
        if (exam != null) {
          out.add(exam);
        }
      }
    }
    return out;
  }
}
