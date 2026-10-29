import 'dart:convert';

import 'package:dio/dio.dart';

import '../auth/cas_client.dart';

class HomeworkAttachment {
  const HomeworkAttachment({
    required this.id,
    required this.name,
    required this.size,
  });

  final int id;
  final String name;
  final int size;

  String get sizeLabel {
    if (size <= 0) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class HomeworkDetail {
  const HomeworkDetail({
    required this.title,
    required this.description,
    required this.deadline,
    required this.closed,
    required this.submitted,
    required this.typeLabel,
    required this.attachments,
    this.courseId = 0,
  });

  final String title;
  final String description;
  final DateTime? deadline;
  final bool closed;
  final bool submitted;
  final String typeLabel;
  final List<HomeworkAttachment> attachments;
  final int courseId;

  static HomeworkDetail? fromJson(Map<String, dynamic> json) {
    final title = (json['title'] ?? '').toString().trim();
    if (title.isEmpty) {
      return null;
    }
    final data =
        (json['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final uploads = (json['uploads'] as List<dynamic>? ?? <dynamic>[]);
    final attachments = <HomeworkAttachment>[];
    for (final item in uploads) {
      if (item is Map) {
        final map = item.cast<String, dynamic>();
        final name = (map['name'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          attachments.add(
            HomeworkAttachment(
              id: (map['id'] as num?)?.toInt() ?? 0,
              name: name,
              size: (map['size'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      }
    }
    final type = (data['homework_type'] ?? '').toString();
    final submitCount = (json['user_submit_count'] as num?)?.toInt() ?? 0;
    return HomeworkDetail(
      title: title,
      description: _stripHtml((data['description'] ?? '').toString()),
      deadline: DateTime.tryParse((json['end_time'] ?? '').toString())
          ?.toLocal(),
      closed: json['is_closed'] == true,
      submitted: submitCount > 0,
      typeLabel: switch (type) {
        'file_upload' => '文件作业',
        'text' => '文字作业',
        'online' => '在线作业',
        _ => '作业',
      },
      attachments: attachments,
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
    );
  }

  static String _stripHtml(String raw) {
    if (raw.isEmpty) {
      return '';
    }
    return raw
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}

/// 我的一次作业提交记录。
class HomeworkSubmission {
  const HomeworkSubmission({
    required this.id,
    required this.activityId,
    required this.createdAt,
    required this.score,
    required this.comment,
    required this.attachments,
  });

  final int id;
  final int activityId;
  final String createdAt;
  final double? score;
  final String comment;
  final List<HomeworkAttachment> attachments;
}

/// 要提交的作业文件。
class HomeworkFile {
  const HomeworkFile({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}

class HomeworkApi {
  HomeworkApi(this.client);

  final CasClient client;

  /// 直接下载附件二进制（PDF 预览用）。
  Future<List<int>> fetchBlob(int uploadId) {
    return client.downloadBytes(
      Uri.parse(
        'https://1906.usst.edu.cn/api/uploads/$uploadId/blob?preview=true',
      ),
    );
  }

  /// 一网畅学作业提交：先申请上传地址，PUT 文件，再创建 submission。
  Future<void> submitHomework(
    int activityId,
    List<HomeworkFile> files, {
    String comment = '',
  }) async {
    final uploadIds = <int>[];
    for (final file in files) {
      final create = await client.sendJson(
        Uri.parse('https://1906.usst.edu.cn/api/uploads'),
        data: <String, dynamic>{
          'name': file.name,
          'size': file.bytes.length,
          'parent_type': null,
          'parent_id': 0,
          'is_scorm': false,
          'is_wmpkg': false,
        },
      );
      final raw = create.data ?? '';
      Map<String, dynamic>? map;
      try {
        map = jsonDecode(raw) as Map<String, dynamic>?;
      } catch (_) {
        map = null;
      }
      final uploadUrl = (map?['upload_url'] ?? '').toString();
      final id = (map?['id'] as num?)?.toInt();
      if (map == null || uploadUrl.isEmpty || id == null) {
        throw Exception('申请上传地址失败');
      }
      final target = Uri.parse(uploadUrl).isAbsolute
          ? Uri.parse(uploadUrl)
          : Uri.parse('https://1906.usst.edu.cn$uploadUrl');
      final dio = Dio(
        BaseOptions(
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 120),
        ),
      );
      final cookie = client.jar.headerFor(target);
      final response = await dio.putUri<dynamic>(
        target,
        data: FormData.fromMap(<String, dynamic>{
          'file': MultipartFile.fromBytes(file.bytes, filename: file.name),
        }),
        options: Options(headers: <String, String>{'Cookie': ?cookie}),
      );
      if ((response.statusCode ?? 0) >= 400) {
        throw Exception('文件上传失败');
      }
      uploadIds.add(id);
    }

    final submit = await client.sendJson(
      Uri.parse(
        'https://1906.usst.edu.cn/api/course/activities/$activityId/submissions',
      ),
      data: <String, dynamic>{
        'comment': comment,
        'uploads': uploadIds,
        'slides': <dynamic>[],
        'is_draft': false,
      },
    );
    if ((submit.statusCode ?? 0) >= 400) {
      throw Exception('作业提交失败');
    }
  }

  /// 我在某门课里的全部提交记录（用来回看交过什么）。
  ///
  /// 一网畅学没有「按活动查我的提交」的接口，只有按课程列全部提交：
  /// `GET /api/course/{courseId}/submissions?fields=...`，
  /// 拿到后按 activity_id 过滤即可。
  Future<List<HomeworkSubmission>> fetchSubmissions(int courseId) async {
    final resp = await client.getApi(
      Uri.parse(
        'https://1906.usst.edu.cn/api/course/$courseId/submissions'
        '?fields=id,activity_id,created_at,score,comment,uploads',
      ),
    );
    final raw = resp.data ?? '';
    if (!raw.trimLeft().startsWith('{')) {
      return const <HomeworkSubmission>[];
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final list = map['submissions'] as List<dynamic>? ?? <dynamic>[];
    final out = <HomeworkSubmission>[];
    for (final item in list) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();
      final uploads = <HomeworkAttachment>[];
      for (final u in (m['uploads'] as List<dynamic>? ?? <dynamic>[])) {
        if (u is! Map) continue;
        final um = u.cast<String, dynamic>();
        final name = (um['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        uploads.add(
          HomeworkAttachment(
            id: (um['id'] as num?)?.toInt() ?? 0,
            name: name,
            size: (um['size'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      out.add(
        HomeworkSubmission(
          id: (m['id'] as num?)?.toInt() ?? 0,
          activityId: (m['activity_id'] as num?)?.toInt() ?? 0,
          createdAt: _formatTime(m['created_at']),
          score: (m['score'] as num?)?.toDouble(),
          comment: (m['comment'] ?? '').toString().trim(),
          attachments: uploads,
        ),
      );
    }
    return out;
  }

  static String _formatTime(Object? raw) {
    final text = (raw ?? '').toString();
    if (text.isEmpty) return '';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return text;
    final local = parsed.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<HomeworkDetail> fetch(int activityId) async {
    final resp = await client.getApi(
      Uri.parse('https://1906.usst.edu.cn/api/activities/$activityId'),
    );
    final raw = resp.data ?? '';
    if (!raw.trimLeft().startsWith('{')) {
      throw Exception('作业详情接口返回异常');
    }
    final detail = HomeworkDetail.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    if (detail == null) {
      throw Exception('作业不存在');
    }
    return detail;
  }
}
