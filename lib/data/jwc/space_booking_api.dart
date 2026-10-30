import 'dart:convert';

import 'package:dio/dio.dart';

import '../auth/cas_client.dart';

/// 图书馆研修间/研讨室模型
class SpaceRoom {
  const SpaceRoom({
    required this.id,
    required this.name,
    required this.floor,
    required this.roomType,
    required this.minNum,
    required this.maxNum,
    required this.devices,
    required this.status, // 0: 正常, 1: 禁用, 2: 维护中
    this.buildingName = '',
    this.spaceTime = 0,
    this.allTime = 0,
    this.openStartTime = '08:00',
    this.openEndTime = '21:00',
    this.reservationMinTime = 60,
    this.reservationMaxTime = 240,
    this.minSignTime = 20,
    this.maxSignTime = 20,
    this.leaveMaxTime = 30,
    this.verify = 0,
    this.label = '',
    this.remark = '',
  });

  final String id;
  final String name;
  final String floor;
  final String roomType;
  final int minNum;
  final int maxNum;
  final String devices;
  final int status; // 0: 正常, 1: 禁用, 2: 维护中
  final String buildingName; // 建筑/馆舍名称，如 "湛恩图书馆"
  final int spaceTime; // 剩余空闲时间
  final int allTime; // 1: 全天可用
  final String openStartTime; // 开放开始时间
  final String openEndTime; // 开放结束时间
  final int reservationMinTime; // 最短预约分钟数
  final int reservationMaxTime; // 最长预约分钟数
  final int minSignTime; // 签到前缓冲分钟
  final int maxSignTime; // 签到后缓冲分钟
  final int leaveMaxTime; // 暂离最大分钟
  final int verify; // 1: 需审核, 0: 免审
  final String label; // 提示标签（如面试须上传凭证）
  final String remark;

  String get shortBuildingName {
    if (buildingName.contains('湛恩') || name.contains('湛恩')) return '湛恩';
    if (buildingName.contains('南校区') || buildingName.contains('334') || name.contains('334')) return '334号';
    if (buildingName.contains('复兴') || name.contains('复兴')) return '复兴';
    if (buildingName.contains('1100') || name.contains('1100')) return '1100号';
    if (buildingName.isNotEmpty) return buildingName;
    return '其他';
  }

  /// 真实可约状态判断（对接系统前端逻辑）：
  /// status 为 0 且存在空闲时间（或全天可用）
  bool get isAvailable => status == 0 && (spaceTime > 0 || allTime == 1);

  String get statusDesc {
    if (status == 1) return '已禁用';
    if (status == 2) return '维护中';
    if (spaceTime == 0 && allTime != 1) return '已约满';
    return '可预约';
  }

  String get capacityDesc {
    if (minNum > 0 && maxNum >= minNum) {
      return '$minNum - $maxNum 人';
    }
    if (maxNum > 0) return '最多 $maxNum 人';
    return '多功能研讨空间';
  }
}

/// 空间预约时段切片模型
class SpaceTimeSlice {
  const SpaceTimeSlice({
    required this.startTime,
    required this.endTime,
    required this.isOccupied,
  });

  final String startTime;
  final String endTime;
  final bool isOccupied; // 是否已被占用
}

/// 已被占用的预约时段信息
class SpaceBookedSegment {
  const SpaceBookedSegment({
    required this.startTime,
    required this.endTime,
    required this.statusDesc,
  });

  final String startTime;
  final String endTime;
  final String statusDesc;

  String get timeRange => '$startTime - $endTime';
}

/// 房间详细信息模型（含当天时段切片与预约占用）
class SpaceRoomDetail {
  const SpaceRoomDetail({
    required this.room,
    required this.timeSlices,
    required this.existingReservations,
    this.bookedSegments = const <SpaceBookedSegment>[],
  });

  final SpaceRoom room;
  final List<SpaceTimeSlice> timeSlices;
  final List<Map<String, dynamic>> existingReservations;
  final List<SpaceBookedSegment> bookedSegments;
}

/// 空间预约订单记录
class SpaceReservation {
  const SpaceReservation({
    required this.id,
    required this.roomName,
    required this.date,
    required this.beginTime,
    required this.endTime,
    required this.status,
    required this.statusDesc,
    required this.isLeader,
    required this.qrCode,
  });

  final String id;
  final String roomName;
  final String date;
  final String beginTime;
  final String endTime;
  final int status; // 0: 待使用, 1: 使用中, 2: 已完成, 3: 已取消
  final String statusDesc;
  final bool isLeader;
  final String qrCode;

  String get timeRange => '$beginTime - $endTime';
  bool get canCancel => status == 0 && isLeader;
}

/// 空间预约服务（对接 libspace.usst.edu.cn 原生接口）
class SpaceBookingApi {
  SpaceBookingApi(this.casClient);

  final CasClient casClient;

  static const String _libspaceBase = 'https://libspace.usst.edu.cn';

  String? accessToken;
  String? userId;
  String? realName;
  String? authCode;
  DateTime? tokenObtainedAt;
  int tokenExpiresInSeconds = 7200;

  /// 检查 Token 是否仍在有效期内（预留 30 分钟缓冲期防边缘失效）
  bool get isTokenValid {
    if (accessToken == null || accessToken!.isEmpty) return false;
    if (tokenObtainedAt == null) return false;
    final elapsed = DateTime.now().difference(tokenObtainedAt!).inSeconds;
    return elapsed < (tokenExpiresInSeconds - 1800);
  }

  /// 确保已认证；若未登录或 Token 即将过期，自动静默通过 CAS SSO 重新获取
  Future<bool> ensureAuthenticated({bool force = false}) async {
    if (!force && isTokenValid) return true;
    return await login();
  }

  /// 获取一个新鲜、未经使用的 authCode（用于免密跳转官方网页端）
  Future<String?> acquireFreshAuthCode({String? redirectPath}) async {
    try {
      final path = redirectPath ?? '/student/studentIndex';
      final authorizeUri = Uri.parse(
        '$_libspaceBase/api/oauth/v1/authorize?redirectURI=${Uri.encodeComponent('$_libspaceBase$path')}',
      );
      final resp = await casClient.getApi(authorizeUri);

      final realUri = resp.realUri;
      String? code = realUri.queryParameters['code'];

      if (code == null || code.isEmpty) {
        final loc = resp.headers.value('location') ?? '';
        if (loc.contains('code=')) {
          final uri = Uri.tryParse(loc);
          code = uri?.queryParameters['code'];
        }
      }
      return code;
    } catch (_) {}
    return null;
  }

  /// 自动走 CAS SSO 流程完成授权并获取 accessToken
  Future<bool> login() async {
    try {
      final authorizeUri = Uri.parse(
        '$_libspaceBase/api/oauth/v1/authorize?redirectURI=${Uri.encodeComponent('$_libspaceBase/student/studentIndex')}',
      );
      final resp = await casClient.getApi(authorizeUri);

      final realUri = resp.realUri;
      String? code = realUri.queryParameters['code'];

      if (code == null || code.isEmpty) {
        final loc = resp.headers.value('location') ?? '';
        if (loc.contains('code=')) {
          final uri = Uri.tryParse(loc);
          code = uri?.queryParameters['code'];
        }
      }

      if (code == null || code.isEmpty) {
        return false;
      }

      authCode = code;

      final tokenUri = Uri.parse(
        '$_libspaceBase/api/studyroom/v1/userAccount/accessToken',
      ).replace(queryParameters: <String, String>{'code': code});
      final tokenResp = await casClient.getApi(tokenUri);

      if (tokenResp.statusCode == 200 && tokenResp.data != null) {
        final Map<String, dynamic> json =
            jsonDecode(tokenResp.data!) as Map<String, dynamic>;
        // 后端直接在根对象返回 accessToken/appId/appSecret
        final data = (json['data'] as Map<String, dynamic>?) ?? json;
        accessToken = data['accessToken']?.toString();
        final appId = data['appId']?.toString() ?? '';
        final appSecret = data['appSecret']?.toString() ?? '';

        if (accessToken != null && accessToken!.isNotEmpty) {
          tokenObtainedAt = DateTime.now();
          if (data['expires'] is num) {
            tokenExpiresInSeconds = (data['expires'] as num).toInt();
          }

          // /api/oauth/v1/user 接口需使用 POST 请求，GET 会报 500
          final userUri = Uri.parse('$_libspaceBase/api/oauth/v1/user').replace(
            queryParameters: <String, String>{
              'accessToken': accessToken!,
              'appId': appId,
              'appSecret': appSecret,
            },
          );
          try {
            final userResp = await casClient.postApi(
              userUri,
              <String, String>{},
              extraHeaders: <String, String>{
                'Authorization': accessToken!,
              },
            );
            if (userResp.statusCode == 200 && userResp.data != null) {
              final Map<String, dynamic> uJson =
                  jsonDecode(userResp.data!) as Map<String, dynamic>;
              final uData = (uJson['data'] as Map<String, dynamic>?) ?? uJson;
              userId = (uData['userId'] ?? uData['id'])?.toString();
              realName = (uData['realName'] ?? uData['userName'] ?? uData['nickName'])?.toString();
            }
          } catch (_) {}

          // 兜底：若接口未返回 userId，从 JWT 的 sub 载荷中解析 uid（学号）
          if (userId == null || userId!.isEmpty) {
            userId = _extractUidFromJwt(accessToken!);
          }

          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// 获取研讨间列表 (mRooms)
  Future<List<SpaceRoom>> fetchRooms({String? date}) async {
    await ensureAuthenticated();

    final queryDate = date ?? _formatDate(DateTime.now());
    final uri = Uri.parse('$_libspaceBase/api/studyroom/v1/room/mRooms').replace(
      queryParameters: <String, String>{
        'date': queryDate,
      },
    );

    try {
      var resp = await casClient.getApi(
        uri,
        headers: <String, String>{
          'Authorization': ?accessToken,
          'Accept': 'application/json;charset=UTF-8',
        },
      );

      // 遇到 Token 失效/401 自动重新静默登录并重试一次
      if (_isUnauthorized(resp)) {
        final reAuthOk = await login();
        if (reAuthOk) {
          resp = await casClient.getApi(
            uri,
            headers: <String, String>{
              'Authorization': ?accessToken,
              'Accept': 'application/json;charset=UTF-8',
            },
          );
        }
      }

      if (resp.statusCode == 200 && resp.data != null) {
        final dynamic raw = jsonDecode(resp.data!);
        final dynamic data = (raw is Map) ? (raw['data'] ?? raw) : raw;
        final list = <SpaceRoom>[];
        if (data is List) {
          for (final group in data) {
            if (group is! Map) continue;
            final buildingName = (group['name'] ?? '').toString();
            final rooms = group['rooms'];
            if (rooms is List) {
              for (final r in rooms) {
                if (r is! Map) continue;
                list.add(_parseRoom(r.cast<String, dynamic>(), buildingName));
              }
            } else {
              list.add(_parseRoom(group.cast<String, dynamic>(), buildingName));
            }
          }
        }
        return list;
      }
    } catch (_) {}
    return const <SpaceRoom>[];
  }

  /// 获取指定房间在某日期的实时预约与时间切片详情
  Future<SpaceRoomDetail?> fetchRoomReservationDetail({
    required String roomId,
    required String date,
  }) async {
    await ensureAuthenticated();

    final uri = Uri.parse('$_libspaceBase/api/studyroom/v1/room/reservation').replace(
      queryParameters: <String, String>{
        'roomId': roomId,
        'date': date,
      },
    );

    try {
      var resp = await casClient.getApi(
        uri,
        headers: <String, String>{
          'Authorization': ?accessToken,
          'Accept': 'application/json;charset=UTF-8',
        },
      );

      if (_isUnauthorized(resp)) {
        if (await login()) {
          resp = await casClient.getApi(
            uri,
            headers: <String, String>{
              'Authorization': ?accessToken,
              'Accept': 'application/json;charset=UTF-8',
            },
          );
        }
      }

      if (resp.statusCode == 200 && resp.data != null) {
        final dynamic rawJson = jsonDecode(resp.data!);
        if (rawJson is Map) {
          final dynamic data = rawJson.containsKey('data') && rawJson['data'] is Map ? rawJson['data'] : rawJson;
          final m = (data as Map).cast<String, dynamic>();
          final room = _parseRoom(m);

          final timeSlices = <SpaceTimeSlice>[];
          final rawSlices = m['dateTimeSlicesList'];
          if (rawSlices is List) {
            for (final group in rawSlices) {
              if (group is List) {
                for (final slice in group) {
                  if (slice is Map) {
                    final start = _formatTimestampOrString(slice['startTime'], timeOnly: true);
                    final end = _formatTimestampOrString(slice['endTime'], timeOnly: true);
                    final status = _parseInt(slice['reservationStatus'], 0);
                    timeSlices.add(
                      SpaceTimeSlice(
                        startTime: start,
                        endTime: end,
                        isOccupied: status != 0,
                      ),
                    );
                  }
                }
              } else if (group is Map) {
                final start = _formatTimestampOrString(group['startTime'], timeOnly: true);
                final end = _formatTimestampOrString(group['endTime'], timeOnly: true);
                final status = _parseInt(group['reservationStatus'], 0);
                timeSlices.add(
                  SpaceTimeSlice(
                    startTime: start,
                    endTime: end,
                    isOccupied: status != 0,
                  ),
                );
              }
            }
          }

          final existingList = <Map<String, dynamic>>[];
          final bookedSegments = <SpaceBookedSegment>[];
          final reservations = m['reservations'];
          if (reservations is List) {
            for (final res in reservations) {
              if (res is Map) {
                final rMap = res.cast<String, dynamic>();
                existingList.add(rMap);
                final sTime = _formatTimestampOrString(rMap['startTime'] ?? rMap['beginTime'], timeOnly: true);
                final eTime = _formatTimestampOrString(rMap['endTime'], timeOnly: true);
                final sDesc = (rMap['stateName'] ?? rMap['statusName'] ?? '已预约').toString();
                if (sTime.isNotEmpty && eTime.isNotEmpty) {
                  bookedSegments.add(
                    SpaceBookedSegment(
                      startTime: sTime,
                      endTime: eTime,
                      statusDesc: sDesc,
                    ),
                  );
                }
              }
            }
          }

          return SpaceRoomDetail(
            room: room,
            timeSlices: timeSlices,
            existingReservations: existingList,
            bookedSegments: bookedSegments,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// 获取当前预约与历史预约
  Future<List<SpaceReservation>> fetchMyReservations() async {
    await ensureAuthenticated();

    if (userId == null || accessToken == null) {
      return const <SpaceReservation>[];
    }

    final headers = <String, String>{
      'Authorization': accessToken!,
      'Accept': 'application/json;charset=UTF-8',
    };

    final list = <SpaceReservation>[];

    try {
      // 1. 当前生效的预约 (reservationByUserId)
      final currentUri = Uri.parse(
        '$_libspaceBase/api/studyroom/v1/reservation/reservationByUserId',
      ).replace(queryParameters: <String, String>{'userId': userId!});
      var cResp = await casClient.getApi(currentUri, headers: headers);
      if (_isUnauthorized(cResp)) {
        if (await login()) {
          headers['Authorization'] = accessToken!;
          cResp = await casClient.getApi(currentUri, headers: headers);
        }
      }

      if (cResp.statusCode == 200 && cResp.data != null && cResp.data!.trim().isNotEmpty) {
        final dynamic raw = jsonDecode(cResp.data!);
        final dynamic data = (raw is Map && raw.containsKey('data')) ? raw['data'] : raw;
        if (data is Map && data.isNotEmpty) {
          list.add(_parseReservation(data.cast<String, dynamic>(), userId));
        } else if (data is List && data.isNotEmpty) {
          for (final item in data) {
            if (item is Map) {
              list.add(_parseReservation(item.cast<String, dynamic>(), userId));
            }
          }
        }
      }

      // 2. 历史预约分页 (pageByUserId，必须使用 POST 提交 JSON body: {userId})
      final pageUri = Uri.parse(
        '$_libspaceBase/api/studyroom/v1/reservation/pageByUserId',
      ).replace(
        queryParameters: <String, String>{'page': '1', 'size': '20'},
      );
      var pResp = await casClient.sendJsonWithHeaders(
        pageUri,
        data: <String, dynamic>{'userId': userId},
        extraHeaders: headers,
      );
      if (_isUnauthorized(pResp)) {
        if (await login()) {
          headers['Authorization'] = accessToken!;
          pResp = await casClient.sendJsonWithHeaders(
            pageUri,
            data: <String, dynamic>{'userId': userId},
            extraHeaders: headers,
          );
        }
      }

      if (pResp.statusCode == 200 && pResp.data != null) {
        final dynamic raw = jsonDecode(pResp.data!);
        final dynamic pData = (raw is Map && raw.containsKey('data')) ? raw['data'] : raw;
        final records = (pData is Map) ? (pData['records'] as List<dynamic>?) : null;
        if (records != null) {
          for (final rec in records) {
            if (rec is! Map) continue;
            final res = _parseReservation(rec.cast<String, dynamic>(), userId);
            if (!list.any((existing) => existing.id == res.id)) {
              list.add(res);
            }
          }
        }
      }
    } catch (_) {}

    return list;
  }

  /// 取消预约（官方接口为 POST /api/studyroom/v1/reservation/cancelReservation?reservationId=...）
  Future<bool> cancelReservation(String reservationId) async {
    await ensureAuthenticated();
    if (accessToken == null) return false;

    final uri = Uri.parse(
      '$_libspaceBase/api/studyroom/v1/reservation/cancelReservation',
    ).replace(
      queryParameters: <String, String>{
        'reservationId': reservationId,
      },
    );
    try {
      var resp = await casClient.postApi(
        uri,
        <String, String>{},
        extraHeaders: <String, String>{
          'Authorization': accessToken!,
          'Accept': 'application/json;charset=UTF-8',
        },
      );
      if (_isUnauthorized(resp)) {
        if (await login()) {
          resp = await casClient.postApi(
            uri,
            <String, String>{},
            extraHeaders: <String, String>{
              'Authorization': accessToken!,
              'Accept': 'application/json;charset=UTF-8',
            },
          );
        }
      }

      if (resp.statusCode == 200 && resp.data != null) {
        final Map<String, dynamic> json =
            jsonDecode(resp.data!) as Map<String, dynamic>;
        return json['code'] == 200 || json['success'] == true;
      }
    } catch (_) {}
    return false;
  }

  static bool _isUnauthorized(Response<String> resp) {
    if (resp.statusCode == 401 || resp.statusCode == 403) return true;
    final body = resp.data ?? '';
    if (body.contains('token is null') ||
        body.contains('未登录') ||
        body.contains('"code":401') ||
        body.contains('"code":2002') ||
        body.contains('"code":2004')) {
      return true;
    }
    return false;
  }

  static SpaceRoom _parseRoom(Map<String, dynamic> m, [String buildingName = '']) {
    return SpaceRoom(
      id: (m['id'] ?? '').toString(),
      name: (m['roomName'] ?? m['name'] ?? '研讨间').toString(),
      floor: (m['floorName'] ?? m['floor'] ?? m['roomLocation'] ?? '').toString(),
      roomType: (m['roomTypeName'] ?? m['type'] ?? '研修空间').toString(),
      minNum: _parseInt(m['minNum'] ?? m['minPerson'] ?? m['minReservationNum'], 1),
      maxNum: _parseInt(m['maxNum'] ?? m['maxPerson'], 8),
      devices: (m['deviceNames'] ?? m['itemRemarks'] ?? m['devices'] ?? '')
          .toString(),
      status: _parseInt(m['state'] ?? m['status'], 0),
      buildingName: buildingName.isNotEmpty ? buildingName : (m['buildingName'] ?? '').toString(),
      spaceTime: _parseInt(m['spaceTime'], 0),
      allTime: _parseInt(m['allTime'], 0),
      openStartTime: (m['startTime'] ?? '08:00').toString(),
      openEndTime: (m['endTime'] ?? '21:00').toString(),
      reservationMinTime: _parseInt(m['reservationMinTime'], 60),
      reservationMaxTime: _parseInt(m['reservationMaxTime'], 240),
      minSignTime: _parseInt(m['minSignTime'], 20),
      maxSignTime: _parseInt(m['maxSignTime'], 20),
      leaveMaxTime: _parseInt(m['leaveMaxTime'], 30),
      verify: _parseInt(m['verify'], 0),
      label: (m['label'] ?? '').toString(),
      remark: (m['remark'] ?? '').toString(),
    );
  }

  static SpaceReservation _parseReservation(Map<String, dynamic> m, [String? currentUserId]) {
    final rawStatus = _parseInt(m['reservationStatus'] ?? m['state'] ?? m['status'], 0);

    // 官方状态码字典对照（libspace 前端 getStatus）：
    // 11: 待审核, 12: 待受约人确认, 21: 已预约, 22: 审核通过, 23: 审核不通过
    // 31: 已签到, 41: 暂离, 42: 取消暂离
    // 51: 个人签退, 52: 管理员签退, 53: 系统签退
    // 61: 个人取消, 62: 管理员取消, 63: 系统取消
    const statusMap = <int, String>{
      11: '待审核',
      12: '待受约人确认',
      21: '已预约',
      22: '审核通过',
      23: '审核不通过',
      31: '已签到',
      41: '暂离',
      42: '取消暂离',
      51: '个人签退',
      52: '管理员签退',
      53: '系统签退',
      61: '个人取消',
      62: '管理员取消',
      63: '系统取消',
    };

    int normalizedStatus = 0;
    if (rawStatus == 31 || rawStatus == 41 || rawStatus == 42 || rawStatus == 1) {
      normalizedStatus = 1; // 使用中
    } else if (rawStatus == 51 || rawStatus == 52 || rawStatus == 53 || rawStatus == 2) {
      normalizedStatus = 2; // 已完成
    } else if (rawStatus == 23 || rawStatus >= 61 || rawStatus == 3) {
      normalizedStatus = 3; // 已取消
    } else {
      normalizedStatus = 0; // 待使用 (11, 12, 21, 22 等)
    }

    final statusDesc = statusMap[rawStatus] ??
        (m['stateName'] ??
            m['statusName'] ??
            (normalizedStatus == 0
                ? '待使用'
                : normalizedStatus == 1
                    ? '使用中'
                    : normalizedStatus == 2
                        ? '已完成'
                        : '已取消'))
            .toString();

    final dateStr = _formatTimestampOrString(m['reservationDate'] ?? m['startTime'] ?? m['date'], dateOnly: true);
    final beginTimeStr = _formatTimestampOrString(m['beginTime'] ?? m['startTime'], timeOnly: true);
    final endTimeStr = _formatTimestampOrString(m['endTime'], timeOnly: true);

    bool isLeader = m['type'] == 0 || m['isLeader'] == true || m['userType'] == 1;
    if (currentUserId != null && m['leader'] is Map) {
      final leaderUserId = (m['leader'] as Map)['userId']?.toString();
      if (leaderUserId != null && leaderUserId.isNotEmpty) {
        isLeader = leaderUserId == currentUserId;
      }
    }

    return SpaceReservation(
      id: (m['id'] ?? m['reservationId'] ?? '').toString(),
      roomName: (m['roomName'] ?? m['name'] ?? '图书馆研讨间').toString(),
      date: dateStr,
      beginTime: beginTimeStr,
      endTime: endTimeStr,
      status: normalizedStatus,
      statusDesc: statusDesc,
      isLeader: isLeader,
      qrCode: (m['signCode'] ?? '').toString(),
    );
  }

  static String _formatTimestampOrString(dynamic val, {bool dateOnly = false, bool timeOnly = false}) {
    if (val == null) return '';
    final str = val.toString().trim();
    if (str.isEmpty) return '';

    // 若是毫秒时间戳（数字或大于 10 位的数字字符串）
    final numVal = int.tryParse(str);
    if (numVal != null && str.length >= 10) {
      final dt = DateTime.fromMillisecondsSinceEpoch(numVal);
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      if (dateOnly) return '$y-$m-$d';
      if (timeOnly) return '$hh:$mm';
      return '$y-$m-$d $hh:$mm';
    }

    // 若是字符串
    if (dateOnly && str.length >= 10 && str.contains('-')) {
      return str.substring(0, 10);
    }
    if (timeOnly && str.contains(':')) {
      final parts = str.split(' ');
      final timePart = parts.length > 1 ? parts.last : parts.first;
      final tParts = timePart.split(':');
      if (tParts.length >= 2) {
        return '${tParts[0]}:${tParts[1]}';
      }
    }
    return str;
  }

  /// 从 JWT 载荷中解析 uid（学号）
  static String? _extractUidFromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1];
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      final sub = map['sub'];
      if (sub is String) {
        final subMap = jsonDecode(sub) as Map<String, dynamic>;
        return subMap['uid']?.toString();
      } else if (sub is Map<String, dynamic>) {
        return sub['uid']?.toString();
      }
    } catch (_) {}
    return null;
  }

  static int _parseInt(dynamic val, int fallback) {
    if (val == null) return fallback;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString().trim()) ?? fallback;
  }

  static String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
