import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../app_exception.dart';
import '../auth/cas_client.dart';
import 'device_id.dart';
import 'rollcall_model.dart';
import 'rollcall_qr.dart';
import 'rollcall_result.dart';

export 'rollcall_model.dart';
export 'rollcall_qr.dart';
export 'rollcall_result.dart';
/// 一网畅学签到接口。
class RollcallApi {
  RollcallApi(this.client);

  final CasClient client;

  static const String host = '1906.usst.edu.cn';
  static const String _base = 'https://$host';

  /// 拉取「正在进行中」的签到（周末/无课时返回空列表）。
  ///
  /// 按数据层契约（`AppException`）：返回空列表只表示「确实没有进行中的签到」；
  /// 登录失效 / 网络失败 / 拿到 HTML 页面都必须抛，不能伪装成空。
  Future<List<Rollcall>> fetchOngoing() async {
    final Response<dynamic> resp;
    try {
      resp = await client.getApi(
        Uri.parse('$_base/api/radar/rollcalls?api_version=1.1.0'),
      );
    } catch (e) {
      throw AppException(AppFailure.network, '签到信息拉取失败，请检查网络', e);
    }
    final status = resp.statusCode ?? 0;
    if (status == 401 || status == 403) {
      throw const AppException(AppFailure.auth, '一网畅学登录已失效，请重新登录后重试');
    }
    if (status < 200 || status >= 300) {
      throw AppException(AppFailure.server, '签到信息拉取失败（HTTP $status）');
    }
    final raw = resp.data ?? '';
    final text = raw.trim();
    if (text.startsWith('<')) {
      // 拿到的是 HTML（登录页 / 错误页），说明会话已经失效
      throw const AppException(AppFailure.auth, '一网畅学登录已失效，请重新登录后重试');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw AppException(AppFailure.parse, '签到信息返回数据无法解析，请稍后重试', e);
    }
    final items = decoded is Map ? decoded['rollcalls'] : decoded;
    if (items is! List ||
        items.any((item) => item is! Map) ||
        (decoded is Map && decoded['success'] == false)) {
      throw const AppException(AppFailure.parse, '签到列表缺失或不完整，请稍后重试');
    }
    final records = parseOngoing(raw);
    if (records.length != items.length) {
      throw const AppException(AppFailure.parse, '签到记录不完整，请稍后重试');
    }
    return records;
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

  /// 自主签到（self_registration）。
  ///
  /// 官方网页端就是发一个空的 `{}`：这种点名没有口令、没有坐标、也没有二维码，
  /// 只要点到就能签上。参考 auto-Tronclass 的 `self_registration_runtime`。
  Future<SignResult> answerSelfRegistration(Rollcall rollcall) async {
    return _put(
      '/api/rollcall/${rollcall.id}/answer_self_registration_rollcall',
      const <String, dynamic>{},
    );
  }

  /// 拉一次花名册，拿到人数统计（和可能存在的数字口令）。
  ///
  /// 返回 null 表示没读到（接口失败 / 结构不认识），调用方不要当成「0 人已签」。
  Future<RosterInfo?> fetchRoster(Rollcall rollcall) async {
    try {
      final resp = await client.getApi(
        Uri.parse('$_base/api/rollcall/${rollcall.id}/student_rollcalls'),
      );
      return parseRoster(resp.data?.toString() ?? '');
    } on AppException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 解析花名册的人数统计（公开供单测）。
  static RosterInfo? parseRoster(String body) {
    try {
      final decoded = jsonDecode(body);
      final dynamic list = decoded is Map
          ? (decoded['student_rollcalls'] ?? decoded['studentRollcalls'])
          : null;
      if (list is! List) return null;
      var total = 0;
      var signed = 0;
      for (final item in list) {
        if (item is! Map) continue;
        total++;
        final status = '${item['status'] ?? item['rollcall_status'] ?? ''}'
            .trim()
            .toLowerCase();
        if (_signedStatuses.contains(status)) signed++;
      }
      return RosterInfo(
        total: total,
        signed: signed,
        numberCode: parseNumberCode(body).code,
      );
    } catch (_) {
      return null;
    }
  }

  /// 花名册里算「已签到」的状态。
  static const Set<String> _signedStatuses = <String>{
    'on_call_fine',
    'attended',
    'present',
    'late',
    'signed',
    'submitted',
  };

  /// 从点名花名册里「借」数字口令。
  ///
  /// 学校这套自部署实例有个老问题：只要班里已经有人签过，老师端口令就会跟着
  /// 别人的签到记录一起出现在花名册里（`number_code`）。一次 GET 就能拿到，
  /// 不用像某些方案那样 0000~9999 爆破。拿不到就返回 [NumberCodeLookup.message]，
  /// 由调用方退回手动输入。
  Future<NumberCodeLookup> fetchNumberCode(Rollcall rollcall) async {
    try {
      final resp = await client.getApi(
        Uri.parse('$_base/api/rollcall/${rollcall.id}/student_rollcalls'),
      );
      return parseNumberCode(resp.data?.toString() ?? '');
    } on AppException catch (e) {
      return NumberCodeLookup(message: e.message);
    } catch (_) {
      return const NumberCodeLookup(message: '读取数字口令失败，请手动输入');
    }
  }

  /// 权威复核：花名册里本账号是不是 `on_call_fine`。
  ///
  /// 只信接口返回的 200 不够——畅课经常「200 + 业务失败」。
  Future<SignResult> recheckAttendance(
    Rollcall rollcall,
    String studentId,
  ) async {
    try {
      final resp = await client.getApi(
        Uri.parse('$_base/api/rollcall/${rollcall.id}/student_rollcalls'),
      );
      final signed = parseAttendance(resp.data?.toString() ?? '', studentId);
      if (signed == null) {
        return const SignResult(success: false, message: '签到结果无法确认，请到一网畅学里看一眼');
      }
      return signed
          ? const SignResult(success: true, statusName: '已签到')
          : const SignResult(success: false, message: '花名册里还没看到你的签到记录');
    } on AppException catch (e) {
      return SignResult(success: false, message: e.message);
    } catch (_) {
      return const SignResult(success: false, message: '复核签到结果失败');
    }
  }

  /// 解析花名册里的数字口令（公开供单测）。
  ///
  /// 兼容三种形态：详情对象、`rollcall` 子对象、`student_rollcalls` 数组。
  /// 数字要给补零（`123` → `0123`），不然前导 0 的口令永远签不上。
  static NumberCodeLookup parseNumberCode(String body) {
    final records = <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        records.add(decoded);
        final detail = decoded['rollcall'];
        if (detail is Map<String, dynamic>) {
          records.add(detail);
        }
        for (final key in const <String>[
          'student_rollcalls',
          'studentRollcalls',
          'records',
          'items',
        ]) {
          final list = decoded[key];
          if (list is List) {
            for (final item in list) {
              if (item is Map<String, dynamic>) {
                records.add(item);
              }
            }
          }
        }
      } else if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            records.add(item);
          }
        }
      } else {
        return const NumberCodeLookup(message: '花名册响应格式无法识别');
      }
    } catch (_) {
      return const NumberCodeLookup(message: '花名册响应不是合法 JSON');
    }

    final codes = <String>{};
    for (final record in records) {
      final raw = record['number_code'] ?? record['numberCode'];
      if (raw == null) continue;
      final code = coerceNumberCode(raw);
      if (code != null) {
        codes.add(code);
      }
    }
    if (codes.isEmpty) {
      return const NumberCodeLookup(message: '花名册里没有数字口令，请手动输入');
    }
    if (codes.length > 1) {
      return const NumberCodeLookup(message: '花名册里有多个不同的口令，已停止自动签到');
    }
    return NumberCodeLookup(code: codes.single);
  }

  /// 把花名册里的 `number_code` 统一成 4 位字符串。
  static String? coerceNumberCode(Object? value) {
    if (value is num) {
      final number = value.toInt();
      if (number < 0 || number > 999999) return null;
      // 1000 以下说明前导 0 被 JSON 吃掉了，补回 4 位
      return number < 1000
          ? number.toString().padLeft(4, '0')
          : number.toString();
    }
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty || text.length > 6) return null;
      if (!RegExp(r'^\d+$').hasMatch(text)) return null;
      return text.length >= 4 ? text : text.padLeft(4, '0');
    }
    return null;
  }

  /// 解析花名册，判断 [studentId] 是否已签到。
  ///
  /// 返回 null 表示响应看不懂（不能当作「没签到」）。
  static bool? parseAttendance(String body, String studentId) {
    final target = studentId.trim().toLowerCase();
    if (target.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      final dynamic list = decoded is Map
          ? (decoded['student_rollcalls'] ?? decoded['studentRollcalls'])
          : decoded;
      if (list is! List) return null;
      for (final item in list) {
        if (item is! Map) continue;
        final uid =
            '${item['user_no'] ?? item['user_id'] ?? item['userNo'] ?? ''}'
                .trim()
                .toLowerCase();
        if (uid != target) continue;
        final status = '${item['status'] ?? item['rollcall_status'] ?? ''}'
            .trim()
            .toLowerCase();
        // on_call_fine 是「已签到」；attended/present/late 是不同部署的叫法
        return status == 'on_call_fine' ||
            status == 'attended' ||
            status == 'present' ||
            status == 'late';
      }
      return false;
    } catch (_) {
      return null;
    }
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

  /// 雷达签到：上报**已经换算成 GCJ-02 的签到基准点**。
  ///
  /// 坐标由 [resolveRadarTarget] 决定（教师基准点 > 教学楼基准点 > 本机定位），
  /// 调用方不要再自己转一次坐标系。
  ///
  /// 对齐 USST 参考实现 `usst-jwgl-client` 的 `answerRadarRollcall`：
  /// - 接口是 `/answer?api_version=1.76`（不是 `/position`，也不是 `/lite`）。
  /// - 请求体固定为 `deviceId / latitude / longitude / accuracy / altitude /
  ///   radarSignal: null`；USST 的雷达点名是纯坐标比对，不自己构造
  ///   `radarSignal`，需要信标的课堂参考实现也明确提示「需要教室蓝牙信号」。
  Future<SignResult> reportRadarPosition(
    Rollcall rollcall,
    double latitude,
    double longitude, {
    double? accuracy,
  }) async {
    final deviceId = await TronDeviceId.get();
    final body = buildRadarPayload(
      deviceId: deviceId,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
    );
    final resp = await client.sendJson(
      Uri.parse('$_base/api/rollcall/${rollcall.id}/answer?api_version=1.76'),
      method: 'PUT',
      data: body,
    );
    return _result(resp);
  }

  /// 构造雷达请求体（公开供单测）。
  ///
  /// `altitude` 固定 10.0、`radarSignal` 固定 null，与 USST 参考实现一致；
  /// 不要额外塞 `altitudeAccuracy` / `heading` / `speed`，服务端并不需要。
  @visibleForTesting
  static Map<String, dynamic> buildRadarPayload({
    required String deviceId,
    required double latitude,
    required double longitude,
    double? accuracy,
  }) => <String, dynamic>{
    'deviceId': deviceId,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': (accuracy != null && accuracy > 0) ? accuracy : 15.0,
    'altitude': 10.0,
    'radarSignal': null,
  };

  Future<SignResult> _put(String path, Map<String, dynamic> data) async {
    final resp = await client.sendJson(
      Uri.parse('$_base$path'),
      method: 'PUT',
      data: data,
    );
    return _result(resp);
  }

  SignResult _result(Response<String> resp) {
    return parseSignResult(
      resp.statusCode ?? 0,
      resp.data ?? '',
      realUrl: resp.realUri.toString(),
    );
  }

  /// 解析签到提交的 HTTP 响应（公开供单元测试与调试）
  static SignResult parseSignResult(
    int code,
    String body, {
    String realUrl = '',
  }) {
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
      final lowerUrl = realUrl.toLowerCase();
      final looksLikeLogin =
          lowerUrl.contains('/auth/') ||
          lowerUrl.contains('passport') ||
          lowerUrl.endsWith('/login');
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
    final errorCode =
        (map?['errorCode'] ?? map?['error_code'] ?? map?['code'])
            ?.toString()
            .trim()
            .toUpperCase() ??
        '';
    const radarErrors = <String, String>{
      'ROLLCALL_RADAR_OUT_OF_SCOPE': '定位超出签到范围，请靠近上课教室后重试',
      'RADAR_ROLLCALL_POSITION_INVALID': '定位坐标无效，请重新定位后重试',
      'ROLLCALL_DEVICE_ALREADY_IN_USE': '这台设备已经给其他账号签过到了',
      'RADAR_SIGNAL_INVALID_NO_SIGNAL': '本堂课开启了蓝牙信标验证，需要教室蓝牙信号支持',
    };
    if (radarErrors.containsKey(errorCode)) {
      return SignResult(success: false, message: radarErrors[errorCode]);
    }
    // 对齐参考实现：401/403 是会话失效，404 是点名已结束/关闭。
    if (code == 401 || code == 403) {
      return const SignResult(success: false, message: '登录状态已失效，请重新登录教务系统');
    }
    if (code == 404) {
      return const SignResult(success: false, message: '点名已结束或已关闭');
    }
    final rawMsg =
        (map?['message'] ?? map?['error'] ?? map?['msg'])?.toString().trim() ??
        '';
    final lowerMsg = rawMsg.toLowerCase();
    if (lowerMsg.contains('out of roll scope') ||
        lowerMsg.contains('out of scope') ||
        lowerMsg.contains('out of rollcall scope')) {
      return const SignResult(success: false, message: '定位超出签到范围，请靠近上课教室后重试');
    }
    if (lowerMsg.contains('position invalid') ||
        lowerMsg.contains('invalid position')) {
      return const SignResult(success: false, message: '定位坐标无效，请重新定位后重试');
    }
    if (lowerMsg.contains('device already in use') ||
        lowerMsg.contains('device_already_in_use')) {
      return const SignResult(success: false, message: '这台设备已经给其他账号签过到了');
    }
    if (lowerMsg.contains('no signal') || lowerMsg.contains('radar signal')) {
      return const SignResult(
        success: false,
        message: '本堂课开启了蓝牙信标验证，需要教室蓝牙信号支持',
      );
    }
    if (rawMsg.isNotEmpty) {
      message = rawMsg;
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

