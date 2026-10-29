import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 登录失败，message 可直接展示给用户。
class CasLoginException implements Exception {
  CasLoginException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 把学校 `*.usst.edu.cn` 的 http 地址升级成 https。
///
/// CAS 链路里很多跳转先返回 http，再由页面 JS 跳到 https；
/// 直接按 302 请求 http 会卡在中间页，必须手动升级。
Uri upgradeCasUrl(Uri uri) {
  if (uri.scheme != 'http') {
    return uri;
  }
  final host = uri.host;
  if (host == 'usst.edu.cn' || host.endsWith('.usst.edu.cn')) {
    return uri.replace(scheme: 'https');
  }
  return uri;
}

/// 统一身份认证（CAS / authserver）登录页里的隐藏字段。
class CasTokens {
  const CasTokens({
    required this.lt,
    required this.execution,
    required this.eventId,
  });

  final String lt;
  final String execution;
  final String eventId;

  bool get isValid => lt.isNotEmpty && execution.isNotEmpty;

  /// 解析失败返回 null（例如页面结构变化或被风控拦截）。
  static CasTokens? parse(String html) {
    String? pick(String name) {
      final match = RegExp('name="$name"[^>]*value="([^"]*)"').firstMatch(html);
      return match?.group(1);
    }

    final lt = pick('lt');
    final execution = pick('execution');
    if (lt == null || execution == null) {
      return null;
    }
    return CasTokens(
      lt: lt,
      execution: execution,
      eventId: pick('_eventId') ?? 'submit',
    );
  }
}

/// 一条 cookie。domain 以 "." 开头表示可命中子域。
class CasCookie {
  const CasCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
  });

  final String name;
  final String value;
  final String domain;
  final String path;

  Map<String, String> toJson() => <String, String>{
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
  };

  static CasCookie fromJson(Map<String, dynamic> json) => CasCookie(
    name: json['name'] as String? ?? '',
    value: json['value'] as String? ?? '',
    domain: json['domain'] as String? ?? '',
    path: json['path'] as String? ?? '/',
  );

  bool matchesHost(String host) {
    if (domain.startsWith('.')) {
      final bare = domain.substring(1);
      return host == bare || host.endsWith(domain);
    }
    return host == domain;
  }

  bool matchesPath(String requestPath) {
    if (requestPath == path) {
      return true;
    }
    if (!requestPath.startsWith(path)) {
      return false;
    }
    return path.endsWith('/') || requestPath[path.length] == '/';
  }
}

/// 轻量 cookie jar：按域 / 路径匹配，够用且不引入额外依赖。
class CasCookieJar {
  final List<CasCookie> cookies = <CasCookie>[];

  void clear() => cookies.clear();

  /// 校验请求来源 [requestHost] 是否允许为 [cookieDomain] 设置 Cookie。
  ///
  /// 符合 RFC 6265 核心规范：
  /// 1. 来源域名必须与目标域名相同，或是目标域名的合法子域；
  /// 2. 目标域名不得为公共后缀（Public Suffix，如 .edu.cn, .com, .cn 等）；
  /// 3. 若来源为主机 IP，禁止设置前导点通配域。
  static bool isDomainAllowed(String requestHost, String cookieDomain) {
    final host = requestHost.toLowerCase().trim();
    var domain = cookieDomain.toLowerCase().trim();
    if (domain.startsWith('.')) {
      domain = domain.substring(1);
    }
    if (host.isEmpty || domain.isEmpty) {
      return false;
    }

    final isIp = RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host);
    if (isIp) {
      return host == domain;
    }

    // 来源域名必须等于目标域名，或是其下级子域
    final isSuffixMatch = host == domain || host.endsWith('.$domain');
    if (!isSuffixMatch) {
      return false;
    }

    // 防范单段顶级域或公共后缀 (Public Suffix) 跨站投毒
    final parts = domain.split('.');
    if (parts.length < 2) {
      return false;
    }

    const publicSuffixes = <String>{
      'cn', 'com', 'net', 'org', 'edu', 'gov',
      'edu.cn', 'com.cn', 'net.cn', 'org.cn', 'gov.cn', 'ac.cn', 'mil.cn',
      'sh.cn', 'bj.cn',
    };
    if (publicSuffixes.contains(domain)) {
      return false;
    }

    return true;
  }

  void absorbSetCookie(Uri from, String line) {
    final parts = line.split(';');
    if (parts.isEmpty) {
      return;
    }
    final pair = parts.first;
    final eq = pair.indexOf('=');
    if (eq <= 0) {
      return;
    }
    final name = pair.substring(0, eq).trim();
    final value = pair.substring(eq + 1).trim();
    var domain = from.host;
    var path = _defaultPath(from.path);
    var hasExplicitDomain = false;
    String? explicitDomain;

    for (final raw in parts.skip(1)) {
      final attr = raw.trim();
      final lower = attr.toLowerCase();
      if (lower.startsWith('domain=')) {
        var d = attr.substring(7).trim();
        if (d.isNotEmpty) {
          hasExplicitDomain = true;
          explicitDomain = d;
          if (!d.startsWith('.')) {
            d = '.$d';
          }
          domain = d;
        }
      } else if (lower.startsWith('path=')) {
        final p = attr.substring(5).trim();
        if (p.startsWith('/')) {
          path = p;
        }
      }
    }

    // RFC 6265 校验：如果显式指定了 Domain，必须符合作用域白名单与公共后缀保护，否则丢弃该 Cookie
    if (hasExplicitDomain && explicitDomain != null) {
      if (!isDomainAllowed(from.host, explicitDomain)) {
        return;
      }
    }

    cookies.removeWhere(
      (c) => c.name == name && c.domain == domain && c.path == path,
    );
    cookies.add(
      CasCookie(name: name, value: value, domain: domain, path: path),
    );
  }

  /// 取某个 host 下所有 cookie（WebView 注入用）。
  List<CasCookie> cookiesForHost(String host) =>
      cookies.where((c) => c.matchesHost(host)).toList();

  /// 生成请求头里的 Cookie 串；同一请求路径优先匹配更长的 path。
  String? headerFor(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    final matched =
        cookies
            .where((c) => c.matchesHost(uri.host) && c.matchesPath(path))
            .toList()
          ..sort((a, b) => b.path.length.compareTo(a.path.length));
    final seen = <String>{};
    final out = <String>[];
    for (final c in matched) {
      if (!seen.add(c.name)) {
        continue;
      }
      out.add('${c.name}=${c.value}');
    }
    return out.isEmpty ? null : out.join('; ');
  }

  static String _defaultPath(String requestPath) {
    if (requestPath.isEmpty || !requestPath.startsWith('/')) {
      return '/';
    }
    final lastSlash = requestPath.lastIndexOf('/');
    return lastSlash <= 0 ? '/' : requestPath.substring(0, lastSlash);
  }
}

/// CAS 在多次密码错误后要求输入验证码。
///
/// 抛出这个异常时，[image] 是已经用当前会话 cookie 拉下来的验证码图片，
/// UI 直接 `Image.memory` 展示即可；用户填完调 [CasClient.loginWithCaptcha] 继续。
class CasCaptchaRequired implements Exception {
  CasCaptchaRequired({
    required this.form,
    required this.field,
    required this.postUri,
    required this.image,
    this.message,
  });

  /// 验证码页面上原样收集的隐藏字段（lt / execution / _eventId …）。
  /// 直接整包回传，比只挑几个字段更抗改版。
  final Map<String, String> form;

  /// 验证码输入框的 name，通常是 captcha
  final String field;
  final Uri postUri;

  /// 验证码图片字节
  final Uint8List image;

  /// 服务端给的提示（比如「验证码错误」）
  final String? message;

  String get displayMessage => (message == null || message!.isEmpty)
      ? '密码错误次数过多，请输入验证码'
      : message!;
}

/// 一次 CAS 登录的最终结果（webvpn 等入口用）。
class CasLoginResult {
  const CasLoginResult({
    required this.body,
    required this.uri,
    required this.statusCode,
  });

  final String body;
  final Uri uri;
  final int statusCode;
}

/// 复刻 usst-jwgl-client 的 CAS SSO 流程：
/// 入口 /sso/jziotlogin → ehall 适配器 → ids6 authserver → 回跳 jwglxt。
class CasClient {
  CasClient({Dio? dio, List<CasCookie> initialCookies = const <CasCookie>[]})
    : _dio = dio ?? _sharedDio {
    jar.cookies.addAll(initialCookies);
  }

  /// 所有 CasClient 共用一个 Dio。
  ///
  /// Dio 底层的 HttpClient 会复用 TCP/TLS 连接；如果每个 CasClient 都 new 一个，
  /// 登录链路里每个请求都要重新握手，登录/刷新会明显变慢。
  static final Dio _sharedDio = _buildDio();

  static const String entryUrl = 'https://jwgl.usst.edu.cn/sso/jziotlogin';
  static const String indexUrl =
      'https://jwgl.usst.edu.cn/jwglxt/xtgl/index_initMenu.html';

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  final Dio _dio;
  final CasCookieJar jar = CasCookieJar();

  String? studentId;

  static Dio _buildDio() {
    return Dio(
      BaseOptions(
        followRedirects: false,
        validateStatus: (status) => status != null && status < 500,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        responseType: ResponseType.plain,
      ),
    );
  }

  /// 登录。成功后 [jar] 里持有 jwglxt 会话 cookie。
  /// 网络抖动时自动重试一次（不会重复输密码）。
  Future<void> login(String username, String password) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _loginOnce(username, password);
        return;
      } on CasLoginException {
        rethrow;
      } on DioException {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    }
    throw CasLoginException('网络不稳定，登录失败，请稍后重试');
  }

  Future<void> _loginOnce(String username, String password) async {
    jar.clear();
    studentId = null;

    final entry = await _send(Uri.parse(entryUrl));
    final entryUri = entry.realUri;
    final entryHtml = entry.data ?? '';
    if (!entryUri.path.contains('authserver')) {
      throw CasLoginException('没有跳转到统一身份认证，请检查网络后重试');
    }
    final tokens = CasTokens.parse(entryHtml);
    if (tokens == null) {
      throw CasLoginException('统一身份认证页面解析失败，请稍后重试');
    }

    // 账号已经被要求输入验证码了就直接抛给 UI，别白白再错一次密码
    final preChallenge = await _captchaChallenge(username, entryUri, entryHtml);
    if (preChallenge != null) {
      throw preChallenge;
    }

    final result = await _send(
      entryUri,
      method: 'POST',
      form: <String, String>{
        'username': username.trim(),
        'password': password,
        'lt': tokens.lt,
        'dllt': 'userNamePasswordLogin',
        'execution': tokens.execution,
        '_eventId': tokens.eventId,
        'rmShown': '1',
      },
      referer: entryUri.toString(),
    );

    if (!await checkSession()) {
      // 密码错误次数多了 CAS 会要求验证码：这时候不能只报错，
      // 得把验证码图片拉下来交给 UI
      final challenge = await _captchaChallenge(
        username,
        entryUri,
        result.data ?? '',
      );
      if (challenge != null) {
        throw challenge;
      }
      final message =
          _extractError(result.data ?? '') ??
          _extractError(entryHtml) ??
          '登录失败，请检查学号和密码';
      throw CasLoginException(message);
    }
    studentId = username.trim();
  }

  /// 带验证码再登一次（[challenge] 来自上一次抛出的 [CasCaptchaRequired]）。
  ///
  /// 验证码错了的话会抛新的 [CasCaptchaRequired]（图片已经换过），
  /// 让 UI 直接刷新图片继续填。
  Future<void> loginWithCaptcha({
    required String username,
    required String password,
    required CasCaptchaRequired challenge,
    required String code,
  }) async {
    final result = await _send(
      challenge.postUri,
      method: 'POST',
      form: <String, String>{
        ...challenge.form,
        'username': username.trim(),
        'password': password,
        'dllt': 'userNamePasswordLogin',
        challenge.field: code.trim(),
      },
      referer: challenge.postUri.toString(),
    );

    if (!await checkSession()) {
      final next = await _captchaChallenge(
        username,
        challenge.postUri,
        result.data ?? '',
      );
      if (next != null) throw next;
      throw CasLoginException(
        _extractError(result.data ?? '') ?? '验证码错误或已过期，请重试',
      );
    }
    studentId = username.trim();
  }

  /// 学校这个 CAS 有个现成的策略接口：needCaptcha.html?username=xxx。
  /// 返回正文里带 true 就说明该账号当前需要验证码 —— 不用靠「猜」，
  /// 也不用先错一次密码。
  Future<bool> needCaptcha(String username) async {
    try {
      final uri = Uri.parse(
        'https://ids6.usst.edu.cn/authserver/needCaptcha.html?username='
        '${Uri.encodeQueryComponent(username.trim())}',
      );
      final resp = await _send(uri);
      if ((resp.statusCode ?? 0) != 200) return false;
      return (resp.data ?? '').toLowerCase().contains('true');
    } catch (_) {
      return false;
    }
  }

  /// 需要验证码时：拉图片 + 收集表单，抛给 UI。
  Future<CasCaptchaRequired?> _captchaChallenge(
    String username,
    Uri postUri,
    String html,
  ) async {
    if (!await needCaptcha(username)) return null;
    if (CasTokens.parse(html) == null) return null;

    final parsed = parseCaptcha(html);
    final field = parsed?.field ?? 'captchaResponse';
    // 图片地址优先用页面里写的；没有 src 就用约定的接口
    final raw = parsed?.src;
    final imageUri = postUri.resolve(
      raw != null && raw.isNotEmpty
          ? raw
          : 'captcha.html?ts=${DateTime.now().millisecondsSinceEpoch}',
    );
    try {
      final bytes = await downloadBytes(imageUri);
      if (bytes.isEmpty) return null;
      return CasCaptchaRequired(
        form: _hiddenFields(html),
        field: field,
        postUri: postUri,
        image: Uint8List.fromList(bytes),
        message: _extractError(html),
      );
    } catch (_) {
      return null;
    }
  }

  /// 收集页面里所有 hidden input，验证码重试时整包回传。
  static Map<String, String> _hiddenFields(String html) {
    final out = <String, String>{};
    final inputTag = RegExp(r'''<input[^>]*>''', caseSensitive: false);
    final hiddenType = RegExp(r'''type=["']hidden["']''', caseSensitive: false);
    final nameAttr = RegExp(r'''name=["']([^"']+)["']''');
    final valueAttr = RegExp(r'''value=["']([^"']*)["']''');
    for (final m in inputTag.allMatches(html)) {
      final tag = m.group(0)!;
      if (!hiddenType.hasMatch(tag)) continue;
      final name = nameAttr.firstMatch(tag)?.group(1);
      if (name == null || name.isEmpty) continue;
      out[name] = valueAttr.firstMatch(tag)?.group(1) ?? '';
    }
    return out;
  }

  /// 从 CAS 页面里找验证码输入框名和图片地址。
  ///
  /// 学校的页面上 <img id="captchaImg"> 是没有 src 的（由 JS 拼
  /// captcha.html?ts=...），所以 src 允许为空，由调用方兜底。
  @visibleForTesting
  static ({String field, String? src})? parseCaptcha(String html) {
    if (html.isEmpty) return null;
    final imgTag = RegExp(r'<img[^>]*>', caseSensitive: false)
        .allMatches(html)
        .map((m) => m.group(0)!)
        .where(
          (tag) => RegExp(
            r'captcha|verify|validatecode|kaptcha|imgcode',
            caseSensitive: false,
          ).hasMatch(tag),
        )
        .toList();
    if (imgTag.isEmpty) return null;

    final src = RegExp(
      r'''src=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(imgTag.first)?.group(1);

    final field =
        RegExp(
          r'''name=["'](captcha|captchaResponse|code|validateCode|authcode)["']''',
          caseSensitive: false,
        ).firstMatch(html)?.group(1) ??
        RegExp(
          r'''id=["'](captchaResponse|captcha|code)["']''',
          caseSensitive: false,
        ).firstMatch(html)?.group(1);

    return (
      field: field ?? 'captchaResponse',
      src: (src == null || src.isEmpty) ? null : src,
    );
  }

  /// 从任意 CAS 入口登录（例如 webvpn 的 authserver），返回最终页面。
  Future<CasLoginResult> loginAt(
    Uri entry,
    String username,
    String password,
  ) async {
    final page = await _send(entry);
    final html = page.data ?? '';
    final tokens = CasTokens.parse(html);
    if (tokens == null) {
      throw CasLoginException('统一身份认证页面解析失败');
    }
    final result = await _send(
      page.realUri,
      method: 'POST',
      form: <String, String>{
        'username': username.trim(),
        'password': password,
        'lt': tokens.lt,
        'dllt': 'userNamePasswordLogin',
        'execution': tokens.execution,
        '_eventId': tokens.eventId,
        'rmShown': '1',
      },
      referer: page.realUri.toString(),
    );
    return CasLoginResult(
      body: result.data ?? '',
      uri: result.realUri,
      statusCode: result.statusCode ?? 0,
    );
  }

  /// 当前会话是否还能访问 jwglxt。
  Future<bool> checkSession() async {
    try {
      final resp = await _send(Uri.parse(indexUrl));
      final code = resp.statusCode ?? 0;
      final body = resp.data ?? '';
      return code == 200 &&
          !body.contains('用户登录') &&
          !body.contains('login_slogin');
    } catch (_) {
      return false;
    }
  }

  /// 用已保存的 cookie 静默进入 jwglxt：CASTGC 没过期时不需要再输密码。
  Future<bool> silentLogin() async {
    try {
      await _send(Uri.parse(entryUrl));
      return await checkSession();
    } catch (_) {
      return false;
    }
  }

  /// 下载二进制文件（PDF 等），同样处理 cookie 与 http->https 跳转。
  Future<List<int>> downloadBytes(Uri uri) async {
    var current = uri;
    for (var hop = 0; hop < 25; hop++) {
      final headers = <String, String>{
        'Accept': '*/*',
        'User-Agent': _userAgent,
      };
      final cookie = jar.headerFor(current);
      if (cookie != null) {
        headers['Cookie'] = cookie;
      }
      final resp = await _dio.requestUri<List<int>>(
        current,
        options: Options(
          method: 'GET',
          headers: headers,
          responseType: ResponseType.bytes,
        ),
      );
      _absorb(resp);
      final code = resp.statusCode ?? 0;
      final location = resp.headers.value('location');
      if (code >= 300 &&
          code < 400 &&
          location != null &&
          location.isNotEmpty) {
        current = upgradeCasUrl(current.resolve(location));
        continue;
      }
      return resp.data ?? const <int>[];
    }
    return const <int>[];
  }

  /// 带登录态提交表单（POST，带 XHR 头），用于教务内部的 AJAX 接口。
  Future<Response<String>> postApi(
    Uri uri,
    Map<String, String> data, {
    String? referer,
    Map<String, String> extraHeaders = const <String, String>{},
  }) {
    return _send(
      uri,
      method: 'POST',
      form: data,
      referer: referer,
      accept: 'application/json, text/plain, */*',
      extraHeaders: <String, String>{
        'X-Requested-With': 'XMLHttpRequest',
        ...extraHeaders,
      },
    );
  }

  /// 带登录态提交 JSON（PUT/POST），用于一网畅学等第三方系统。
  Future<Response<String>> sendJson(
    Uri uri, {
    String method = 'POST',
    Map<String, dynamic> data = const <String, dynamic>{},
  }) {
    return _send(
      uri,
      method: method,
      jsonBody: data,
      accept: 'application/json, text/plain, */*',
      extraHeaders: const <String, String>{
        'X-Requested-With': 'XMLHttpRequest',
      },
    );
  }

  /// 带登录态 GET 一个 JSON API（会带上 cookie，不设 jwgl 的 Referer）。
  Future<Response<String>> getApi(Uri uri, {Map<String, String>? headers}) {
    return _send(
      uri,
      accept: 'application/json, text/plain, */*',
      extraHeaders: <String, String>{
        'X-Requested-With': 'XMLHttpRequest',
        ...?headers,
      },
    );
  }

  /// 带登录态发请求（后续课表 / 成绩接口用）。
  Future<Response<String>> getJson(Uri uri, {Map<String, String>? data}) {
    return _send(
      uri,
      method: data == null ? 'GET' : 'POST',
      form: data,
      referer: indexUrl,
      accept: 'application/json, text/javascript, */*; q=0.01',
      extraHeaders: const <String, String>{
        'X-Requested-With': 'XMLHttpRequest',
      },
    );
  }

  Future<Response<String>> _send(
    Uri url, {
    String method = 'GET',
    Map<String, String>? form,
    Object? jsonBody,
    String? referer,
    String accept =
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    var current = url;
    var currentMethod = method;
    Map<String, String>? body = form;
    Object? currentJson = jsonBody;
    String? currentReferer = referer;
    Response<String>? last;

    for (var hop = 0; hop < 25; hop++) {
      final headers = <String, String>{
        'Accept': accept,
        'User-Agent': _userAgent,
        'Accept-Language': 'zh-CN,zh;q=0.9',
        ...extraHeaders,
      };
      final cookie = jar.headerFor(current);
      if (cookie != null) {
        headers['Cookie'] = cookie;
      }
      if (currentReferer != null) {
        headers['Referer'] = currentReferer;
      }

      final resp = await _dio.requestUri<String>(
        current,
        data: body ?? (currentJson == null ? null : jsonEncode(currentJson)),
        options: Options(
          method: currentMethod,
          headers: headers,
          contentType: body != null
              ? Headers.formUrlEncodedContentType
              : (currentJson == null ? null : Headers.jsonContentType),
        ),
      );
      _absorb(resp);
      last = resp;

      final code = resp.statusCode ?? 0;
      final location = resp.headers.value('location');
      if (code >= 300 &&
          code < 400 &&
          location != null &&
          location.isNotEmpty) {
        current = upgradeCasUrl(current.resolve(location));
        currentMethod = 'GET';
        body = null;
        currentJson = null;
        currentReferer = current.toString();
        continue;
      }
      return resp;
    }
    return last!;
  }

  void _absorb(Response<dynamic> resp) {
    final raw = resp.headers.map['set-cookie'];
    if (raw == null || raw.isEmpty) {
      return;
    }
    final uri = resp.realUri;
    for (final line in raw) {
      jar.absorbSetCookie(uri, line);
    }
  }

  static String? _extractError(String html) {
    final match = RegExp('id="msg"[^>]*>([^<]*)<').firstMatch(html);
    final text = match?.group(1)?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }
}
