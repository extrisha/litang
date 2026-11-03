import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_theme.dart';
import '../data/auth/cas_client.dart';
import '../data/chaoxing/web_cookie_bridge.dart';

/// 带 cookie 注入的通用内嵌网页，可以单独塞进任意页面里用。
class CookieWebView extends StatefulWidget {
  const CookieWebView({
    super.key,
    required this.url,
    this.cookies = const <CasCookie>[],
    this.html,
  });

  final String url;
  final List<CasCookie> cookies;

  /// 已经抓到的 HTML。给了就直接渲染它（baseUrl 用 [url]），
  /// 用来绕开"某些站点在 WebView 里认不出 cookie、跳登录页"的问题。
  final String? html;

  @override
  State<CookieWebView> createState() => CookieWebViewState();
}

class CookieWebViewState extends State<CookieWebView> {
  static final bool _supported =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  WebViewController? _controller;
  bool _loading = true;
  String? _error;

  void reload() => _controller?.reload();

  @override
  void initState() {
    super.initState();
    if (!_supported) {
      _loading = false;
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (mounted && (error.isForMainFrame ?? false)) {
              setState(() {
                _loading = false;
                _error = '页面加载失败：${error.description}';
              });
            }
          },
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return NavigationDecision.navigate;
            }
            // 拦截非 http/https 协议（如 tel:, mailto:, intent:// 等），交给外部系统处理
            if (await canLaunchUrl(uri)) {
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            }
            return NavigationDecision.prevent;
          },
        ),
      );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final controller = _controller;
    if (controller == null) return;
    final html = widget.html;
    if (html != null && html.isNotEmpty) {
      await controller.loadHtmlString(html, baseUrl: widget.url);
      return;
    }
    final target = Uri.tryParse(widget.url);
    if (target == null ||
        (target.scheme != 'http' && target.scheme != 'https')) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '不支持的网页地址协议';
        });
      }
      return;
    }
    if (widget.cookies.isNotEmpty) {
      final injected = await _injectCookies(
        widget.cookies,
        target.host.toLowerCase(),
      );
      debugPrint('[webview] cookie 注入 $injected 条 → ${target.host}');
    }
    await controller.loadRequest(target);
  }

  /// 把 [cookies] 注入 WebView。
  ///
  /// 优先走原生 `CookieManager`（`litang/web_cookies` 通道的 `write`），因为
  /// 只有它能写 `Domain` 属性 —— `.usst.edu.cn` 这类父域 cookie 才能被
  /// `ids6.usst.edu.cn` 的 CAS 那一跳带上。
  ///
  /// 没有原生通道时（iOS/桌面）退回 `webview_flutter`，它只能写 host-only
  /// cookie，于是按 cookie 自己的域逐个主机注入：`ids6` 的 CASTGC 至少能
  /// 落在 `ids6` 上，CAS 那一跳仍然是登录态。
  Future<int> _injectCookies(List<CasCookie> cookies, String host) async {
    final plan = WebCookieBridge.buildInjection(cookies, 'https://$host/');
    final written = await WebCookieBridge.writeAll(plan);
    if (written >= 0) return written;

    try {
      final manager = WebViewCookieManager();
      var count = 0;
      for (final cookie in plan) {
        // plan 里的 url 形如 https://ids6.usst.edu.cn/，取回主机名
        final cookieHost = Uri.tryParse(cookie.url)?.host ?? '';
        if (cookieHost.isEmpty) continue;
        // iOS 的 WebViewCookie domain 参数要的是「域」而不是 URL
        final domain = defaultTargetPlatform == TargetPlatform.android
            ? cookie.url
            : cookieHost;
        await manager.setCookie(
          WebViewCookie(
            name: _nameOf(cookie.cookie),
            value: _valueOf(cookie.cookie),
            domain: domain,
            path: _pathOf(cookie.cookie),
          ),
        );
        count++;
      }
      return count;
    } catch (_) {
      // 注入失败也继续打开
      return 0;
    }
  }

  static String _nameOf(String setCookie) {
    final pair = setCookie.split(';').first;
    final eq = pair.indexOf('=');
    return eq <= 0 ? '' : pair.substring(0, eq).trim();
  }

  static String _valueOf(String setCookie) {
    final pair = setCookie.split(';').first;
    final eq = pair.indexOf('=');
    return eq <= 0 ? '' : pair.substring(eq + 1).trim();
  }

  static String _pathOf(String setCookie) {
    for (final part in setCookie.split(';').skip(1)) {
      final text = part.trim();
      if (text.toLowerCase().startsWith('path=')) {
        final value = text.substring(5).trim();
        return value.isEmpty ? '/' : value;
      }
    }
    return '/';
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '该页面只能在手机 App 内打开',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return Stack(
      children: <Widget>[
        if (_controller != null) WebViewWidget(controller: _controller!),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.white,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
