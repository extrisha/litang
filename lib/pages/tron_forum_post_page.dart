import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/lms/exam_forum_api.dart';
import '../data/lms/tronclass_auth.dart';

/// 讨论发言页：发一条新话题。
class TronForumPostPage extends StatefulWidget {
  const TronForumPostPage({
    super.key,
    required this.courseId,
    required this.activityId,
    required this.courseName,
  });

  final String courseId;
  final String activityId;
  final String courseName;

  @override
  State<TronForumPostPage> createState() => _TronForumPostPageState();
}

class _TronForumPostPageState extends State<TronForumPostPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title.addListener(_refresh);
    _content.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _title.text.trim().isNotEmpty && _content.text.trim().isNotEmpty;

  Future<void> _submit() async {
    final title = _title.text.trim();
    final content = _content.text.trim();
    if (content.isEmpty || title.isEmpty || _submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await TronclassAuth.instance.ensureLoggedIn();
      final client = JwglAuth.instance.client;
      if (client == null) {
        throw Exception('登录已失效');
      }
      await TronExamForumApi(client).createTopic(
        courseId: widget.courseId,
        activityId: widget.activityId,
        title: title,
        content: content,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = '发言失败，请稍后重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('发言'),
        actions: <Widget>[
          TextButton(
            onPressed: (_submitting || !_canSubmit) ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    '发布',
                    style: TextStyle(
                      color: _canSubmit
                          ? AppColors.usstRed
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          Text(
            widget.courseName,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          _field(controller: _title, hint: '标题（必填）', maxLines: 1),
          const SizedBox(height: 10),
          _field(
            controller: _content,
            hint: '说点什么…',
            maxLines: 10,
            autofocus: true,
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: AppColors.usstRed),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_submitting || !_canSubmit) ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              minimumSize: const Size.fromHeight(46),
            ),
            child: const Text('发布'),
          ),
          const SizedBox(height: 10),
          const Text(
            '发布后会出现在这门课的讨论里，所有选课同学可见。',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required int maxLines,
    bool autofocus = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        autofocus: autofocus,
        // `_canSubmit` 是在 build 里算的，而 TextField 改内容只会重建它自己，
        // 不会重建页面。没有这个回调的话，「发布」按钮永远停在禁用状态——
        // 内容都填满了也点不动。
        onChanged: (_) {
          if (mounted) setState(() {});
        },
        textInputAction: maxLines == 1
            ? TextInputAction.next
            : TextInputAction.newline,
        style: const TextStyle(fontSize: 14, height: 1.6),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
