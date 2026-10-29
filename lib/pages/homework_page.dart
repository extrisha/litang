import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../app_theme.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/attachment_cache.dart';
import '../data/lms/homework_api.dart';
import '../data/lms/todo_api.dart';
import '../data/lms/tronclass_auth.dart';
import '../services/reminder_service.dart';
import 'homework_submit_page.dart';
import '../data/lms/exam_forum_api.dart';
import 'image_preview_page.dart';
import 'pdf_preview_page.dart';
import 'simple_web_page.dart';
import 'tron_exam_detail_page.dart';

/// 作业详情（原生）：只保留标题、截止时间、状态、说明和附件。
class HomeworkPage extends StatefulWidget {
  const HomeworkPage({super.key, required this.todo});

  final LmsTodo todo;

  @override
  State<HomeworkPage> createState() => _HomeworkPageState();
}

class _HomeworkPageState extends State<HomeworkPage> {
  HomeworkDetail? _detail;
  List<HomeworkSubmission> _submissions = const <HomeworkSubmission>[];
  bool? _reminderOn;
  bool _loading = true;
  String? _error;
  int? _openingId;

  @override
  void initState() {
    super.initState();
    _load();
    _loadReminder();
  }

  Future<void> _loadReminder() async {
    final on = await ReminderService.instance.isReminderEnabled(
      'tron:${widget.todo.id}',
    );
    if (mounted) setState(() => _reminderOn = on);
  }

  /// 详情接口里才有准确截止时间（从通知点进来时 widget.todo 可能没有）。
  DateTime? get _deadline => _detail?.deadline ?? widget.todo.deadline;

  Future<void> _toggleReminder(bool value) async {
    setState(() => _reminderOn = value);
    await ReminderService.instance.setReminderEnabled(
      'tron:${widget.todo.id}',
      value,
    );
    if (value) {
      await ReminderService.instance.scheduleHomeworkOne(
        LmsTodo(
          id: widget.todo.id,
          courseId: widget.todo.courseId,
          title: widget.todo.title,
          courseName: widget.todo.courseName,
          type: widget.todo.type,
          deadline: _deadline,
        ),
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(value ? '已开启截止提醒' : '已关闭截止提醒')));
  }

  Widget _reminderCard() {
    final on = _reminderOn;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SwitchListTile.adaptive(
        value: on ?? true,
        onChanged: on == null ? null : _toggleReminder,
        activeThumbColor: AppColors.usstRed,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('截止前提醒我', style: TextStyle(fontSize: 13.5)),
        subtitle: const Text(
          '截止前 1 天和 2 小时各提醒一次',
          style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Future<void> _load() async {
    final ok = await TronclassAuth.instance.ensureLoggedIn();
    final client = JwglAuth.instance.client;
    if (!ok || client == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '一网畅学登录失败，请稍后重试';
        });
      }
      return;
    }
    try {
      final api = HomeworkApi(client);
      final detail = await api.fetch(widget.todo.id);
      // 历史提交要单独查：接口按课程返回，再按 activity_id 过滤。
      var submissions = const <HomeworkSubmission>[];
      try {
        final all = await api.fetchSubmissions(widget.todo.courseId);
        submissions = all.where((s) => s.activityId == widget.todo.id).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } catch (_) {
        submissions = const <HomeworkSubmission>[];
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail;
        _submissions = submissions;
        _loading = false;
      });
    } catch (e) {
      // 容错：有些选择题/客观题测试在接口里可能被当作测试/考试处理，尝试查考试接口
      try {
        await TronExamForumApi(client).fetchExam(widget.todo.id);
        if (mounted) {
          // 如果确实是测验/考试，直接无缝跳转到测验详情页并替换当前页
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => TronExamDetailPage(
                courseId: widget.todo.courseId.toString(),
                examId: widget.todo.id,
                courseName: widget.todo.courseName,
              ),
            ),
          );
          return;
        }
      } catch (_) {
        // 说明既不是普通作业也不是考试接口，或者网络错误
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '作业详情加载失败，请稍后重试';
        });
      }
    }
  }

  int get _effectiveCourseId {
    if (widget.todo.courseId > 0) {
      return widget.todo.courseId;
    }
    return _detail?.courseId ?? 0;
  }

  Future<void> _openWeb() async {
    final cookies = await TronclassAuth.instance.getMergedCookies();
    final courseId = _effectiveCourseId;
    final isExam = widget.todo.type == 'exam' || widget.todo.type == 'quiz';
    final targetRoute = isExam ? 'exam/${widget.todo.id}' : '${widget.todo.id}';
    final url =
        'https://1906.usst.edu.cn/course/$courseId'
        '/learning-activity/full-screen#/$targetRoute';
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimpleWebPage(
          title: widget.todo.courseName.isEmpty ? '作业详情' : widget.todo.courseName,
          url: url,
          cookies: cookies,
        ),
      ),
    );
    if (mounted) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('作业详情'),
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
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TextButton(
                          onPressed: _load,
                          child: const Text('重试'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _openWeb,
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('在网页中打开'),
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
                _header(detail!),
                const SizedBox(height: 12),
                _infoCard(detail),
                if (_deadline != null && !detail.closed) ...<Widget>[
                  const SizedBox(height: 12),
                  _reminderCard(),
                ],
                if (detail.description.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  _descriptionCard(detail.description),
                ],
                if (detail.attachments.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  _attachmentCard(detail.attachments),
                ],
                if (_submissions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  _submissionCard(),
                ],
                const SizedBox(height: 20),
                if (detail.closed)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: <Widget>[
                        Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '作业已截止，不能再提交了。',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('提交作业'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.usstRed,
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _header(HomeworkDetail detail) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            detail.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            widget.todo.courseName,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _tag(
                detail.submitted ? '已提交' : '未提交',
                detail.submitted ? const Color(0xFF2E8B57) : AppColors.usstRed,
              ),
              const SizedBox(width: 8),
              _tag(detail.typeLabel, AppColors.textSecondary),
              if (detail.closed) ...<Widget>[
                const SizedBox(width: 8),
                _tag('已截止', const Color(0xFFB03A2E)),
              ],
            ],
          ),
        ],
      ),
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

  Widget _infoCard(HomeworkDetail detail) {
    final deadline = detail.deadline;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.schedule, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            deadline == null ? '截止时间未公布' : '截止 ${_formatTime(deadline)}',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _descriptionCard(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '作业要求',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(fontSize: 13, height: 1.6)),
        ],
      ),
    );
  }

  Widget _attachmentCard(List<HomeworkAttachment> attachments) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '附件',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          for (final file in attachments)
            InkWell(
              onTap: () => _openAttachment(file),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.attach_file,
                      size: 15,
                      color: AppColors.usstRed,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    Text(
                      file.sizeLabel,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (_openingId == file.id)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(
                        Icons.chevron_right,
                        size: 15,
                        color: AppColors.textSecondary,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final client = JwglAuth.instance.client;
    if (client == null) {
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => HomeworkSubmitPage(
          title: widget.todo.title,
          subtitle: widget.todo.courseName,
          onSubmit: (payload) async {
            final uploads = payload.attachments
                .map((a) => HomeworkFile(name: a.name, bytes: a.bytes))
                .toList();
            await HomeworkApi(client)
                .submitHomework(widget.todo.id, uploads, comment: payload.text);
          },
        ),
      ),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('作业已提交')));
      await _load();
    }
  }

  Widget _submissionCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.history, size: 16, color: AppColors.usstRed),
              const SizedBox(width: 6),
              const Text(
                '我的提交',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${_submissions.length} 次',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          for (var i = 0; i < _submissions.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 20),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '第 ${_submissions.length - i} 次 · '
                    '${_submissions[i].createdAt}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (_submissions[i].score != null)
                  Text(
                    '${_submissions[i].score!.toStringAsFixed(1)} 分',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF2E8B57),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            if (_submissions[i].comment.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _submissions[i].comment,
                style: const TextStyle(fontSize: 12.5, height: 1.6),
              ),
            ],
            for (final file in _submissions[i].attachments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(
                  Icons.insert_drive_file_outlined,
                  size: 18,
                  color: AppColors.usstRed,
                ),
                title: Text(file.name, style: const TextStyle(fontSize: 12.5)),
                subtitle: file.sizeLabel.isEmpty
                    ? null
                    : Text(
                        file.sizeLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                trailing: _openingId == file.id
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.open_in_new,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                onTap: _openingId == null ? () => _openAttachment(file) : null,
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _openAttachment(HomeworkAttachment file) async {
    final client = JwglAuth.instance.client;
    if (client == null) {
      return;
    }
    final lower = file.name.toLowerCase();
    final isPdf = lower.endsWith('.pdf');
    final isImage = isImageName(file.name);
    // 图片直接内置预览，和 PDF 一样不再弹“下载后打开”。
    if (isImage) {
      setState(() => _openingId = file.id);
      try {
        final bytes = await HomeworkApi(client).fetchBlob(file.id);
        final path = await AttachmentCache.save(file.name, bytes);
        if (!mounted) {
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ImagePreviewPage(title: file.name, path: path),
          ),
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('图片加载失败，请稍后重试')));
        }
      } finally {
        if (mounted) {
          setState(() => _openingId = null);
        }
      }
      return;
    }
    if (!isPdf) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('下载附件'),
          content: Text(
            '${file.name}'
            '${file.sizeLabel.isEmpty ? '' : '（${file.sizeLabel}）'}'
            '\n\n不是 PDF，需要下载后用其他应用打开。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('下载'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) {
        return;
      }
      setState(() => _openingId = file.id);
      try {
        final bytes = await HomeworkApi(client).fetchBlob(file.id);
        final path = await AttachmentCache.save(file.name, bytes);
        final result = await OpenFilex.open(path);
        if (result.type != ResultType.done && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.message.isEmpty ? '没有可打开该附件的应用' : result.message,
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
        if (mounted) {
          setState(() => _openingId = null);
        }
      }
      return;
    }

    setState(() => _openingId = file.id);
    try {
      final bytes = await HomeworkApi(client).fetchBlob(file.id);
      final path = await AttachmentCache.save(file.name, bytes);
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PdfPreviewPage(title: file.name, path: path),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('PDF 加载失败，请稍后重试')));
      }
    } finally {
      if (mounted) {
        setState(() => _openingId = null);
      }
    }
  }

  String _formatTime(DateTime time) {
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    return '$m-$d $h:$min';
  }
}
