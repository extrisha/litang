import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/cas_client.dart';

/// 用教务的 CAS 会话，静默换取学习通（超星）的 cookie。
///
/// 为什么要它：App 里的 CAS cookie 存在 [CasClient.jar] 中，而平台的 WebView
/// 有自己独立的 cookie 存储——两边不共享。所以之前打开 WebView 走 SSO 时，
/// WebView 里没有 CASTGC，只能让用户重新输一遍学校密码。
///
/// 这里的做法是把整条跳转链在 Dart 里跑完：
///
/// ```
/// GET tyrzfw.chaoxing.com/auth3/usst/cas/init?isLogout=0
///   → 200 HTML，JS 里带 CAS 地址
/// GET ids6.usst.edu.cn/authserver/login?service=.../auth3/usst/cas/index
///   → 带 CASTGC，CAS 直接 302 发 ticket
/// GET tyrzfw.chaoxing.com/auth3/usst/cas/index?ticket=ST-...
///   → 校验后种下 .chaoxing.com 的 _uid / _dstu 等
/// ```
///
/// 拿到 cookie 后交给 `ChaoxingAuth.loginWithCookies` 即可，全程不弹网页。
class ChaoxingSso {
  ChaoxingSso._();

  /// 上理的 CAS 入口（App 里 `ChaoxingLoginPage.ssoUrl` 用的同一个）。
  static const String entryUrl =
      'https://tyrzfw.chaoxing.com/auth3/usst/cas/init?isLogout=0'
      '&refer=https%3A%2F%2Fi.chaoxing.com&casinfo=&casenc=&casfrom=login';

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// 教务 CAS 带着有效 CASTGC 时，直接从 ids6 发起认证，
  /// 少走一次 tyrzfw 入口页 + JS 跳转解析。
  static const String _directCasUrl =
      'https://ids6.usst.edu.cn/authserver/login'
      '?service=https%3A%2F%2Ftyrzfw.chaoxing.com%2Fauth3%2Fusst%2Fcas%2Findex';

  /// 跑完 SSO，返回学习通域下的 cookie；失败返回空列表（调用方回退到网页登录）。
  ///
  /// [cas] 必须持有有效的 ids6 `CASTGC`，否则 CAS 会返回登录页——
  /// 那种情况说明教务会话也过期了，只能让用户重新登录教务。
  ///
  /// [forceEntry] 为 true 时跳过 ids6 快路径，强制从 tyrzfw 入口走一遍。
  static Future<List<CasCookie>> login(
    CasClient cas, {
    bool forceEntry = false,
  }) async {
    final dio = Dio(
      BaseOptions(
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.plain,
        headers: <String, String>{'User-Agent': _ua},
      ),
    );

    try {
      // 有 CASTGC 时先走 ids6；失败再回退到 tyrzfw 入口页。
      final starts = <Uri>[
        if (!forceEntry && _hasCastgc(cas)) Uri.parse(_directCasUrl),
        Uri.parse(entryUrl),
      ];
      for (final start in starts) {
        final local = CasCookieJar();
        try {
          await _follow(dio, cas, local, start);
        } catch (e) {
          debugPrint('[ChaoxingSSO] 跳转链异常 ($start): $e');
        }
        final cookies = local.cookies
            .where((c) => c.domain.contains('chaoxing'))
            .toList(growable: false);
        if (cookies.isNotEmpty) {
          return cookies;
        }
      }
    } finally {
      dio.close(force: true);
    }

    return const <CasCookie>[];
  }

  static bool _hasCastgc(CasClient cas) => cas.jar.cookies.any(
    (c) =>
        c.name == 'CASTGC' &&
        c.value.isNotEmpty &&
        c.matchesHost('ids6.usst.edu.cn'),
  );

  /// 给登录 UI 判断：没有 CASTGC 时隐藏 WebView 也换不到 SSO。
  static bool hasCastgc(CasClient? cas) => cas != null && _hasCastgc(cas);

  static Future<void> _follow(
    Dio dio,
    CasClient cas,
    CasCookieJar local,
    Uri start,
  ) async {
    var current = start;
    var method = 'GET';
    String? body;
    String? referer;
    for (var hop = 0; hop < 10; hop++) {
      final cookie = _mergeCookie(cas.jar, local, current);
      final response = await dio.requestUri<dynamic>(
        current,
        data: body,
        options: Options(
          method: method,
          headers: <String, String>{
            if (cookie.isNotEmpty) 'Cookie': cookie,
            'Referer': ?referer,
          },
        ),
      );

      _absorb(local, current, response);
      _log(hop, method, current, response);

      final status = response.statusCode ?? 0;
      final location = response.headers.value('location');

      // 1) 常规重定向
      if (status >= 300 && status < 400 && location != null) {
        referer = current.toString();
        current = current.resolve(location);
        if (status == 303) {
          method = 'GET';
          body = null;
        }
        continue;
      }

      final html = response.data?.toString() ?? '';

      // 2) 超星用 JS 跳转（`window.location = "..."`），必须自己解析
      final jsTarget = _jsRedirect(html);
      if (jsTarget != null) {
        referer = current.toString();
        current = current.resolve(jsTarget);
        continue;
      }

      // 3) 落到学习通页面 = 流程结束
      if (current.host.endsWith('chaoxing.com') &&
          !current.path.contains('/cas/')) {
        break;
      }

      // 4) 还在 CAS 登录页 = 教务会话无效
      if (current.host.contains('ids6') || html.contains('authserver/login')) {
        debugPrint('[ChaoxingSSO] 停在统一身份认证页，教务会话已失效');
      }
      break;
    }
  }

  /// 两个 jar 的 cookie 合并成一个 Cookie 头（各取自己匹配的 host）。
  static String _mergeCookie(CasCookieJar cas, CasCookieJar local, Uri uri) {
    final parts = <String>[];
    final a = cas.headerFor(uri);
    if (a != null && a.isNotEmpty) parts.add(a);
    final b = local.headerFor(uri);
    if (b != null && b.isNotEmpty) parts.add(b);
    return parts.join('; ');
  }

  static void _absorb(CasCookieJar jar, Uri from, Response<dynamic> resp) {
    final lines = resp.headers['set-cookie'];
    if (lines == null) return;
    for (final line in lines) {
      jar.absorbSetCookie(from, line);
    }
  }

  /// 超星返回的是 `<script>window.location = "https:\/\/ids6...";</script>`。
  static String? _jsRedirect(String html) {
    if (html.isEmpty) return null;
    final match = RegExp(
      r'''window\.location(?:\.href)?\s*=\s*["']([^"']+)["']''',
    ).firstMatch(html);
    final raw = match?.group(1);
    if (raw == null || raw.isEmpty) return null;
    return _unescapeJs(raw);
  }

  /// 还原 JS 字符串里的转义。
  ///
  /// 超星会把整条 URL 塞进 JS 字符串，其中 `&` 写成 `\u0026`、`/` 写成 `\/`。
  /// 只还原斜杠是不够的：`\u0026` 留着的话，所有查询参数会串成一个值，
  /// 服务端就会报「time不能为空」（实测踩过）。
  static String _unescapeJs(String raw) {
    final slashes = raw.replaceAll(r'\/', '/');
    return slashes.replaceAllMapped(
      RegExp(r'\\u([0-9a-fA-F]{4})'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );
  }

  static void _log(int hop, String method, Uri uri, Response<dynamic> resp) {
    if (!kDebugMode) return;
    final location = resp.headers.value('location') ?? '';
    debugPrint(
      '[ChaoxingSSO] [$hop] ${resp.statusCode} $method ${uri.host}${uri.path}'
      '${location.isEmpty ? '' : ' -> $location'}',
    );
  }

  /// 仅测试用：确认 JS 跳转解析能处理转义斜杠。
  @visibleForTesting
  static String? parseJsRedirect(String html) => _jsRedirect(html);
}
