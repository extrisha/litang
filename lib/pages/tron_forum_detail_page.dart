import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/lms/exam_forum_api.dart';
import '../data/lms/tronclass_auth.dart';
import '../widgets/async_state.dart';
import 'tron_forum_post_page.dart';

/// 一网畅学讨论详情：问题 + 发言列表（可排序、可只看自己）+ 右下角发言。
class TronForumDetailPage extends StatefulWidget {
  const TronForumDetailPage({
    super.key,
    required this.courseId,
    required this.activityId,
    required this.title,
    required this.description,
    required this.courseName,
  });

  final String courseId;
  final String activityId;

  /// 讨论的问题标题（活动标题）。
  final String title;

  /// 讨论的问题正文。
  final String description;
  final String courseName;

  @override
  State<TronForumDetailPage> createState() => _TronForumDetailPageState();
}

class _TronForumDetailPageState extends State<TronForumDetailPage> {
  List<TronForumTopic>? _topics;
  String? _error;
  String _uid = '';
  bool _newestFirst = true;
  bool _onlyMine = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await TronclassAuth.instance.ensureLoggedIn();
      final client = JwglAuth.instance.client;
      if (client == null) {
        setState(() => _error = '请先登录教务系统');
        return;
      }
      final api = TronExamForumApi(client);
      if (_uid.isEmpty) {
        _uid = await api.currentUserId();
      }
      final topics = await api.fetchForumTopics(widget.activityId);
      if (mounted) {
        setState(() => _topics = topics);
      }
    } catch (_) {
      if (mounted) setState(() => _error = '讨论加载失败');
    }
  }

  List<TronForumTopic> get _visible {
    final list = (_topics ?? const <TronForumTopic>[])
        .where((t) => !_onlyMine || (_uid.isNotEmpty && t.authorId == _uid))
        .toList();
    list.sort(
      (a, b) => _newestFirst
          ? b.createdAt.compareTo(a.createdAt)
          : a.createdAt.compareTo(b.createdAt),
    );
    return list;
  }

  int get _mineCount => (_topics ?? const <TronForumTopic>[])
      .where((t) => _uid.isNotEmpty && t.authorId == _uid)
      .length;

  Future<void> _compose() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => TronForumPostPage(
          courseId: widget.courseId,
          activityId: widget.activityId,
          courseName: widget.courseName,
        ),
      ),
    );
    if (created == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('发言已发布')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final topics = _topics;
    final visible = _visible;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('讨论详情')),
      floatingActionButton: FloatingActionButton(
        onPressed: _compose,
        shape: const CircleBorder(),
        backgroundColor: AppColors.usstRed,
        foregroundColor: Colors.white,
        tooltip: '发言',
        child: const Icon(Icons.add),
      ),
      body: _error != null
          ? Center(
              child: AsyncStateView(error: _error, onRetry: _load),
            )
          : topics == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: <Widget>[
                _questionCard(),
                const SizedBox(height: 12),
                _filterBar(visible.length),
                const SizedBox(height: 4),
                if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        _onlyMine ? '你还没有发过言' : '还没有人发言',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  )
                else
                  for (final topic in visible) ...<Widget>[
                    const SizedBox(height: 8),
                    _topicCard(topic),
                  ],
              ],
            ),
    );
  }

  Widget _questionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.title.isNotEmpty) ...<Widget>[
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            widget.description.isEmpty ? '（这个问题没有补充说明）' : widget.description,
            style: const TextStyle(fontSize: 13.5, height: 1.7),
          ),
          const SizedBox(height: 10),
          Text(
            '共 ${_topics?.length ?? 0} 条发言 · 我 $_mineCount 条',
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar(int count) {
    return Row(
      children: <Widget>[
        _chip(
          _newestFirst ? '最新在前' : '最早在前',
          icon: Icons.swap_vert,
          selected: true,
          onTap: () => setState(() => _newestFirst = !_newestFirst),
        ),
        const SizedBox(width: 8),
        _chip(
          '仅我的发言',
          icon: Icons.person_outline,
          selected: _onlyMine,
          onTap: () => setState(() => _onlyMine = !_onlyMine),
        ),
        const Spacer(),
        Text(
          '$count 条',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _chip(
    String label, {
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.redTint : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.usstRed : const Color(0xFFE6E6E9),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 13,
              color: selected ? AppColors.usstRed : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? AppColors.usstRed : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topicCard(TronForumTopic topic) {
    final isMine = _uid.isNotEmpty && topic.authorId == _uid;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isMine
            ? Border.all(color: AppColors.redTint, width: 1.2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  topic.title.isEmpty ? '（无标题）' : topic.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isMine) _mineTag(),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            topic.content,
            style: const TextStyle(fontSize: 13, height: 1.65),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              const Icon(
                Icons.person_outline,
                size: 13,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  <String>[
                    if (topic.author.isNotEmpty) topic.author,
                    if (topic.createdAt.isNotEmpty) topic.createdAt,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (topic.likeCount > 0) ...<Widget>[
                const Icon(
                  Icons.favorite_border,
                  size: 13,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 3),
                Text(
                  '${topic.likeCount}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          if (topic.replies.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFFE6E6E9), width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final reply in topic.replies) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      reply.content,
                      style: const TextStyle(fontSize: 12.5, height: 1.6),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        if (reply.author.isNotEmpty) reply.author,
                        if (reply.createdAt.isNotEmpty) reply.createdAt,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mineTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.redTint,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        '我的',
        style: TextStyle(fontSize: 9.5, color: AppColors.usstRed),
      ),
    );
  }
}
