import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/auth/cas_client.dart';
import '../data/chaoxing/chaoxing_auth.dart';
import '../data/chaoxing/chaoxing_client.dart';
import '../data/chaoxing/chaoxing_course_detail.dart';
import '../widgets/cookie_web_view.dart';
import 'simple_web_page.dart';

/// 学习通考试详情。
///
/// 按「考试不要乱动」的原则：
///   - 已结束/已完成且有答卷分析地址 → 页面里内嵌答卷与得分分析；
///   - 还没做完的 → 只给信息 + 一个「去网页参加考试」的入口（实际作答在网页里）。
///
/// 答卷页是服务端渲染的静态 HTML，所以我们先用带 cookie 的 HTTP 请求把 HTML
/// 抓下来再交给 WebView 渲染。这样即使 WebView 里的 cookie 不被站点认可
/// （之前就是一点进去跳登录页），也能正常看到内容。
class ChaoxingExamDetailPage extends StatefulWidget {
  const ChaoxingExamDetailPage({
    super.key,
    required this.exam,
    required this.course,
  });

  final ChaoxingExam exam;
  final ChaoxingCourse course;

  @override
  State<ChaoxingExamDetailPage> createState() => _ChaoxingExamDetailPageState();
}

class _ChaoxingExamDetailPageState extends State<ChaoxingExamDetailPage> {
  String? _html;
  bool _loading = true;

  /// 抓下来的 HTML 看着像登录页：说明 cookie 已经不被服务端认可。
  bool _loginRequired = false;

  /// 只靠长度判断不够：登录页也有好几千字符，原来会被当成「正常答卷页」
  /// 直接塞进 WebView，用户看到的是一个登录表单，却不知道是 cookie 失效。
  static bool _looksLikeLoginPage(String body) =>
      body.contains('passport2.chaoxing.com/login') ||
      body.contains('请输入密码') ||
      body.contains('id="loginForm"');

  bool get _finished =>
      widget.exam.status.contains('已完成') || widget.exam.status.contains('已批阅');

  bool get _hasAnalysis => widget.exam.analysisUrl.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_finished || !_hasAnalysis) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final client = ChaoxingAuth.instance.client;
      if (client != null) {
        final resp = await client.getPage(Uri.parse(widget.exam.analysisUrl));
        final body = (resp.data as String?) ?? '';
        if (_looksLikeLoginPage(body)) {
          _loginRequired = true;
        } else if (body.length > 1000) {
          // 太长/太短都不太像正常答卷页，宁可回退到直接加载
          _html = body;
        }
      }
    } catch (e) {
      // 抓不到就回退成直接打开网址
      debugPrint('[chaoxing] 答卷页抓取失败: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_finished && _hasAnalysis) {
      return _analysisPage();
    }
    return _infoPage(context);
  }

  Widget _analysisPage() {
    final cookies =
        ChaoxingAuth.instance.client?.jar.cookies ?? const <CasCookie>[];
    final exam = widget.exam;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('答卷与得分分析')),
      body: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        exam.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        <String>[
                          widget.course.name,
                          if (exam.score.isNotEmpty) '${exam.score} 分',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _tag(exam.status, const Color(0xFF2E8B57)),
              ],
            ),
          ),
          if (_loginRequired)
            Container(
              width: double.infinity,
              color: const Color(0xFFFEF3C7),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Row(
                children: <Widget>[
                  Icon(Icons.info_outline, size: 15, color: Color(0xFFD97706)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '学习通登录状态可能已失效。若下方要求登录，请回到「我的」重新登录学习通。',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : CookieWebView(
                    url: exam.analysisUrl,
                    cookies: cookies,
                    html: _html,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _infoPage(BuildContext context) {
    final exam = widget.exam;
    final color = exam.status.contains('过期')
        ? const Color(0xFF8A8A8E)
        : exam.status.contains('已完成')
        ? const Color(0xFF2E8B57)
        : AppColors.usstRed;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('考试详情')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  exam.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.course.name,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _tag(exam.status.isEmpty ? '—' : exam.status, color),
                    if (exam.score.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 8),
                      _tag('${exam.score} 分', const Color(0xFF2E8B57)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (exam.remaining.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _card(
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.schedule,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    exam.remaining,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _card(
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _finished
                        ? '老师还没有公布答卷，暂时看不到题目和答案。'
                        : '作答请到网页里进行，App 只做信息展示。',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _openWebExam(context),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('去网页查看 / 参加考试'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              minimumSize: const Size.fromHeight(46),
            ),
          ),
        ],
      ),
    );
  }

  void _openWebExam(BuildContext context) {
    final cookies =
        ChaoxingAuth.instance.client?.jar.cookies ?? const <CasCookie>[];
    final url =
        'https://mooc1.chaoxing.com/mooc-ans/mooc2/exam/exam-list'
        '?courseid=${widget.course.courseId}&clazzid=${widget.course.classId}'
        '&personid=${widget.course.cpi}';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimpleWebPage(title: '考试', url: url, cookies: cookies),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
