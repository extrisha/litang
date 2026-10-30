import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/attachment_cache.dart';

void main() {
  group('AttachmentCache.safeFilename', () {
    test('常规正常文件名保持不变', () {
      expect(AttachmentCache.safeFilename('homework.pdf'), 'homework.pdf');
      expect(AttachmentCache.safeFilename('实验报告_李华.docx'), '实验报告_李华.docx');
    });

    test('过滤非法文件系统字符', () {
      expect(
        AttachmentCache.safeFilename('report/2026:01*test?.pdf'),
        'report_2026_01_test_.pdf',
      );
      expect(
        AttachmentCache.safeFilename(r'path\to<file>|"pipe".doc'),
        'path_to_file___pipe_.doc',
      );
    });

    test('防止路径遍历（.. 和多点攻击）', () {
      expect(
        AttachmentCache.safeFilename('../../etc/passwd'),
        '____etc_passwd',
      );
      expect(
        AttachmentCache.safeFilename('..'),
        startsWith('attachment_'),
      );
      expect(
        AttachmentCache.safeFilename('.'),
        startsWith('attachment_'),
      );
      expect(
        AttachmentCache.safeFilename(''),
        startsWith('attachment_'),
      );
      expect(
        AttachmentCache.safeFilename('....'),
        startsWith('attachment_'),
      );
    });
  });
}
