import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/jwc/space_booking_api.dart';

class _MockCasClient extends CasClient {
  _MockCasClient(this.mockResponses);

  final Map<String, dynamic> mockResponses;

  @override
  Future<Response<String>> getApi(Uri uri, {Map<String, String>? headers}) async {
    final key = uri.toString();
    if (key.contains('oauth/v1/authorize')) {
      return Response<String>(
        requestOptions: RequestOptions(
          path: 'https://libspace.usst.edu.cn/student/studentIndex?code=mock_code_123',
        ),
        statusCode: 200,
        data: '<html>redirect</html>',
      );
    }
    for (final entry in mockResponses.entries) {
      if (key.contains(entry.key)) {
        return Response<String>(
          requestOptions: RequestOptions(path: key),
          statusCode: 200,
          data: entry.value is String ? entry.value as String : jsonEncode(entry.value),
        );
      }
    }
    return Response<String>(
      requestOptions: RequestOptions(path: key),
      statusCode: 404,
      data: 'Not Found',
    );
  }

  @override
  Future<Response<String>> postApi(
    Uri uri,
    Map<String, String> data, {
    String? referer,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final key = uri.toString();
    for (final entry in mockResponses.entries) {
      if (key.contains(entry.key)) {
        return Response<String>(
          requestOptions: RequestOptions(path: key),
          statusCode: 200,
          data: entry.value is String ? entry.value as String : jsonEncode(entry.value),
        );
      }
    }
    return Response<String>(
      requestOptions: RequestOptions(path: key),
      statusCode: 404,
      data: 'Not Found',
    );
  }

  @override
  Future<Response<String>> sendJsonWithHeaders(
    Uri uri, {
    String method = 'POST',
    Map<String, dynamic> data = const <String, dynamic>{},
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final key = uri.toString();
    for (final entry in mockResponses.entries) {
      if (key.contains(entry.key)) {
        return Response<String>(
          requestOptions: RequestOptions(path: key),
          statusCode: 200,
          data: entry.value is String ? entry.value as String : jsonEncode(entry.value),
        );
      }
    }
    return Response<String>(
      requestOptions: RequestOptions(path: key),
      statusCode: 404,
      data: 'Not Found',
    );
  }
}

void main() {
  group('SpaceBookingApi Unit Tests', () {
    test('login success with root accessToken & post user', () async {
      final jwtPayload = base64Url.encode(
        utf8.encode(jsonEncode(<String, dynamic>{
          'sub': jsonEncode(<String, dynamic>{'uid': '123456'}),
        })),
      ).replaceAll('=', '');
      final mockJwt = 'header.$jwtPayload.signature';

      final mockClient = _MockCasClient(<String, dynamic>{
        'studyroom/v1/userAccount/accessToken': <String, dynamic>{
          'accessToken': mockJwt,
          'appId': 'testApp',
          'appSecret': 'testSecret',
        },
        'oauth/v1/user': <String, dynamic>{
          'userId': '123456',
          'realName': '张三',
        },
      });

      final api = SpaceBookingApi(mockClient);
      final ok = await api.login();
      expect(ok, isTrue);
      expect(api.accessToken, mockJwt);
      expect(api.userId, '123456');
      expect(api.realName, '张三');
    });

    test('fetchRooms parses grouped and direct rooms', () async {
      final mockClient = _MockCasClient(<String, dynamic>{
        'studyroom/v1/room/mRooms': <dynamic>[
          <String, dynamic>{
            'name': '一楼大厅',
            'rooms': <dynamic>[
              <String, dynamic>{
                'id': 101,
                'name': '研讨间101',
                'floorName': '1楼',
                'minNum': 2,
                'maxNum': 6,
                'state': 1,
              },
            ],
          },
        ],
      });

      final api = SpaceBookingApi(mockClient);
      final rooms = await api.fetchRooms();
      expect(rooms.length, 1);
      expect(rooms.first.name, '研讨间101');
      expect(rooms.first.capacityDesc, '2 - 6 人');
    });

    test('fetchMyReservations parses active & history with status mappings', () async {
      final mockClient = _MockCasClient(<String, dynamic>{
        'reservationByUserId': <String, dynamic>{
          'id': 'res1',
          'roomName': '研讨间101',
          'startTime': '2026-10-30 14:00:00',
          'endTime': '2026-10-30 16:00:00',
          'reservationStatus': 21,
          'type': 0,
        },
        'pageByUserId': <String, dynamic>{
          'records': <dynamic>[
            <String, dynamic>{
              'id': 'res2',
              'roomName': '研讨间102',
              'startTime': '2026-10-29 10:00:00',
              'endTime': '2026-10-29 12:00:00',
              'reservationStatus': 51,
              'type': 1,
            },
          ],
        },
      });

      final api = SpaceBookingApi(mockClient);
      api.userId = '123456';
      api.accessToken = 'test-token';

      final list = await api.fetchMyReservations();
      expect(list.length, 2);
      expect(list[0].statusDesc, '已预约');
      expect(list[0].status, 0); // 待使用
      expect(list[0].isLeader, isTrue);

      expect(list[1].statusDesc, '个人签退');
      expect(list[1].status, 2); // 已完成
      expect(list[1].isLeader, isFalse);
    });

    test('cancelReservation calls postApi', () async {
      final mockClient = _MockCasClient(<String, dynamic>{
        'reservation/cancelReservation': <String, dynamic>{
          'code': 200,
          'success': true,
        },
      });

      final api = SpaceBookingApi(mockClient);
      api.accessToken = 'test-token';

      final ok = await api.cancelReservation('res1');
      expect(ok, isTrue);
    });

    test('SpaceRoom availability and statusDesc rules', () {
      const roomAvailable = SpaceRoom(
        id: '1',
        name: '研讨间1',
        floor: '1F',
        roomType: '研讨间',
        minNum: 2,
        maxNum: 6,
        devices: '投影',
        status: 0,
        spaceTime: 120,
        allTime: 0,
      );
      expect(roomAvailable.isAvailable, isTrue);
      expect(roomAvailable.statusDesc, '可预约');

      const roomFull = SpaceRoom(
        id: '2',
        name: '研讨间2',
        floor: '1F',
        roomType: '研讨间',
        minNum: 2,
        maxNum: 6,
        devices: '投影',
        status: 0,
        spaceTime: 0,
        allTime: 0,
      );
      expect(roomFull.isAvailable, isFalse);
      expect(roomFull.statusDesc, '已约满');

      const roomDisabled = SpaceRoom(
        id: '3',
        name: '研讨间3',
        floor: '1F',
        roomType: '研讨间',
        minNum: 2,
        maxNum: 6,
        devices: '投影',
        status: 1,
        spaceTime: 120,
        allTime: 0,
      );
      expect(roomDisabled.isAvailable, isFalse);
      expect(roomDisabled.statusDesc, '已禁用');

      const roomMaintenance = SpaceRoom(
        id: '4',
        name: '研讨间4',
        floor: '1F',
        roomType: '研讨间',
        minNum: 2,
        maxNum: 6,
        devices: '投影',
        status: 2,
        spaceTime: 120,
        allTime: 0,
      );
      expect(roomMaintenance.isAvailable, isFalse);
      expect(roomMaintenance.statusDesc, '维护中');
    });

    test('fetchRoomReservationDetail parses time slices and booked segments', () async {
      final mockClient = _MockCasClient(<String, dynamic>{
        'studyroom/v1/room/reservation': <String, dynamic>{
          'id': '101',
          'roomName': '湛恩101',
          'state': 0,
          'dateTimeSlicesList': <dynamic>[
            <dynamic>[
              <String, dynamic>{
                'startTime': '2026-10-30 08:00:00',
                'endTime': '2026-10-30 08:30:00',
                'reservationStatus': 0,
              },
              <String, dynamic>{
                'startTime': '2026-10-30 08:30:00',
                'endTime': '2026-10-30 09:00:00',
                'reservationStatus': 1,
              },
            ],
          ],
          'reservations': <dynamic>[
            <String, dynamic>{
              'startTime': '2026-10-30 08:30:00',
              'endTime': '2026-10-30 09:00:00',
              'stateName': '已预约',
            },
          ],
        },
      });

      final api = SpaceBookingApi(mockClient);
      api.accessToken = 'test-token';

      final detail = await api.fetchRoomReservationDetail(roomId: '101', date: '2026-10-30');
      expect(detail, isNotNull);
      expect(detail!.room.name, '湛恩101');
      expect(detail.timeSlices.length, 2);
      expect(detail.timeSlices[0].startTime, '08:00');
      expect(detail.timeSlices[0].endTime, '08:30');
      expect(detail.timeSlices[0].isOccupied, isFalse);
      expect(detail.timeSlices[1].isOccupied, isTrue);

      expect(detail.bookedSegments.length, 1);
      expect(detail.bookedSegments[0].timeRange, '08:30 - 09:00');
      expect(detail.bookedSegments[0].statusDesc, '已预约');
    });
  });
}
