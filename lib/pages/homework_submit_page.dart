import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';

import '../app_theme.dart';
import '../data/upload_file.dart';

/// 附件类型。
enum SubmitKind { image, video, file }

/// 待提交的附件。
class SubmitAttachment {
  const SubmitAttachment({required this.upload, required this.kind});

  final UploadFile upload;
  String get name => upload.name;
  int get length => upload.length;
  final SubmitKind kind;

  bool get isVideo => kind == SubmitKind.video;
}

/// 提交内容（文字 + 附件）。
class SubmitPayload {
  const SubmitPayload({
    required this.text,
    required this.attachments,
    required this.cancelToken,
    required this.onProgress,
    required this.onSubmitting,
  });

  final String text;
  final List<SubmitAttachment> attachments;
  final CancelToken cancelToken;
  final void Function(double) onProgress;
  final VoidCallback onSubmitting;
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
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  final List<SubmitAttachment> _attachments = <SubmitAttachment>[];
  bool _submitting = false;
  bool _picking = false;
  bool _committing = false;
  double _progress = 0;
  CancelToken? _cancelToken;

  int get _totalBytes => _attachments.fold<int>(0, (sum, a) => sum + a.length);

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 统一包一层：选文件/读文件都会抛（权限被拒、SAF 异常、文件已删除…），
  /// 不兜住的话用户点「添加图片」就是毫无反应。
  Future<void> _guardPick(String action, Future<void> Function() body) async {
    if (_picking || _submitting) return;
    setState(() => _picking = true);
    try {
      await body();
    } catch (e) {
      debugPrint('[submit] $action 失败: $e');
      _toast('$action失败，请检查存储/相册权限后重试');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  void dispose() {
    if (!_committing) _cancelToken?.cancel('已离开提交页面');
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (files.isEmpty || !mounted) return;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      await _addFile(file, SubmitKind.image);
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickVideo() async {
    final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    await _addFile(file, SubmitKind.video);
    if (mounted) setState(() {});
  }

  Future<void> _pickFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[XTypeGroup(label: '文件')],
    );
    if (files.isEmpty || !mounted) return;
    for (final file in files) {
      await _addFile(file, SubmitKind.file);
    }
    if (mounted) setState(() {});
  }

  Future<void> _addFile(XFile file, SubmitKind kind) async {
    final length = await file.length();
    if (!mounted) return;
    final error = UploadFile.selectionError(length, _totalBytes);
    if (error != null) {
      _toast('${file.name}：$error');
      return;
    }
    // Repeated picker taps should not queue the same local file twice.
    if (_attachments.any(
      (a) => a.upload.file.path == file.path && a.length == length,
    )) {
      return;
    }
    _attachments.add(
      SubmitAttachment(
        upload: UploadFile(file: file, name: file.name, length: length),
        kind: kind,
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting || _picking) return;
    final text = _controller.text.trim();
    if (text.isEmpty && _attachments.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写文字或添加附件')));
      return;
    }
    final token = CancelToken();
    setState(() {
      _submitting = true;
      _committing = false;
      _progress = 0;
      _cancelToken = token;
    });
    try {
      await widget.onSubmit(
        SubmitPayload(
          text: text,
          attachments: List<SubmitAttachment>.unmodifiable(_attachments),
          cancelToken: token,
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onSubmitting: () {
            if (mounted) setState(() => _committing = true);
          },
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is DioException && CancelToken.isCancel(e)
                  ? '上传已取消，附件仍保留，可重新提交'
                  : '提交失败：${e.toString().split("\n").first}',
            ),
          ),
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
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
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
                    onPressed: _submitting
                        ? null
                        : () => _guardPick('添加图片', _pickImages),
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
                    onPressed: _submitting
                        ? null
                        : () => _guardPick('添加视频', _pickVideo),
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
                    onPressed: _submitting
                        ? null
                        : () => _guardPick('添加文件', _pickFiles),
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
                        _sizeLabel(_attachments[i].length),
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
            if (_submitting) ...[
              LinearProgressIndicator(value: _committing ? null : _progress),
              Text(
                _committing
                    ? '正在确认提交结果…'
                    : '正在上传 ${(_progress * 100).round()}%',
              ),
              if (!_committing)
                TextButton(
                  onPressed: () => _cancelToken?.cancel('用户取消上传'),
                  child: const Text('取消上传'),
                ),
            ],
            FilledButton(
              onPressed: _submitting || _picking ? null : _submit,
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
      ),
    );
  }

  static String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
