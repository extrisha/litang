import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../auth/cas_client.dart';

/// 学习通课程。
class ChaoxingCourse {
  const ChaoxingCourse({
    required this.courseId,
    required this.classId,
    required this.cpi,
    required this.name,
    this.teacher = '',
  });

  final String courseId;
  final String classId;
  final String cpi;
  final String name;
  final String teacher;

  Map<String, dynamic> toCacheJson() => <String, dynamic>{
    'courseId': courseId,
    'classId': classId,
    'cpi': cpi,
    'name': name,
    'teacher': teacher,
  };

  static ChaoxingCourse? fromCacheJson(Map<String, dynamic> json) {
    final id = (json['courseId'] ?? '').toString();
    final classId = (json['classId'] ?? '').toString();
    if (id.isEmpty || classId.isEmpty) return null;
    return ChaoxingCourse(
      courseId: id,
      classId: classId,
      cpi: (json['cpi'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      teacher: (json['teacher'] ?? '').toString(),
    );
  }
}

/// 学习通活动（签到等）。
class ChaoxingActivity {
  const ChaoxingActivity({
    required this.id,
    required this.name,
    required this.activeType,
    required this.status,
    required this.signCode,
    required this.courseName,
    required this.courseId,
    required this.classId,
  });

  final String id;
  final String name;
  final String activeType;
  final int status;
  final String signCode;
  final String courseName;
  final String courseId;
  final String classId;

  Map<String, dynamic> toCacheJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'activeType': activeType,
    'status': status,
    'signCode': signCode,
    'courseName': courseName,
    'courseId': courseId,
    'classId': classId,
  };

  static ChaoxingActivity? fromCacheJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    if (id.isEmpty) return null;
    return ChaoxingActivity(
      id: id,
      name: (json['name'] ?? '').toString(),
      activeType: (json['activeType'] ?? '').toString(),
      status: (json['status'] as num?)?.toInt() ?? 0,
      signCode: (json['signCode'] ?? '').toString(),
      courseName: (json['courseName'] ?? '').toString(),
      courseId: (json['courseId'] ?? '').toString(),
      classId: (json['classId'] ?? '').toString(),
    );
  }

  String get typeLabel {
    if (name.contains('签到') || activeType.contains('sign')) return '签到';
    if (activeType.contains('task')) return '任务';
    return '活动';
  }
}

/// 学习通作业。
class ChaoxingWork {
  const ChaoxingWork({
    required this.workId,
    required this.title,
    required this.courseName,
    required this.statusText,
    required this.deadline,
    required this.expired,
    required this.taskUrl,
    this.score = '',
  });

  final String workId;
  final String title;
  final String courseName;
  final String statusText;
  final String deadline;

  /// 页面用灰色图标（icon-zy-g）标记的已截止作业。
  final bool expired;

  /// 作业作答页地址（已带 enc，可直接用 WebView 打开）。
  final String taskUrl;

  /// 批阅后的分数；没批阅时为空（列表页本身不带分数，要进详情页才有）。
  final String score;

  Map<String, dynamic> toCacheJson() => <String, dynamic>{
    'workId': workId,
    'title': title,
    'courseName': courseName,
    'statusText': statusText,
    'deadline': deadline,
    'expired': expired,
    'taskUrl': taskUrl,
    'score': score,
  };

  static ChaoxingWork? fromCacheJson(Map<String, dynamic> json) {
    final id = (json['workId'] ?? '').toString();
    if (id.isEmpty) return null;
    return ChaoxingWork(
      workId: id,
      title: (json['title'] ?? '').toString(),
      courseName: (json['courseName'] ?? '').toString(),
      statusText: (json['statusText'] ?? '').toString(),
      deadline: (json['deadline'] ?? '').toString(),
      expired: json['expired'] == true,
      taskUrl: (json['taskUrl'] ?? '').toString(),
      score: (json['score'] ?? '').toString(),
    );
  }

  bool get finished =>
      statusText.contains('已交') ||
      statusText.contains('已完成') ||
      statusText.contains('已批阅') ||
      statusText.contains('待批阅') ||
      statusText.contains('已提交');

  ChaoxingWork withScore(String value) => ChaoxingWork(
    workId: workId,
    title: title,
    courseName: courseName,
    statusText: statusText,
    deadline: deadline,
    expired: expired,
    taskUrl: taskUrl,
    score: value,
  );
}

/// 学习通提交附件。
class ChaoxingAttachment {
  const ChaoxingAttachment({
    required this.name,
    required this.bytes,
    required this.isVideo,
    this.isFile = false,
  });

  final String name;
  final List<int> bytes;
  final bool isVideo;
  final bool isFile;
}

/// 学习通作业中的一道题。
class ChaoxingQuestion {
  const ChaoxingQuestion({
    required this.id,
    required this.answerType,
    required this.type,
    required this.text,
  });

  final String id;
  final String answerType;
  final String type;
  final String text;
}

/// 学习通作业详情（原生解析）。
class ChaoxingWorkDetail {
  const ChaoxingWorkDetail({
    required this.title,
    required this.info,
    required this.questions,
    required this.answerText,
    required this.answerImages,
    required this.answerFiles,
  });

  final String title;
  final String info;
  final List<ChaoxingQuestion> questions;
  final String answerText;
  final List<String> answerImages;
  final List<String> answerFiles;

  bool get hasAnswer =>
      answerText.isNotEmpty ||
      answerImages.isNotEmpty ||
      answerFiles.isNotEmpty;
}

/// 学习通客户端：登录、课程、活动、作业。
class ChaoxingClient {
  ChaoxingClient({
    Dio? dio,
    List<CasCookie> initialCookies = const <CasCookie>[],
  }) : _dio = dio ?? _buildDio() {
    jar.cookies.addAll(initialCookies);
  }

  /// 登录走内嵌网页（见 `ChaoxingLoginPage`），这里只负责带着 cookie 干活。
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  final Dio _dio;
  final CasCookieJar jar = CasCookieJar();

  static Dio _buildDio() {
    return Dio(
      BaseOptions(
        followRedirects: false,
        validateStatus: (status) => status != null && status < 500,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        responseType: ResponseType.plain,
        headers: <String, String>{'User-Agent': _ua},
      ),
    );
  }

  /// 通用 GET，课程内页接口用。
  Future<Response<dynamic>> getPage(Uri uri, {Map<String, String>? headers}) =>
      _send(uri, headers: headers);

  Future<Response<dynamic>> _send(
    Uri uri, {
    String method = 'GET',
    Map<String, String>? form,
    Map<String, String>? headers,
  }) async {
    var current = uri;
    var currentMethod = method;
    var currentForm = form;
    for (var hop = 0; hop < 6; hop++) {
      // 调用方传入的请求头（Referer / Accept 等）每次跳转都要带上。
      // 注意：这里不能再用 headers 命名局部变量，否则会把同名参数遮住，
      // 导致传进来的 Referer 被静默丢弃（老 bug）。
      final requestHeaders = <String, String>{...?headers};
      final cookie = jar.headerFor(current);
      if (cookie != null && cookie.isNotEmpty) {
        requestHeaders['Cookie'] = cookie;
      }
      final body = currentForm?.entries
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
          )
          .join('&');
      final response = await _dio.requestUri<dynamic>(
        current,
        data: body,
        options: Options(
          method: currentMethod,
          headers: requestHeaders,
          contentType: currentForm == null
              ? null
              : Headers.formUrlEncodedContentType,
        ),
      );
      final setCookie = response.headers['set-cookie'];
      if (setCookie != null) {
        for (final line in setCookie) {
          jar.absorbSetCookie(current, line);
        }
      }
      final status = response.statusCode ?? 0;
      final location = response.headers.value('location');
      if ((status == 301 ||
              status == 302 ||
              status == 303 ||
              status == 307 ||
              status == 308) &&
          location != null &&
          location.isNotEmpty) {
        current = current.resolve(location);
        if (status == 303 || (status == 302 && currentMethod == 'POST')) {
          currentMethod = 'GET';
          currentForm = null;
        }
        continue;
      }
      return response;
    }
    throw Exception('登录跳转次数过多，请稍后重试');
  }

  /// 检查当前 cookie 是否仍有效。
  Future<bool> checkSession() async {
    try {
      final response = await _send(Uri.parse('https://i.chaoxing.com/base'));
      final body = (response.data as String?) ?? '';
      final url = response.realUri.toString();
      return response.statusCode == 200 &&
          !url.contains('passport2') &&
          !body.contains('用户登录');
    } catch (_) {
      return false;
    }
  }

  String get _fid {
    for (final cookie in jar.cookies) {
      if (cookie.name == 'fid' && cookie.value.isNotEmpty) {
        return cookie.value;
      }
    }
    return '24960';
  }

  /// 我的课程。
  Future<List<ChaoxingCourse>> fetchCourses() async {
    final response = await _send(
      Uri.parse(
        'https://mooc1-1.chaoxing.com/visit/courselistdata?courseType=1&isActive=1',
      ),
    );
    final html = (response.data as String?) ?? '';
    final courses = <ChaoxingCourse>[];
    final startRe = RegExp(
      r'<li[^>]*courseId="(\d+)"[^>]*clazzId="(\d+)"[^>]*personId="(\d+)"[^>]*>',
    );
    final starts = startRe.allMatches(html).toList();
    for (var i = 0; i < starts.length; i++) {
      final match = starts[i];
      final bodyEnd = i + 1 < starts.length
          ? starts[i + 1].start
          : (match.end + 4000 < html.length ? match.end + 4000 : html.length);
      final body = html.substring(match.end, bodyEnd);
      final title =
          RegExp(r'title="([^"]+)"').firstMatch(body)?.group(1) ??
          RegExp(r'course-name[^>]*>([^<]+)<').firstMatch(body)?.group(1) ??
          '';
      if (title.isEmpty) continue;
      final teacher =
          RegExp(r'<p[^>]*class="line2"[^>]*title="([^"]*)"')
              .firstMatch(body)
              ?.group(1)
              ?.trim() ??
          '';
      courses.add(
        ChaoxingCourse(
          courseId: match.group(1)!,
          classId: match.group(2)!,
          cpi: match.group(3)!,
          name: title,
          teacher: teacher,
        ),
      );
    }
    return courses;
  }

  /// 各课程进行中的活动（签到）。
  Future<List<ChaoxingActivity>> fetchActivities(List<ChaoxingCourse> courses) {
    return _concurrentMap(courses, (course) async {
      final out = <ChaoxingActivity>[];
      try {
        final uri =
            Uri.parse(
              'https://mobilelearn.chaoxing.com/v2/apis/active/student/activelist',
            ).replace(
              queryParameters: <String, String>{
                'fid': _fid,
                'courseId': course.courseId,
                'classId': course.classId,
                'showNotStartedActive': '1',
              },
            );
        final response = await _send(uri);
        final map = jsonDecode(
          (response.data as String?) ?? '{}',
        ) as Map<String, dynamic>;
        final data = map['data'] as Map<String, dynamic>?;
        final list = (data?['activeList'] as List<dynamic>? ?? <dynamic>[]);
        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          final id = (item['id'] ?? '').toString();
          final status = (item['status'] as num?)?.toInt() ?? 0;
          final activeType = (item['activeType'] ?? '').toString();
          if (id.isEmpty || status != 1 || activeType != '2') continue;
          out.add(
            ChaoxingActivity(
              id: id,
              name: (item['name'] ?? item['content'] ?? '签到').toString(),
              activeType: activeType,
              status: status,
              signCode: (item['signCode'] ?? '').toString(),
              courseName: course.name,
              courseId: course.courseId,
              classId: course.classId,
            ),
          );
        }
      } catch (_) {
        // 单门课失败不影响其他课程
      }
      return out;
    });
  }

  /// 各课程作业列表。
  Future<List<ChaoxingWork>> fetchWorks(List<ChaoxingCourse> courses) {
    return _concurrentMap(courses, (course) async {
      final out = <ChaoxingWork>[];
      try {
        final middle = await _send(
          Uri.parse(
            'https://mooc1-1.chaoxing.com/mooc-ans/visit/stucoursemiddle'
            '?courseid=${course.courseId}&clazzid=${course.classId}'
            '&vc=1&cpi=${course.cpi}&ismooc2=1&v=2',
          ),
        );
        final middleHtml = (middle.data as String?) ?? '';
        final workEnc = _hidden(middleHtml, 'workEnc') ?? '';
        if (workEnc.isEmpty) return out;
        final list = await _send(
          Uri.parse(
            'https://mooc1.chaoxing.com/mooc2/work/list'
            '?courseId=${course.courseId}&classId=${course.classId}'
            '&enc=$workEnc&cpi=${course.cpi}&ut=s',
          ),
        );
        final html = (list.data as String?) ?? '';
        final itemRe = RegExp(
          r'<li[^>]*onclick="goTask\(this\);"[^>]*data="([^"]+)"[^>]*>(.*?)</li>',
          dotAll: true,
        );
        for (final match in itemRe.allMatches(html)) {
          final dataUrl = match.group(1) ?? '';
          final workId =
              RegExp(r'workId=(\d+)').firstMatch(dataUrl)?.group(1) ?? '';
          if (workId.isEmpty) continue;
          final body = match.group(2) ?? '';
          final title =
              RegExp(r'class="overHidden2[^"]*"[^>]*>([^<]+)<')
                  .firstMatch(body)
                  ?.group(1)
                  ?.trim() ??
              '作业';
          final status =
              RegExp(r'class="status[^"]*"[^>]*>([^<]+)<')
                  .firstMatch(body)
                  ?.group(1)
                  ?.trim() ??
              '';
          final timeText =
              RegExp(r'class="time[^"]*"[^>]*>(.*?)</div>', dotAll: true)
                  .firstMatch(body)
                  ?.group(1)
                  ?.replaceAll(RegExp(r'<[^>]+>'), '')
                  .trim() ??
              '';
          out.add(
            ChaoxingWork(
              workId: workId,
              title: title,
              courseName: course.name,
              statusText: status,
              deadline: timeText,
              expired: body.contains('icon-zy-g'),
              taskUrl: dataUrl.replaceAll('&amp;', '&'),
            ),
          );
        }
      } catch (_) {
        // 单门课失败不影响其他课程
      }
      return out;
    });
  }

  /// 多门课并发请求；每个 worker 按课程取数据，单门失败只返回空列表。
  Future<List<R>> _concurrentMap<T, R>(
    List<T> items,
    Future<List<R>> Function(T) task, {
    int limit = 4,
  }) async {
    if (items.isEmpty) return <R>[];
    final results = List<List<R>?>.filled(items.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next;
        next++;
        if (index >= items.length) return;
        try {
          results[index] = await task(items[index]);
        } catch (_) {
          results[index] = <R>[];
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(min(limit, items.length), (_) => worker()),
    );
    return <R>[for (final result in results) ...?result];
  }

  /// 已批阅作业的分数；没批阅返回空串。
  ///
  /// 注意别用 `totalScore`：那是「我的答案」里**单题**的得分（经常是 0）。
  /// 页头那个橙色的总分在 `<span class="resultNum"><i>95</i>分</span>` 里。
  Future<String> fetchWorkScore(ChaoxingWork work) async {
    try {
      final response = await _send(Uri.parse(work.taskUrl));
      final html = (response.data as String?) ?? '';
      final match = RegExp(
        r'class="resultNum[^"]*"[^>]*>[\s\S]{0,80}?<i[^>]*>([^<]+)</i>',
      ).firstMatch(html);
      return match?.group(1)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 解析作业作答页，拿到标题、题量/时间、题目文本。
  Future<ChaoxingWorkDetail> fetchWorkDetail(ChaoxingWork work) async {
    final response = await _send(Uri.parse(work.taskUrl));
    final html = (response.data as String?) ?? '';
    final title =
        RegExp(
              r'<h2[^>]*class="[^"]*mark_title[^"]*"[^>]*>(.*?)</h2>',
              dotAll: true,
            )
            .firstMatch(html)
            ?.group(1)
            ?.replaceAll(RegExp(r'<[^>]+>'), '')
            .trim() ??
        work.title;
    final infoBlock = RegExp(
      r'<div[^>]*class="[^"]*infoHead[^"]*"[^>]*>(.*?)</div>',
      dotAll: true,
    ).firstMatch(html)?.group(1);
    final info = infoBlock == null
        ? ''
        : _stripHtml(infoBlock).replaceAll(RegExp(r'\s+'), ' ').trim();

    final questions = <ChaoxingQuestion>[];
    final blockRe = RegExp(r'<div[^>]*class="[^"]*questionLi[^"]*"[^>]*>');
    final starts = blockRe.allMatches(html).toList();
    for (var i = 0; i < starts.length; i++) {
      final start = starts[i];
      final end = i + 1 < starts.length ? starts[i + 1].start : html.length;
      final block = html.substring(start.start, end);
      final qid =
          RegExp(r'id="question(\d+)"').firstMatch(block)?.group(1) ??
          RegExp(r'data="(\d+)"').firstMatch(block)?.group(1) ??
          '';
      if (qid.isEmpty) continue;
      final h3 =
          RegExp(
            r'<h3[^>]*class="[^"]*mark_name[^"]*"[^>]*>(.*?)</h3>',
            dotAll: true,
          ).firstMatch(block)?.group(1) ??
          '';
      final type =
          RegExp(
                r'<span[^>]*class="[^"]*colorShallow[^"]*"[^>]*>(.*?)</span>',
                dotAll: true,
              )
              .firstMatch(h3)
              ?.group(1)
              ?.replaceAll(RegExp(r'<[^>]+>'), '')
              .trim() ??
          '';
      final answerType =
          RegExp('id="answertype$qid"[^>]*value="(\\d+)"')
              .firstMatch(block)
              ?.group(1) ??
          '8';
      final text = _stripHtml(h3)
          .replaceAll(type, '')
          .replaceAll(RegExp(r'^\s*\d+\.\s*'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isNotEmpty) {
        questions.add(
          ChaoxingQuestion(
            id: qid,
            answerType: answerType,
            type: type,
            text: text,
          ),
        );
      }
    }
    final answer = _parseAnswer(html);
    return ChaoxingWorkDetail(
      title: title,
      info: info,
      questions: questions,
      answerText: answer.$1,
      answerImages: answer.$2,
      answerFiles: answer.$3,
    );
  }

  /// 从作答页 `textarea#answer<id>` 中提取历史提交。
  static (String, List<String>, List<String>) _parseAnswer(String html) {
    final texts = <String>[];
    final images = <String>[];
    final files = <String>[];
    final re = RegExp(
      r'<textarea[^>]*id="answer(\d+)"[^>]*>(.*?)</textarea>',
      dotAll: true,
    );
    final sources = <String>[
      for (final match in re.allMatches(html)) match.group(2) ?? '',
    ];
    // 解剖学等课程的历史作答在 stuAnswer 容器里，而不是 textarea。
    // doingWork 页用 textarea#answer<id>；
    // viewWork 查看页没有编辑器，答案在 .stuAnswerContent 里。
    final answerDiv = RegExp(
      r'<div[^>]*class="[^"]*(?:stuAnswerContent|stuAnswer|studentAnswer)[^"]*"[^>]*>(.*?)</div>',
      dotAll: true,
    );
    for (final match in answerDiv.allMatches(html)) {
      sources.add(match.group(1) ?? '');
    }
    for (var raw in sources) {
      raw = raw
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&nbsp;', ' ');
      for (final img in RegExp(
        r'''<img[^>]+src=["']([^"']+)["']''',
        caseSensitive: false,
      ).allMatches(raw)) {
        final src = img.group(1)!.trim();
        if (src.isNotEmpty && !images.contains(src)) images.add(src);
      }
      for (final link in RegExp(
        r'''<a[^>]+href=["']([^"']+)["']''',
        caseSensitive: false,
      ).allMatches(raw)) {
        final href = link.group(1)!.trim();
        if (href.isEmpty) continue;
        final lower = href.toLowerCase();
        if (lower.contains('/upload') ||
            lower.endsWith('.pdf') ||
            lower.endsWith('.doc') ||
            lower.endsWith('.docx') ||
            lower.endsWith('.ppt') ||
            lower.endsWith('.pptx')) {
          if (!files.contains(href)) files.add(href);
        }
      }
      final text = _stripHtml(
        raw
            .replaceAll(RegExp(r'<img[^>]*>', caseSensitive: false), '')
            .replaceAll(RegExp(r'<video[^>]*>.*?</video>', dotAll: true), '')
            .replaceAll(RegExp(r'<a[^>]*>(.*?)</a>', dotAll: true), r'$1'),
      ).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isNotEmpty) texts.add(text);
    }
    // viewWork 的 .stuAnswerContent 里经常有嵌套 div，正则可能截断；
    // 这里再兜底抓答案区常见的 ans-ued-img 图片。
    if (images.isEmpty) {
      for (final tag in RegExp(
        r'<img[^>]+>',
        caseSensitive: false,
      ).allMatches(html)) {
        final raw = tag.group(0)!;
        if (!raw.contains('ans-ued-img') &&
            !raw.contains('/star4/') &&
            !raw.contains('/star3/750_1024')) {
          continue;
        }
        final src = RegExp(
          r'''src=["']([^"']+)["']''',
          caseSensitive: false,
        ).firstMatch(raw)?.group(1);
        if (src != null && src.isNotEmpty && !images.contains(src)) {
          images.add(src);
        }
      }
    }
    return (texts.join('\n'), images, files);
  }

  static String _stripHtml(String raw) {
    return raw
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .trim();
  }

  /// 上传作业图片，返回可插入答案的图片 URL。
  Future<Uri> uploadWorkImage(
    ChaoxingWork work,
    String filename,
    List<int> bytes,
  ) async {
    final page = await _send(Uri.parse(work.taskUrl));
    final html = (page.data as String?) ?? '';
    final uid =
        RegExp("window\\[\"uid\"\\] = '(\\d+)'").firstMatch(html)?.group(1) ??
        '';
    final timestamp =
        RegExp("window\\[\"currentTime\"\\] = '(\\d+)'")
            .firstMatch(html)
            ?.group(1) ??
        '';
    final uploadEnc =
        RegExp("window\\[\"uploadEnc\"\\] = '([^']+)'")
            .firstMatch(html)
            ?.group(1) ??
        '';
    if (uid.isEmpty || timestamp.isEmpty || uploadEnc.isEmpty) {
      throw Exception('学习通上传参数解析失败');
    }
    final uri =
        Uri.parse('https://mooc1.chaoxing.com/upload-ans/ueditorupload/upload')
            .replace(
              queryParameters: <String, String>{
                't': timestamp,
                'enc2': uploadEnc,
                'uid': uid,
                'uploadtype': 'work',
              },
            );
    final cookie = jar.headerFor(uri);
    final form = FormData();
    form.files.add(
      MapEntry('upfile', MultipartFile.fromBytes(bytes, filename: filename)),
    );
    final response = await _dio.postUri<dynamic>(
      uri,
      data: form,
      options: Options(
        contentType: 'multipart/form-data',
        headers: <String, String>{'Referer': work.taskUrl, 'Cookie': ?cookie},
      ),
    );
    final raw = (response.data as String?) ?? '';
    final map = jsonDecode(raw) as Map<String, dynamic>?;
    final url = (map?['url'] ?? '').toString();
    if (map?['state'] != 'SUCCESS' || url.isEmpty) {
      throw Exception('图片上传失败');
    }
    return Uri.parse(url);
  }

  /// 提交作业（文字 + 图片/视频附件）。
  Future<void> submitWorkContent(
    ChaoxingWork work,
    ChaoxingQuestion question, {
    String text = '',
    List<ChaoxingAttachment> attachments = const <ChaoxingAttachment>[],
  }) async {
    final buffer = StringBuffer();
    if (text.trim().isNotEmpty) {
      for (final line in text.trim().split('\n')) {
        final safe = line
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;');
        buffer.write('<p>$safe</p>');
      }
    }
    for (final attachment in attachments) {
      final url = await uploadWorkImage(
        work,
        attachment.name,
        attachment.bytes,
      );
      if (attachment.isVideo) {
        buffer.write('<p><video controls="controls" src="$url"></video></p>');
      } else if (attachment.isFile) {
        final safe = attachment.name
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;');
        buffer.write('<p><a href="$url" target="_blank">$safe</a></p>');
      } else {
        buffer.write('<p><img src="$url" /></p>');
      }
    }
    await _submitAnswerHtml(work, question, buffer.toString());
  }

  Future<void> _submitAnswerHtml(
    ChaoxingWork work,
    ChaoxingQuestion question,
    String answerHtml,
  ) async {
    final page = await _send(Uri.parse(work.taskUrl));
    final html = (page.data as String?) ?? '';
    final action =
        RegExp(r'<form[a-zA-Z0-9_ ="\-]*action="([^"]+)"')
            .firstMatch(html)
            ?.group(1)
            ?.replaceAll('&amp;', '&') ??
        '';
    if (action.isEmpty) {
      throw Exception('未找到作业提交入口');
    }
    final fields = <String, String>{};
    for (final match in RegExp(
      r'<input[^>]*name="([^"]+)"[^>]*value="([^"]*)"',
    ).allMatches(html)) {
      fields[match.group(1)!] = match.group(2) ?? '';
    }
    fields['answerwqbid'] = question.id;
    fields['answertype${question.id}'] = question.answerType;
    fields['answer${question.id}'] = answerHtml;

    final resp = await _send(
      Uri.parse('https://mooc1.chaoxing.com$action'),
      method: 'POST',
      form: fields,
    );
    final raw = (resp.data as String?) ?? '';
    Map<String, dynamic>? map;
    try {
      map = jsonDecode(raw) as Map<String, dynamic>?;
    } catch (_) {
      map = null;
    }
    if (map == null || map['status'] != true) {
      throw Exception('作业提交失败：${map?['msg'] ?? '未知错误'}');
    }
  }

  static String? _hidden(String html, String id) {
    final forward = RegExp('id="$id"[^>]*value="([^"]*)"')
        .firstMatch(html)
        ?.group(1);
    if (forward != null) return forward;
    return RegExp('value="([^"]*)"[^>]*id="$id"').firstMatch(html)?.group(1);
  }
}
