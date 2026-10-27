import 'dart:convert';

import '../auth/cas_client.dart';

/// 一网畅学课程详情数据（原生页面用）。
class TronCourseChapter {
  const TronCourseChapter({
    required this.activityId,
    required this.moduleId,
    required this.title,
    required this.typeLabel,
    required this.description,
    required this.publishTime,
  });

  final String activityId;
  final String moduleId;
  final String title;
  final String typeLabel;
  final String description;
  final String publishTime;
}

class TronCourseHomework {
  const TronCourseHomework({
    required this.id,
    required this.title,
    required this.description,
    required this.deadline,
  });

  final int id;
  final String title;
  final String description;
  final String deadline;
}

class TronAttachment {
  const TronAttachment({
    required this.id,
    required this.name,
    required this.size,
  });

  final int id;
  final String name;
  final int size;

  String get typeLabel {
    if (name.toLowerCase().endsWith('.pdf')) return 'PDF';
    if (name.toLowerCase().endsWith('.ppt') ||
        name.toLowerCase().endsWith('.pptx')) {
      return 'PPT';
    }
    if (name.toLowerCase().endsWith('.doc') ||
        name.toLowerCase().endsWith('.docx')) {
      return 'DOC';
    }
    return 'FILE';
  }
}

class TronActivityDetail {
  const TronActivityDetail({
    required this.title,
    required this.description,
    required this.content,
    required this.attachments,
  });

  final String title;
  final String description;
  final String content;
  final List<TronAttachment> attachments;
}

class TronCourseAnnouncement {
  const TronCourseAnnouncement({
    required this.title,
    required this.content,
    required this.createdAt,
    this.attachments = const <TronAttachment>[],
  });

  final String title;
  final String content;
  final String createdAt;

  /// 公告也可能带附件（例如 .rar / .pdf）。
  final List<TronAttachment> attachments;
}

class TronCourseExam {
  const TronCourseExam({
    required this.id,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.status,
    this.score,
  });

  final int id;
  final String title;
  final double? score;
  final String startAt;
  final String endAt;
  final String status;
}

class TronCourseDiscussion {
  const TronCourseDiscussion({
    required this.id,
    required this.title,
    required this.description,
    required this.replies,
  });

  final String id;
  final String title;
  final String description;
  final int replies;
}

class TronCourseDetail {
  const TronCourseDetail({
    required this.chapters,
    required this.announcements,
    required this.homeworks,
    required this.modules,
    required this.exams,
    required this.discussions,
  });

  final List<TronCourseChapter> chapters;
  final List<TronCourseAnnouncement> announcements;
  final List<TronCourseHomework> homeworks;
  final Map<String, String> modules;
  final List<TronCourseExam> exams;
  final List<TronCourseDiscussion> discussions;
}

class TronCourseDetailApi {
  TronCourseDetailApi(this.client);

  final CasClient client;

  Future<TronCourseDetail> fetch(String courseId) async {
    // 四个接口互不依赖，并发请求
    final activitiesFuture = _activities(courseId);
    final modulesFuture = _modules(courseId);
    final bulletinsFuture = _bulletins(courseId);
    final examsFuture = _exams(courseId);
    final activities = await activitiesFuture;
    final modules = await modulesFuture;
    final bulletins = await bulletinsFuture;
    final exams = await examsFuture;

    final chapters = <TronCourseChapter>[];
    final homeworks = <TronCourseHomework>[];
    final discussions = <TronCourseDiscussion>[];
    for (final item in activities) {
      final type = (item['type'] ?? '').toString();
      final title = (item['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      if (type == 'forum') {
        discussions.add(
          TronCourseDiscussion(
            id: (item['id'] ?? '').toString(),
            title: title,
            description: _plain(_dataString(item, 'description')),
            replies: (item['forum_count'] as num?)?.toInt() ?? 0,
          ),
        );
        continue;
      }
      if (type == 'homework') {
        final id = int.tryParse((item['id'] ?? '').toString()) ?? 0;
        if (id > 0) {
          homeworks.add(
            TronCourseHomework(
              id: id,
              title: title,
              description: _plain(_dataString(item, 'description')),
              deadline: _date(_endTime(item)),
            ),
          );
        }
        continue;
      }
      if (type == 'exam') continue;
      chapters.add(
        TronCourseChapter(
          activityId: (item['id'] ?? '').toString(),
          moduleId: (item['module_id'] ?? '').toString(),
          title: title,
          typeLabel: _typeLabel(type),
          description: _plain(_dataString(item, 'description')),
          publishTime: _date(_dataString(item, 'publish_time')),
        ),
      );
    }

    return TronCourseDetail(
      chapters: chapters,
      announcements: bulletins,
      homeworks: homeworks,
      modules: modules,
      exams: exams,
      discussions: discussions,
    );
  }

  Future<List<Map<String, dynamic>>> _activities(String courseId) async {
    final response = await client.getApi(
      Uri.parse('https://1906.usst.edu.cn/api/courses/$courseId/activities'),
    );
    final map = _json(response.data);
    return (map['activities'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, String>> _modules(String courseId) async {
    final response = await client.getApi(
      Uri.parse('https://1906.usst.edu.cn/api/courses/$courseId/modules'),
    );
    final map = _json(response.data);
    final list = map['modules'] as List<dynamic>? ?? <dynamic>[];
    final out = <String, String>{};
    for (final item in list) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();
      final id = (m['id'] ?? '').toString();
      final name = (m['name'] ?? '').toString().trim();
      if (id.isNotEmpty && name.isNotEmpty) out[id] = name;
    }
    return out;
  }

  /// 单个活动的详情 + 附件。
  Future<TronActivityDetail> fetchActivity(String activityId) async {
    final response = await client.getApi(
      Uri.parse('https://1906.usst.edu.cn/api/activities/$activityId'),
    );
    final map = _json(response.data);
    final attachments = parseUploads(map['uploads']);
    return TronActivityDetail(
      title: (map['title'] ?? '').toString().trim(),
      description: _plain(_dataString(map, 'description')),
      content: _plain(_dataString(map, 'content')),
      attachments: attachments,
    );
  }

  Future<List<TronCourseAnnouncement>> _bulletins(String courseId) async {
    final response = await client.getApi(
      Uri.parse('https://1906.usst.edu.cn/api/courses/$courseId/bulletins'),
    );
    final map = _json(response.data);
    final list = map['bulletins'] as List<dynamic>? ?? <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) {
          final m = e.cast<String, dynamic>();
          return TronCourseAnnouncement(
            title: (m['title'] ?? '').toString().trim(),
            content: _plain((m['content'] ?? '').toString()),
            createdAt: _date((m['created_at'] ?? '').toString()),
            attachments: parseUploads(m['uploads']),
          );
        })
        .where((e) => e.title.isNotEmpty)
        .toList();
  }

  /// 解析活动 / 公告的 `uploads` 数组，保留 .rar 等普通文件。
  static List<TronAttachment> parseUploads(dynamic raw) {
    final list = raw is List ? raw : const <dynamic>[];
    final out = <TronAttachment>[];
    for (final upload in list) {
      if (upload is! Map) continue;
      final m = upload.cast<String, dynamic>();
      final id = int.tryParse('${m['id'] ?? ''}') ?? 0;
      final name = (m['name'] ?? '').toString().trim();
      if (id <= 0 || name.isEmpty) continue;
      out.add(
        TronAttachment(
          id: id,
          name: name,
          size: (m['size'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return out;
  }

  Future<List<TronCourseExam>> _exams(String courseId) async {
    final response = await client.getApi(
      Uri.parse('https://1906.usst.edu.cn/api/courses/$courseId/exams'),
    );
    final map = _json(response.data);
    final list = map['exams'] as List<dynamic>? ?? <dynamic>[];
    final seeds = <_ExamSeed>[];
    for (final item in list) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();
      final id = (m['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) continue;
      final title = (m['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      final started = m['is_started'] == true;
      final closed = m['is_closed'] == true;
      seeds.add(
        _ExamSeed(
          id: id,
          title: title,
          startAt: _date((m['start_time'] ?? '').toString()),
          endAt: _date((m['end_time'] ?? '').toString()),
          status: closed ? '已结束' : (started ? '进行中' : '未开始'),
        ),
      );
    }
    // 分数是每场考试单独一个接口，并发拉，避免串行把整页首屏拖住。
    final scores = await Future.wait(seeds.map((e) => _examScore(e.id)));
    return <TronCourseExam>[
      for (var i = 0; i < seeds.length; i++)
        TronCourseExam(
          id: seeds[i].id,
          title: seeds[i].title,
          startAt: seeds[i].startAt,
          endAt: seeds[i].endAt,
          status: seeds[i].status,
          score: scores[i],
        ),
    ];
  }

  /// 单场考试的得分；没交卷 / 没批阅 / 接口失败都返回 null。
  Future<double?> _examScore(int examId) async {
    try {
      final response = await client.getApi(
        Uri.parse('https://1906.usst.edu.cn/api/exams/$examId/submissions'),
      );
      final raw = _json(response.data)['exam_score'];
      return raw is num ? raw.toDouble() : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _json(dynamic data) {
    try {
      final raw = (data ?? '').toString();
      if (!raw.trim().startsWith('{')) return <String, dynamic>{};
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static String _dataString(Map<String, dynamic> item, String key) {
    final data = item['data'];
    if (data is Map) return (data[key] ?? '').toString();
    return '';
  }

  /// 活动截止时间：列表接口里可能在顶层，也可能塞在 data 里。
  static String _endTime(Map<String, dynamic> item) {
    final top = (item['end_time'] ?? '').toString();
    if (top.isNotEmpty) return top;
    return _dataString(item, 'end_time');
  }

  static String _typeLabel(String type) {
    const labels = <String, String>{
      'material': '资料',
      'online_video': '视频',
      'page': '页面',
      'slide': '微课',
      'web_link': '链接',
      'live': '直播',
      'questionnaire': '问卷',
    };
    return labels[type] ?? '内容';
  }

  static String _plain(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String _date(String raw) {
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// 考试列表的中间数据：分数要单独请求，先攒起来再并发拉。
class _ExamSeed {
  const _ExamSeed({
    required this.id,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.status,
  });

  final int id;
  final String title;
  final String startAt;
  final String endAt;
  final String status;
}
