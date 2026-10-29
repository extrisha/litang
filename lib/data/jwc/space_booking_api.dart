import 'dart:convert';

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
    required this.status,
  });

  final String id;
  final String name;
  final String floor;
  final String roomType;
  final int minNum;
  final int maxNum;
  final String devices;
  final int status; // 1: 正常/可约

  String get capacityDesc {
    if (minNum > 0 && maxNum >= minNum) {
      return '$minNum - $maxNum 人';
    }
    if (maxNum > 0) return '最多 $maxNum 人';
    return '多功能研讨空间';
  }
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
        final data = json['data'] as Map<String, dynamic>?;
        if (data != null) {
          accessToken = data['accessToken']?.toString();
          final appId = data['appId']?.toString() ?? '';
          final appSecret = data['appSecret']?.toString() ?? '';

          if (accessToken != null && accessToken!.isNotEmpty) {
            final userUri = Uri.parse('$_libspaceBase/api/oauth/v1/user').replace(
              queryParameters: <String, String>{
                'accessToken': accessToken!,
                'appId': appId,
                'appSecret': appSecret,
              },
            );
            final userResp = await casClient.getApi(userUri);
            if (userResp.statusCode == 200 && userResp.data != null) {
              final Map<String, dynamic> uJson =
                  jsonDecode(userResp.data!) as Map<String, dynamic>;
              final uData = uJson['data'] as Map<String, dynamic>?;
              if (uData != null) {
                userId = uData['userId']?.toString();
                realName = uData['realName']?.toString();
              }
            }
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// 获取研讨间列表 (mRooms)
  Future<List<SpaceRoom>> fetchRooms({String? date}) async {
    final queryDate = date ?? _formatDate(DateTime.now());
    final uri = Uri.parse('$_libspaceBase/api/studyroom/v1/room/mRooms').replace(
      queryParameters: <String, String>{
        'date': queryDate,
      },
    );

    final headers = <String, String>{
      'Authorization': ?accessToken,
      'Accept': 'application/json;charset=UTF-8',
    };

    try {
      final resp = await casClient.getApi(uri, headers: headers);
      if (resp.statusCode == 200 && resp.data != null) {
        final Map<String, dynamic> json =
            jsonDecode(resp.data!) as Map<String, dynamic>;
        final data = json['data'];
        final list = <SpaceRoom>[];
        if (data is List) {
          for (final group in data) {
            if (group is! Map) continue;
            final rooms = group['rooms'];
            if (rooms is List) {
              for (final r in rooms) {
                if (r is! Map) continue;
                list.add(_parseRoom(r.cast<String, dynamic>()));
              }
            } else {
              list.add(_parseRoom(group.cast<String, dynamic>()));
            }
          }
        }
        return list;
      }
    } catch (_) {}
    return const <SpaceRoom>[];
  }

  /// 获取当前预约与历史预约
  Future<List<SpaceReservation>> fetchMyReservations() async {
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
      final cResp = await casClient.getApi(currentUri, headers: headers);
      if (cResp.statusCode == 200 && cResp.data != null) {
        final Map<String, dynamic> json =
            jsonDecode(cResp.data!) as Map<String, dynamic>;
        final data = json['data'];
        if (data is Map) {
          list.add(_parseReservation(data.cast<String, dynamic>()));
        } else if (data is List && data.isNotEmpty) {
          for (final item in data) {
            if (item is Map) {
              list.add(_parseReservation(item.cast<String, dynamic>()));
            }
          }
        }
      }

      // 2. 历史预约分页 (pageByUserId)
      final pageUri = Uri.parse(
        '$_libspaceBase/api/studyroom/v1/reservation/pageByUserId',
      ).replace(
        queryParameters: <String, String>{'page': '1', 'size': '10'},
      );
      final pResp = await casClient.getApi(
        pageUri,
        headers: headers,
      );
      if (pResp.statusCode == 200 && pResp.data != null) {
        final Map<String, dynamic> json =
            jsonDecode(pResp.data!) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>?;
        final records = data?['records'] as List<dynamic>?;
        if (records != null) {
          for (final rec in records) {
            if (rec is! Map) continue;
            final res = _parseReservation(rec.cast<String, dynamic>());
            if (!list.any((existing) => existing.id == res.id)) {
              list.add(res);
            }
          }
        }
      }
    } catch (_) {}

    return list;
  }

  /// 取消预约
  Future<bool> cancelReservation(String reservationId) async {
    if (accessToken == null) return false;
    final uri = Uri.parse(
      '$_libspaceBase/api/studyroom/v1/reservation/cancelReservation',
    ).replace(
      queryParameters: <String, String>{
        'reservationId': reservationId,
        'cancelType': '1',
      },
    );
    try {
      final resp = await casClient.getApi(
        uri,
        headers: <String, String>{
          'Authorization': accessToken!,
          'Accept': 'application/json;charset=UTF-8',
        },
      );
      if (resp.statusCode == 200 && resp.data != null) {
        final Map<String, dynamic> json =
            jsonDecode(resp.data!) as Map<String, dynamic>;
        return json['code'] == 200 || json['success'] == true;
      }
    } catch (_) {}
    return false;
  }

  static SpaceRoom _parseRoom(Map<String, dynamic> m) {
    return SpaceRoom(
      id: (m['id'] ?? '').toString(),
      name: (m['roomName'] ?? m['name'] ?? '研讨间').toString(),
      floor: (m['floorName'] ?? m['floor'] ?? '').toString(),
      roomType: (m['roomTypeName'] ?? m['type'] ?? '研修空间').toString(),
      minNum: _parseInt(m['minNum'] ?? m['minPerson'], 1),
      maxNum: _parseInt(m['maxNum'] ?? m['maxPerson'], 8),
      devices: (m['deviceNames'] ?? m['itemRemarks'] ?? m['devices'] ?? '')
          .toString(),
      status: _parseInt(m['state'] ?? m['status'], 1),
    );
  }

  static SpaceReservation _parseReservation(Map<String, dynamic> m) {
    final status = _parseInt(m['state'] ?? m['status'], 0);
    String statusDesc = '待使用';
    switch (status) {
      case 0:
        statusDesc = '待使用';
        break;
      case 1:
        statusDesc = '使用中';
        break;
      case 2:
        statusDesc = '已完成';
        break;
      case 3:
        statusDesc = '已取消';
        break;
      default:
        statusDesc = (m['stateName'] ?? m['statusName'] ?? '已预约').toString();
    }

    return SpaceReservation(
      id: (m['id'] ?? m['reservationId'] ?? '').toString(),
      roomName: (m['roomName'] ?? m['name'] ?? '图书馆研讨间').toString(),
      date: (m['reservationDate'] ?? m['date'] ?? '').toString(),
      beginTime: (m['beginTime'] ?? m['startTime'] ?? '').toString(),
      endTime: (m['endTime'] ?? '').toString(),
      status: status,
      statusDesc: statusDesc,
      isLeader: m['isLeader'] == true || m['userType'] == 1,
      qrCode: (m['signCode'] ?? '').toString(),
    );
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
