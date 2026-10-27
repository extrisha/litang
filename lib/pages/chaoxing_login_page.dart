import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_theme.dart';
import '../data/auth/cas_client.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/chaoxing/chaoxing_auth.dart';
import '../data/chaoxing/web_cookie_bridge.dart';

/// 学习通登录：开内嵌网页，登完把 cookie 读回来。
///
/// 优先走学校 CAS 单点登录（超星机构列表里「上海理工大学」的第二个入口），
/// 把教务 CAS cookie 注入 WebView，页面自己跳 ids6 并完成认证。
///
/// [hidden] 为 true 时只渲染 1×1 的 WebView，外面盖一个「正在登录」小提示；
/// SSO 或验证码超时会返回 false，由调用方切回可见登录页。
class ChaoxingLoginPage extends StatefulWidget {
  const ChaoxingLoginPage({
    super.key,
    this.username,
    this.password,
    this.hidden = false,
  });

  /// 可选：教务保存的学号 / 密码，SSO 失败且落到超星登录页时自动填表。
  final String? username;
  final String? password;

  /// 隐藏 WebView 模式：只跑 SSO，不展示登录页。
  final bool hidden;

  /// 学校专属的登录页：`fid=207` 是上海理工在超星那边的机构号。
  static const String loginUrl =
      'https://passport2.chaoxing.com/login?fid=207&newversion=true'
      '&refer=https%3A%2F%2Fi.chaoxing.com';

  /// 超星机构列表里第二个「上海理工大学」（schoolid=24960）的 CAS 入口。
  /// 该入口会 302/JS 跳到 ids6，认证后回到超星并种下 .chaoxing.com cookie。
  static const String ssoUrl =
      'https://tyrzfw.chaoxing.com/auth3/usst/cas/init?isLogout=0'
      '&refer=https%3A%2F%2Fi.chaoxing.com&casinfo=&casenc=&casfrom=login';

  @override
  State<ChaoxingLoginPage> createState() => _ChaoxingLoginPageState();
}

class _ChaoxingLoginPageState extends State<ChaoxingLoginPage> {
  static final bool _supported =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  WebViewController? _controller;
  bool _loading = true;
  bool _finishing = false;
  bool _autoLoginAttempted = false;
  Timer? _hiddenTimeout;
  String? _error;

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
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() => _loading = false);
            // 登录成功后超星会跳到 i.chaoxing.com（或课程首页），这时抓一次 cookie
            if (!_finishing && _looksLoggedIn(url)) {
              _finish();
              return;
            }
            if (!_autoLoginAttempted &&
                url.contains('passport2.chaoxing.com/login') &&
                (widget.username?.isNotEmpty ?? false) &&
                (widget.password?.isNotEmpty ?? false)) {
              _autoLoginAttempted = true;
              _autoFillAndSubmit();
            }
          },
        ),
      );
    _start();
    if (widget.hidden) {
      _hiddenTimeout = Timer(const Duration(seconds: 25), () {
        if (mounted && !_finishing) {
          Navigator.of(context).pop(false);
        }
      });
    }
  }

  @override
  void dispose() {
    _hiddenTimeout?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final controller = _controller;
    if (controller == null) return;
    final cas = JwglAuth.instance.client;
    if (cas != null && cas.jar.cookies.isNotEmpty) {
      await _injectCasCookies(cas.jar.cookies);
      if (!mounted) return;
      await controller.loadRequest(Uri.parse(ChaoxingLoginPage.ssoUrl));
      return;
    }
    await controller.loadRequest(Uri.parse(ChaoxingLoginPage.loginUrl));
  }

  /// 把教务 CAS 的 cookie 注入 WebView，让 SSO 页能直接拿到 ids6 登录态。
  ///
  /// Android 的 WebViewCookieManager 只能按 host 设 cookie，所以 `.usst.edu.cn`
  /// 这种域 cookie 要按 CAS 实际使用的 ids6 host 注入。
  Future<void> _injectCasCookies(List<CasCookie> cookies) async {
    try {
      final manager = WebViewCookieManager();
      for (final cookie in cookies) {
        final String targetUrl;
        if (cookie.domain.startsWith('.')) {
          if (cookie.matchesHost('ids6.usst.edu.cn')) {
            targetUrl = 'https://ids6.usst.edu.cn/';
          } else if (cookie.matchesHost('tyrzfw.chaoxing.com')) {
            targetUrl = 'https://tyrzfw.chaoxing.com/';
          } else if (cookie.matchesHost('i.chaoxing.com')) {
            targetUrl = 'https://i.chaoxing.com/';
          } else {
            continue;
          }
        } else {
          if (cookie.domain.isEmpty) continue;
          targetUrl = 'https://${cookie.domain}/';
        }
        final domain = defaultTargetPlatform == TargetPlatform.android
            ? targetUrl
            : cookie.domain;
        await manager.setCookie(
          WebViewCookie(
            name: cookie.name,
            value: cookie.value,
            domain: domain,
            path: cookie.path,
          ),
        );
      }
    } catch (_) {
      // 注入失败就退回普通登录页
    }
  }

  bool _looksLoggedIn(String url) {
    if (url.contains('passport2.chaoxing.com')) return false;
    return url.contains('i.chaoxing.com') ||
        url.contains('mooc1.chaoxing.com') ||
        url.contains('mooc2-ans.chaoxing.com');
  }

  /// 用教务保存的学号/密码填超星官方登录页并提交。
  ///
  /// 这样超星自己的 JS 仍会做 AES 加密、验证码和双因子判断；
  /// 我们只模拟用户输入，不复制对方的登录协议。
  Future<void> _autoFillAndSubmit() async {
    final controller = _controller;
    final username = widget.username;
    final password = widget.password;
    if (controller == null ||
        username == null ||
        password == null ||
        username.isEmpty ||
        password.isEmpty) {
      return;
    }
    final userJs = jsonEncode(username);
    final passJs = jsonEncode(password);
    try {
      await controller.runJavaScript('''
        (function () {
          var phone = document.getElementById('phone');
          var pwd = document.getElementById('pwd');
          if (phone) phone.value = $userJs;
          if (pwd) pwd.value = $passJs;
          if (typeof loginByPhoneAndPwd === 'function') {
            loginByPhoneAndPwd();
          }
        })();
      ''');
    } catch (_) {
      // 页面结构变化/注入失败就退回手动登录，不阻塞用户。
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() {
      _finishing = true;
      _error = null;
    });
    try {
      final cookies = await WebCookieBridge.read();
      if (cookies.isEmpty) {
        if (widget.hidden) {
          if (mounted) Navigator.of(context).pop(false);
          return;
        }
        if (mounted) {
          setState(() {
            _finishing = false;
            _error = '还没读到登录状态，请先完成登录';
          });
        }
        return;
      }
      final ok = await ChaoxingAuth.instance.loginWithCookies(cookies);
      if (!mounted) return;
      if (ok) {
        _hiddenTimeout?.cancel();
        Navigator.of(context).pop(true);
      } else if (widget.hidden) {
        Navigator.of(context).pop(false);
      } else {
        setState(() {
          _finishing = false;
          _error = '登录状态无效，请重新登录';
        });
      }
    } catch (_) {
      if (!mounted) return;
      if (widget.hidden) {
        Navigator.of(context).pop(false);
        return;
      }
      setState(() {
        _finishing = false;
        _error = '读取登录状态失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hidden) {
      return _hiddenBuild();
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('登录学习通'),
        actions: <Widget>[
          if (_controller != null)
            TextButton(
              onPressed: _finishing ? null : _finish,
              child: _finishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('完成'),
            ),
        ],
      ),
      body: !_supported
          ? _message('网页登录只能在手机 App 内使用')
          : Column(
              children: <Widget>[
                if (_error != null)
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFFFF4E5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9A6A1F),
                      ),
                    ),
                  ),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      if (_controller != null)
                        WebViewWidget(controller: _controller!),
                      if (_finishing)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Color(0x66FFFFFF),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _hiddenBuild() {
    if (!_supported) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: <Widget>[
          if (_controller != null)
            Positioned(
              left: 0,
              top: 0,
              width: 1,
              height: 1,
              child: WebViewWidget(controller: _controller!),
            ),
          Center(
            child: Material(
              color: Colors.white,
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('正在登录学习通…', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
      ),
    ),
  );
}
