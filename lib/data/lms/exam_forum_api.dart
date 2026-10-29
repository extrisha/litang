import 'dart:convert';

import '../auth/cas_client.dart';

/// 一条考试提交记录。
class TronExamSubmission {
  const TronExamSubmission({
    required this.score,
    required this.submittedAt,
    required this.methodText,
  });

  final double? score;
  final String submittedAt;
  final String methodText;
}

/// 一网畅学考试详情。
class TronExamDetail {
  const TronExamDetail({
    required this.title,
    required this.description,
    required this.startAt,
    required this.endAt,
    required this.closed,
    required this.started,
    required this.subjectsCount,
    required this.totalPoints,
    required this.submitTimes,
    required this.submittedTimes,
    required this.score,
    required this.submissions,
    this.courseId = 0,
  });

  final String title;
  final String description;
  final String startAt;
  final String endAt;
  final bool closed;
  final bool started;
  final int subjectsCount;
  final double? totalPoints;
  final int submitTimes;
  final int submittedTimes;
  final int courseId;

  /// 我的得分（最高分口径）；没交卷时为 null。
  final double? score;
  final List<TronExamSubmission> submissions;

  String get status => closed ? '已结束' : (started ? '进行中' : '未开始');
}

/// 讨论区里的一条回复。
class TronForumReply {
  const TronForumReply({
    required this.author,
    required this.content,
    required this.createdAt,
  });

  final String author;
  final String content;
  final String createdAt;
}

/// 讨论区里的一个话题。
class TronForumTopic {
  const TronForumTopic({
    required this.id,
    required this.title,
    required this.content,
    required this.author,
    required this.authorId,
    required this.createdAt,
    required this.likeCount,
    required this.replies,
  });

  final String id;
  final String title;
  final String content;
  final String author;

  /// 发言人的用户 id，用来筛「仅我的发言」。
  final String authorId;
  final String createdAt;
  final int likeCount;
  final List<TronForumReply> replies;
}

/// 考试详情 / 讨论话题的接口。
class TronExamForumApi {
  TronExamForumApi(this.client);

  final CasClient client;

  static const String _base = 'https://1906.usst.edu.cn';

  /// 考试详情：元信息来自 /api/exams/{id}，得分与提交记录来自 submissions。
  Future<TronExamDetail> fetchExam(int examId) async {
    final examResp = await client.getApi(Uri.parse('$_base/api/exams/$examId'));
    final exam = _json(examResp.data);
    if (exam.isEmpty) {
      throw Exception('考试详情读取失败');
    }
    // 分数接口失败不影响基本信息展示
    var scoreMap = <String, dynamic>{};
    try {
      final resp = await client.getApi(
        Uri.parse('$_base/api/exams/$examId/submissions'),
      );
      scoreMap = _json(resp.data);
    } catch (_) {
      scoreMap = <String, dynamic>{};
    }

    final submissions = <TronExamSubmission>[];
    for (final item in (scoreMap['submissions'] as List?) ?? const []) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();
      final submitted = (m['submitted_at'] ?? m['created_at'] ?? '').toString();
      submissions.add(
        TronExamSubmission(
          score: _double(m['score']),
          submittedAt: _date(submitted),
          methodText: (m['submit_method_text'] ?? '').toString(),
        ),
      );
    }

    final cId = (exam['course_id'] as num?)?.toInt() ?? 0;
    return TronExamDetail(
      title: (exam['title'] ?? '').toString().trim(),
      description: _plain((exam['description'] ?? '').toString()),
      startAt: _date((exam['start_time'] ?? '').toString()),
      endAt: _date((exam['end_time'] ?? '').toString()),
      closed: exam['is_closed'] == true,
      started: exam['is_started'] == true,
      subjectsCount: (exam['subjects_count'] as num?)?.toInt() ?? 0,
      totalPoints: (exam['total_points'] as num?)?.toDouble(),
      submitTimes: (exam['submit_times'] as num?)?.toInt() ?? 0,
      submittedTimes: (exam['submitted_times'] as num?)?.toInt() ?? 0,
      score: _double(scoreMap['exam_score']),
      submissions: submissions,
      courseId: cId,
    );
  }

  /// 讨论区的全部话题（含回复）。
  Future<List<TronForumTopic>> fetchForumTopics(String activityId) async {
    final resp = await client.getApi(
      Uri.parse('$_base/api/activities/$activityId/topics'),
    );
    final map = _json(resp.data);
    final list = (map['topics'] as List?) ?? const [];
    final out = <TronForumTopic>[];
    for (final item in list) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();
      final author = ((m['created_by'] as Map?)?['name'] ?? '')
          .toString()
          .trim();
      final authorId = ((m['created_by'] as Map?)?['id'] ?? '').toString();
      out.add(
        TronForumTopic(
          id: (m['id'] ?? '').toString(),
          title: (m['title'] ?? '').toString().trim(),
          content: _plain((m['content'] ?? '').toString()),
          author: author,
          authorId: authorId,
          createdAt: _date((m['created_at'] ?? '').toString()),
          likeCount: (m['like_count'] as num?)?.toInt() ?? 0,
          replies: _parseReplies(m['replies']),
        ),
      );
    }
    return out;
  }

  String? _uidCache;

  /// 当前登录用户的 id（「仅我的发言」筛选要用）。
  Future<String> currentUserId() async {
    final cached = _uidCache;
    if (cached != null) return cached;
    try {
      final resp = await client.getApi(Uri.parse('$_base/user/index'));
      final uid =
          RegExp(r'id="userId"[^>]*value="([^"]+)"')
              .firstMatch(resp.data ?? '')
              ?.group(1) ??
          '';
      _uidCache = uid;
      return uid;
    } catch (_) {
      return '';
    }
  }

  /// 发一条新话题。
  ///
  /// 学习通发帖不是往活动路径 POST，而是 `POST /api/topics`，
  /// 并且必须带 `category_id`——分类要先从
  /// `GET /api/courses/{courseId}/topic-categories` 里按活动 id 查出来。
  Future<void> createTopic({
    required String courseId,
    required String activityId,
    required String title,
    required String content,
  }) async {
    final categoryId = await _categoryIdFor(courseId, activityId);
    if (categoryId == null) {
      throw Exception('没有找到这个讨论的分类');
    }
    final resp = await client.sendJson(
      Uri.parse('$_base/api/topics'),
      data: <String, dynamic>{
        'category_id': categoryId,
        'title': title,
        'content': content,
      },
    );
    final code = resp.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw Exception('发言失败（HTTP $code）');
    }
  }

  Future<int?> _categoryIdFor(String courseId, String activityId) async {
    final resp = await client.getApi(
      Uri.parse('$_base/api/courses/$courseId/topic-categories'),
    );
    final map = _json(resp.data);
    for (final item in (map['topic_categories'] as List?) ?? const []) {
      if (item is! Map) continue;
      final activity = item['activity'];
      if (activity is! Map) continue;
      if ('${activity['id']}' != activityId) continue;
      final raw = item['id'];
      return raw is num ? raw.toInt() : int.tryParse('$raw');
    }
    return null;
  }

  static List<TronForumReply> _parseReplies(Object? raw) {
    if (raw is! List) return const <TronForumReply>[];
    final out = <TronForumReply>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();
      final content = _plain((m['content'] ?? '').toString());
      if (content.isEmpty) continue;
      out.add(
        TronForumReply(
          author: ((m['created_by'] as Map?)?['name'] ?? '').toString().trim(),
          content: content,
          createdAt: _date((m['created_at'] ?? '').toString()),
        ),
      );
    }
    return out;
  }

  static Map<String, dynamic> _json(String? raw) {
    final text = (raw ?? '').trim();
    if (!text.startsWith('{')) return <String, dynamic>{};
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}');
  }

  static String _plain(String html) {
    if (html.isEmpty) return '';
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
