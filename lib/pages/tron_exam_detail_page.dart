import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/lms/exam_forum_api.dart';
import '../data/lms/tronclass_auth.dart';
import 'simple_web_page.dart';

/// 一网畅学考试详情：时间、题数、总分、我的得分与提交记录。
///
/// 考试相关的内容不在 App 里做（风险太高），实际作答/查看都跳网页。
class TronExamDetailPage extends StatefulWidget {
  const TronExamDetailPage({
    super.key,
    required this.courseId,
    required this.examId,
    required this.courseName,
  });

  final String courseId;
  final int examId;
  final String courseName;

  @override
  State<TronExamDetailPage> createState() => _TronExamDetailPageState();
}

class _TronExamDetailPageState extends State<TronExamDetailPage> {
  TronExamDetail? _detail;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await TronclassAuth.instance.ensureLoggedIn();
      final client = JwglAuth.instance.client;
      if (client == null) {
        setState(() {
          _loading = false;
          _error = '请先登录教务系统';
        });
        return;
      }
      final detail = await TronExamForumApi(client).fetchExam(widget.examId);
      if (mounted) {
        setState(() {
          _detail = detail;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '考试详情加载失败';
        });
      }
    }
  }

  String get _effectiveCourseId {
    if (widget.courseId.isNotEmpty && widget.courseId != '0') {
      return widget.courseId;
    }
    if (_detail != null && _detail!.courseId > 0) {
      return _detail!.courseId.toString();
    }
    return widget.courseId;
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('测验与考试'),
        actions: <Widget>[
          IconButton(
            tooltip: '在网页中打开',
            icon: const Icon(Icons.open_in_new, size: 20),
            onPressed: _openWeb,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || detail == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _error ?? '暂无数据',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TextButton(onPressed: _load, child: const Text('重试')),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _openWeb,
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('直接在网页中打开作答'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.usstRed,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: <Widget>[
                _header(detail),
                const SizedBox(height: 12),
                _infoCard(detail),
                if (detail.description.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  _card(
                    child: Text(
                      detail.description,
                      style: const TextStyle(fontSize: 13, height: 1.7),
                    ),
                  ),
                ],
                if (detail.submissions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  _submissionCard(detail),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _openWeb,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(detail.closed ? '在网页中查看' : '去网页作答'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.usstRed,
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _openWeb() async {
    final cookies = await TronclassAuth.instance.getMergedCookies();
    final courseId = _effectiveCourseId;
    final url =
        'https://1906.usst.edu.cn/course/$courseId'
        '/learning-activity/full-screen#/exam/${widget.examId}';
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimpleWebPage(
          title: widget.courseName.isEmpty ? '测验与考试' : widget.courseName,
          url: url,
          cookies: cookies,
        ),
      ),
    );
    if (mounted) {
      _load();
    }
  }

  Widget _header(TronExamDetail detail) {
    final color = detail.closed
        ? const Color(0xFF8A8A8E)
        : (detail.started ? AppColors.usstRed : const Color(0xFF2E6FA3));
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            detail.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            widget.courseName,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _tag(detail.status, color),
              if (detail.score != null) ...<Widget>[
                const SizedBox(width: 8),
                _tag('得分 ${_num(detail.score)}', const Color(0xFF2E8B57)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoCard(TronExamDetail detail) {
    return _card(
      child: Column(
        children: <Widget>[
          _row('开始时间', detail.startAt.isEmpty ? '未公布' : detail.startAt),
          _divider(),
          _row('结束时间', detail.endAt.isEmpty ? '未公布' : detail.endAt),
          _divider(),
          _row(
            '题目 / 总分',
            '${detail.subjectsCount} 题'
                '${detail.totalPoints == null ? '' : ' · ${_num(detail.totalPoints)} 分'}',
          ),
          _divider(),
          _row(
            '作答次数',
            detail.submitTimes > 0
                ? '已提交 ${detail.submittedTimes} / 可提交 ${detail.submitTimes}'
                : '已提交 ${detail.submittedTimes}',
          ),
        ],
      ),
    );
  }

  Widget _submissionCard(TronExamDetail detail) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '提交记录',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < detail.submissions.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 18),
            Row(
              children: <Widget>[
                Text(
                  '第 ${i + 1} 次',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        detail.submissions[i].methodText.isEmpty
                            ? '已提交'
                            : detail.submissions[i].methodText,
                        style: const TextStyle(fontSize: 13),
                      ),
                      if (detail.submissions[i].submittedAt.isNotEmpty)
                        Text(
                          detail.submissions[i].submittedAt,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  detail.submissions[i].score == null
                      ? '—'
                      : '${_num(detail.submissions[i].score)} 分',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, color: Color(0xFFF0F0F2));

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

  static String _num(double? value) {
    if (value == null) return '—';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }
}
