import 'dart:convert';

import '../bounded_requests.dart';

import '../app_exception.dart';
import 'chaoxing_client.dart';

/// 学习通课程章节。
class ChaoxingChapter {
  const ChaoxingChapter({
    required this.id,
    required this.title,
    required this.number,
    required this.completed,
  });

  final String id;
  final String title;
  final String number;
  final bool completed;
}

class ChaoxingChapterUnit {
  const ChaoxingChapterUnit({required this.title, required this.chapters});

  final String title;
  final List<ChaoxingChapter> chapters;
}

class ChaoxingCourseAttachment {
  const ChaoxingCourseAttachment({
    required this.objectId,
    required this.name,
    required this.size,
    this.isVideo = false,
  });

  final String objectId;
  final String name;
  final int size;

  /// cards 页里 attachment.type == 'video'。
  /// 视频的扩展名五花八门（flv/wmv/avi/rmvb/mpg/mp4），
  /// 靠后缀判断容易漏，所以让接口直接告诉我们类型。
  final bool isVideo;
}

class ChaoxingYunFile {
  const ChaoxingYunFile({
    required this.pdfUrl,
    required this.downloadUrl,
    required this.streamUrl,
  });

  final String pdfUrl;
  final String downloadUrl;
  final String streamUrl;
}

class ChaoxingExam {
  const ChaoxingExam({
    required this.id,
    required this.title,
    required this.status,
    required this.remaining,
    this.score = '',
    this.analysisUrl = '',
  });

  /// 考试 id（页面里 viewExamAnswer 的第一个参数）。
  final String id;
  final String title;
  final String status;
  final String remaining;
  final String score;

  /// 答卷分析页地址；老师没公布时为空。
  final String analysisUrl;
}

class ChaoxingCourseDetailApi {
  ChaoxingCourseDetailApi(this.client);

  final ChaoxingClient client;

  /// 一个章节里的附件（PPT/文档/视频）。
  Future<List<ChaoxingCourseAttachment>> fetchAttachments(
    ChaoxingCourse course,
    String chapterId,
  ) async {
    final referer =
        'https://mooc1.chaoxing.com/mycourse/studentstudy'
        '?chapterId=$chapterId&courseId=${course.courseId}'
        '&clazzid=${course.classId}&cpi=${course.cpi}&mooc2=1';
    final response = await client.getPage(
      Uri.parse(
        'https://mooc1.chaoxing.com/mooc-ans/knowledge/cards'
        '?clazzid=${course.classId}&courseid=${course.courseId}'
        '&knowledgeid=$chapterId&num=0&ut=s&cpi=${course.cpi}'
        '&mooc2=1&isMicroCourse=false&editorPreview=0&crossId=0',
      ),
      headers: <String, String>{'Referer': referer},
    );
    final html = (response.data as String?) ?? '';
    return parseAttachments(html);
  }

  /// 解析章节附件。
  ///
  /// 真实数据在 cards 页的 `mArg = {...}` JSON 里，形如：
  /// ```
  /// {"attachments":[
  ///   {"type":"document","property":{"objectid":"...","name":"课件.ppt",
  ///    "size":13809152,"type":".ppt","module":"insertdoc"}},
  ///   {"type":"video","property":{"objectid":"...","name":"绪论.flv",
  ///    "size":120341672,"type":".flv","module":"insertvideo"}}
  /// ]}
  /// ```
  /// 实测只有 document / video 两族，元数据都在 `property` 下。
  /// 有的课程章节压根没有 mArg（没上传内容），此时返回空列表。
  static List<ChaoxingCourseAttachment> parseAttachments(String html) {
    final marg = extractMarg(html);
    if (marg == null) return const <ChaoxingCourseAttachment>[];
    final raw = marg['attachments'];
    if (raw is! List) return const <ChaoxingCourseAttachment>[];
    final out = <ChaoxingCourseAttachment>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final property = item['property'];
      // 个别课程可能把字段平铺在顶层，兜一下
      final fields = property is Map ? property : item;
      final objectId = (fields['objectid'] ?? item['objectId'] ?? '')
          .toString();
      final name = (fields['name'] ?? fields['title'] ?? '').toString().trim();
      if (objectId.isEmpty || name.isEmpty) continue;
      out.add(
        ChaoxingCourseAttachment(
          objectId: objectId,
          name: name,
          size: (fields['size'] as num?)?.toInt() ?? 0,
          isVideo: '${item['type']}' == 'video',
        ),
      );
    }
    return out;
  }

  /// 从 cards 页里抠 `mArg = {...}` 这段 JSON。
  ///
  /// 页面里 mArg 经常被赋值多次（先 `mArg = "";`，再赋真正的对象），
  /// 所以按出现顺序逐个尝试。花括号按字符串/转义规则配对，
  /// 避免 JSON 字符串里的花括号把截断点带偏。
  static Map<String, dynamic>? extractMarg(String html) {
    for (final match in RegExp(r'mArg\s*=\s*\{').allMatches(html)) {
      final start = html.indexOf('{', match.start);
      if (start < 0) continue;
      final end = _matchingBrace(html, start);
      if (end < 0) continue;
      try {
        final decoded = jsonDecode(html.substring(start, end + 1));
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        // 这一段不是合法 JSON，继续找下一处赋值
      }
    }
    return null;
  }

  /// 返回与 [openIndex] 处 '{' 配对的 '}' 下标；找不到返回 -1。
  static int _matchingBrace(String text, int openIndex) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = openIndex; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// 学习通云盘转换文件：PPT/DOCX 会返回 PDF 直链。
  Future<ChaoxingYunFile?> fetchYunFile(String objectId) async {
    try {
      final response = await client.getPage(
        Uri.parse(
          'https://contestyd.chaoxing.com/app/files/$objectId/getYunFiles?key=allData',
        ),
        headers: const <String, String>{'Accept': 'application/json'},
      );
      final map = jsonDecode((response.data ?? '').toString()) as Map;
      final data = map['data'];
      if (data is! Map) return null;
      return ChaoxingYunFile(
        pdfUrl: (data['pdf'] ?? '').toString(),
        downloadUrl: (data['download'] ?? '').toString(),
        streamUrl: (data['http'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 学习通考试列表。
  /// 抓回来的页面如果其实是登录页，说明 cookie 已失效。
  ///
  /// 以前这里会正常解析出空列表，页面就显示「暂无考试 / 暂无作业 / 暂无章节」，
  /// 把「登录失效」伪装成「没有内容」——这就是全项目反复出现的
  /// 「取不到 ≠ 没有」。按 `AppException` 契约，这种情况必须抛出来。
  static void _ensureNotLoginPage(String html) {
    if (html.trim().isEmpty) {
      throw const AppException(AppFailure.parse, '学习通返回了空内容，请稍后重试');
    }
    if (html.contains('passport2.chaoxing.com/login') ||
        html.contains('请输入密码') ||
        html.contains('loginForm')) {
      throw const AppException(AppFailure.auth, '学习通登录已失效，请回到「我的」重新登录');
    }
  }

  Future<List<ChaoxingExam>> fetchExams(ChaoxingCourse course) async {
    final response = await client.getPage(
      Uri.parse(
        'https://mooc1.chaoxing.com/mooc-ans/mooc2/exam/exam-list'
        '?courseid=${course.courseId}&clazzid=${course.classId}'
        '&personid=${course.cpi}',
      ),
      headers: <String, String>{
        'Referer':
            'https://mooc1.chaoxing.com/visit/interaction'
            '?courseid=${course.courseId}&clazzid=${course.classId}'
            '&personid=${course.cpi}',
      },
    );
    final html = (response.data as String?) ?? '';
    _ensureNotLoginPage(html);
    return parseExams(html);
  }

  /// 解析考试列表页的 HTML（独立出来便于测试）。
  ///
  /// 每个考试是一个 `<li>`，里面有 `viewExamAnswer('<examId>', ...)`，
  /// 以及「智能分析」链接（stat2-ans 的答卷分析页）。
  static List<ChaoxingExam> parseExams(String html) {
    final out = <ChaoxingExam>[];
    final blocks = RegExp(r'<li>(.*?)</li>', dotAll: true).allMatches(html);
    for (final block in blocks) {
      final body = block.group(1) ?? '';
      if (!body.contains('overHidden2')) continue;
      final title = _strip(
        RegExp(
              r'<p class="overHidden2[^"]*"[^>]*>(.*?)</p>',
              dotAll: true,
            ).firstMatch(body)?.group(1) ??
            '',
      );
      if (title.isEmpty) continue;
      final status = _strip(
        RegExp(
              r'<p class="status[^"]*"[^>]*>(.*?)</p>',
              dotAll: true,
            ).firstMatch(body)?.group(1) ??
            '',
      );
      final remaining =
          RegExp(r'剩余[^<]*').firstMatch(body)?.group(0)?.trim() ?? '';
      final scoreBlock =
          RegExp(
            r'class="numspan"[^>]*>(.*?)</span>',
            dotAll: true,
          ).firstMatch(body)?.group(1) ??
          '';
      final score =
          RegExp(r'\d+(?:\.\d+)?').firstMatch(scoreBlock)?.group(0) ?? '';
      final id =
          RegExp(r"viewExamAnswer\('(\d+)'").firstMatch(body)?.group(1) ??
          RegExp(r"goTest\('[^']*',(\d+)").firstMatch(body)?.group(1) ??
          '';
      final analysisUrl =
          RegExp(r'''href="(https://stat2-ans[^"]+)"''')
              .firstMatch(body)
              ?.group(1)
              ?.replaceAll('&amp;', '&') ??
          '';
      out.add(
        ChaoxingExam(
          id: id,
          title: title,
          status: status,
          remaining: remaining,
          score: score,
          analysisUrl: analysisUrl,
        ),
      );
    }
    return out;
  }

  /// 学习通课程作业。
  ///
  /// [withScores] 为 true 时，会再给「已批阅」的作业各发一次详情请求补分数
  /// （列表页本身没有分数）。并发拉，避免串行。
  Future<List<ChaoxingWork>> fetchHomeworks(
    ChaoxingCourse course, {
    bool withScores = false,
  }) async {
    final works = await client.fetchWorks(<ChaoxingCourse>[course]);
    if (!withScores) return works;
    final targets = <int>[
      for (var i = 0; i < works.length; i++)
        if (_graded(works[i].statusText)) i,
    ];
    if (targets.isEmpty) return works;
    final scores = await mapWithConcurrency(
      targets,
      (i) => client.fetchWorkScore(works[i]),
    );
    final out = List<ChaoxingWork>.of(works);
    for (var k = 0; k < targets.length; k++) {
      if (scores[k].isNotEmpty) {
        out[targets[k]] = out[targets[k]].withScore(scores[k]);
      }
    }
    return out;
  }

  static bool _graded(String status) =>
      status.contains('已完成') || status.contains('已批阅');

  /// 学习通章节列表：来自 mooc2-ans 的 studentcourse iframe。
  Future<List<ChaoxingChapterUnit>> fetchChapters(ChaoxingCourse course) async {
    final referer = Uri.parse(
      'https://mooc1.chaoxing.com/visit/interaction'
      '?courseid=${course.courseId}&clazzid=${course.classId}'
      '&personid=${course.cpi}',
    );
    final url = Uri.parse(
      'https://mooc2-ans.chaoxing.com/mycourse/studentcourse'
      '?courseid=${course.courseId}&clazzid=${course.classId}'
      '&cpi=${course.cpi}&ut=s',
    );
    final response = await client.getPage(
      url,
      headers: <String, String>{'Referer': referer.toString()},
    );
    final html = (response.data as String?) ?? '';
    _ensureNotLoginPage(html);
    final units = <ChaoxingChapterUnit>[];
    final parts = html.split('class="chapter_unit"');
    for (final part in parts.skip(1)) {
      final unitTitle = RegExp(
        r'class="catalog_name[^"]*"[^>]*>.*?<span title="([^"]+)"',
        dotAll: true,
      ).firstMatch(part)?.group(1)?.trim();
      final chapters = <ChaoxingChapter>[];
      final matches = RegExp(
        r'class="chapter_item"[^>]*?id="cur(\d+)"[^>]*?title="([^"]+)"',
        dotAll: true,
      ).allMatches(part).toList();
      for (var i = 0; i < matches.length; i++) {
        final m = matches[i];
        final startAt = m.start;
        final endAt = i + 1 < matches.length
            ? matches[i + 1].start
            : part.length;
        final block = part.substring(startAt, endAt);
        final number =
            RegExp(r'class="catalog_sbar"[^>]*>([^<]+)<')
                .firstMatch(block)
                ?.group(1)
                ?.trim() ??
            '';
        chapters.add(
          ChaoxingChapter(
            id: m.group(1)!,
            title: m.group(2)!.trim(),
            number: number,
            completed: block.contains('icon_yiwanc') || block.contains('已完成'),
          ),
        );
      }
      if (chapters.isEmpty) continue;
      units.add(
        ChaoxingChapterUnit(
          title: unitTitle == null || unitTitle.isEmpty ? '课程章节' : unitTitle,
          chapters: chapters,
        ),
      );
    }
    if (units.isEmpty) {
      final chapters = <ChaoxingChapter>[];
      for (final m in RegExp(
        r'class="chapter_item"[^>]*?id="cur(\d+)"[^>]*?title="([^"]+)"',
        dotAll: true,
      ).allMatches(html)) {
        chapters.add(
          ChaoxingChapter(
            id: m.group(1)!,
            title: m.group(2)!.trim(),
            number: '',
            completed: false,
          ),
        );
      }
      if (chapters.isNotEmpty) {
        units.add(ChaoxingChapterUnit(title: '课程章节', chapters: chapters));
      }
    }
    return units;
  }

  static String _strip(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
