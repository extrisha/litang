import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../data/auth/cas_client.dart';
import '../data/auth/jwgl_auth.dart';
import '../widgets/cookie_web_view.dart';

/// 空间预约页面（图书馆研修间 / 空间预约系统）
class SpaceBookingPage extends StatefulWidget {
  const SpaceBookingPage({super.key});

  static const String spaceUrl =
      'https://libspace.usst.edu.cn/student/studentIndex';

  @override
  State<SpaceBookingPage> createState() => _SpaceBookingPageState();
}

class _SpaceBookingPageState extends State<SpaceBookingPage> {
  final GlobalKey<CookieWebViewState> _webKey = GlobalKey<CookieWebViewState>();
  bool _showBanner = true;

  void _showGuideDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: <Widget>[
            Icon(Icons.menu_book_outlined, color: AppColors.usstRed, size: 22),
            SizedBox(width: 8),
            Text('图书馆预约指引', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '1. 空间预约系统（当前页面）',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 4),
              Text(
                '• 服务对象：主要用于预约图书馆研讨间、小组研修间与多媒体自习空间。\n'
                '• 认证方式：支持上理统一身份认证（CAS）免密自动登录。',
                style: TextStyle(fontSize: 12.5, height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                '2. 图书馆日常座位预约（我去图书馆）',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 4),
              Text(
                '• 服务对象：图书馆各楼层日常普通自习座席的预约、选座与离馆签退。\n'
                '• 使用方式：微信搜索并打开【我去图书馆】官方小程序，绑定上理学号即可使用。',
                style: TextStyle(fontSize: 12.5, height: 1.5),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cookies =
        JwglAuth.instance.client?.jar.cookies ?? const <CasCookie>[];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('空间预约'),
        actions: <Widget>[
          IconButton(
            tooltip: '预约指引',
            icon: const Icon(Icons.info_outline, size: 20),
            onPressed: _showGuideDialog,
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => _webKey.currentState?.reload(),
          ),
          IconButton(
            tooltip: '在浏览器中打开',
            icon: const Icon(Icons.open_in_new, size: 20),
            onPressed: () async {
              final uri = Uri.tryParse(SpaceBookingPage.spaceUrl);
              if (uri == null) return;
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_showBanner)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFFE8F3FC),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.event_seat_outlined,
                    size: 16,
                    color: Color(0xFF1E88E5),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '图书馆研修间与自习空间预约 · 座位选座可看指引',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _showGuideDialog,
                    child: const Text(
                      '说明',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E88E5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _showBanner = false),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Color(0xFF5A8EBA),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: CookieWebView(
              key: _webKey,
              url: SpaceBookingPage.spaceUrl,
              cookies: cookies,
            ),
          ),
        ],
      ),
    );
  }
}
