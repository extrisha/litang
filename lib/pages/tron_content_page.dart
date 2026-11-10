import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../app_theme.dart';
import '../data/attachment_cache.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/lms/course_detail_api.dart';
import '../data/lms/homework_api.dart';
import '../data/lms/tronclass_auth.dart';
import '../widgets/async_state.dart';
import 'docx_text_page.dart';
import 'image_preview_page.dart';
import 'pdf_preview_page.dart';

/// 一网畅学单个资料/视频活动的原生详情页。
class TronContentPage extends StatefulWidget {
  const TronContentPage({
    super.key,
    required this.courseName,
    required this.activityId,
    required this.title,
  });

  final String courseName;
  final String activityId;
  final String title;

  @override
  State<TronContentPage> createState() => _TronContentPageState();
}

class _TronContentPageState extends State<TronContentPage> {
  TronActivityDetail? _detail;
  String? _error;
  int? _openingId;
  String? _downloadKey;

  @override
  void dispose() {
    if (_downloadKey != null) AttachmentCache.cancel(_downloadKey!);
    super.dispose();
  }

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
      final detail = await TronCourseDetailApi(client)
          .fetchActivity(widget.activityId);
      if (mounted) setState(() => _detail = detail);
    } catch (_) {
      if (mounted) setState(() => _error = '内容加载失败');
    }
  }

  /// 正文：页面 / 链接类活动只有 content 有内容，附件类活动常常只有 description。
  /// 两者相同时只渲染一次，避免重复。
  List<String> get _blocks {
    final detail = _detail;
    if (detail == null) return const <String>[];
    return <String>[
      if (detail.description.isNotEmpty) detail.description,
      if (detail.content.isNotEmpty && detail.content != detail.description)
        detail.content,
    ];
  }

  Future<void> _open(TronAttachment attachment) async {
    if (_openingId != null) return;
    setState(() => _openingId = attachment.id);
    try {
      await TronclassAuth.instance.ensureLoggedIn();
      final client = JwglAuth.instance.client;
      if (client == null) throw Exception('登录已失效');
      final api = HomeworkApi(client);
      _downloadKey = api.attachmentKey(attachment.id, size: attachment.size);
      final path = await api.cachedAttachment(
        attachment.id,
        attachment.name,
        size: attachment.size,
      );
      _downloadKey = null;
      if (!mounted) return;
      final lower = attachment.name.toLowerCase();
      if (isImageName(attachment.name)) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ImagePreviewPage(title: attachment.name, path: path),
          ),
        );
      } else if (lower.endsWith('.pdf')) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PdfPreviewPage(title: attachment.name, path: path),
          ),
        );
      } else if (lower.endsWith('.docx')) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DocxTextPage(title: attachment.name, path: path),
          ),
        );
      } else {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('下载完成'),
            content: Text(
              '${attachment.name} 已保存到下载文件夹。\n'
              '建议使用 WPS Office 或 Microsoft Office 打开。',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await OpenFilex.open(path);
                },
                child: const Text('打开'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('附件下载失败，请稍后重试')));
      }
    } finally {
      _downloadKey = null;
      if (mounted) setState(() => _openingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: _error != null
          ? Center(
              child: AsyncStateView(error: _error, onRetry: _load),
            )
          : detail == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                for (final text in _blocks)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      text,
                      style: const TextStyle(fontSize: 13, height: 1.7),
                    ),
                  ),
                if (detail.attachments.isEmpty)
                  const Text(
                    '这个内容没有可下载附件',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  )
                else
                  for (final attachment in detail.attachments)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF5FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            attachment.typeLabel,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Color(0xFF3B5BDB),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        title: Text(
                          attachment.name,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          _sizeLabel(attachment.size),
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        trailing: _openingId == attachment.id
                            ? IconButton(
                                tooltip: '取消下载',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  if (_downloadKey != null) {
                                    AttachmentCache.cancel(_downloadKey!);
                                  }
                                },
                              )
                            : const Icon(
                                Icons.chevron_right,
                                size: 20,
                                color: AppColors.textSecondary,
                              ),
                        onTap: _openingId == null
                            ? () => _open(attachment)
                            : null,
                      ),
                    ),
              ],
            ),
    );
  }

  static String _sizeLabel(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
