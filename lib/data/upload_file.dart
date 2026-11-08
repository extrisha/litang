import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';

/// Holds the picker handle, never a full-size byte buffer.
class UploadFile {
  const UploadFile({
    required this.file,
    required this.name,
    required this.length,
  });
  final XFile file;
  final String name;
  final int length;
  static const maxSingleBytes = 50 * 1024 * 1024;
  static const maxTotalBytes = 100 * 1024 * 1024;

  static String? selectionError(int length, int selectedBytes) {
    if (length <= 0) return '不能添加空文件';
    if (length > maxSingleBytes) return '单个附件不能超过 50MB';
    if (selectedBytes + length > maxTotalBytes) return '附件总大小超过 100MB，请分批提交';
    return null;
  }

  static Future<void> validateAll(Iterable<UploadFile> files) async {
    var total = 0;
    for (final file in files) {
      final error = selectionError(file.length, total);
      if (error != null) throw StateError(error);
      if (await file.file.length() != file.length) {
        throw StateError('附件已变化，请重新选择：${file.name}');
      }
      total += file.length;
    }
  }

  MultipartFile multipart() =>
      MultipartFile.fromStream(() => file.openRead(), length, filename: name);
}
