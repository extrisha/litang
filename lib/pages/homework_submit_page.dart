import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';

import '../app_theme.dart';

/// 附件类型。
enum SubmitKind { image, video, file }

/// 待提交的附件。
class SubmitAttachment {
  const SubmitAttachment({
    required this.name,
    required this.bytes,
    required this.kind,
  });

  final String name;
  final List<int> bytes;
  final SubmitKind kind;

  bool get isVideo => kind == SubmitKind.video;
}

/// 提交内容（文字 + 附件）。
class SubmitPayload {
  const SubmitPayload({required this.text, required this.attachments});

  final String text;
  final List<SubmitAttachment> attachments;
}

/// 通用作业提交页：文字输入 + 图片/视频附件。
class HomeworkSubmitPage extends StatefulWidget {
  const HomeworkSubmitPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onSubmit,
    this.initialText = '',
  });

  final String title;
  final String subtitle;
  final String initialText;
  final Future<void> Function(SubmitPayload payload) onSubmit;

  @override
  State<HomeworkSubmitPage> createState() => _HomeworkSubmitPageState();
}

class _HomeworkSubmitPageState extends State<HomeworkSubmitPage> {
  static const int maxSingleAttachmentBytes = 50 * 1024 * 1024; // 50MB

  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  final List<SubmitAttachment> _attachments = <SubmitAttachment>[];
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (files.isEmpty || !mounted) return;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final length = await file.length();
      if (length > maxSingleAttachmentBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('图片 ${file.name} 超过 50MB，无法添加')),
          );
        }
        continue;
      }
      final bytes = await file.readAsBytes();
      _attachments.add(
        SubmitAttachment(
          name: file.name.isEmpty
              ? 'image_${DateTime.now().millisecondsSinceEpoch}_$i.jpg'
              : file.name,
          bytes: bytes,
          kind: SubmitKind.image,
        ),
      );
    }
    setState(() {});
  }

  Future<void> _pickVideo() async {
    final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final length = await file.length();
    if (length > maxSingleAttachmentBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('视频文件过大（超过 50MB），请压缩后添加')),
        );
      }
      return;
    }
    final bytes = await file.readAsBytes();
    _attachments.add(
      SubmitAttachment(
        name: file.name.isEmpty
            ? 'video_${DateTime.now().millisecondsSinceEpoch}.mp4'
            : file.name,
        bytes: bytes,
        kind: SubmitKind.video,
      ),
    );
    setState(() {});
  }

  Future<void> _pickFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[XTypeGroup(label: '文件')],
    );
    if (files.isEmpty || !mounted) return;
    for (final file in files) {
      final length = await file.length();
      if (length > maxSingleAttachmentBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('文件 ${file.name} 超过 50MB，无法添加')),
          );
        }
        continue;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) continue;
      _attachments.add(
        SubmitAttachment(name: file.name, bytes: bytes, kind: SubmitKind.file),
      );
    }
    setState(() {});
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachments.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写文字或添加附件')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        SubmitPayload(
          text: text,
          attachments: List<SubmitAttachment>.unmodifiable(_attachments),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提交失败：${e.toString().split("\n").first}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('提交作业')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.subtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    widget.subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              controller: _controller,
              minLines: 5,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '输入文字说明或答案（可选）',
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickImages,
                  icon: const Icon(Icons.image_outlined, size: 15),
                  label: const Text('添加图片', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickVideo,
                  icon: const Icon(Icons.videocam_outlined, size: 15),
                  label: const Text('添加视频', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickFiles,
                  icon: const Icon(Icons.attach_file, size: 15),
                  label: const Text('添加文件', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                  ),
                ),
              ),
            ],
          ),
          if (_attachments.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            for (var i = 0; i < _attachments.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      switch (_attachments[i].kind) {
                        SubmitKind.video => Icons.videocam_outlined,
                        SubmitKind.file => Icons.insert_drive_file_outlined,
                        SubmitKind.image => Icons.image_outlined,
                      },
                      size: 16,
                      color: AppColors.usstRed,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _attachments[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      _sizeLabel(_attachments[i].bytes.length),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _attachments.removeAt(i)),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              minimumSize: const Size.fromHeight(46),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('提交'),
          ),
        ],
      ),
    );
  }

  static String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
