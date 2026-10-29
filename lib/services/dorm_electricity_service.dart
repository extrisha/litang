import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../data/cache_store.dart';
import '../data/http/api_client.dart';

/// 宿舍电费服务。
///
/// 数据来源：`https://ssgl.usst.edu.cn/`（学工一体化 · 移动端）
/// 认证方式：ids6 统一身份认证（CAS），登录后拿 ASP.NET 会话 cookie，
///          接口本身不再校验任何 token。
///
/// 关键结论（2026-10 验证）：
/// - 页面 `SSGL/StuMobile/StuView/VoucherCenter.html` 调
///   `GET /api/Voucher/GetDormElectricityFees?IsLoadData=false`
/// - 只有在 WeLink 客户端里才会附加 `x-hw-code`（HWH5.getAuthCode），
///   普通浏览器下该头为空字符串，服务端靠 cookie 识别身份
/// - 照明（ZM）与空调（KT）是两路独立计量，各自有余额（元）和剩余（度）
/// - 必须走 HTTPS：Android 的网络安全配置禁止明文 HTTP，且 ssgl 的
///   HTTPS 证书正常，CAS 服务地址也使用 https。
class DormElectricity {
  /// 宿舍地址，例如「二公寓三号楼237 室」
  final String dormAddress;

  /// 照明剩余电量（度）
  final String zmKwh;

  /// 照明余额（元），可能为负（欠费）
  final String zmMoney;

  /// 空调剩余电量（度）
  final String ktKwh;

  /// 空调余额（元）
  final String ktMoney;

  /// 是否有空调计量
  final bool hasAirConditioner;

  const DormElectricity({
    required this.dormAddress,
    required this.zmKwh,
    required this.zmMoney,
    required this.ktKwh,
    required this.ktMoney,
    required this.hasAirConditioner,
  });

  factory DormElectricity.fromJson(Map<String, dynamic> data) {
    return DormElectricity(
      dormAddress: (data['SSDZ'] as String?)?.trim() ?? '',
      zmKwh: (data['SurplusZM'] as String?)?.trim() ?? '',
      zmMoney: (data['SurplusZMMoney'] as String?)?.trim() ?? '',
      ktKwh: (data['SurplusKT'] as String?)?.trim() ?? '',
      ktMoney: (data['SurplusKTMoney'] as String?)?.trim() ?? '',
      hasAirConditioner: data['HasKT'] == true,
    );
  }

  /// 本地缓存用（与接口字段名解耦）。
  Map<String, dynamic> toCacheJson() => <String, dynamic>{
    'dormAddress': dormAddress,
    'zmKwh': zmKwh,
    'zmMoney': zmMoney,
    'ktKwh': ktKwh,
    'ktMoney': ktMoney,
    'hasAirConditioner': hasAirConditioner,
  };

  static DormElectricity? fromCacheJson(Map<String, dynamic> json) {
    final address = (json['dormAddress'] ?? '').toString();
    if (address.isEmpty) {
      return null;
    }
    return DormElectricity(
      dormAddress: address,
      zmKwh: (json['zmKwh'] ?? '').toString(),
      zmMoney: (json['zmMoney'] ?? '').toString(),
      ktKwh: (json['ktKwh'] ?? '').toString(),
      ktMoney: (json['ktMoney'] ?? '').toString(),
      hasAirConditioner: json['hasAirConditioner'] == true,
    );
  }

  /// 照明余额（元），解析失败返回 null
  double? get zmMoneyValue => _num(zmMoney);

  /// 空调余额（元）
  double? get ktMoneyValue => _num(ktMoney);

  /// 照明是否欠费
  bool get zmInArrears {
    final v = zmMoneyValue;
    return v != null && v < 0;
  }

  static double? _num(String raw) {
    final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(raw);
    return m == null ? null : double.tryParse(m.group(0)!);
  }

  @override
  String toString() =>
      'DormElectricity($dormAddress, 照明 $zmKwh/$zmMoney, 空调 $ktKwh/$ktMoney)';
}

/// 进程内电费缓存，避免每次进「生活」页都重新 CAS 登录。
///
/// 按学号隔离，退出/换账号后不会把上一个账号的宿舍数据展示出来。
class DormElectricityCache {
  DormElectricityCache._();

  static const String _keyPrefix = 'dorm_electricity_v1';

  static String? _username;
  static DormElectricity? _data;
  static DateTime? _fetchedAt;

  static String _keyFor(String username) => '${_keyPrefix}_$username';

  /// 从磁盘恢复上次的数据（冷启动用）。
  ///
  /// 优先从系统安全存储（Keystore/Keychain）恢复；若为空，兼容读取旧版文件存储并迁移。
  /// 内存里已有数据时不覆盖：那是本次会话刚拉到的，比磁盘新。
  static Future<void> load(String username) async {
    final key = username.trim();
    if (key.isEmpty) {
      return;
    }
    if (_data != null && _username == key) {
      return;
    }
    // 换账号时先清掉内存里的旧账号数据，安全存储按 username 各存一份。
    _username = null;
    _data = null;
    _fetchedAt = null;

    var entry = await CacheStore.read(_keyFor(key), secure: true);
    if (entry == null) {
      // 兼容读取旧版本明文文件缓存
      entry = await CacheStore.read(_keyFor(key), secure: false);
      if (entry != null && entry.data is Map) {
        // 自动迁移升级到加密存储，并清除旧的明文缓存
        unawaited(CacheStore.write(_keyFor(key), entry.data!, secure: true));
        unawaited(CacheStore.remove(_keyFor(key), secure: false));
      }
    }

    final raw = entry?.data;
    if (raw is! Map) {
      return;
    }
    final data = DormElectricity.fromCacheJson(Map<String, dynamic>.from(raw));
    if (data == null) {
      return;
    }
    _username = key;
    _data = data;
    _fetchedAt = entry!.savedAt;
  }

  static DormElectricity? dataFor(String username) {
    final key = username.trim();
    return key.isNotEmpty && key == _username ? _data : null;
  }

  static DateTime? fetchedAtFor(String username) {
    final key = username.trim();
    return key.isNotEmpty && key == _username ? _fetchedAt : null;
  }

  static Duration? ageFor(String username) {
    final at = fetchedAtFor(username);
    return at == null ? null : DateTime.now().difference(at);
  }

  static void put(String username, DormElectricity data) {
    final key = username.trim();
    if (key.isEmpty) {
      return;
    }
    _username = key;
    _data = data;
    _fetchedAt = DateTime.now();
    // 加密落盘（安全存储，避免明文泄露宿舍物理住址与用电账单）
    unawaited(CacheStore.write(_keyFor(key), data.toCacheJson(), secure: true));
  }

  static Future<void> clear() async {
    final key = _username;
    _username = null;
    _data = null;
    _fetchedAt = null;
    if (key != null) {
      await CacheStore.remove(_keyFor(key), secure: true);
      await CacheStore.remove(_keyFor(key), secure: false);
    }
  }

  /// 只清内存、保留磁盘，用来模拟「App 冷启动」。
  @visibleForTesting
  static void resetMemoryForTest() {
    _username = null;
    _data = null;
    _fetchedAt = null;
  }
}

class DormElectricityException implements Exception {
  final String message;
  DormElectricityException(this.message);
  @override
  String toString() => message;
}

/// 按 URI 取 Cookie 请求头的值（复用 `CasClient.jar` 时用它）。
typedef CookieHeaderProvider = String? Function(Uri uri);

/// 把响应里的 `Set-Cookie` 写回外部会话。
typedef SetCookieSink = void Function(Uri from, String line);

class DormElectricityService {
  static const String _casBase = 'https://ids6.usst.edu.cn/authserver/login';
  static const String _service = 'https://ssgl.usst.edu.cn/default.aspx';
  static const String _base = 'https://ssgl.usst.edu.cn';
  static const String _elecApi = '$_base/api/Voucher/GetDormElectricityFees';

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  final Dio _dio;
  final Map<String, String> _cookies = <String, String>{};

  /// 从外部会话（例如 `CasClient.jar`）读 Cookie 头。
  final CookieHeaderProvider? _cookieHeader;

  /// 把响应里新种下的 cookie 写回外部会话。
  final SetCookieSink? _onSetCookie;

  DormElectricityService({Dio? dio, Map<String, String>? cookies})
    : _dio = dio ?? ApiClient.dio,
      _cookieHeader = null,
      _onSetCookie = null {
    if (cookies != null) _cookies.addAll(cookies);
  }

  /// 复用已有的 CAS 会话（`JwglAuth.instance.client!.jar`），不再需要账号密码。
  ///
  /// 请求 ssgl 会被重定向到 ids6；只要会话里还有 `CASTGC`，
  /// CAS 会直接发 ticket 跳回来，全程不需要重新登录。
  /// 相比 [fetch] 每次走完整登录流程，能省 1~2 秒。
  DormElectricityService.withSession(
    this._cookieHeader,
    this._onSetCookie, {
    Dio? dio,
  }) : _dio = dio ?? ApiClient.dio;

  /// 登录并拉取电费。
  ///
  /// [username] 学号，[password] 统一身份认证密码（不是校园卡查询密码）。
  Future<DormElectricity> fetch({
    required String username,
    required String password,
  }) async {
    await _login(username, password);
    return _fetchElectricity();
  }

  /// 直接注入已存在的会话 cookie（用于调试或复用外部登录态）。
  DormElectricityService.withCookies(Map<String, String> cookies, {Dio? dio})
    : this(dio: dio, cookies: cookies);

  /// 已登录状态下只刷新数据。
  Future<DormElectricity> refresh() => _fetchElectricity();

  /// 是否已经建立过会话。
  bool get isLoggedIn => _cookies.isNotEmpty;

  // ------------------------------------------------------------------ 登录

  Future<void> _login(String username, String password) async {
    _cookies.clear();

    final loginPage = await _request(
      Uri.parse(_casBase).replace(queryParameters: {'service': _service}),
      method: 'GET',
    );
    if (loginPage.statusCode != 200) {
      throw DormElectricityException('无法打开认证页：HTTP ${loginPage.statusCode}');
    }

    final fields = _parseInputs(loginPage.data.toString());
    if (!fields.containsKey('lt') || !fields.containsKey('execution')) {
      throw DormElectricityException('认证页结构变了（找不到 lt/execution）');
    }
    fields['username'] = username;
    fields['password'] = password;
    fields['captchaResponse'] = fields['captchaResponse'] ?? '';

    final body = fields.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');

    final resp = await _request(
      loginPage.realUri,
      method: 'POST',
      body: body,
      contentType: Headers.formUrlEncodedContentType,
    );

    final html = resp.data.toString();
    for (final entry in const {
      '密码有误': '密码错误',
      '用户名或密码错误': '密码错误',
      '请输入验证码': '需要验证码（风控），请先用浏览器登录一次',
      '账号已被锁定': '账号已被锁定',
    }.entries) {
      if (html.contains(entry.key)) {
        throw DormElectricityException(entry.value);
      }
    }
    if (resp.realUri.host == 'ids6.usst.edu.cn' &&
        html.contains('authserver')) {
      throw DormElectricityException('登录未完成，仍停留在认证页');
    }
  }

  // ------------------------------------------------------------------ 电费

  Future<DormElectricity> _fetchElectricity() async {
    final resp = await _request(
      Uri.parse('$_elecApi?IsLoadData=false'),
      method: 'GET',
      headers: {
        'x-hw-code': '',
        'Access_platform': 'pc',
        'Referer': '$_base/SSGL/StuMobile/StuView/VoucherCenter.html',
      },
    );

    if (resp.statusCode != 200) {
      throw DormElectricityException('电费接口 HTTP ${resp.statusCode}');
    }
    final decoded = jsonDecode(resp.data.toString());
    if (decoded is! Map || decoded['Success'] != true) {
      final msg = decoded is Map ? decoded['Message'] : null;
      throw DormElectricityException('电费接口返回失败：${msg ?? decoded}');
    }
    final data = decoded['Data'];
    if (data is! Map<String, dynamic>) {
      throw DormElectricityException('电费接口缺少 Data 字段');
    }
    return DormElectricity.fromJson(data);
  }

  // ------------------------------------------------------- cookie / 重定向

  Future<Response<dynamic>> _request(
    Uri url, {
    required String method,
    Object? body,
    String? contentType,
    Map<String, String>? headers,
  }) async {
    var current = url;
    var currentMethod = method;
    var currentBody = body;

    for (var hop = 0; hop < 10; hop++) {
      // 有外部会话就按 URI 现取（不同 host 的 cookie 不能混发），
      // 否则用自己维护的那份。
      final cookieHeader =
          _cookieHeader?.call(current) ??
          _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

      final resp = await _dio.requestUri<dynamic>(
        current,
        data: currentBody,
        options: Options(
          method: currentMethod,
          contentType: contentType,
          responseType: ResponseType.plain,
          // CAS 登录要逐跳收集 cookie，不能让 Dio 自动跟随重定向
          followRedirects: false,
          headers: {
            'User-Agent': _ua,
            if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
            ...?headers,
          },
        ),
      );

      _absorbCookies(current, resp);

      final status = resp.statusCode ?? 0;
      final location = resp.headers.value('location');
      if (status >= 300 && status < 400 && location != null) {
        current = current.resolve(location);
        // 强制将学校域名的 http 升级为 https，防局域网会话被嗅探
        if (current.scheme == 'http' &&
            (current.host == 'usst.edu.cn' || current.host.endsWith('.usst.edu.cn'))) {
          current = current.replace(scheme: 'https');
        }
        if (status == 303) {
          currentMethod = 'GET';
          currentBody = null;
          contentType = null;
        }
        continue;
      }
      return resp;
    }
    throw DormElectricityException('重定向次数过多');
  }

  void _absorbCookies(Uri from, Response<dynamic> resp) {
    final raw = resp.headers['set-cookie'];
    if (raw == null) return;
    for (final line in raw) {
      // 有外部会话时交给它管理（domain/path 由它自己判断）
      _onSetCookie?.call(from, line);

      final first = line.split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      final name = first.substring(0, eq).trim();
      final value = first.substring(eq + 1).trim();
      if (value.isEmpty) {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
    }
  }

  /// 解析登录页里的 `<input name=... value=...>`，只取不需要用户填的隐藏字段。
  Map<String, String> _parseInputs(String html) {
    final result = <String, String>{};
    final tags = RegExp(
      r'<input[^>]*>',
      caseSensitive: false,
    ).allMatches(html).map((m) => m.group(0)!);
    for (final tag in tags) {
      final type = _attr(tag, 'type')?.toLowerCase() ?? 'text';
      if (type == 'button' || type == 'submit' || type == 'image') continue;
      final name = _attr(tag, 'name');
      if (name == null || name.isEmpty) continue;
      result[name] = _unescape(_attr(tag, 'value') ?? '');
    }
    return result;
  }

  static String? _attr(String tag, String name) {
    final m = RegExp(
      '$name\\s*=\\s*"([^"]*)"',
      caseSensitive: false,
    ).firstMatch(tag);
    return m?.group(1);
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}
