import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/chaoxing/chaoxing_auth.dart';
import '../data/chaoxing/chaoxing_client.dart';
import '../services/reminder_service.dart';
import 'homework_submit_page.dart';
import 'simple_web.dart';

/// 学习通作业详情（原生），避免 WebView 登录态问题。
class ChaoxingHomeworkPage extends StatefulWidget {
  const ChaoxingHomeworkPage({super.key, required this.work});

  final ChaoxingWork work;

  @override
  State<ChaoxingHomeworkPage> createState() => _ChaoxingHomeworkPageState();
}

class _ChaoxingHomeworkPageState extends State<ChaoxingHomeworkPage> {
  ChaoxingWorkDetail? _detail;
  bool? _reminderOn;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _loadReminder();
  }

  Future<void> _loadReminder() async {
    final on = await ReminderService.instance.isReminderEnabled(
      'cx:${widget.work.workId}',
    );
    if (mounted) setState(() => _reminderOn = on);
  }

  Future<void> _toggleReminder(bool value) async {
    setState(() => _reminderOn = value);
    await ReminderService.instance.setReminderEnabled(
      'cx:${widget.work.workId}',
      value,
    );
    if (value) {
      await ReminderService.instance.scheduleChaoxingOne(widget.work);
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
          '按「剩余时间」推算，截止前 1 天和 2 小时各提醒一次',
          style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Future<void> _load() async {
    final auth = ChaoxingAuth.instance;
    if (!auth.isLoggedIn && !await auth.ensureSession()) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '学习通登录已失效';
        });
      }
      return;
    }
    final client = auth.client;
    if (client == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '学习通登录已失效';
        });
      }
      return;
    }
    try {
      final detail = await client.fetchWorkDetail(widget.work);
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
          _error = '作业详情加载失败';
        });
      }
    }
  }

  void _openWeb() {
    final client = ChaoxingAuth.instance.client;
    final cookies =
        client?.jar.cookiesForHost('mooc1.chaoxing.com') ?? const <Never>[];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimpleWebPage(
          title: widget.work.title,
          url: widget.work.taskUrl,
          cookies: cookies.cast(),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final detail = _detail;
    if (detail == null || detail.questions.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有解析到题目，请用网页版提交')));
      return;
    }
    final client = ChaoxingAuth.instance.client;
    if (client == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('学习通登录已失效')));
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => HomeworkSubmitPage(
          title: widget.work.title,
          subtitle: widget.work.courseName,
          onSubmit: (payload) async {
            final attachments = payload.attachments
                .map(
                  (a) => ChaoxingAttachment(
                    name: a.name,
                    bytes: a.bytes,
                    isVideo: a.isVideo,
                    isFile: a.kind == SubmitKind.file,
                  ),
                )
                .toList();
            await client.submitWorkContent(
              widget.work,
              detail.questions.first,
              text: payload.text,
              attachments: attachments,
            );
          },
        ),
      ),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('作业已提交，等待老师批阅')));
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('作业详情')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
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
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _openWeb,
                    child: const Text('用网页版打开'),
                  ),
                ],
              ),
            )
          : _content(_detail!),
    );
  }

  Widget _content(ChaoxingWorkDetail detail) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Container(
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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.work.courseName,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              if (detail.info.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  detail.info,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
              if (widget.work.score.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5EE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '得分 ${widget.work.score}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF2E8B57),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!widget.work.finished &&
            !widget.work.expired &&
            ReminderService.parseRemaining(widget.work.deadline) !=
                null) ...<Widget>[_reminderCard(), const SizedBox(height: 12)],
        if (detail.questions.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '没有解析到题目，可点右上角「网页版」查看',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          )
        else
          for (var i = 0; i < detail.questions.length; i++) ...<Widget>[
            _questionCard(i + 1, detail.questions[i]),
            const SizedBox(height: 8),
          ],
        if (detail.hasAnswer) ...<Widget>[
          const SizedBox(height: 12),
          _answerCard(detail),
        ],
        const SizedBox(height: 12),
        if (widget.work.expired)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '该作业已截止，无法提交',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _openWeb,
            child: const Text('用网页版提交', style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _answerCard(ChaoxingWorkDetail detail) {
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
              const Icon(
                Icons.check_circle_outline,
                size: 18,
                color: Color(0xFF2E9E5B),
              ),
              const SizedBox(width: 6),
              const Text(
                '我的提交',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                widget.work.statusText,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (detail.answerText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              detail.answerText,
              style: const TextStyle(fontSize: 12, height: 1.6),
            ),
          ],
          if (detail.answerImages.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final image in detail.answerImages)
                  GestureDetector(
                    onTap: () => _previewImage(image),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        image,
                        width: 110,
                        height: 110,
                        fit: BoxFit.cover,
                        // 只按显示尺寸解码（2x 供高 DPI），避免原图整张进内存
                        cacheWidth: 220,
                        headers: const <String, String>{
                          'Referer': 'https://mooc1.chaoxing.com/',
                          'User-Agent': 'Mozilla/5.0',
                        },
                        errorBuilder: (_, _, _) => Container(
                          width: 110,
                          height: 110,
                          color: const Color(0xFFF1F2F4),
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (detail.answerFiles.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            for (final file in detail.answerFiles)
              Text(
                file,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Color(0xFF3B5BDB)),
              ),
          ],
        ],
      ),
    );
  }

  void _previewImage(String url) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            headers: const <String, String>{
              'Referer': 'https://mooc1.chaoxing.com/',
              'User-Agent': 'Mozilla/5.0',
            },
            errorBuilder: (_, _, _) => const SizedBox(
              width: 200,
              height: 200,
              child: Center(
                child: Text('图片加载失败', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _questionCard(int index, ChaoxingQuestion question) {
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
              Text(
                '第 $index 题',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (question.type.isNotEmpty) ...<Widget>[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.redTint,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    question.type,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.usstRed,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            question.text,
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
        ],
      ),
    );
  }
}
