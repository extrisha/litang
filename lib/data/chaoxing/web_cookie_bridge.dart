import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../auth/cas_client.dart';

/// 内嵌 WebView 登录后，把 cookie 读回来交给客户端。
///
/// 之所以要原生那一层：`webview_flutter` 4.x 没有读取 cookie 的 API，
/// 而学习通的会话 cookie 是 httpOnly 的，`document.cookie` 也读不到。
/// Android 侧在 `MainActivity` 里用 `CookieManager.getCookie(url)` 实现，
/// 通道名 `litang/web_cookies`；桌面/其它平台没有通道，直接返回空。
class WebCookieBridge {
  WebCookieBridge._();

  static const MethodChannel _channel = MethodChannel('litang/web_cookies');

  /// 学习通的会话 cookie 挂在 `.chaoxing.com` 上，这几个域走一遍基本能全拿到。
  static const List<String> chaoxingUrls = <String>[
    'https://i.chaoxing.com/',
    'https://passport2.chaoxing.com/',
    'https://mooc1.chaoxing.com/',
    'https://mooc2-ans.chaoxing.com/',
  ];

  /// 读 cookie；读不到就是空列表（不抛异常，让调用方自己决定怎么提示）。
  static Future<List<CasCookie>> read({List<String>? urls}) async {
    final targets = urls ?? chaoxingUrls;
    try {
      final map = await _channel.invokeMapMethod<String, String>('read', {
        'urls': targets,
      });
      if (map == null || map.isEmpty) return const <CasCookie>[];
      final out = <CasCookie>[];
      final seen = <String>{};
      for (final entry in map.entries) {
        final domain = cookieDomain(entry.key);
        for (final cookie in parseCookieHeader(entry.value, domain: domain)) {
          // 同名 cookie 只在第一次出现时保留（chaoxing 各子域值通常一致）
          if (seen.add(cookie.name)) out.add(cookie);
        }
      }
      return out;
    } on PlatformException {
      return const <CasCookie>[];
    } on MissingPluginException {
      return const <CasCookie>[];
    }
  }

  /// 退出登录时清 WebView 的会话：**cookie + localStorage/sessionStorage**。
  ///
  /// 只清 cookie 会漏：上理体育（ydmap）把登录 token 放在 `window.localStorage`
  /// 里（`fe.put` 走 localStorage，JSON 编码），换账号后不清就是上一个人的登录态。
  /// 这里一次性清空，代价是同一 App 内其它 WebView 的网页缓存也没了 —— 退出登录
  /// 本来就要这个效果，和「换账号旧缓存不能留」一致。
  static Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } catch (_) {
      // 没有通道（桌面端）就算了
    }
  }

  /// 把 cookie 写进系统 CookieManager（支持 `Domain` 属性）。
  ///
  /// 返回写入条数；**返回 -1 表示当前平台没有这个通道**，调用方应退回
  /// `webview_flutter` 的 `WebViewCookieManager`（只能写 host-only cookie）。
  static Future<int> writeAll(
    List<({String url, String cookie})> entries,
  ) async {
    if (entries.isEmpty) return 0;
    try {
      final count = await _channel.invokeMethod<int>('write', {
        'cookies': <Map<String, String>>[
          for (final e in entries)
            <String, String>{'url': e.url, 'cookie': e.cookie},
        ],
      });
      return count ?? 0;
    } on PlatformException {
      return -1;
    } on MissingPluginException {
      return -1;
    }
  }

  /// 生成注入计划：把 [cookies] 里**与目标同站**的 cookie 转成
  /// `(url, Set-Cookie 串)`，交给原生 `CookieManager.setCookie`。
  ///
  /// 两个要点：
  /// 1. 只注入同一站点的 cookie（`usst.edu.cn` 的会话绝不带给 `chaoxing.com`）；
  /// 2. 不再要求「cookie 域是目标主机的父域」——CAS 的 CASTGC 往往挂在
  ///    `ids6.usst.edu.cn` 上，和 `libspace.usst.edu.cn` 是**兄弟**关系，
  ///    旧逻辑会把它整条丢掉，于是 WebView 里的 CAS 那一跳必然要求重新登录。
  static List<({String url, String cookie})> buildInjection(
    List<CasCookie> cookies,
    String targetUrl,
  ) {
    final targetHost = (Uri.tryParse(targetUrl)?.host ?? '').toLowerCase();
    if (targetHost.isEmpty) return const <({String url, String cookie})>[];
    final site = siteOf(targetHost);
    if (site.isEmpty) return const <({String url, String cookie})>[];

    final out = <({String url, String cookie})>[];
    final seen = <String>{};
    for (final c in cookies) {
      final bare = c.domain.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
      if (bare.isEmpty) continue;
      if (bare != site && !bare.endsWith('.$site')) continue;
      if (!seen.add('$bare|${c.path}|${c.name}')) continue;

      final path = c.path.isEmpty ? '/' : c.path;
      final buffer = StringBuffer('${c.name}=${c.value}; Path=$path');
      // 只有原本就是父域 cookie（以 . 开头）才写 Domain；host-only 的
      // 写到它自己的主机上即可，写 Domain 反而会扩大作用域。
      if (c.domain.startsWith('.')) {
        buffer.write('; Domain=${c.domain}');
      }
      buffer.write('; Secure');
      out.add((url: 'https://$bare/', cookie: buffer.toString()));
    }
    return out;
  }

  /// 粗略的「站点」判定：`libspace.usst.edu.cn` → `usst.edu.cn`，
  /// `i.chaoxing.com` → `chaoxing.com`。
  @visibleForTesting
  static String siteOf(String host) {
    final parts = host
        .toLowerCase()
        .split('.')
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length <= 2) return parts.join('.');
    const twoLevel = <String>{
      'edu.cn',
      'com.cn',
      'net.cn',
      'org.cn',
      'gov.cn',
      'ac.cn',
      'edu.hk',
    };
    final lastTwo = parts.sublist(parts.length - 2).join('.');
    if (twoLevel.contains(lastTwo)) {
      return parts.sublist(parts.length - 3).join('.');
    }
    return lastTwo;
  }

  /// `Cookie` 头 → cookie 列表，例如 `_uid=123; _d=abc; fid=42`。
  @visibleForTesting
  static List<CasCookie> parseCookieHeader(
    String raw, {
    required String domain,
  }) {
    final out = <CasCookie>[];
    for (final piece in raw.split(';')) {
      final text = piece.trim();
      if (text.isEmpty) continue;
      final eq = text.indexOf('=');
      if (eq <= 0) continue;
      final name = text.substring(0, eq).trim();
      final value = text.substring(eq + 1).trim();
      if (name.isEmpty) continue;
      out.add(CasCookie(name: name, value: value, domain: domain, path: '/'));
    }
    return out;
  }

  /// cookie 的归属域：chaoxing 的子域统一记到 `.chaoxing.com`，
  /// 这样 `i.chaoxing.com` / `mooc1.chaoxing.com` 都能带上；
  /// 其它域名按 host-only 处理（别把 `edu.cn` 当成可共享的域）。
  @visibleForTesting
  static String cookieDomain(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return '';
    if (host == 'chaoxing.com' || host.endsWith('.chaoxing.com')) {
      return '.chaoxing.com';
    }
    return host;
  }
}
