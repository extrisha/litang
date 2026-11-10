import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfx/pdfx.dart';

import '../app_theme.dart';

/// 本地 PDF 预览（支持双指缩放）。
class PdfPreviewPage extends StatefulWidget {
  const PdfPreviewPage({super.key, required this.title, required this.path});

  final String title;
  final String path;

  @override
  State<PdfPreviewPage> createState() => _PdfPreviewPageState();
}

class _PdfPreviewPageState extends State<PdfPreviewPage> {
  PdfControllerPinch? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final document = await PdfDocument.openFile(widget.path);
      if (!mounted) {
        await document.close();
        return;
      }
      _controller = PdfControllerPinch(document: Future.value(document));
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'PDF 打开失败');
      }
    }
  }

  Future<void> _openExternal() async {
    final result = await OpenFilex.open(widget.path);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message.isEmpty ? '没有可打开 PDF 的应用' : result.message,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
            tooltip: '下载 / 用其他应用打开',
            icon: const Icon(Icons.download_outlined),
            onPressed: _openExternal,
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            )
          : _controller == null
          ? const Center(child: CircularProgressIndicator())
          : PdfViewPinch(controller: _controller!),
    );
  }
}
