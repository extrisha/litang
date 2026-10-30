import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 作业附件下载目录（持久化，可手动清理）。
class AttachmentCache {
  AttachmentCache._();

  /// 当前下载目录占用，下载/清理后自动通知界面刷新。
  static final ValueNotifier<int> sizeNotifier = ValueNotifier<int>(0);

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/downloads');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String safeFilename(String name) {
    var safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    while (safe.contains('..')) {
      safe = safe.replaceAll('..', '_');
    }
    final stripped = safe.replaceAll(RegExp(r'[._]'), '');
    if (stripped.isEmpty) {
      safe = 'attachment_${DateTime.now().millisecondsSinceEpoch}';
    }
    return safe;
  }

  static Future<String?> existing(String name) async {
    final dir = await _dir();
    final safe = safeFilename(name);
    final file = File('${dir.path}/$safe');
    return await file.exists() ? file.path : null;
  }

  static Future<String> save(String name, List<int> bytes) async {
    final dir = await _dir();
    final safe = safeFilename(name);
    final file = File('${dir.path}/$safe');
    await file.writeAsBytes(bytes, flush: true);
    await refreshSize();
    return file.path;
  }

  static Future<int> size() async {
    final dir = await _dir();
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    sizeNotifier.value = total;
    return total;
  }

  static Future<void> refreshSize() async {
    await size();
  }

  static Future<void> clear() async {
    final dir = await _dir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    sizeNotifier.value = 0;
  }
}
