import 'dart:convert';

import 'package:dio/dio.dart';

import '../auth/cas_client.dart';
import 'device_id.dart';

/// 签到提交结果。
class SignResult {
  const SignResult({required this.success, this.message, this.statusName});

  final bool success;
  final String? message;

  /// 服务端返回的状态名，如「已签到」「迟到」。
  final String? statusName;
}

/// 进行中的一个签到。
class Rollcall {
  const Rollcall({
    required this.id,
    required this.courseName,
    required this.type,
    required this.timeText,
    this.isNumber = false,
    this.isRadar = false,
    this.isExpired = false,
    this.status = '',
  });

  final String id;
  final String courseName;

  /// 原始类型，如 qr_rollcall / number_rollcall / radar_rollcall。
  final String type;
  final String timeText;

  /// 服务端用 is_number / is_radar 两个布尔字段标类型，type 不一定会给。
  final bool isNumber;
  final bool isRadar;
  final bool isExpired;

  /// absent / on_call / on_call_fine / ...
  final String status;

  /// 本地缓存用（与上游字段名解耦）。
  Map<String, dynamic> toCacheJson() => <String, dynamic>{
    'id': id,
    'courseName': courseName,
    'type': type,
    'timeText': timeText,
    'isNumber': isNumber,
    'isRadar': isRadar,
    'isExpired': isExpired,
    'status': status,
  };

  static Rollcall? fromCacheJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    if (id.isEmpty) {
      return null;
    }
    return Rollcall(
      id: id,
      courseName: (json['courseName'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      timeText: (json['timeText'] ?? '').toString(),
      isNumber: json['isNumber'] == true,
      isRadar: json['isRadar'] == true,
      isExpired: json['isExpired'] == true,
      status: (json['status'] ?? '').toString(),
    );
  }

  String get _lowerType => type.toLowerCase();

  bool get isNumberRollcall => isNumber || _lowerType.contains('number');

  bool get isRadarRollcall =>
      isRadar || _lowerType.contains('radar') || _lowerType.contains('roomis');

  bool get isQrRollcall => _lowerType.contains('qr');

  bool get isSelfRollcall => _lowerType.contains('self');

  static const Set<String> _signedStatuses = <String>{
    'on_call_fine',
    'attended',
    'present',
    'signed',
    'submitted',
    'late',
    'leave',
  };

  bool get isSigned => _signedStatuses.contains(status.toLowerCase());

  bool get isSignable => !isExpired && !isSigned;

  String get typeLabel {
    if (isNumberRollcall) {
      return '数字口令';
    }
    if (isRadarRollcall) {
      return '雷达点名';
    }
    if (isQrRollcall) {
      return '二维码签到';
    }
    if (_lowerType.contains('manual')) {
      return '手动点名';
    }
    if (isSelfRollcall) {
      return '自主签到';
    }
    return '签到';
  }

  static bool _truthy(Object? value) {
    if (value == true || value == 1) {
      return true;
    }
    final text = '${value ?? ''}'.toLowerCase();
    return text == 'true' || text == '1';
  }

  static String _firstId(Map<String, dynamic> json) {
    for (final key in <String>['id', 'rollcall_id', 'rollcallId', 'uuid']) {
      final value = '${json[key] ?? ''}'.trim();
      if (value.isNotEmpty && value != '0') {
        return value;
      }
    }
    return '';
  }

  static Rollcall? fromJson(Map<String, dynamic> json) {
    final id = _firstId(json);
    if (id.isEmpty) {
      return null;
    }

    var courseName = '';
    final course = json['course'];
    if (course is Map) {
      courseName =
          (course['name'] ??
                  course['course_name'] ??
                  course['courseName'] ??
                  course['title'] ??
                  '')
              .toString();
    }
    if (courseName.isEmpty) {
      courseName =
          (json['course_title'] ??
                  json['course_name'] ??
                  json['courseName'] ??
                  json['kcmc'] ??
                  json['title'] ??
                  '')
              .toString();
    }

    final type =
        (json['type'] ??
                json['source'] ??
                json['rollcall_type'] ??
                json['rollcallType'] ??
                '')
            .toString();

    final time =
        (json['created_at'] ??
                json['createdAt'] ??
                json['start_at'] ??
                json['begin_at'] ??
                json['started_at'] ??
                '')
            .toString();

    return Rollcall(
      id: id,
      courseName: courseName.isEmpty ? '未知课程' : courseName,
      type: type,
      timeText: _shortTime(time),
      isNumber:
          _truthy(json['is_number']) ||
          _truthy(json['isNumber']) ||
          type.toLowerCase().contains('number'),
      isRadar:
          _truthy(json['is_radar']) ||
          _truthy(json['isRadar']) ||
          type.toLowerCase().contains('radar') ||
          type.toLowerCase().contains('roomis'),
      isExpired: _truthy(json['is_expired']) || _truthy(json['expired']),
      status:
          (json['status'] ??
                  json['rollcall_status'] ??
                  json['rollcallStatus'] ??
                  '')
              .toString(),
    );
  }

  static String _shortTime(String raw) {
    if (raw.isEmpty) {
      return '';
    }
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(raw);
    if (match != null) {
      return '${match.group(1)!.padLeft(2, '0')}:${match.group(2)}';
    }
    return raw;
  }
}

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

/// 一网畅学签到接口。
class RollcallApi {
  RollcallApi(this.client);

  final CasClient client;

  static const String host = '1906.usst.edu.cn';
  static const String _base = 'https://$host';

  /// 拉取「正在进行中」的签到（周末/无课时返回空列表）。
  Future<List<Rollcall>> fetchOngoing() async {
    final resp = await client.getApi(
      Uri.parse('$_base/api/radar/rollcalls?api_version=1.1.0'),
    );
    return parseOngoing(resp.data ?? '');
  }

  /// 数字口令签到。
  ///
  /// 服务端要的是 `{"deviceId": ..., "numberCode": ...}`；
  /// 之前发的是 `{"code": ...}`，字段名不对，所以永远签不上。
  Future<SignResult> answerNumber(Rollcall rollcall, String code) async {
    final deviceId = await TronDeviceId.get();
    return _put(
      '/api/rollcall/${rollcall.id}/answer_number_rollcall',
      <String, dynamic>{'deviceId': deviceId, 'numberCode': code.trim()},
    );
  }

  /// 二维码签到。
  ///
  /// 先按官方协议把二维码解成 `(rollcallId, data)`，提交时只发 `data`。
  /// 如果二维码本身没带 rollcallId，就用列表里的 id 兜底。
  Future<SignResult> answerQr(Rollcall rollcall, String raw) async {
    final payload = QrPayload.parse(raw);
    if (payload == null) {
      return const SignResult(
        success: false,
        message: '无法识别这个二维码，请对准老师屏幕上的签到码重试',
      );
    }
    final qrId = payload.rollcallId;
    final id = (qrId != null && qrId > 0)
        ? qrId
        : (int.tryParse(rollcall.id) ?? 0);
    if (id <= 0) {
      return const SignResult(
        success: false,
        message: '二维码里没有签到 ID，请刷新签到列表后重试',
      );
    }
    final deviceId = await TronDeviceId.get();
    return _put('/api/rollcall/$id/answer_qr_rollcall', <String, dynamic>{
      'deviceId': deviceId,
      'data': payload.data,
    });
  }

  /// 雷达签到：上报**本机真实定位**。
  ///
  /// 只用系统定位结果，不提供「选教学楼 / 手填坐标」的入口——那种远程代签
  /// 不是这个 App 要做的事。接口是 `/answer?api_version=1.76`，
  /// 不是 `/position`（后者不存在，所以以前雷达也一定失败）。
  Future<SignResult> reportRadarPosition(
    Rollcall rollcall,
    double latitude,
    double longitude, {
    double? accuracy,
    double? altitude,
    double? altitudeAccuracy,
    double? heading,
    double? speed,
  }) async {
    final deviceId = await TronDeviceId.get();
    final body = <String, dynamic>{
      'deviceId': deviceId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': ?accuracy,
      'altitude': ?altitude,
      'altitudeAccuracy': ?altitudeAccuracy,
      'heading': ?heading,
      'speed': ?speed,
      'radarSignal': null,
    };
    final resp = await client.sendJson(
      Uri.parse('$_base/api/rollcall/${rollcall.id}/answer?api_version=1.76'),
      method: 'PUT',
      data: body,
    );
    return _result(resp);
  }

  Future<SignResult> _put(String path, Map<String, dynamic> data) async {
    final resp = await client.sendJson(
      Uri.parse('$_base$path'),
      method: 'PUT',
      data: data,
    );
    return _result(resp);
  }

  SignResult _result(Response<String> resp) {
    final code = resp.statusCode ?? 0;
    final body = resp.data ?? '';
    Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        map = decoded;
      }
    } catch (_) {
      // 有些成功响应是空 body / HTML
    }
    if (code >= 200 && code < 300) {
      final realUrl = resp.realUri.toString().toLowerCase();
      final looksLikeLogin =
          realUrl.contains('/auth/') ||
          realUrl.contains('passport') ||
          realUrl.endsWith('/login');
      // 会话失效时 Dio 会跟到登录页并拿到 200 HTML，不能当成签到成功
      if (looksLikeLogin) {
        return const SignResult(success: false, message: '登录状态已失效，请重新登录教务系统');
      }
      if (body.trim().isEmpty || map != null) {
        final statusName = map?['status_name']?.toString();
        return SignResult(success: true, statusName: statusName);
      }
    }
    var message = '签到失败（HTTP $code）';
    final errorCode = map?['errorCode']?.toString() ?? '';
    const radarErrors = <String, String>{
      'ROLLCALL_RADAR_OUT_OF_SCOPE': '定位超出签到范围，请靠近上课教室后重试',
      'RADAR_ROLLCALL_POSITION_INVALID': '定位坐标无效，请重新定位后重试',
      'ROLLCALL_DEVICE_ALREADY_IN_USE': '这台设备已经给其他账号签过到了',
      'RADAR_SIGNAL_INVALID_NO_SIGNAL': '本堂课需要教室蓝牙信标，请在教室内重试',
    };
    if (radarErrors.containsKey(errorCode)) {
      return SignResult(success: false, message: radarErrors[errorCode]);
    }
    final msg = map?['message'] ?? map?['error'] ?? map?['msg'];
    if (msg != null && msg.toString().trim().isNotEmpty) {
      message = msg.toString();
    }
    return SignResult(success: false, message: message);
  }

  /// 解析 /api/radar/rollcalls 的响应。
  static List<Rollcall> parseOngoing(String raw) {
    final text = raw.trimLeft();
    if (!text.startsWith('{') && !text.startsWith('[')) {
      return const <Rollcall>[];
    }
    try {
      final decoded = jsonDecode(text);
      final list = decoded is Map
          ? (decoded['rollcalls'] as List<dynamic>? ?? <dynamic>[])
          : (decoded is List ? decoded : const <dynamic>[]);
      final out = <Rollcall>[];
      for (final item in list) {
        if (item is Map) {
          final rollcall = Rollcall.fromJson(item.cast<String, dynamic>());
          if (rollcall != null) {
            out.add(rollcall);
          }
        }
      }
      return out;
    } catch (_) {
      return const <Rollcall>[];
    }
  }
}
