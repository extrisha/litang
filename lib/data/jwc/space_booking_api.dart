import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../app_exception.dart';
import '../auth/cas_client.dart';
import '../auth/jwgl_auth.dart';
import '../date_format.dart';
import 'space_booking_rules.dart';

/// 空间预约接口失败。
///
/// 继承 [AppException]：`authRelated` 为 true 时归一成 [AppFailure.auth]，
/// 页面既可以写 `catch (AppException e) => e.message`，也保留原来的
/// `authRelated` 判断。
class SpaceBookingException extends AppException {
  SpaceBookingException(String message, {bool authRelated = false})
    : authRelated = authRelated,
      super(authRelated ? AppFailure.auth : AppFailure.server, message);

  /// 是否属于「登录态失效」这类问题（与 `failure == AppFailure.auth` 等价，
  /// 保留是为了不改已有调用点）。
  final bool authRelated;
}

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
  final int spaceTime; // 剩余空闲时间（分钟）
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
    if (buildingName.contains('南校区') ||
        buildingName.contains('334') ||
        name.contains('334')) {
      return '334号';
    }
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
    if (spaceTime == 0 && allTime != 1) return '当天已约满';
    return '可预约';
  }

  String get capacityDesc {
    if (minNum > 0 && maxNum >= minNum) {
      return '$minNum - $maxNum 人';
    }
    if (maxNum > 0) return '最多 $maxNum 人';
    return '多功能研讨空间';
  }

  String get locationDesc {
    final b = buildingName.isNotEmpty ? buildingName : shortBuildingName;
    if (floor.isNotEmpty && !b.contains(floor)) {
      return '$b · $floor';
    }
    return b;
  }

  String get freeTimeDesc {
    if (allTime == 1) return '全天可约';
    if (spaceTime <= 0) return '暂无空闲';
    if (spaceTime >= 120) {
      final hours = (spaceTime / 60).toStringAsFixed(
        spaceTime % 60 == 0 ? 0 : 1,
      );
      return '余约 $hours 小时';
    }
    return '剩余 $spaceTime 分钟';
  }

  List<String> get deviceList {
    if (devices.isEmpty) return const <String>[];
    return devices
        .split(RegExp(r'[,，、;；\s]+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
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
  SpaceRoomDetail({
    required this.room,
    required this.timeSlices,
    required this.existingReservations,
    this.bookedSegments = const <SpaceBookedSegment>[],
  }) : hourSlots = _buildHourSlots(room, timeSlices, bookedSegments);

  final SpaceRoom room;
  final List<SpaceTimeSlice> timeSlices;
  final List<Map<String, dynamic>> existingReservations;
  final List<SpaceBookedSegment> bookedSegments;

  /// 全天按 1 小时整点聚合后的时段列表。
  ///
  /// 在构造时算一次并缓存：原先是重算 getter，而两个页面都在
  /// `GridView.itemBuilder` 里访问它，等于每个格子都重算一遍整表。
  final List<SpaceHourSlot> hourSlots;

  static List<SpaceHourSlot> _buildHourSlots(
    SpaceRoom room,
    List<SpaceTimeSlice> timeSlices,
    List<SpaceBookedSegment> bookedSegments,
  ) {
    final slots = <SpaceHourSlot>[];
    final openStartParts = room.openStartTime.split(':');
    final openEndParts = room.openEndTime.split(':');
    final startH = int.tryParse(openStartParts.first) ?? 8;
    final endH = int.tryParse(openEndParts.first) ?? 21;

    for (var h = startH; h < endH; h++) {
      final sHour = '${h.toString().padLeft(2, '0')}:00';
      final eHour = '${(h + 1).toString().padLeft(2, '0')}:00';

      bool occupied = false;
      String desc = '';

      for (final b in bookedSegments) {
        if (sHour.compareTo(b.endTime) < 0 &&
            eHour.compareTo(b.startTime) > 0) {
          occupied = true;
          desc = b.statusDesc;
          break;
        }
      }

      if (!occupied && timeSlices.isNotEmpty) {
        for (final slice in timeSlices) {
          if (slice.isOccupied &&
              sHour.compareTo(slice.endTime) < 0 &&
              eHour.compareTo(slice.startTime) > 0) {
            occupied = true;
            desc = '已被约';
            break;
          }
        }
      }

      slots.add(
        SpaceHourSlot(
          startHour: sHour,
          endHour: eHour,
          isOccupied: occupied,
          occupantDesc: desc,
        ),
      );
    }

    return slots;
  }
}

/// 1 小时整点颗粒度时段模型
class SpaceHourSlot {
  const SpaceHourSlot({
    required this.startHour,
    required this.endHour,
    required this.isOccupied,
    this.occupantDesc = '',
  });

  final String startHour; // 如 "08:00"
  final String endHour; // 如 "09:00"
  final bool isOccupied;
  final String occupantDesc;

  String get timeRange => '$startHour - $endHour';

  /// 判断该时段对于指定日期是否已经过期
  bool isPastFor(DateTime date) {
    final startH = int.tryParse(startHour.split(':').first) ?? 0;
    return SpaceBookingRules.isPastHour(startH, date, DateTime.now());
  }
}

/// 用户在空间预约系统中的账户与信用档案
class SpaceUserProfile {
  const SpaceUserProfile({
    required this.userId,
    required this.realName,
    required this.departmentName,
    required this.totalScore,
    this.cardNumber = '',
    this.mobile = '',
    this.faceUrl = '',
  });

  final String userId;
  final String realName;
  final String departmentName;
  final int totalScore; // 信用积分，满分 10
  final String cardNumber;
  final String mobile;
  final String faceUrl;
}

/// 空间预约用途类型模型（字典）
class SpacePurpose {
  const SpacePurpose({
    required this.id,
    required this.label,
    required this.minNum,
    required this.maxTime,
    required this.verify,
    required this.remark,
  });

  final int id;
  final String label; // 研讨交流, 面试, 单人研习
  final int minNum; // 最少人数
  final int maxTime; // 最长时长（分钟）
  final int verify; // 0: 免审, 1: 须审核
  final String remark;
}

/// 预约操作结果
class ReservationResult {
  const ReservationResult({
    required this.success,
    required this.message,
    this.reservationId,
    this.outcomeUnknown = false,
  });

  final bool success;
  final String message;
  final String? reservationId;

  /// 请求可能已送达，但服务端未确认；此时只能查询，不能盲目重发。
  final bool outcomeUnknown;
}

class SpaceReservationPage {
  const SpaceReservationPage({
    required this.items,
    required this.page,
    required this.hasMore,
  });

  final List<SpaceReservation> items;
  final int page;
  final bool hasMore;
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
    this.roomId = '',
    this.minSignTime = '',
    this.maxSignTime = '',
    this.signInTime = '',
    this.signOutTime = '',
    this.remark = '',
    this.departmentName = '',
    this.mobile = '',
    this.dictId = 0,
    this.dictName = '',
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
  final String roomId;
  final String minSignTime;
  final String maxSignTime;
  final String signInTime;
  final String signOutTime;
  final String remark;
  final String departmentName;
  final String mobile;
  final int dictId;
  final String dictName;

  String get timeRange => '$beginTime - $endTime';
  bool get canCancel => status == 0 && isLeader;
  bool get isInProgress => status == 1; // 使用中
  bool get isUpcoming => status == 0; // 待使用
  bool get isFinished => status == 2; // 已完成
  bool get isCancelled => status == 3; // 已取消
  bool get canSignOut => status == 1; // 使用中可手动签退
  bool get canAfk => status == 1; // 使用中可暂离
}

/// 空间预约服务（对接 libspace.usst.edu.cn 原生接口）
class SpaceBookingApi {
  SpaceBookingApi([CasClient? client]) : _casClient = client;

  CasClient? _casClient;

  CasClient get casClient =>
      _casClient ?? JwglAuth.instance.client ?? CasClient();

  set casClient(CasClient client) {
    _casClient = client;
  }

  static const String _libspaceBase = 'https://libspace.usst.edu.cn';

  String? accessToken;
  String? userId;
  String? realName;
  String? authCode;
  DateTime? tokenObtainedAt;
  int tokenExpiresInSeconds = 7200;

  SpaceUserProfile? userProfile;
  List<SpacePurpose>? cachedPurposes;

  /// 登录单飞：并发调用共享同一个 Future。
  Future<bool>? _loginInFlight;
  final Map<String, Future<ReservationResult>> _submissions = {};

  /// 结果未知的提交：key → 进入「未知」状态的时间。
  ///
  /// 用 Map 而不是 Set，是为了让它**会过期**：早先只有「查到预约已存在」才会移除，
  /// 一旦查询失败或服务端还没落库，这个 key 就永久留在集合里，
  /// 之后同一时段的提交永远只走查询、再也提交不了。
  final Map<String, DateTime> _uncertainSubmissions = {};

  /// 「结果未知」状态保留多久。超过后允许重新提交——
  /// 期间一直没查到这条预约，基本可以判定没约上。
  static const Duration _uncertainTtl = Duration(minutes: 2);

  /// 登录失败后的冷却截止时间，避免连续失败时反复捶 CAS / 令牌接口。
  DateTime? _loginCooldownUntil;

  /// [String] 登录失败冷却时长。
  static const Duration _loginCooldown = Duration(seconds: 3);

  /// 提前刷新的安全余量上下限（秒）。
  static const int _minRefreshMarginSeconds = 15;
  static const int _maxRefreshMarginSeconds = 120;

  /// 按 token 寿命比例算出的提前刷新余量。
  ///
  /// 原来固定留 600 秒。服务端 `expires` 只有 900 秒左右时，扣掉 600 秒只剩
  /// 300 秒（5 分钟）可用，挂机一会儿就失效；`expires` 若 ≤ 600 秒则「签发即
  /// 过期」，每次调用都会重走 CAS 登录。改成取寿命的 20%，并夹在 15~120 秒：
  /// 短寿命 token 能真正用掉大部分时间，长寿命 token 的刷新也不会拖太久。
  int get _refreshMarginSeconds {
    final scaled = (tokenExpiresInSeconds * 0.2).round();
    if (scaled < _minRefreshMarginSeconds) return _minRefreshMarginSeconds;
    if (scaled > _maxRefreshMarginSeconds) return _maxRefreshMarginSeconds;
    return scaled;
  }

  /// 检查 Token 是否仍在有效期内（按寿命比例预留缓冲，防边缘失效）
  bool get isTokenValid {
    if (accessToken == null || accessToken!.isEmpty) return false;
    final margin = _refreshMarginSeconds;

    // 优先检查 JWT 内部自带的 exp 真实过期秒数时间戳
    final exp = _extractExpFromJwt(accessToken!);
    if (exp != null) {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (nowSec >= exp - margin) return false;
    }

    if (tokenObtainedAt == null) return false;
    final elapsed = DateTime.now().difference(tokenObtainedAt!).inSeconds;
    return elapsed < (tokenExpiresInSeconds - margin);
  }

  /// 确保已认证；若未登录或 Token 即将过期，自动静默通过 CAS SSO 重新获取
  Future<bool> ensureAuthenticated({bool force = false}) async {
    if (!force && isTokenValid) return true;
    // force 表示「用户主动重试」，要能绕过登录失败后的冷却
    return await login(force: force);
  }

  /// 获取一个新鲜、未经使用的 authCode（用于免密跳转官方网页端）
  Future<String?> acquireFreshAuthCode({String? redirectPath}) async {
    try {
      final path = redirectPath ?? '/student/studentIndex';
      final authorizeUri = Uri.parse(
        '$_libspaceBase/api/oauth/v1/authorize?redirectURI=${Uri.encodeComponent('$_libspaceBase$path')}',
      );
      var resp = await casClient.getApi(authorizeUri);

      var realUri = resp.realUri;
      String? code = realUri.queryParameters['code'];

      if (code == null || code.isEmpty) {
        final loc = resp.headers.value('location') ?? '';
        if (loc.contains('code=')) {
          final uri = Uri.tryParse(loc);
          code = uri?.queryParameters['code'];
        }
      }

      // 若未拿到 code，检查是否被 CAS 登录页拦截；若是则自动重登 CAS 恢复
      if (code == null || code.isEmpty) {
        final isCasIntercepted =
            realUri.toString().contains('cas.usst.edu.cn') ||
            (resp.data?.contains('username') == true &&
                resp.data?.contains('password') == true);
        if (isCasIntercepted) {
          final sessionOk = await JwglAuth.instance.ensureSession();
          if (sessionOk) {
            if (JwglAuth.instance.client != null) {
              _casClient = JwglAuth.instance.client;
            }
            resp = await casClient.getApi(authorizeUri);
            realUri = resp.realUri;
            code = realUri.queryParameters['code'];
            if (code == null || code.isEmpty) {
              final loc = resp.headers.value('location') ?? '';
              if (loc.contains('code=')) {
                code = Uri.tryParse(loc)?.queryParameters['code'];
              }
            }
          }
        }
      }

      return code;
    } catch (e) {
      debugPrint('[space] 获取 authCode 失败: $e');
    }
    return null;
  }

  /// 自动走 CAS SSO 流程完成授权并获取 accessToken。
  ///
  /// **必须单飞**：房间列表和「我的预约」是并发拉取的，token 一旦被服务端判
  /// 无效，两边会**同时**触发重登。没有单飞就会同时发起两轮 CAS 授权 + 两次
  /// 换 token，互相覆盖 `accessToken`；如果服务端在签发新 token 时让旧 token
  /// 失效，两边最终都拿着已被顶掉的 token，表现就是
  /// 「明明刚登录成功，却一直提示登录失效」——重试几次又偶尔好一次。
  ///
  /// 失败后再加 [3 秒冷却]：避免 token 长期不可用时，每个并发请求都触发一轮
  /// 登录，把 CAS 和令牌接口打成风暴。
  Future<bool> login({bool force = false}) {
    final inFlight = _loginInFlight;
    if (inFlight != null) return inFlight;

    final cooldownUntil = _loginCooldownUntil;
    if (!force &&
        cooldownUntil != null &&
        DateTime.now().isBefore(cooldownUntil)) {
      debugPrint('[space] 登录冷却中，跳过本次重登');
      return Future<bool>.value(false);
    }

    final future = _loginOnce()
        .then((ok) {
          _loginCooldownUntil = ok ? null : DateTime.now().add(_loginCooldown);
          return ok;
        })
        .whenComplete(() => _loginInFlight = null);
    _loginInFlight = future;
    return future;
  }

  Future<bool> _loginOnce() async {
    try {
      final authorizeUri = Uri.parse(
        '$_libspaceBase/api/oauth/v1/authorize?redirectURI=${Uri.encodeComponent('$_libspaceBase/student/studentIndex')}',
      );
      var resp = await casClient.getApi(authorizeUri);

      var realUri = resp.realUri;
      String? code = realUri.queryParameters['code'];

      if (code == null || code.isEmpty) {
        final loc = resp.headers.value('location') ?? '';
        if (loc.contains('code=')) {
          final uri = Uri.tryParse(loc);
          code = uri?.queryParameters['code'];
        }
      }

      // 如果未拿到 code，说明 CAS SSO 会话已过期，被重定向到了 cas.usst.edu.cn/cas/login
      if (code == null || code.isEmpty) {
        final isCasIntercepted =
            realUri.toString().contains('cas.usst.edu.cn') ||
            (resp.data?.contains('username') == true &&
                resp.data?.contains('password') == true);
        if (isCasIntercepted) {
          final sessionOk = await JwglAuth.instance.ensureSession();
          if (sessionOk) {
            if (JwglAuth.instance.client != null) {
              _casClient = JwglAuth.instance.client;
            }
            resp = await casClient.getApi(authorizeUri);
            realUri = resp.realUri;
            code = realUri.queryParameters['code'];
            if (code == null || code.isEmpty) {
              final loc = resp.headers.value('location') ?? '';
              if (loc.contains('code=')) {
                code = Uri.tryParse(loc)?.queryParameters['code'];
              }
            }
          }
        }
      }

      if (code == null || code.isEmpty) {
        // 拿不到授权码：CAS 没放行，也不像登录页（否则上面会尝试恢复会话）
        debugPrint(
          '[space] 登录失败：没拿到 code'
          '（realUri=${realUri.path}，status=${resp.statusCode}）',
        );
        return false;
      }

      authCode = code;

      final tokenUri = Uri.parse(
        '$_libspaceBase/api/studyroom/v1/userAccount/accessToken',
      ).replace(queryParameters: <String, String>{'code': code});
      final tokenResp = await casClient.getApi(tokenUri);

      if (tokenResp.statusCode != 200 || tokenResp.data == null) {
        // 用 code 换 token 失败：CAS 票据可能已被用过/过期（有效期很短）
        final body = (tokenResp.data ?? '').trim();
        debugPrint(
          '[space] 登录失败：换 token 返回 ${tokenResp.statusCode}'
          '（code 长度 ${code.length}，body=${body.length > 160 ? '${body.substring(0, 160)}…' : body}）',
        );
      }

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
          // 便于排查「token 多久失效」：只在 debug 构建里输出
          debugPrint(
            '[space] token 有效期 ${tokenExpiresInSeconds}s，'
            '提前刷新余量 ${_refreshMarginSeconds}s',
          );

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
              extraHeaders: <String, String>{'Authorization': accessToken!},
            );
            if (userResp.statusCode == 200 && userResp.data != null) {
              final Map<String, dynamic> uJson =
                  jsonDecode(userResp.data!) as Map<String, dynamic>;
              final uData = (uJson['data'] as Map<String, dynamic>?) ?? uJson;
              userId = (uData['userId'] ?? uData['id'])?.toString();
              realName =
                  (uData['realName'] ?? uData['userName'] ?? uData['nickName'])
                      ?.toString();
            }
          } catch (_) {}

          // 兜底：若接口未返回 userId，从 JWT 的 sub 载荷中解析 uid（学号）
          if (userId == null || userId!.isEmpty) {
            userId = _extractUidFromJwt(accessToken!);
          }

          return true;
        }
        // 200 但没拿到 accessToken：多半是 code 被复用或已过期
        debugPrint('[space] 登录失败：令牌响应里没有 accessToken');
      }
    } catch (e) {
      debugPrint('[space] 登录异常: $e');
    }
    return false;
  }

  /// 获取当前登录用户的空间预约信用与个人信息档案
  Future<SpaceUserProfile?> fetchUserProfile({bool force = false}) async {
    if (!force && userProfile != null) return userProfile;
    await ensureAuthenticated();
    if (userId == null || accessToken == null) return null;

    final uri = Uri.parse('$_libspaceBase/api/studyroom/v1/user/$userId');
    try {
      var resp = await casClient.getApi(
        uri,
        headers: <String, String>{
          'Authorization': accessToken!,
          'Accept': 'application/json;charset=UTF-8',
        },
      );
      if (_isUnauthorized(resp)) {
        if (await login()) {
          resp = await casClient.getApi(
            uri,
            headers: <String, String>{
              'Authorization': accessToken!,
              'Accept': 'application/json;charset=UTF-8',
            },
          );
        }
      }

      if (resp.statusCode == 200 && resp.data != null) {
        final dynamic json = jsonDecode(resp.data!);
        if (json is Map) {
          final m = (json['data'] is Map ? json['data'] : json) as Map;
          final profile = SpaceUserProfile(
            userId: (m['userId'] ?? userId ?? '').toString(),
            realName: (m['realName'] ?? m['nickName'] ?? realName ?? '')
                .toString(),
            departmentName: (m['departmentName'] ?? '').toString(),
            totalScore: _parseInt(m['totalScore'], 10),
            cardNumber: (m['cardNumber'] ?? '').toString(),
            mobile: (m['mobile'] ?? '').toString(),
            faceUrl: (m['faceUrl'] ?? '').toString(),
          );
          userProfile = profile;
          return profile;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 获取预约用途类型列表（研讨交流、单人研习、面试）
  Future<List<SpacePurpose>> fetchPurposes({bool force = false}) async {
    if (!force && cachedPurposes != null && cachedPurposes!.isNotEmpty) {
      return cachedPurposes!;
    }
    await ensureAuthenticated();

    const fallbackPurposes = <SpacePurpose>[
      SpacePurpose(
        id: 1,
        label: '研讨交流',
        minNum: 3,
        maxTime: 240,
        verify: 0,
        remark: '3人及以上预约',
      ),
      SpacePurpose(
        id: 3,
        label: '单人研习',
        minNum: 1,
        maxTime: 120,
        verify: 0,
        remark: '静音舱规则',
      ),
      SpacePurpose(
        id: 2,
        label: '面试',
        minNum: 1,
        maxTime: 120,
        verify: 1,
        remark: '需上传面试凭证',
      ),
    ];

    if (accessToken == null) return fallbackPurposes;

    final uri = Uri.parse(
      '$_libspaceBase/api/studyroom/v1/dict/type?type=reservation_use',
    );
    try {
      var resp = await casClient.getApi(
        uri,
        headers: <String, String>{
          'Authorization': accessToken!,
          'Accept': 'application/json;charset=UTF-8',
        },
      );
      if (_isUnauthorized(resp)) {
        if (await login()) {
          resp = await casClient.getApi(
            uri,
            headers: <String, String>{
              'Authorization': accessToken!,
              'Accept': 'application/json;charset=UTF-8',
            },
          );
        }
      }

      if (resp.statusCode == 200 && resp.data != null) {
        final dynamic raw = jsonDecode(resp.data!);
        final records = (raw is Map && raw['records'] is List)
            ? (raw['records'] as List)
            : (raw is List ? raw : null);
        if (records != null && records.isNotEmpty) {
          final list = <SpacePurpose>[];
          for (final r in records) {
            if (r is! Map) continue;
            list.add(
              SpacePurpose(
                id: _parseInt(r['id'], 0),
                label: (r['label'] ?? '').toString(),
                minNum: _parseInt(r['minNum'], 1),
                maxTime: _parseInt(r['maxTime'], 120),
                verify: _parseInt(r['verify'], 0),
                remark: (r['remark'] ?? '').toString(),
              ),
            );
          }
          if (list.isNotEmpty) {
            cachedPurposes = list;
            return list;
          }
        }
      }
    } catch (_) {}
    return fallbackPurposes;
  }

  /// 让本地缓存的 token 立即失效，把下一次调用逼回 CAS 重新取 token。
  ///
  /// 用在两种场景：① 从网页端返回（网页登录可能已经把服务端会话换掉了）；
  /// ② 接口明确拒绝了当前 token（400/401/403）——不主动清掉的话，
  /// `isTokenValid` 还按签发时间认为它有效，用户点「重试」会拿同一个死 token
  /// 再撞一次，永远好不了。
  void invalidateToken() {
    accessToken = null;
    tokenObtainedAt = null;
    authCode = null;
    // 换了认证身份就重来：上一个会话里「结果未知」的提交不该锁住新会话。
    _uncertainSubmissions.clear();
  }

  /// 服务端对「Token 过期/无效」有时返回 400 而不是 401（网关判成「格式错误」）。
  ///
  /// 只用于**只读**接口：写接口（提交/取消/签退）上把 400 当认证问题会导致
  /// 重登后重试一次，万一第一次其实已经生效就是重复提交。
  static bool _isAuthRejectedForRead(Response<String> resp) {
    if (_isUnauthorized(resp)) return true;
    if (resp.statusCode != 400) return false;
    // 400 至少有两种来源：
    // ① 网关把「token 过期/无效」判成 400 —— 需要重登；
    // ② 请求参数确实不对（日期格式、房间 id…）—— 重登一万次也没用。
    // body 里有明确内容时按内容判断（_isUnauthorized 已覆盖常见措辞），
    // 只有 body 为空、拿不到原因时才保守地当成认证问题。
    return (resp.data ?? '').trim().isEmpty;
  }

  /// 获取研讨间列表 (mRooms)
  ///
  /// 失败会抛 [SpaceBookingException]，不再返回空列表——否则页面会把
  /// 「取不到」显示成「没有房间」。
  Future<List<SpaceRoom>> fetchRooms({String? date}) async {
    final authed = await ensureAuthenticated();
    if (!authed) {
      throw SpaceBookingException('空间预约登录失败，请重新登录统一身份认证后重试');
    }

    final queryDate = date ?? _formatDate(DateTime.now());
    final uri = Uri.parse('$_libspaceBase/api/studyroom/v1/room/mRooms')
        .replace(queryParameters: <String, String>{'date': queryDate});

    Response<String> resp;
    try {
      resp = await casClient.getApi(
        uri,
        headers: <String, String>{
          'Authorization': accessToken ?? '',
          'Accept': 'application/json;charset=UTF-8',
        },
      );

      // 遇到 Token 失效（401/403，或网关把过期 token 判成 400）
      // 自动重新登录并重试一次
      if (_isAuthRejectedForRead(resp)) {
        invalidateToken();
        final reAuthOk = await login();
        if (!reAuthOk) {
          throw SpaceBookingException('空间预约登录已失效，请重新登录后重试', authRelated: true);
        }
        resp = await casClient.getApi(
          uri,
          headers: <String, String>{
            'Authorization': accessToken ?? '',
            'Accept': 'application/json;charset=UTF-8',
          },
        );
      }
    } on SpaceBookingException {
      rethrow;
    } catch (e) {
      throw SpaceBookingException('获取房间列表失败：$e');
    }

    if (resp.statusCode != 200 || resp.data == null) {
      final authLike = _isAuthRejectedForRead(resp);
      if (authLike) {
        // 重登之后还是被拒：把 token 彻底作废，让下次「重试」必定重新认证
        invalidateToken();
        throw SpaceBookingException('空间预约登录已失效，请重新登录后重试', authRelated: true);
      }
      // 400 但不像认证问题：把服务端原话带出来，别再一律说成「登录失效」
      final body = (resp.data ?? '').trim();
      final detail = body.isEmpty
          ? ''
          : '：${body.length > 120 ? '${body.substring(0, 120)}…' : body}';
      debugPrint('[space] mRooms 返回 ${resp.statusCode}$detail');
      throw SpaceBookingException('获取房间列表失败（HTTP ${resp.statusCode}$detail）');
    }

    final list = <SpaceRoom>[];
    try {
      final dynamic raw = jsonDecode(resp.data!);
      final dynamic data = (raw is Map) ? (raw['data'] ?? raw) : raw;
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
    } catch (e) {
      throw SpaceBookingException('房间列表解析失败：$e');
    }
    return list;
  }

  /// 获取指定房间在某日期的实时预约与时间切片详情。
  ///
  /// 返回 `null` 只代表「服务端没有这个房间当天的详情」；网络、HTTP、解析
  /// 失败一律抛 [SpaceBookingException]。原来所有失败都被吞成 `null`，
  /// 页面无法把「没取到」和「当天没有时段」区分开。
  Future<SpaceRoomDetail?> fetchRoomReservationDetail({
    required String roomId,
    required String date,
  }) async {
    // 与 fetchRooms 不同，这里不把 `ensureAuthenticated() == false` 直接当成
    // 失败：本地按签发时间判过期未必等于服务端已失效（时钟偏差、网页端换
    // 会话都会出现）。保留旧 token 继续请求，真失效时下面的 401 重试兜底；
    // 完全没有 token 才直接报登录失败。
    await ensureAuthenticated();
    if (accessToken == null || accessToken!.isEmpty) {
      throw SpaceBookingException('空间预约登录失败，请重新登录统一身份认证后重试', authRelated: true);
    }

    final uri = Uri.parse('$_libspaceBase/api/studyroom/v1/room/reservation')
        .replace(
          queryParameters: <String, String>{'roomId': roomId, 'date': date},
        );

    Response<String> resp;
    try {
      resp = await casClient.getApi(
        uri,
        headers: <String, String>{
          'Authorization': accessToken ?? '',
          'Accept': 'application/json;charset=UTF-8',
        },
      );

      if (_isAuthRejectedForRead(resp)) {
        // 只读接口：400 也当成 token 失效，作废后重登一次
        invalidateToken();
        if (await login()) {
          resp = await casClient.getApi(
            uri,
            headers: <String, String>{
              'Authorization': accessToken ?? '',
              'Accept': 'application/json;charset=UTF-8',
            },
          );
        }
        if (_isAuthRejectedForRead(resp)) {
          invalidateToken();
          throw SpaceBookingException('空间预约登录已失效，请重新登录后重试', authRelated: true);
        }
      }
    } on SpaceBookingException {
      rethrow;
    } catch (e) {
      throw SpaceBookingException('获取房间时段失败：$e');
    }

    if (resp.statusCode != 200 || resp.data == null) {
      throw SpaceBookingException('获取房间时段失败（HTTP ${resp.statusCode}）');
    }

    try {
      final dynamic rawJson = jsonDecode(resp.data!);
      if (rawJson is! Map) {
        throw SpaceBookingException('房间时段数据格式异常');
      }
      final dynamic data = rawJson.containsKey('data') && rawJson['data'] is Map
          ? rawJson['data']
          : rawJson;
      final m = (data as Map).cast<String, dynamic>();
      final room = _parseRoom(m);

      final timeSlices = <SpaceTimeSlice>[];
      final rawSlices = m['dateTimeSlicesList'];
      if (rawSlices is List) {
        for (final group in rawSlices) {
          if (group is List) {
            for (final slice in group) {
              if (slice is Map) {
                final start = _formatTimestampOrString(
                  slice['startTime'],
                  timeOnly: true,
                );
                final end = _formatTimestampOrString(
                  slice['endTime'],
                  timeOnly: true,
                );
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
            final start = _formatTimestampOrString(
              group['startTime'],
              timeOnly: true,
            );
            final end = _formatTimestampOrString(
              group['endTime'],
              timeOnly: true,
            );
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
            final sTime = _formatTimestampOrString(
              rMap['startTime'] ?? rMap['beginTime'],
              timeOnly: true,
            );
            final eTime = _formatTimestampOrString(
              rMap['endTime'],
              timeOnly: true,
            );
            final sDesc = (rMap['stateName'] ?? rMap['statusName'] ?? '已预约')
                .toString();
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
    } on SpaceBookingException {
      rethrow;
    } catch (e) {
      throw SpaceBookingException('房间时段数据解析失败：$e');
    }
  }

  Future<Map<String, String>> _reservationHeaders() async {
    await ensureAuthenticated();
    if (userId == null || accessToken == null) {
      throw SpaceBookingException('空间预约登录已失效，请重新登录后重试', authRelated: true);
    }
    return <String, String>{
      'Authorization': accessToken!,
      'Accept': 'application/json;charset=UTF-8',
    };
  }

  dynamic _reservationData(Response<String> response, String label) {
    if (response.statusCode != 200) {
      throw SpaceBookingException('$label失败（HTTP ${response.statusCode}）');
    }
    final body = response.data?.trim() ?? '';
    if (body.isEmpty) throw SpaceBookingException('$label未返回有效数据');
    final dynamic raw = jsonDecode(body);
    if (raw is Map) {
      final code = _parseInt(raw['code'], 200);
      if (raw['success'] == false || (code != 200 && code != 0)) {
        throw SpaceBookingException(
          (raw['msg'] ?? raw['message'] ?? '$label失败').toString(),
        );
      }
      if (raw.containsKey('data')) return raw['data'];
    }
    return raw;
  }

  Future<List<SpaceReservation>> fetchCurrentReservations() async {
    final headers = await _reservationHeaders();
    try {
      final uri = Uri.parse(
        '$_libspaceBase/api/studyroom/v1/reservation/reservationByUserId',
      ).replace(queryParameters: <String, String>{'userId': userId!});
      var response = await casClient.getApi(uri, headers: headers);
      if (_isUnauthorized(response)) {
        if (await login()) {
          headers['Authorization'] = accessToken!;
          response = await casClient.getApi(uri, headers: headers);
        }
      }
      final data = _reservationData(response, '获取当前预约');
      if (data == null || (data is Map && data.isEmpty)) return [];
      final records = data is Map && data.containsKey('id')
          ? [data]
          : data is List
          ? data
          : null;
      if (records == null || records.any((item) => item is! Map)) {
        throw SpaceBookingException('当前预约数据格式不正确');
      }
      return records
          .map(
            (item) => _parseReservation(
              (item as Map).cast<String, dynamic>(),
              userId,
            ),
          )
          .toList();
    } on SpaceBookingException {
      rethrow;
    } catch (e) {
      throw SpaceBookingException('获取当前预约失败：$e');
    }
  }

  Future<SpaceReservationPage> fetchReservationHistory({
    int page = 1,
    int size = 20,
  }) async {
    if (page < 1 || size < 1) throw ArgumentError('页码和页大小必须大于零');
    final headers = await _reservationHeaders();
    try {
      final uri = Uri.parse(
        '$_libspaceBase/api/studyroom/v1/reservation/pageByUserId',
      ).replace(queryParameters: {'page': '$page', 'size': '$size'});
      var response = await casClient.sendJsonWithHeaders(
        uri,
        data: <String, dynamic>{'userId': userId},
        extraHeaders: headers,
      );
      if (_isUnauthorized(response)) {
        if (await login()) {
          headers['Authorization'] = accessToken!;
          response = await casClient.sendJsonWithHeaders(
            uri,
            data: <String, dynamic>{'userId': userId},
            extraHeaders: headers,
          );
        }
      }
      final data = _reservationData(response, '获取历史预约');
      final records = data is Map ? data['records'] : null;
      if (records is! List || records.any((item) => item is! Map)) {
        throw SpaceBookingException('历史预约数据格式不正确');
      }
      final total = _parseInt(data['total'], -1);
      final pages = _parseInt(data['pages'], -1);
      return SpaceReservationPage(
        items: records
            .map(
              (item) => _parseReservation(
                (item as Map).cast<String, dynamic>(),
                userId,
              ),
            )
            .toList(),
        page: page,
        hasMore:
            records.isNotEmpty &&
            (pages >= 0
                ? page < pages
                : total >= 0
                ? page * size < total
                : records.length >= size),
      );
    } on SpaceBookingException {
      rethrow;
    } catch (e) {
      throw SpaceBookingException('获取历史预约失败：$e');
    }
  }

  /// 兼容旧调用；页面分别加载两路数据，以显示各自的加载/错误状态。
  Future<List<SpaceReservation>> fetchMyReservations() async {
    SpaceBookingException? firstError;
    var succeeded = 0;
    Future<List<SpaceReservation>> capture(
      Future<List<SpaceReservation>> future,
    ) async {
      try {
        final result = await future;
        succeeded++;
        return result;
      } on SpaceBookingException catch (e) {
        firstError ??= e;
        return [];
      }
    }

    final results = await Future.wait([
      capture(fetchCurrentReservations()),
      capture(fetchReservationHistory().then((page) => page.items)),
    ]);
    if (succeeded == 0) throw firstError!;
    final unique = <String, SpaceReservation>{};
    for (final item in results.expand((items) => items)) {
      unique.putIfAbsent(item.id, () => item);
    }
    return unique.values.toList();
  }

  /// 原生提交预约
  ///
  /// 对接官方 POST /api/studyroom/v1.1/reservation/reservation
  /// [startTime] 和 [endTime] 格式: "YYYY-MM-DD HH:mm:ss"
  Future<ReservationResult> submitReservation({
    required String roomId,
    required String startTime,
    required String endTime,
    required int dictId,
    List<String> memberIds = const <String>[],
    String mobile = '',
    String remark = '',
    String filePath = '',
  }) {
    final key = '$userId|$roomId|$startTime|$endTime';
    return _submissions.putIfAbsent(
      key,
      () =>
          _submitReservation(
            key: key,
            roomId: roomId,
            startTime: startTime,
            endTime: endTime,
            dictId: dictId,
            memberIds: memberIds,
            mobile: mobile,
            remark: remark,
            filePath: filePath,
          ).whenComplete(() {
            _submissions.remove(key);
          }),
    );
  }

  Future<ReservationResult> _reconcileSubmission(
    String key,
    String roomId,
    String startTime,
    String endTime,
  ) async {
    final since = _uncertainSubmissions.putIfAbsent(key, DateTime.now);
    try {
      final current = await fetchCurrentReservations();
      for (final item in current) {
        final start = DateTime.tryParse('${item.date} ${item.beginTime}');
        final end = DateTime.tryParse('${item.date} ${item.endTime}');
        if (item.roomId == roomId &&
            !item.isCancelled &&
            start == DateTime.tryParse(startTime) &&
            end == DateTime.tryParse(endTime)) {
          _uncertainSubmissions.remove(key);
          return ReservationResult(
            success: true,
            message: '已确认预约成功',
            reservationId: item.id,
          );
        }
      }
      // 查询成功但没有这条预约：过了保留期就判定「没约上」并放开闩锁，
      // 否则用户会被永久挡住；保留期内仍可能只是服务端还没落库。
      if (DateTime.now().difference(since) >= _uncertainTtl) {
        _uncertainSubmissions.remove(key);
        return const ReservationResult(
          success: false,
          message: '没有查到这次预约，可能并未提交成功，可以重新提交',
        );
      }
    } catch (_) {
      // 查询失败不能证明预约失败；保留待确认状态。
    }
    return const ReservationResult(
      success: false,
      outcomeUnknown: true,
      message: '提交结果尚未确认，请先到“我的预约”或网页端核对。再次点击只会查询结果，不会重复提交。',
    );
  }

  Future<ReservationResult> _submitReservation({
    required String key,
    required String roomId,
    required String startTime,
    required String endTime,
    required int dictId,
    required List<String> memberIds,
    required String mobile,
    required String remark,
    required String filePath,
  }) async {
    final uncertainSince = _uncertainSubmissions[key];
    if (uncertainSince != null) {
      if (DateTime.now().difference(uncertainSince) < _uncertainTtl) {
        return _reconcileSubmission(key, roomId, startTime, endTime);
      }
      // 过了保留期仍在集合里：期间没确认成功，允许重新提交
      _uncertainSubmissions.remove(key);
    }
    await ensureAuthenticated();
    if (accessToken == null || userId == null) {
      return const ReservationResult(success: false, message: '未登录空间预约系统，请重试');
    }

    final queryParams = <String, String>{
      'userId': userId!,
      'roomId': roomId,
      'startTime': startTime,
      'endTime': endTime,
      'dictId': dictId.toString(),
      'behaviorMode': '4', // 移动端标识
      'memberIds': memberIds.join(','),
      'mobile': mobile,
      'remark': remark,
      'filePath': filePath,
    };

    final uri = Uri.parse(
      '$_libspaceBase/api/studyroom/v1.1/reservation/reservation',
    ).replace(queryParameters: queryParams);

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

      final body = resp.data ?? '';
      if (body.isEmpty || (resp.statusCode ?? 500) >= 500) {
        return await _reconcileSubmission(key, roomId, startTime, endTime);
      }

      final dynamic raw = jsonDecode(body);
      if (raw is Map &&
          (raw.containsKey('code') || raw.containsKey('success'))) {
        final code = _parseInt(raw['code'], -1);
        final success = raw['success'] == true || code == 200 || code == 0;
        final msg =
            (raw['msg'] ?? raw['message'] ?? (success ? '预约成功' : '预约失败'))
                .toString();
        final resId =
            (raw['data'] is Map ? (raw['data'] as Map)['id'] : raw['data'])
                ?.toString();

        return ReservationResult(
          success: success,
          message: msg,
          reservationId: resId,
        );
      }
    } catch (_) {
      return _reconcileSubmission(key, roomId, startTime, endTime);
    }

    return _reconcileSubmission(key, roomId, startTime, endTime);
  }

  /// 预约前成员冲突预检查 (reservationUserJudge)
  Future<bool> checkReservationUserJudge({
    required String startTime,
    List<String> memberIds = const <String>[],
  }) async {
    await ensureAuthenticated();
    if (accessToken == null || userId == null) return false;

    final uri =
        Uri.parse(
          '$_libspaceBase/api/studyroom/v1/reservation/reservationUserJudge',
        ).replace(
          queryParameters: <String, String>{
            'userId': userId!,
            'memberIds': memberIds.join(','),
            'startTime': startTime,
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
      return resp.statusCode == 200;
    } catch (_) {}
    return true;
  }

  /// 获取常用同行人列表 (topContactsByUserId)
  Future<List<Map<String, dynamic>>> fetchTopContacts() async {
    await ensureAuthenticated();
    if (accessToken == null || userId == null) {
      return const <Map<String, dynamic>>[];
    }

    final uri = Uri.parse(
      '$_libspaceBase/api/studyroom/v1/reservation/topContactsByUserId',
    ).replace(queryParameters: <String, String>{'userId': userId!});

    try {
      final resp = await casClient.getApi(
        uri,
        headers: <String, String>{
          'Authorization': accessToken!,
          'Accept': 'application/json;charset=UTF-8',
        },
      );
      if (resp.statusCode == 200 && resp.data != null) {
        final dynamic raw = jsonDecode(resp.data!);
        final dynamic list = (raw is Map && raw['data'] is List)
            ? raw['data']
            : (raw is List ? raw : null);
        if (list is List) {
          return list
              .whereType<Map>()
              .map((m) => m.cast<String, dynamic>())
              .toList();
        }
      }
    } catch (_) {}
    return const <Map<String, dynamic>>[];
  }

  /// 根据学号精确查询同学信息（用于研讨交流添加同行成员）。
  ///
  /// 返回 `null` 表示**服务端确实没有这个人**；网络、HTTP、解析失败抛
  /// [SpaceBookingException]。原先所有失败都返回 `null`，调用方只能把
  /// 「查无此人」和「查询失败」当成同一件事，静默把学号塞进同行名单。
  Future<Map<String, dynamic>?> searchUser(String studentIdOrName) async {
    // 同 fetchRoomReservationDetail：保留旧 token 继续请求，
    // 真失效时由下面的 401 重试兜底。
    await ensureAuthenticated();
    if (accessToken == null || accessToken!.isEmpty) {
      throw SpaceBookingException('空间预约登录已失效，请重新登录后重试', authRelated: true);
    }

    final uri = Uri.parse('$_libspaceBase/api/studyroom/v1/user/pageUser')
        .replace(
          queryParameters: <String, String>{
            'param': studentIdOrName.trim(),
            'page': '1',
            'size': '10',
          },
        );

    Response<String> resp;
    try {
      resp = await casClient.getApi(
        uri,
        headers: <String, String>{
          'Authorization': accessToken!,
          'Accept': 'application/json;charset=UTF-8',
        },
      );
      if (_isAuthRejectedForRead(resp)) {
        invalidateToken();
        if (await login()) {
          resp = await casClient.getApi(
            uri,
            headers: <String, String>{
              'Authorization': accessToken!,
              'Accept': 'application/json;charset=UTF-8',
            },
          );
        }
        if (_isAuthRejectedForRead(resp)) {
          invalidateToken();
          throw SpaceBookingException('空间预约登录已失效，请重新登录后重试', authRelated: true);
        }
      }
    } on SpaceBookingException {
      rethrow;
    } catch (e) {
      throw SpaceBookingException('查询同学信息失败：$e');
    }

    if (resp.statusCode != 200 || resp.data == null) {
      throw SpaceBookingException('查询同学信息失败（HTTP ${resp.statusCode}）');
    }

    try {
      final dynamic raw = jsonDecode(resp.data!);
      final records = (raw is Map && raw['records'] is List)
          ? (raw['records'] as List)
          : null;
      if (records == null || records.isEmpty) return null;
      final first = records.first;
      return first is Map ? first.cast<String, dynamic>() : null;
    } catch (e) {
      throw SpaceBookingException('同学信息解析失败：$e');
    }
  }

  /// 原生提前签退（使用中主动释放房间）
  /// 对接 POST /api/studyroom/v1/reservation/signOut?userId=...&roomId=...
  Future<bool> signOutReservation({required String roomId}) async {
    await ensureAuthenticated();
    if (accessToken == null || userId == null) return false;

    final uri = Uri.parse('$_libspaceBase/api/studyroom/v1/reservation/signOut')
        .replace(
          queryParameters: <String, String>{
            'userId': userId!,
            'roomId': roomId,
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

  /// 原生暂离登记（使用中临时离开）
  /// 对接 POST /api/studyroom/v1/reservation/afk?userId=...&roomId=...
  Future<bool> afkReservation({required String roomId}) async {
    await ensureAuthenticated();
    if (accessToken == null || userId == null) return false;

    final uri = Uri.parse('$_libspaceBase/api/studyroom/v1/reservation/afk')
        .replace(
          queryParameters: <String, String>{
            'userId': userId!,
            'roomId': roomId,
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

  /// 取消预约（官方接口为 POST /api/studyroom/v1/reservation/cancelReservation?reservationId=...）
  Future<bool> cancelReservation(String reservationId) async {
    await ensureAuthenticated();
    if (accessToken == null) return false;

    final uri =
        Uri.parse(
          '$_libspaceBase/api/studyroom/v1/reservation/cancelReservation',
        ).replace(
          queryParameters: <String, String>{'reservationId': reservationId},
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
    final realUriStr = resp.realUri.toString();
    if (realUriStr.contains('cas.usst.edu.cn') ||
        realUriStr.contains('/oauth/v1/authorize')) {
      return true;
    }
    final body = resp.data ?? '';
    if (body.contains('token is null') ||
        body.contains('未登录') ||
        body.contains('请先登录') ||
        body.contains('token invalid') ||
        body.contains('token expired') ||
        body.contains('token已过期') ||
        body.contains('token失效') ||
        body.contains('code过期') ||
        body.contains('code已过期') ||
        body.contains('code不存在') ||
        body.contains('凭据失效') ||
        body.contains('认证失败') ||
        body.contains('"code":401') ||
        body.contains('"code":403') ||
        body.contains('"code":2001') ||
        body.contains('"code":2002') ||
        body.contains('"code":2004') ||
        body.contains('"code":2005')) {
      return true;
    }
    return false;
  }

  static SpaceRoom _parseRoom(
    Map<String, dynamic> m, [
    String buildingName = '',
  ]) {
    return SpaceRoom(
      id: (m['id'] ?? '').toString(),
      name: (m['roomName'] ?? m['name'] ?? '研讨间').toString(),
      floor: (m['floorName'] ?? m['floor'] ?? m['roomLocation'] ?? '')
          .toString(),
      roomType: (m['roomTypeName'] ?? m['type'] ?? '研修空间').toString(),
      minNum: _parseInt(
        m['minNum'] ?? m['minPerson'] ?? m['minReservationNum'],
        1,
      ),
      maxNum: _parseInt(m['maxNum'] ?? m['maxPerson'], 8),
      devices: (m['deviceNames'] ?? m['itemRemarks'] ?? m['devices'] ?? '')
          .toString(),
      status: _parseInt(m['state'] ?? m['status'], 0),
      buildingName: buildingName.isNotEmpty
          ? buildingName
          : (m['buildingName'] ?? '').toString(),
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

  static SpaceReservation _parseReservation(
    Map<String, dynamic> m, [
    String? currentUserId,
  ]) {
    final rawStatus = _parseInt(
      m['reservationStatus'] ?? m['state'] ?? m['status'],
      0,
    );

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
    if (rawStatus == 31 ||
        rawStatus == 41 ||
        rawStatus == 42 ||
        rawStatus == 1) {
      normalizedStatus = 1; // 使用中
    } else if (rawStatus == 51 ||
        rawStatus == 52 ||
        rawStatus == 53 ||
        rawStatus == 2) {
      normalizedStatus = 2; // 已完成
    } else if (rawStatus == 23 || rawStatus >= 61 || rawStatus == 3) {
      normalizedStatus = 3; // 已取消
    } else {
      normalizedStatus = 0; // 待使用 (11, 12, 21, 22 等)
    }

    final statusDesc =
        statusMap[rawStatus] ??
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

    final dateStr = _formatTimestampOrString(
      m['reservationDate'] ?? m['startTime'] ?? m['date'],
      dateOnly: true,
    );
    final beginTimeStr = _formatTimestampOrString(
      m['beginTime'] ?? m['startTime'],
      timeOnly: true,
    );
    final endTimeStr = _formatTimestampOrString(m['endTime'], timeOnly: true);

    bool isLeader =
        m['type'] == 0 || m['isLeader'] == true || m['userType'] == 1;
    if (currentUserId != null && m['leader'] is Map) {
      final leaderUserId = (m['leader'] as Map)['userId']?.toString();
      if (leaderUserId != null && leaderUserId.isNotEmpty) {
        isLeader = leaderUserId == currentUserId;
      }
    }

    final minSignStr = _formatTimestampOrString(
      m['minSignTime'],
      timeOnly: true,
    );
    final maxSignStr = _formatTimestampOrString(
      m['maxSignTime'],
      timeOnly: true,
    );
    final signInStr = _formatTimestampOrString(m['signInTime'], timeOnly: true);
    final signOutStr = _formatTimestampOrString(
      m['signOutTime'],
      timeOnly: true,
    );

    final dictId = _parseInt(m['dictId'], 0);
    String dictName = (m['dictValue'] ?? m['dictName'] ?? '').toString();
    if (dictName.isEmpty) {
      if (dictId == 1) dictName = '研讨交流';
      if (dictId == 2) dictName = '面试';
      if (dictId == 3) dictName = '单人研习';
    }

    return SpaceReservation(
      id: (m['id'] ?? m['reservationId'] ?? '').toString(),
      roomId: (m['roomId'] ?? '').toString(),
      roomName: (m['roomName'] ?? m['name'] ?? '图书馆研讨间').toString(),
      date: dateStr,
      beginTime: beginTimeStr,
      endTime: endTimeStr,
      status: normalizedStatus,
      statusDesc: statusDesc,
      isLeader: isLeader,
      qrCode: (m['signCode'] ?? m['qrSignCheckCode'] ?? '').toString(),
      minSignTime: minSignStr,
      maxSignTime: maxSignStr,
      signInTime: signInStr,
      signOutTime: signOutStr,
      remark: (m['remark'] ?? '').toString(),
      departmentName: (m['departmentName'] ?? '').toString(),
      mobile: (m['mobile'] ?? '').toString(),
      dictId: dictId,
      dictName: dictName,
    );
  }

  static String _formatTimestampOrString(
    dynamic val, {
    bool dateOnly = false,
    bool timeOnly = false,
  }) {
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
      // 兼容 "2026-11-02T09:00" 这种带 T 的 ISO 写法
      final parts = str.replaceAll('T', ' ').split(' ');
      final timePart = parts.length > 1 ? parts.last : parts.first;
      final tParts = timePart.split(':');
      if (tParts.length >= 2) {
        // 统一补零成 HH:mm：占用判定用的是字符串比较，'9:00' 与 '09:00' 混用会漏判
        final hh = tParts[0].trim().padLeft(2, '0');
        final mm = tParts[1].trim().padLeft(2, '0');
        return '$hh:$mm';
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

  /// 从 JWT 载荷中解析 exp（过期 UNIX 秒数时间戳）
  static int? _extractExpFromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1];
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      final exp = map['exp'];
      if (exp is num) return exp.toInt();
    } catch (_) {}
    return null;
  }

  static int _parseInt(dynamic val, int fallback) {
    if (val == null) return fallback;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString().trim()) ?? fallback;
  }

  static String _formatDate(DateTime dt) => DateFmt.ymd(dt);
}
