import 'dart:convert';

import '../upload_file.dart';
import '../task_deadline.dart';
import '../bounded_requests.dart';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/cas_client.dart';
import 'chaoxing_html.dart';

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
    this.url = '',
  });

  final String id;
  final String name;
  final String activeType;
  final int status;
  final String signCode;
  final String courseName;
  final String courseId;
  final String classId;

  /// 服务端给的活动页地址。
  ///
  /// 官方客户端对签到活动就是直接打开这个 URL（见 flutter_chaoxing 对
  /// `StudentMission.url` 的说明）。自己拼 `widget/sign/e` 是拼不对的：
  /// 其中的 `c` 是每 10 秒轮换的校验值，不是活动 id。
  final String url;

  Map<String, dynamic> toCacheJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'activeType': activeType,
    'status': status,
    'signCode': signCode,
    'courseName': courseName,
    'courseId': courseId,
    'classId': classId,
    'url': url,
  };

  static ChaoxingActivity? fromCacheJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    if (id.isEmpty) return null;
    return ChaoxingActivity(
      id: id,
      name: (json['name'] ?? '').toString(),
      activeType: (json['activeType'] ?? '').toString(),
      status: (json['status'] is num
          ? (json['status'] as num).toInt()
          : int.tryParse('${json['status'] ?? ''}') ?? 0),
      signCode: (json['signCode'] ?? '').toString(),
      courseName: (json['courseName'] ?? '').toString(),
      courseId: (json['courseId'] ?? '').toString(),
      classId: (json['classId'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
    );
  }

  String get typeLabel {
    if (name.contains('签到') || activeType.contains('sign')) return '签到';
    if (activeType.contains('task')) return '任务';
    return '活动';
  }
}

/// 扫码签到的结果类别。
enum ChaoxingSignStatus {
  /// 本次签到成功
  success,

  /// 之前已经签过（重复扫码）
  alreadySigned,

  /// 签到已结束 / 二维码过期
  ended,

  /// 二维码无效或不是学习通的签到码
  invalid,

  /// 服务端返回了看不懂的内容
  unknown,
}

/// 扫码签到的结果。
class ChaoxingSignResult {
  const ChaoxingSignResult(this.status, this.message);

  final ChaoxingSignStatus status;
  final String message;

  bool get success =>
      status == ChaoxingSignStatus.success ||
      status == ChaoxingSignStatus.alreadySigned;
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
    this.courseId = '',
    this.classId = '',
    this.fetchedAt,
    this.deadlineAt,
  });

  final String workId;
  final String title;
  final String courseName;
  final String statusText;
  final String deadline;
  final String courseId;
  final String classId;
  final DateTime? fetchedAt;
  final DateTime? deadlineAt;

  DateTime? get dueAt =>
      deadlineAt ??
      TaskDeadline.parse(
        deadline,
        now: fetchedAt,
        allowRelative: fetchedAt != null,
      );

  String get courseKey {
    final query =
        Uri.tryParse(taskUrl)?.queryParameters ?? const <String, String>{};
    return '${courseId.isEmpty ? query['courseId'] ?? '' : courseId}:${classId.isEmpty ? query['classId'] ?? query['clazzid'] ?? '' : classId}';
  }

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
    'courseId': courseId,
    'classId': classId,
    'fetchedAt': fetchedAt?.toIso8601String(),
    'deadlineAt': dueAt?.toIso8601String(),
  };

  static ChaoxingWork? fromCacheJson(
    Map<String, dynamic> json, {
    DateTime? fetchedAt,
  }) {
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
      courseId: (json['courseId'] ?? '').toString(),
      classId: (json['classId'] ?? '').toString(),
      fetchedAt: DateTime.tryParse('${json['fetchedAt'] ?? ''}') ?? fetchedAt,
      deadlineAt: DateTime.tryParse('${json['deadlineAt'] ?? ''}'),
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
    courseId: courseId,
    classId: classId,
    fetchedAt: fetchedAt,
    deadlineAt: dueAt,
  );
}

/// 学习通提交附件。
class ChaoxingAttachment {
  const ChaoxingAttachment({
    required this.file,
    required this.isVideo,
    this.isFile = false,
  });

  final UploadFile file;
  String get name => file.name;
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
  ///
  /// 优先走 JSON 接口 `backclazzdata`——它一次就把 courseId / classId / cpi
  /// 全给了（实测结构见 [parseCourseListJson]），不用再靠正则扒 HTML。
  /// JSON 不可用（接口变动、未登录等）时退回解析课程列表页。
  Future<List<ChaoxingCourse>> fetchCourses() async {
    final fromJson = await _fetchCoursesFromJson();
    if (fromJson != null && fromJson.isNotEmpty) {
      return fromJson;
    }
    return _fetchCoursesFromHtml();
  }

  Future<List<ChaoxingCourse>?> _fetchCoursesFromJson() async {
    try {
      final response = await _send(
        Uri.parse(
          'https://mooc1-api.chaoxing.com/mycourse/backclazzdata'
          '?view=json&rss=1',
        ),
      );
      return parseCourseListJson((response.data as String?) ?? '');
    } catch (_) {
      return null;
    }
  }

  /// 解析 `backclazzdata` 的响应。返回 null 表示「结构不认识」，调用方应回退。
  ///
  /// 实测结构（2026-10-28）：
  /// ```json
  /// {"result":1,"channelList":[
  ///   {"key":155660593, "cpi":497874758,
  ///    "content":{"course":{"data":[
  ///       {"id":267465996,"name":"人体解剖学实验","teacherfactor":"王艳"}]}}}]}
  /// ```
  /// - `channel.key`  → classId
  /// - `channel.cpi`  → 该账号的 personId（各 channel 相同）
  /// - `data[].id`    → courseId
  @visibleForTesting
  static List<ChaoxingCourse>? parseCourseListJson(String raw) {
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['result'] != 1) return null;
      final channels = decoded['channelList'];
      if (channels is! List) return null;

      final courses = <ChaoxingCourse>[];
      for (final channel in channels) {
        if (channel is! Map) continue;
        final content = channel['content'];
        if (content is! Map) continue;
        final course = content['course'];
        if (course is! Map) continue;
        final data = course['data'];
        if (data is! List) continue;

        final classId = (channel['key'] ?? '').toString();
        final cpi = (channel['cpi'] ?? '').toString();
        for (final item in data) {
          if (item is! Map) continue;
          final courseId = (item['id'] ?? '').toString();
          final name = (item['name'] ?? '').toString().trim();
          if (courseId.isEmpty || name.isEmpty) continue;
          courses.add(
            ChaoxingCourse(
              courseId: courseId,
              classId: classId,
              cpi: cpi,
              name: name,
              teacher: (item['teacherfactor'] ?? '').toString().trim(),
            ),
          );
        }
      }
      return courses;
    } catch (_) {
      return null;
    }
  }

  Future<List<ChaoxingCourse>> _fetchCoursesFromHtml() async {
    final response = await _send(
      Uri.parse(
        'https://mooc1-1.chaoxing.com/visit/courselistdata?courseType=1&isActive=1',
      ),
    );
    final html = (response.data as String?) ?? '';

    // 1) DOM 解析（同时兼容 `<li courseId>` 和 `stucoursemiddle?courseid=` 两种模板）
    final domRows = ChaoxingHtml.courseRows(html);
    if (domRows.isNotEmpty) {
      return <ChaoxingCourse>[
        for (final row in domRows)
          ChaoxingCourse(
            courseId: row.courseId,
            classId: row.classId,
            cpi: row.cpi,
            name: row.name,
            teacher: row.teacher,
          ),
      ];
    }

    // 2) 正则兜底
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
    // 同一门课会出现两次（课程名入口 + 教师名入口），按 courseId+classId 去重
    final seen = <String>{};
    return <ChaoxingCourse>[
      for (final course in courses)
        if (seen.add('${course.courseId}:${course.classId}')) course,
    ];
  }

  /// 各课程进行中的活动（签到）。
  Future<List<ChaoxingActivity>> fetchActivities(
    List<ChaoxingCourse> courses,
  ) async => (await fetchActivitiesBatch(courses)).requireComplete();

  Future<CourseBatch<ChaoxingActivity>> fetchActivitiesBatch(
    List<ChaoxingCourse> courses,
  ) => CourseBatch.fetch(
    courses,
    key: (c) => '${c.courseId}:${c.classId}',
    name: (c) => c.name,
    task: (course) async {
      final uri =
          Uri.parse(
            'https://mobilelearn.chaoxing.com/v2/apis/active/student/activelist',
          ).replace(
            queryParameters: {
              'fid': _fid,
              'courseId': course.courseId,
              'classId': course.classId,
              'showNotStartedActive': '1',
            },
          );
      final response = await _send(
        uri,
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'Referer': 'https://i.chaoxing.com/',
        },
      );
      final raw = (response.data as String?) ?? '';
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['result'] == 0 ||
          decoded['result'] == false) {
        throw StateError('活动响应无效');
      }
      final data = decoded['data'];
      final list =
          (data is Map ? data['activeList'] : null) ?? decoded['activeList'];
      if (list is! List) throw StateError('活动列表缺失');
      return parseActivities(raw, course);
    },
  );

  /// 解析 activelist 响应（公开以便单测）。
  ///
  /// 常见结构是 `{result:1, data:{activeList:[...]}}`，但部分版本把
  /// `activeList` 放在顶层，所以两种都兼容。`activeType == 2` 是签到，
  /// `status == 1` 是进行中；`url` 是官方客户端打开的签到页地址。
  @visibleForTesting
  static List<ChaoxingActivity> parseActivities(
    String raw,
    ChaoxingCourse course,
  ) {
    final text = raw.trim();
    if (text.isEmpty || text.startsWith('<')) {
      return const <ChaoxingActivity>[];
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return const <ChaoxingActivity>[];
      }
      final data = decoded['data'];
      final list =
          (data is Map ? data['activeList'] : null) ??
          decoded['activeList'] ??
          <dynamic>[];
      final out = <ChaoxingActivity>[];
      for (final item in list) {
        if (item is! Map) continue;
        final id = (item['id'] ?? '').toString();
        final rawStatus = item['status'];
        final status = rawStatus is num
            ? rawStatus.toInt()
            : int.tryParse('$rawStatus') ?? 0;
        final activeType = (item['activeType'] ?? '').toString();
        if (id.isEmpty || status != 1 || activeType != '2') continue;
        out.add(
          ChaoxingActivity(
            id: id,
            name: (item['name'] ?? item['nameOne'] ?? item['content'] ?? '签到')
                .toString(),
            activeType: activeType,
            status: status,
            signCode: (item['signCode'] ?? '').toString(),
            courseName: course.name,
            courseId: course.courseId,
            classId: course.classId,
            // 官方客户端打开的就是这个地址；二维码/拍照等各签到形态都靠它。
            url: (item['url'] ?? '').toString(),
          ),
        );
      }
      return out;
    } catch (_) {
      return const <ChaoxingActivity>[];
    }
  }

  /// 扫码签到。
  ///
  /// 老师屏幕上那张二维码编码的是：
  /// `https://mobilelearn.chaoxing.com/widget/sign/e?id=<activeId>&c=<activeId>&enc=<...>`
  ///
  /// 关键点：**带会话直接 GET 这个地址就会完成签到**，不是"先查询再提交"。
  /// 实测（2026-10-28）已签过的账号再用同一链接请求，服务端返回
  /// 「签到结果 / 签到成功 / 10-28 09:48」——即回显那次签到的时间。
  ///
  /// 另外服务端会看 UA：桌面浏览器 UA 只会得到「请使用客户端进行扫码签到」，
  /// 所以这里必须伪装成学习通客户端。
  /// 校验二维码 URL 是否合法且属于超星签到服务。
  @visibleForTesting
  static bool isValidSignQrUrl(Uri uri) {
    if (!uri.hasScheme) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') return false;
    final host = uri.host.toLowerCase();
    final isChaoxingHost =
        host == 'chaoxing.com' || host.endsWith('.chaoxing.com');
    if (!isChaoxingHost) return false;
    if (!uri.path.contains('/widget/sign/')) return false;
    return uri.queryParameters.containsKey('enc');
  }

  Future<ChaoxingSignResult> signByQr(String raw) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme) {
      return const ChaoxingSignResult(ChaoxingSignStatus.invalid, '不是有效的二维码');
    }
    final host = uri.host.toLowerCase();
    final isChaoxingHost =
        host == 'chaoxing.com' || host.endsWith('.chaoxing.com');
    if (!isChaoxingHost || !uri.path.contains('/widget/sign/')) {
      return const ChaoxingSignResult(
        ChaoxingSignStatus.invalid,
        '这不是学习通的签到二维码',
      );
    }
    final params = uri.queryParameters;
    final activeId = (params['id'] ?? params['activeId'] ?? '').trim();
    final enc = (params['enc'] ?? '').trim();
    if (activeId.isEmpty) {
      return const ChaoxingSignResult(
        ChaoxingSignStatus.invalid,
        '二维码里没有签到活动 ID',
      );
    }
    if (enc.isEmpty) {
      return const ChaoxingSignResult(
        ChaoxingSignStatus.invalid,
        '二维码缺少 enc 参数',
      );
    }

    // 第一步：调 H5 页面真正使用的提交接口。
    // 只 GET 二维码地址往往只是打开「签到结果」页，并没有提交签到；
    // 之前把已签到账号的页面回显误当成「扫码成功」，正常账号反而签不上。
    final ajax = await _answerQrByAjax(activeId, enc);
    if (ajax != null && ajax.success) {
      return ajax;
    }

    // 第二步：/pptSign 不认（缺 uid、接口改版等）时，退回打开二维码页面，
    // 交给服务端页面自己处理，至少不把原来能用的路径弄坏。
    final response = await _send(
      uri,
      headers: <String, String>{
        'User-Agent': _mobileUa,
        'Referer': 'https://mobilelearn.chaoxing.com/',
      },
    );
    final page = parseSignResult((response.data as String?) ?? '');
    if (ajax != null && page.status == ChaoxingSignStatus.unknown) {
      // 页面也看不出结果时，用 ajax 的具体错误提示，别只报「结果未知」。
      return ajax;
    }
    return page;
  }

  /// 学习通 H5 二维码签到的提交接口。
  ///
  /// 抓包得到的地址是 `pptSign/stuSignajax?enc=...&activeId=...&uid=...&fid=...`，
  /// 二维码里的 `enc` 才是核心密钥；只打开页面不算签到。
  Future<ChaoxingSignResult?> _answerQrByAjax(
    String activeId,
    String enc,
  ) async {
    final uid = _cookieValue('_uid').isNotEmpty
        ? _cookieValue('_uid')
        : _cookieValue('UID');
    if (uid.isEmpty) {
      // 没有 uid 说明 cookie 不完整，交给页面路径。
      return null;
    }
    final uri =
        Uri.parse('https://mobilelearn.chaoxing.com/pptSign/stuSignajax')
            .replace(
              queryParameters: <String, String>{
                'enc': enc,
                'activeId': activeId,
                'uid': uid,
                'fid': _fid,
                'name': '',
                'clientip': '',
                'useragent': '',
                'latitude': '-1',
                'longitude': '-1',
                'appType': '15',
              },
            );
    try {
      final response = await _send(
        uri,
        headers: <String, String>{
          'User-Agent': _mobileUa,
          'Referer': 'https://mobilelearn.chaoxing.com/',
        },
      );
      return parseAjaxSignResult((response.data as String?) ?? '');
    } catch (_) {
      return null;
    }
  }

  String _cookieValue(String name) {
    for (final cookie in jar.cookies) {
      if (cookie.name == name && cookie.value.isNotEmpty) {
        return cookie.value;
      }
    }
    return '';
  }

  /// 学习通客户端的 UA——服务端据此判断是不是 App 在请求。
  static const String _mobileUa =
      'Dalvik/2.1.0 (Linux; U; Android 14; 23127PN0CC) (CHAOXING/6.5.0)';

  /// 解析 `stuSignajax` 的纯文本响应（公开以便单测）。
  ///
  /// 成功时服务端直接回 `success` / `success2`，失败则是
  /// 「签到已结束」「您已签到」「不在签到范围」这类中文短句。
  @visibleForTesting
  static ChaoxingSignResult parseAjaxSignResult(String body) {
    final text = body
        .replaceAll(RegExp(r'<script[\s\S]*?</script>'), ' ')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>'), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) {
      return const ChaoxingSignResult(ChaoxingSignStatus.unknown, '服务端没有返回内容');
    }
    final lower = text.toLowerCase();
    if (lower == 'success' ||
        lower == 'success2' ||
        text.contains('签到成功') ||
        lower.contains('"status":true')) {
      return const ChaoxingSignResult(ChaoxingSignStatus.success, '签到成功');
    }
    if (text.contains('已签到') || text.contains('已经签到')) {
      return const ChaoxingSignResult(
        ChaoxingSignStatus.alreadySigned,
        '已经签过到了',
      );
    }
    if (text.contains('结束') || text.contains('过期') || text.contains('超时')) {
      return const ChaoxingSignResult(ChaoxingSignStatus.ended, '签到已结束');
    }
    if (text.contains('无效') ||
        text.contains('不存在') ||
        text.contains('失败') ||
        text.contains('不在签到范围') ||
        text.contains('距离')) {
      return ChaoxingSignResult(
        ChaoxingSignStatus.invalid,
        text.length > 40 ? text.substring(0, 40) : text,
      );
    }
    if (text.contains('请使用客户端')) {
      return const ChaoxingSignResult(
        ChaoxingSignStatus.unknown,
        '服务端没认出客户端身份，请重试',
      );
    }
    return ChaoxingSignResult(
      ChaoxingSignStatus.unknown,
      text.length > 40 ? text.substring(0, 40) : '签到结果未知',
    );
  }

  /// 解析签到结果页（公开以便单测）。
  @visibleForTesting
  static ChaoxingSignResult parseSignResult(String html) {
    if (html.isEmpty) {
      return const ChaoxingSignResult(ChaoxingSignStatus.unknown, '服务端没有返回内容');
    }
    final text = html
        .replaceAll(RegExp(r'<script[\s\S]*?</script>'), ' ')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>'), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.contains('签到成功')) {
      return ChaoxingSignResult(ChaoxingSignStatus.success, '签到成功');
    }
    if (text.contains('已签到') || text.contains('已经签到')) {
      return const ChaoxingSignResult(
        ChaoxingSignStatus.alreadySigned,
        '已经签过到了',
      );
    }
    if (text.contains('结束') || text.contains('过期') || text.contains('超时')) {
      return const ChaoxingSignResult(ChaoxingSignStatus.ended, '签到已结束');
    }
    if (text.contains('无效') || text.contains('不存在') || text.contains('失败')) {
      return ChaoxingSignResult(
        ChaoxingSignStatus.invalid,
        text.length > 40 ? text.substring(0, 40) : text,
      );
    }
    if (text.contains('请使用客户端')) {
      return const ChaoxingSignResult(
        ChaoxingSignStatus.unknown,
        '服务端没认出客户端身份，请重试',
      );
    }
    return ChaoxingSignResult(
      ChaoxingSignStatus.unknown,
      text.length > 40 ? text.substring(0, 40) : '签到结果未知',
    );
  }

  /// 各课程作业列表。
  Future<List<ChaoxingWork>> fetchWorks(List<ChaoxingCourse> courses) async =>
      (await fetchWorksBatch(courses)).requireComplete();

  Future<CourseBatch<ChaoxingWork>> fetchWorksBatch(
    List<ChaoxingCourse> courses,
  ) => CourseBatch.fetch(
    courses,
    key: (c) => '${c.courseId}:${c.classId}',
    name: (c) => c.name,
    task: (course) async {
      final middle = await _send(
        Uri.parse(
          'https://mooc1-1.chaoxing.com/mooc-ans/visit/stucoursemiddle'
          '?courseid=${course.courseId}&clazzid=${course.classId}'
          '&vc=1&cpi=${course.cpi}&ismooc2=1&v=2',
        ),
      );
      final middleHtml = (middle.data as String?) ?? '';
      final workEnc =
          ChaoxingHtml.hiddenFields(middleHtml)['workEnc'] ??
          _hidden(middleHtml, 'workEnc') ??
          '';
      if (workEnc.isEmpty) throw StateError('作业入口未取得，请刷新登录状态');
      final response = await _send(
        Uri.parse(
          'https://mooc1.chaoxing.com/mooc2/work/list'
          '?courseId=${course.courseId}&classId=${course.classId}'
          '&enc=$workEnc&cpi=${course.cpi}&ut=s',
        ),
        // 作业/考试列表没这个头会返回空页面或跳转
        headers: const <String, String>{
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'text/html, */*; q=0.01',
        },
      );
      final html = (response.data as String?) ?? '';
      final works = parseWorkListHtml(html, course);
      if (works.isEmpty &&
          !RegExp(r'暂无作业|没有作业|暂无数据|noWork|workList|work-list|list-con')
              .hasMatch(html)) {
        throw StateError('无法确认作业列表');
      }
      return works;
    },
  );

  /// 解析作业列表页。
  ///
  /// 页面结构（2026-10-28 实测）：
  /// ```html
  /// <li onclick="goTask(this);"
  ///     data="...work/task?courseId=..&workId=57616202&answerId=0&enc=.."
  ///     aria-label="消化系统 ; 未交">
  ///   <p class="overHidden2 fl">消化系统</p>
  ///   <p class="status fl">未交</p>
  ///   <div class="time notOver">...</div>
  /// </li>
  /// ```
  ///
  /// 优先读 `aria-label`（一个属性里同时有标题和状态，比依赖两个 `<p>` 的
  /// class 顺序稳），读不到再退回原来的 class 匹配。
  @visibleForTesting
  static List<ChaoxingWork> parseWorkListHtml(
    String html,
    ChaoxingCourse course, {
    DateTime? fetchedAt,
  }) {
    final observedAt = fetchedAt ?? DateTime.now();
    final out = <ChaoxingWork>[];
    if (html.isEmpty) return out;

    // 1) DOM 解析：锚点是 `li[data]`，不依赖 onclick 里的 goTask(this)。
    final domRows = ChaoxingHtml.workRows(html);
    if (domRows.isNotEmpty) {
      for (final row in domRows) {
        final workId =
            RegExp(r'workId=(\d+)').firstMatch(row.url)?.group(1) ?? '';
        if (workId.isEmpty) continue;
        out.add(
          ChaoxingWork(
            workId: workId,
            title: row.title,
            courseName: course.name,
            statusText: row.status,
            deadline: row.timeText,
            fetchedAt: observedAt,
            deadlineAt: TaskDeadline.parse(row.timeText, now: observedAt),
            courseId: course.courseId,
            classId: course.classId,
            expired: row.expired,
            taskUrl: row.url,
          ),
        );
      }
      return out;
    }

    // 2) 正则兜底：个别租户还是老模板
    final tagRe = RegExp(r'<li[^>]*goTask\(this\)[^>]*>');
    for (final match in tagRe.allMatches(html)) {
      final tag = match.group(0) ?? '';
      final dataUrl = _attr(tag, 'data');
      if (dataUrl == null || dataUrl.isEmpty) continue;
      final workId =
          RegExp(r'workId=(\d+)').firstMatch(dataUrl)?.group(1) ?? '';
      if (workId.isEmpty) continue;

      // aria-label 形如 "消化系统 ; 未交"
      final label = _attr(tag, 'aria-label') ?? '';
      var title = '';
      var status = '';
      if (label.contains(';')) {
        final parts = label.split(';');
        title = parts.first.trim();
        status = parts.skip(1).join(';').trim();
      } else {
        title = label.trim();
      }

      final bodyStart = match.end;
      final bodyEnd = html.indexOf('</li>', bodyStart);
      final body = bodyEnd > bodyStart
          ? html.substring(bodyStart, bodyEnd)
          : '';

      if (title.isEmpty) {
        title =
            RegExp(r'class="overHidden2[^"]*"[^>]*>([^<]+)<')
                .firstMatch(body)
                ?.group(1)
                ?.trim() ??
            '作业';
      }
      if (status.isEmpty) {
        status =
            RegExp(r'class="status[^"]*"[^>]*>([^<]+)<')
                .firstMatch(body)
                ?.group(1)
                ?.trim() ??
            '';
      }
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
          fetchedAt: observedAt,
          deadlineAt: TaskDeadline.parse(timeText, now: observedAt),
          courseId: course.courseId,
          classId: course.classId,
          expired: body.contains('icon-zy-g'),
          taskUrl: dataUrl.replaceAll('&amp;', '&'),
        ),
      );
    }
    return out;
  }

  /// 从一段标签文本里取属性值（处理 `&amp;`）。
  static String? _attr(String tag, String name) {
    final match = RegExp('$name="([^"]*)"').firstMatch(tag);
    final raw = match?.group(1);
    return raw?.replaceAll('&amp;', '&').replaceAll('&#39;', "'");
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
      // 题干优先取 `span.qtContent`（结构见学习通作业详情：h3.mark_name 里
      // 「序号. + 题型 + qtContent」三段），取不到再退回整段 h3 反推。
      final qtContent =
          RegExp(
            r'<span[^>]*class="[^"]*qtContent[^"]*"[^>]*>(.*?)</span>',
            dotAll: true,
          ).firstMatch(block)?.group(1) ??
          '';
      final text = qtContent.trim().isEmpty
          ? _stripHtml(h3)
                .replaceAll(type, '')
                .replaceAll(RegExp(r'^\s*\d+\.\s*'), '')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim()
          : _stripHtml(qtContent).replaceAll(RegExp(r'\s+'), ' ').trim();
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
    UploadFile file, {
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
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
    form.files.add(MapEntry('upfile', file.multipart()));
    final response = await _dio.postUri<dynamic>(
      uri,
      data: form,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
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
    CancelToken? cancelToken,
    void Function(double)? onProgress,
    void Function()? onSubmitting,
  }) async {
    await UploadFile.validateAll(attachments.map((a) => a.file));
    final total = attachments.fold<int>(0, (sum, a) => sum + a.file.length);
    var sent = 0;
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
        attachment.file,
        cancelToken: cancelToken,
        onSendProgress: (current, count) {
          if (count > 0 && total > 0) {
            onProgress?.call(
              (sent + attachment.file.length * (current / count).clamp(0, 1)) /
                  total,
            );
          }
        },
      );
      sent += attachment.file.length;
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
    if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
    onSubmitting?.call();
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
    // 先按 DOM 取（属性顺序、单双引号都不影响），再退回正则
    final fromDom = ChaoxingHtml.hiddenFields(html)[id];
    if (fromDom != null && fromDom.isNotEmpty) return fromDom;
    final forward = RegExp('id="$id"[^>]*value="([^"]*)"')
        .firstMatch(html)
        ?.group(1);
    if (forward != null) return forward;
    return RegExp('value="([^"]*)"[^>]*id="$id"').firstMatch(html)?.group(1);
  }
}
