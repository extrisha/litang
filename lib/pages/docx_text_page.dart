import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../app_theme.dart';

/// 极简 DOCX 阅读器：解压 document.xml，按段落提取文字。
/// 不保留复杂排版/图片，但足够在 App 内查看文档内容。
class DocxTextPage extends StatefulWidget {
  const DocxTextPage({super.key, required this.title, required this.path});

  final String title;
  final String path;

  @override
  State<DocxTextPage> createState() => _DocxTextPageState();
}

class _DocxTextPageState extends State<DocxTextPage> {
  static const int maxDocxFileSize = 20 * 1024 * 1024; // 20 MB
  static const int maxXmlDecompressedSize = 15 * 1024 * 1024; // 15 MB

  String? _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.path);
      if (!await file.exists()) {
        if (mounted) setState(() => _error = '文档文件不存在');
        return;
      }
      final size = await file.length();
      if (size > maxDocxFileSize) {
        if (mounted) {
          setState(() => _error = '文档文件过大（超过 20MB），请使用右上角外部应用打开');
        }
        return;
      }
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final entry = archive.files.firstWhere(
        (e) => e.name == 'word/document.xml',
        orElse: () => throw Exception('不是有效的 DOCX'),
      );
      final entryBytes = entry.content as List<int>;
      if (entryBytes.length > maxXmlDecompressedSize) {
        if (mounted) {
          setState(() => _error = '文档内容过大，请使用右上角外部应用打开');
        }
        return;
      }
      final xml = utf8.decode(entryBytes, allowMalformed: true);
      final text = _extract(xml);
      if (mounted) setState(() => _text = text);
    } catch (_) {
      if (mounted) setState(() => _error = 'DOCX 解析失败');
    }
  }

  /// 文件已缓存在本地，这里交给系统选择保存 / 分享 / 用其他应用打开。
  Future<void> _openExternal() async {
    final result = await OpenFilex.open(widget.path);
    if (!mounted) {
      return;
    }
    if (result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message.isEmpty ? '没有可打开该文档的应用' : result.message,
          ),
        ),
      );
    }
  }

  static String _extract(String xml) {
    final paragraphs = <String>[];
    final paragraphRe = RegExp(r'<w:p[ >].*?</w:p>', dotAll: true);
    for (final match in paragraphRe.allMatches(xml)) {
      final runs = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true)
          .allMatches(match.group(0)!)
          .map((e) => _decode(e.group(1) ?? ''))
          .join();
      if (runs.trim().isNotEmpty) paragraphs.add(runs);
    }
    return paragraphs.join('\n\n');
  }

  static String _decode(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'<[^>]+>'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
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
          : _text == null
          ? const Center(child: CircularProgressIndicator())
          : _text!.isEmpty
          ? const Center(
              child: Text(
                '文档没有可提取的文字',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: SelectableText(
                _text!,
                style: const TextStyle(fontSize: 14, height: 1.8),
              ),
            ),
    );
  }
}
