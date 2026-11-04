import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../data/app_exception.dart';
import '../data/cache_store.dart';
import '../data/http/api_client.dart';

/// 一次校园跑进度快照。
///
/// 数据来源：`https://www.sportcampus.cn`（第三方 SaaS「高校体育」，
/// 运营方上海微摇网络科技有限公司；上理是它的客户，所以这不是校方系统）。
class SportCampusProgress {
  const SportCampusProgress({
    required this.username,
    required this.school,
    required this.teacher,
    required this.course,
    required this.goal,
    required this.surplus,
  });

  /// 姓名（接口字段 `username`）
  final String username;

  /// 学校名，正常是「上海理工大学」
  final String school;

  /// 任课体育老师
  final String teacher;

  /// 体育课名称
  final String course;

  /// 本学期目标次数（跑够多少次算及格）
  final int? goal;

  /// 还剩多少次（`goal - surplus` 就是已跑次数）
  final int? surplus;

  /// 已跑次数。接口只给 goal/surplus，且两者可能被学校手工调整过
  /// （出现过 surplus 大于 goal 的情况），这里夹到 `[0, goal]`。
  int? get done {
    final g = goal;
    final s = surplus;
    if (g == null || s == null || g <= 0) {
      return null;
    }
    final value = g - s;
    if (value < 0) {
      return 0;
    }
    return value > g ? g : value;
  }

  /// 完成度 0~1，用于进度条。
  double? get ratio {
    final g = goal;
    final d = done;
    if (g == null || d == null || g <= 0) {
      return null;
    }
    return (d / g).clamp(0.0, 1.0);
  }

  /// 是否已经跑够。
  bool get finished => surplus != null && surplus! <= 0;

  bool get hasData => goal != null || surplus != null;

  Map<String, dynamic> toCacheJson() => <String, dynamic>{
    'username': username,
    'school': school,
    'teacher': teacher,
    'course': course,
    'goal': goal,
    'surplus': surplus,
  };

  static SportCampusProgress? fromCacheJson(Map<String, dynamic> json) {
    final goal = _asInt(json['goal']);
    final surplus = _asInt(json['surplus']);
    if (goal == null && surplus == null) {
      return null;
    }
    return SportCampusProgress(
      username: (json['username'] ?? '').toString(),
      school: (json['school'] ?? '').toString(),
      teacher: (json['teacher'] ?? '').toString(),
      course: (json['course'] ?? '').toString(),
      goal: goal,
      surplus: surplus,
    );
  }

  /// 解析登录响应里的 `data`。
  ///
  /// 按项目约定，纯解析器不抛异常：字段缺失就返回 null，由调用方决定报什么错。
  static SportCampusProgress? parse(Map<String, dynamic> data) {
    final goal = _asInt(data['goal']);
    final surplus = _asInt(data['surplus']);
    if (goal == null && surplus == null) {
      return null;
    }
    return SportCampusProgress(
      username: (data['username'] ?? '').toString().trim(),
      school: (data['school'] ?? '').toString().trim(),
      teacher: (data['teacher'] ?? '').toString().trim(),
      course: (data['course'] ?? '').toString().trim(),
      goal: goal,
      surplus: surplus,
    );
  }

  static int? _asInt(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.round();
    }
    final match = RegExp(r'-?\d+').firstMatch(raw.toString());
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  @override
  String toString() =>
      'SportCampusProgress($school $username, 目标 $goal, 剩余 $surplus)';
}

/// 高校体育接口失败。
///
/// 继承 [AppException]，页面统一用 `e.message` 展示。
class SportCampusException extends AppException {
  const SportCampusException(super.failure, super.message, [super.cause]);
}

/// 进程内 + 磁盘缓存，避免每次切回「校园」页都重新登录一次。
///
/// 按手机号隔离：换账号不会看到上一个人的次数。
/// 磁盘那层走安全存储（本次数属于个人数据，和课表同级）。
class SportCampusCache {
  SportCampusCache._();

  static const String _keyPrefix = 'sport_campus_v1';

  static String? _mobile;
  static SportCampusProgress? _data;
  static DateTime? _fetchedAt;

  static String _keyFor(String mobile) => '${_keyPrefix}_$mobile';

  /// 冷启动恢复上次的数据。
  static Future<void> load(String mobile) async {
    final key = mobile.trim();
    if (key.isEmpty) {
      return;
    }
    if (_data != null && _mobile == key) {
      return;
    }
    _mobile = null;
    _data = null;
    _fetchedAt = null;

    final entry = await CacheStore.read(_keyFor(key), secure: true);
    final raw = entry?.data;
    if (raw is! Map) {
      return;
    }
    final data = SportCampusProgress.fromCacheJson(
      Map<String, dynamic>.from(raw),
    );
    if (data == null) {
      return;
    }
    _mobile = key;
    _data = data;
    _fetchedAt = entry!.savedAt;
  }

  static SportCampusProgress? dataFor(String mobile) {
    final key = mobile.trim();
    return key.isNotEmpty && key == _mobile ? _data : null;
  }

  static DateTime? fetchedAtFor(String mobile) {
    final key = mobile.trim();
    return key.isNotEmpty && key == _mobile ? _fetchedAt : null;
  }

  static Duration? ageFor(String mobile) {
    final at = fetchedAtFor(mobile);
    return at == null ? null : DateTime.now().difference(at);
  }

  static void put(String mobile, SportCampusProgress data) {
    final key = mobile.trim();
    if (key.isEmpty) {
      return;
    }
    _mobile = key;
    _data = data;
    _fetchedAt = DateTime.now();
    // 加密落盘：跑步次数 + 姓名 + 体育课，属于个人数据
    unawaited(CacheStore.write(_keyFor(key), data.toCacheJson(), secure: true));
  }

  static Future<void> clear() async {
    final key = _mobile;
    _mobile = null;
    _data = null;
    _fetchedAt = null;
    if (key != null) {
      await CacheStore.remove(_keyFor(key), secure: true);
    }
  }

  /// 只清内存、保留磁盘，用来模拟「App 冷启动」。
  @visibleForTesting
  static void resetMemoryForTest() {
    _mobile = null;
    _data = null;
    _fetchedAt = null;
  }
}

/// 高校体育（校园跑）客户端。
///
/// 协议来自社区逆向（polichan/FSC、takakura-anzu/sportcampus），2020 年至今没变：
///
/// ```http
/// GET https://www.sportcampus.cn/api/reg/login?sign=<md5>&data=<紧凑JSON>
/// sign = md5( PREFIX + "data" + data )
/// data = {"info":"<设备UUID>","mobile":"<手机号>","password":"<密码>","type":"<机型>"}
/// ```
///
/// 登录响应里直接带 `goal`（目标次数）/ `surplus`（剩余次数），
/// 所以查次数不需要额外的“跑步记录”接口——每次刷新重新登录一次即可。
class SportCampusService {
  SportCampusService({Dio? dio}) : _dio = dio ?? ApiClient.dio;

  static const String apiBase = 'https://www.sportcampus.cn';

  /// 签名前缀。逆向自 App，不是密钥：服务端只用它算 md5。
  static const String _signPrefix = r'lpKK*TJE8WaIg%93O0pfn0#xS0i3xE$z';

  static const String _loginPath = '/api/reg/login';

  /// 上报的机型。风控会看这个字段，别随手改。
  static const String deviceType = 'iPhone 11';

  static const String _ua =
      'CollegeSports2/2.2.14 (iPhone; iOS 11.0; Scale/3.00)';

  final Dio _dio;

  /// 紧凑 JSON：与 App 的序列化一致（无空格、保持插入顺序）。
  static String compactJson(Map<String, dynamic> payload) =>
      jsonEncode(payload);

  /// `sign = md5(PREFIX + "data" + payload)`。
  static String signOf(String payload) =>
      md5.convert(utf8.encode('${_signPrefix}data$payload')).toString();

  /// 登录并取回次数。
  Future<SportCampusProgress> fetch({
    required String mobile,
    required String password,
    required String deviceId,
  }) async {
    final payload = compactJson(<String, dynamic>{
      'info': deviceId,
      'mobile': mobile,
      'password': password,
      'type': deviceType,
    });
    final json = await _get(_loginPath, payload);

    final code = '${json['code']}';
    if (code != '200') {
      throw _errorFor(code, '${json['msg'] ?? ''}');
    }
    final data = json['data'];
    if (data is! Map) {
      throw const SportCampusException(
        AppFailure.parse,
        '高校体育登录响应里没有 data 字段，接口可能改版了',
      );
    }
    final progress = SportCampusProgress.parse(Map<String, dynamic>.from(data));
    if (progress == null) {
      // 拿到了 200 却没有 goal/surplus：多半是学期还没配置校园跑要求
      throw const SportCampusException(
        AppFailure.parse,
        '高校体育没返回目标次数，可能本学期还没配置校园跑',
      );
    }
    return progress;
  }

  Future<Map<String, dynamic>> _get(String path, String payload) async {
    final uri = Uri.parse('$apiBase$path').replace(
      queryParameters: <String, String>{
        'sign': signOf(payload),
        'data': payload,
      },
    );

    final Response<dynamic> resp;
    try {
      resp = await _dio.getUri<dynamic>(
        uri,
        options: Options(
          responseType: ResponseType.plain,
          headers: <String, dynamic>{
            'User-Agent': _ua,
            'Content-Type': 'application/x-www-form-urlencoded',
            'versionCode': '309',
            'versionName': '2.2.15',
            'xxversionxx': '20180601',
            'platform': 'iOS',
          },
        ),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status != null && status >= 500) {
        throw SportCampusException(
          AppFailure.server,
          '高校体育服务暂时不可用（HTTP $status），稍后再试',
          e,
        );
      }
      throw SportCampusException(AppFailure.network, '连不上高校体育服务，请检查网络后重试', e);
    }

    final raw = resp.data?.toString() ?? '';
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        json = decoded;
      }
    } catch (_) {
      // 非 JSON：直接落到下面的 parse 错误里，不吞
      debugPrint(
        '[sportcampus] 响应不是 JSON: ${raw.length > 80 ? raw.substring(0, 80) : raw}',
      );
    }
    if (json == null) {
      throw SportCampusException(AppFailure.parse, '高校体育返回的不是 JSON，接口可能改版了');
    }
    return json;
  }

  static AppException _errorFor(String code, String message) {
    if (message.contains('用户不存在')) {
      return const SportCampusException(
        AppFailure.auth,
        '这个手机号没在高校体育注册过，或者填错了',
      );
    }
    if (message.contains('密码')) {
      return const SportCampusException(AppFailure.auth, '高校体育密码不对，请重新输入');
    }
    if (message.contains('_Sign Error_')) {
      return const SportCampusException(
        AppFailure.parse,
        '高校体育的接口签名校验失败（协议可能更新了）',
      );
    }
    return SportCampusException(
      AppFailure.server,
      message.isNotEmpty ? message : '高校体育返回错误码 $code',
    );
  }
}
