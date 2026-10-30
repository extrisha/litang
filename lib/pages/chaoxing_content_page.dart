import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_theme.dart';
import '../data/attachment_cache.dart';
import '../data/chaoxing/chaoxing_auth.dart';
import '../data/chaoxing/chaoxing_client.dart';
import '../data/chaoxing/chaoxing_course_detail.dart';
import 'chaoxing_video_page.dart';
import 'docx_text_page.dart';
import 'pdf_preview_page.dart';

/// 学习通章节内容：原生附件列表 + PDF/文档预览 + 右上角下载。
class ChaoxingContentPage extends StatefulWidget {
  const ChaoxingContentPage({
    super.key,
    required this.course,
    required this.chapterId,
    required this.title,
  });

  final ChaoxingCourse course;
  final String chapterId;
  final String title;

  @override
  State<ChaoxingContentPage> createState() => _ChaoxingContentPageState();
}

class _ChaoxingContentPageState extends State<ChaoxingContentPage> {
  List<ChaoxingCourseAttachment>? _attachments;
  String? _error;
  String? _openingObjectId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final auth = ChaoxingAuth.instance;
      if (!auth.isLoggedIn) await auth.restore();
      if (!await auth.ensureSession()) {
        setState(() => _error = '学习通登录已失效');
        return;
      }
      final client = auth.client;
      if (client == null) return;
      final list = await ChaoxingCourseDetailApi(client)
          .fetchAttachments(widget.course, widget.chapterId);
      if (mounted) setState(() => _attachments = list);
    } catch (_) {
      if (mounted) setState(() => _error = '章节内容加载失败');
    }
  }

  Future<void> _open(ChaoxingCourseAttachment attachment) async {
    if (_openingObjectId != null) return;
    setState(() => _openingObjectId = attachment.objectId);
    try {
      final auth = ChaoxingAuth.instance;
      final client = auth.client;
      if (client == null) throw Exception('登录失效');
      final api = ChaoxingCourseDetailApi(client);
      final yun = await api.fetchYunFile(attachment.objectId);

      final lowerName = attachment.name.toLowerCase();
      // 接口直接给了 isVideo 就用它；其余按后缀兜底，避免漏掉 mpg/mov 这类。
      final isVideo =
          attachment.isVideo ||
          lowerName.endsWith('.mp4') ||
          lowerName.endsWith('.flv') ||
          lowerName.endsWith('.wmv') ||
          lowerName.endsWith('.avi') ||
          lowerName.endsWith('.rmvb') ||
          lowerName.endsWith('.mpg') ||
          lowerName.endsWith('.mpeg') ||
          lowerName.endsWith('.mov') ||
          lowerName.endsWith('.m4v');
      if (isVideo) {
        final stream = yun?.streamUrl ?? '';
        if (stream.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('这个视频暂时没有可播放地址')));
          }
          return;
        }
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ChaoxingVideoPage(title: attachment.name, url: stream),
          ),
        );
        return;
      }
      final isPdf =
          attachment.name.toLowerCase().endsWith('.pdf') ||
          (yun?.pdfUrl.isNotEmpty ?? false);
      final cacheName = isPdf && !lowerName.endsWith('.pdf')
          ? '${attachment.name}.pdf'
          : attachment.name;
      var path = await AttachmentCache.existing(cacheName);
      String? remote = isPdf ? yun?.pdfUrl : yun?.downloadUrl;
      if (remote == null || remote.isEmpty) {
        remote = yun?.pdfUrl.isNotEmpty == true
            ? yun!.pdfUrl
            : yun?.downloadUrl;
      }
      if (path == null && remote != null && remote.isNotEmpty) {
        final bytes = await _fetchBytes(remote);
        if (bytes.isNotEmpty) {
          path = await AttachmentCache.save(cacheName, bytes);
        }
      }
      if (!mounted) return;

      if (path == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('这个附件暂时没有可用的下载地址')));
        return;
      }
      final lower = attachment.name.toLowerCase();
      if (isPdf || lower.endsWith('.pdf')) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PdfPreviewPage(title: attachment.name, path: path!),
          ),
        );
      } else if (lower.endsWith('.docx')) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DocxTextPage(title: attachment.name, path: path!),
          ),
        );
      } else {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('下载完成'),
            content: Text(
              '${attachment.name} 已保存。\n'
              '视频或特殊格式建议使用对应播放器/Office 打开。',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
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
      if (mounted) setState(() => _openingObjectId = null);
    }
  }

  Future<List<int>> _fetchBytes(String url) async {
    var uri = Uri.parse(url);
    if (uri.scheme == 'http') {
      uri = uri.replace(scheme: 'https');
    }
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..headers['User-Agent'] = 'Mozilla/5.0';
      final response =
          await client.send(request).timeout(const Duration(seconds: 120));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }
      const maxDownloadSize = 50 * 1024 * 1024; // 50MB
      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > maxDownloadSize) {
        throw Exception('附件过大（超过 50MB），建议在网页端下载');
      }
      final bytes = await response.stream.toBytes();
      if (bytes.length > maxDownloadSize) {
        throw Exception('附件过大（超过 50MB），建议在网页端下载');
      }
      return bytes;
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _attachments;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _load, child: const Text('重试')),
                ],
              ),
            )
          : items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const Center(
              child: Text(
                '这个章节没有可下载内容',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final item = items[i];
                final opening = _openingObjectId == item.objectId;
                return Container(
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
                        color: AppColors.redTint,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.insert_drive_file_outlined,
                        size: 19,
                        color: AppColors.usstRed,
                      ),
                    ),
                    title: Text(
                      item.name,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      _sizeLabel(item.size),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    trailing: opening
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                    onTap: _openingObjectId == null ? () => _open(item) : null,
                  ),
                );
              },
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
