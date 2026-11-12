/// 进行中的一个签到。
class Rollcall {
  const Rollcall({
    required this.id,
    required this.courseName,
    required this.type,
    required this.timeText,
    this.isNumber = false,
    this.isRadar = false,
    this.isSelfRegistration = false,
    this.isExpired = false,
    this.status = '',
    this.latitude,
    this.longitude,
    this.scope,
    this.classroom,
  });

  final String id;
  final String courseName;

  /// 原始类型，如 qr_rollcall / number_rollcall / radar_rollcall。
  final String type;
  final String timeText;

  /// 服务端用 is_number / is_radar 两个布尔字段标类型，type 不一定会给。
  final bool isNumber;
  final bool isRadar;

  /// 自主签到（self_registration）：不用口令、不用坐标、不用扫码。
  final bool isSelfRegistration;
  final bool isExpired;

  /// absent / on_call / on_call_fine / ...
  final String status;

  /// 雷达点名时平台下发的教师端基准点（GCJ-02）；没下发就是 null。
  final double? latitude;
  final double? longitude;

  /// 雷达点名的有效半径（米），平台不一定给。
  final double? scope;

  /// 上课教室，用来匹配教学楼基准点。
  final String? classroom;

  /// 平台是否下发了可用的教师基准点。
  bool get hasTeacherReference =>
      latitude != null &&
      longitude != null &&
      !(latitude == 0 && longitude == 0);

  /// 本地缓存用（与上游字段名解耦）。
  Map<String, dynamic> toCacheJson() => <String, dynamic>{
    'id': id,
    'courseName': courseName,
    'type': type,
    'timeText': timeText,
    'isNumber': isNumber,
    'isRadar': isRadar,
    'isSelfRegistration': isSelfRegistration,
    'isExpired': isExpired,
    'status': status,
    'latitude': latitude,
    'longitude': longitude,
    'scope': scope,
    'classroom': classroom,
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
      isSelfRegistration: json['isSelfRegistration'] == true,
      isExpired: json['isExpired'] == true,
      status: (json['status'] ?? '').toString(),
      latitude: _optionalDouble(json['latitude']),
      longitude: _optionalDouble(json['longitude']),
      scope: _optionalDouble(json['scope']),
      classroom: (json['classroom'] ?? '').toString().isEmpty
          ? null
          : (json['classroom'] ?? '').toString(),
    );
  }

  String get _lowerType => type.toLowerCase();

  bool get isNumberRollcall => isNumber || _lowerType.contains('number');

  bool get isRadarRollcall =>
      isRadar || _lowerType.contains('radar') || _lowerType.contains('roomis');

  bool get isQrRollcall => _lowerType.contains('qr');

  /// 自主签到：`is_self_registration`，或者 type 里带 self。
  bool get isSelfRollcall =>
      isSelfRegistration ||
      _lowerType.contains('self') ||
      _lowerType.contains('registration');

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

  /// 服务端有的实例把数字给成字符串，统一转成 double；无效值返回 null。
  static double? _optionalDouble(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.isFinite ? value.toDouble() : null;
    }
    final parsed = double.tryParse('$value'.trim());
    return (parsed != null && parsed.isFinite) ? parsed : null;
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
                json['rollcall_time'] ??
                json['rollcallTime'] ??
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
      isSelfRegistration:
          _truthy(json['is_self_registration']) ||
          _truthy(json['isSelfRegistration']) ||
          type.toLowerCase().contains('self') ||
          type.toLowerCase().contains('registration'),
      isExpired: _truthy(json['is_expired']) || _truthy(json['expired']),
      status:
          (json['status'] ??
                  json['rollcall_status'] ??
                  json['rollcallStatus'] ??
                  '')
              .toString(),
      latitude: _optionalDouble(json['latitude'] ?? json['lat']),
      longitude: _optionalDouble(json['longitude'] ?? json['lng']),
      scope: _optionalDouble(json['scope'] ?? json['radius']),
      classroom: _optionalText(json['classroom'] ?? json['room']),
    );
  }

  static String? _optionalText(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  static String _shortTime(String raw) {
    if (raw.isEmpty) {
      return '';
    }
    // 服务端给的是 UTC（带 Z / 时区偏移）时，直接截字符串会差 8 小时。
    // 和 USST 参考实现一致：能解析成 DateTime 就转本地时区再显示。
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      final local = parsed.toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      return '${two(local.hour)}:${two(local.minute)}';
    }
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(raw);
    if (match != null) {
      return '${match.group(1)!.padLeft(2, '0')}:${match.group(2)}';
    }
    return raw;
  }
}

