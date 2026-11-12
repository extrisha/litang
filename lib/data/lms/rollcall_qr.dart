import 'dart:convert';

/// 从扫码内容里解出来的签到信息。
///
/// 老师屏幕上的二维码并不是「一串口令」，而是这几种之一：
///   - `https://1906.usst.edu.cn/j?p=<Base36 紧凑编码>`（最常见）
///   - 紧凑编码：`4~<rollcallId>!3~<data>!0~<courseId>`，前面可能带 \x10 前缀
///   - JSON：`{"rollcallId": "...", "data": "..."}`
///   - 带参数的 URL
///
/// 服务端真正要的是解出来的 `data`，不是二维码原文；这一点是之前签不上的
/// 主要原因之一。
class QrPayload {
  const QrPayload({required this.data, this.rollcallId, this.courseId});

  final String data;
  final int? rollcallId;
  final int? courseId;

  static const Map<String, String> _compactKeys = <String, String>{
    '0': 'courseId',
    '1': 'activityId',
    '2': 'activityType',
    '3': 'data',
    '4': 'rollcallId',
  };

  static int? _decodeId(String? raw) {
    if (raw == null) {
      return null;
    }
    final clean = raw
        .trim()
        .replaceAll('\u0010', '')
        .replaceAll('\u001A', '')
        .replaceAll('%10', '')
        .replaceAll('%1A', '')
        .replaceAll('%1a', '');
    if (clean.isEmpty) {
      return null;
    }
    return int.tryParse(clean) ?? int.tryParse(clean, radix: 36);
  }

  static String _decodeData(String raw) {
    return raw.replaceAll('\u001E', '~').replaceAll('\u001F', '!');
  }

  /// 解析失败返回 null，由调用方提示「无法识别」。
  static QrPayload? parse(String raw) {
    var text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    text = text.replaceAll('\u0010', '').replaceAll('\u001A', '');

    var payload = text;
    var fromUrl = false;
    final lower = text.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        text.contains('/j?p=') ||
        text.contains('/scanner-jumper?')) {
      fromUrl = true;
      final uri = Uri.tryParse(text);
      if (uri != null) {
        final underscore = uri.queryParameters['_p'];
        final p = uri.queryParameters['p'];
        if (underscore != null && underscore.trim().isNotEmpty) {
          payload = underscore.trim();
        } else if (p != null && p.trim().isNotEmpty) {
          payload = p.trim();
        } else {
          final id = _decodeId(
            uri.queryParameters['rollcall_id'] ??
                uri.queryParameters['rollcallId'],
          );
          final data =
              uri.queryParameters['data'] ?? uri.queryParameters['qr_token'];
          final courseId = _decodeId(
            uri.queryParameters['course_id'] ?? uri.queryParameters['courseId'],
          );
          if (id != null && id > 0 && data != null && data.isNotEmpty) {
            return QrPayload(
              data: _decodeData(data),
              rollcallId: id,
              courseId: courseId,
            );
          }
        }
      }
    }

    if (payload.startsWith('{') && payload.endsWith('}')) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map) {
          final id = _decodeId(
            '${decoded['rollcallId'] ?? decoded['rollcall_id'] ?? ''}',
          );
          final data = '${decoded['data'] ?? decoded['qr_token'] ?? ''}'.trim();
          final courseId = _decodeId(
            '${decoded['courseId'] ?? decoded['course_id'] ?? ''}',
          );
          if (data.isNotEmpty) {
            return QrPayload(
              data: _decodeData(data),
              rollcallId: id,
              courseId: courseId,
            );
          }
        }
      } catch (_) {
        // 落到下面的兜底
      }
      return null;
    }

    if (payload.contains('!') || payload.contains('~')) {
      int? rollcallId;
      int? courseId;
      String? data;
      for (final part in payload.split('!')) {
        final index = part.indexOf('~');
        if (index <= 0) {
          continue;
        }
        final rawKey = part.substring(0, index);
        final key = _compactKeys[rawKey] ?? rawKey;
        final value = part.substring(index + 1);
        if (key == 'rollcallId') {
          rollcallId = _decodeId(value);
        } else if (key == 'courseId') {
          courseId = _decodeId(value);
        } else if (key == 'data') {
          data = _decodeData(value);
        }
      }
      if (data != null && data.isNotEmpty) {
        return QrPayload(
          data: data,
          rollcallId: rollcallId,
          courseId: courseId,
        );
      }
      if (fromUrl) {
        return null;
      }
    }

    if (fromUrl) {
      return null;
    }
    // 有些二维码直接就是 data token，没有外层结构。
    return QrPayload(data: text);
  }
}

