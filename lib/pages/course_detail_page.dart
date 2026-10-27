import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../app_theme.dart';
import '../data/attachment_cache.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/lms/course_detail_api.dart';
import '../data/lms/homework_api.dart';
import '../data/lms/todo_api.dart';
import '../data/lms/tronclass_auth.dart';
import 'homework_page.dart';
import 'tron_content_page.dart';
import 'tron_exam_detail_page.dart';
import 'tron_forum_detail_page.dart';

/// 一网畅学课程详情（原生页面）。
class TronCourseDetailPage extends StatefulWidget {
  const TronCourseDetailPage({
    super.key,
    required this.courseName,
    required this.courseId,
  });

  final String courseName;
  final String courseId;

  @override
  State<TronCourseDetailPage> createState() => _TronCourseDetailPageState();
}

class _TronCourseDetailPageState extends State<TronCourseDetailPage> {
  TronCourseDetail? _detail;
  String? _error;
  bool _loading = true;
  int? _openingAttachmentId;

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
        setState(() => _error = '请先登录教务系统');
        return;
      }
      final detail = await TronCourseDetailApi(client).fetch(widget.courseId);
      if (mounted) setState(() => _detail = detail);
    } catch (_) {
      if (mounted) setState(() => _error = '课程详情拉取失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.courseName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || detail == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.courseName)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _error ?? '暂无数据',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              TextButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.courseName, overflow: TextOverflow.ellipsis),
          bottom: TabBar(
            labelColor: AppColors.usstRed,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.usstRed,
            tabs: <Widget>[
              Tab(text: '章节 ${detail.chapters.length}'),
              Tab(text: '公告 ${detail.announcements.length}'),
              Tab(text: '作业 ${detail.homeworks.length}'),
              Tab(text: '测试 ${detail.exams.length}'),
              Tab(text: '讨论 ${detail.discussions.length}'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _chapterList(detail.chapters, detail.modules),
            _announcementList(detail.announcements),
            _homeworkList(detail.homeworks),
            _examList(detail.exams),
            _discussionList(detail.discussions),
          ],
        ),
      ),
    );
  }

  Widget _empty(String text) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
    );
  }

  Widget _chapterList(
    List<TronCourseChapter> items,
    Map<String, String> modules,
  ) {
    if (items.isEmpty) return _empty('暂无课程内容');
    final groups = <String, List<TronCourseChapter>>{};
    for (final item in items) {
      final key = item.moduleId.isEmpty
          ? '__single_${item.title}'
          : item.moduleId;
      groups.putIfAbsent(key, () => <TronCourseChapter>[]).add(item);
    }
    final entries = groups.entries.toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final list = entries[i].value;
        if (list.length == 1) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _chapterItem(list.first),
          );
        }
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExpansionTile(
            initiallyExpanded: i == 0,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              modules[entries[i].key] ?? '模块 ${i + 1}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${list.length} 项内容',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
            children: <Widget>[
              for (final item in list)
                ListTile(
                  dense: true,
                  title: Text(item.title, style: const TextStyle(fontSize: 13)),
                  trailing: _tag(item.typeLabel, const Color(0xFF3B5BDB)),
                  onTap: () => _openContent(context, item),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openContent(BuildContext context, TronCourseChapter item) {
    if (item.activityId.isEmpty) {
      _showContent(item.title, item.description);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TronContentPage(
          courseName: widget.courseName,
          activityId: item.activityId,
          title: item.title,
        ),
      ),
    );
  }

  Widget _chapterItem(TronCourseChapter item) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openContent(context, item),
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _tag(item.typeLabel, const Color(0xFF3B5BDB)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (item.description.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                item.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (item.publishTime.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                item.publishTime,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _announcementList(List<TronCourseAnnouncement> items) {
    if (items.isEmpty) return _empty('暂无公告');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final item = items[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showContent(item.title, item.content),
          child: _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.content,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (item.attachments.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  for (final attachment in item.attachments)
                    _attachmentRow(attachment),
                ],
                if (item.createdAt.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    item.createdAt,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _attachmentRow(TronAttachment attachment) {
    final opening = _openingAttachmentId == attachment.id;
    return InkWell(
      onTap: opening ? null : () => _openAttachment(attachment),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.attach_file,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                attachment.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.usstRed),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${attachment.typeLabel} · ${_sizeLabel(attachment.size)}',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            if (opening)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.download_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAttachment(TronAttachment attachment) async {
    if (_openingAttachmentId != null) return;
    setState(() => _openingAttachmentId = attachment.id);
    try {
      await TronclassAuth.instance.ensureLoggedIn();
      final client = JwglAuth.instance.client;
      if (client == null) throw Exception('登录已失效');
      final path =
          await AttachmentCache.existing(attachment.name) ??
          await AttachmentCache.save(
            attachment.name,
            await HomeworkApi(client).fetchBlob(attachment.id),
          );
      if (!mounted) return;
      final result = await OpenFilex.open(path);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已保存到下载目录：${attachment.name}'
              '${result.message.isEmpty ? '' : '\n${result.message}'}',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('附件下载失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _openingAttachmentId = null);
    }
  }

  String _sizeLabel(int bytes) {
    if (bytes <= 0) return '未知大小';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  Widget _homeworkList(List<TronCourseHomework> items) {
    if (items.isEmpty) return _empty('暂无作业');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final item = items[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final id = int.tryParse(widget.courseId) ?? 0;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HomeworkPage(
                  todo: LmsTodo(
                    id: item.id,
                    courseId: id,
                    title: item.title,
                    courseName: widget.courseName,
                    type: 'homework',
                    deadline: null,
                  ),
                ),
              ),
            );
          },
          child: _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.assignment_outlined,
                      size: 18,
                      color: Color(0xFF3B5BDB),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.description.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                if (item.deadline.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    '截止 ${item.deadline}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _examList(List<TronCourseExam> items) {
    if (items.isEmpty) return _empty('暂无测试');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final item = items[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TronExamDetailPage(
                courseId: widget.courseId,
                examId: item.id,
                courseName: widget.courseName,
              ),
            ),
          ),
          child: _card(
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF5FF),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.assignment_outlined,
                    size: 20,
                    color: Color(0xFF3B5BDB),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item.startAt.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          '${item.startAt} ~ ${item.endAt}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    _tag(item.status, AppColors.usstRed),
                    if (item.score != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        '${item.score!.toStringAsFixed(0)} 分',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _discussionList(List<TronCourseDiscussion> items) {
    if (items.isEmpty) return _empty('暂无讨论');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final item = items[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TronForumDetailPage(
                courseId: widget.courseId,
                activityId: item.id,
                title: item.title,
                description: item.description,
                courseName: widget.courseName,
              ),
            ),
          ),
          child: _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
                if (item.description.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    item.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }

  void _showContent(String title, String content) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(18),
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(content, style: const TextStyle(fontSize: 13, height: 1.7)),
          ],
        ),
      ),
    );
  }
}
