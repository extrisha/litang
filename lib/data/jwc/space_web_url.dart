/// 图书馆空间预约（libspace）网页端地址构造。
///
/// 之前两个页面各自手工拼 query 字符串，把 OAuth 授权码直接插进去：
/// `...?code=$code`。授权码是 base64 风格，含 `+`、`/`、`=`，
/// `+` 会被服务端解成空格、`=` 会截断参数，导致免密跳转偶发失效。
/// 统一走 `Uri.replace(queryParameters:)` 做百分号编码。
class SpaceWebUrl {
  SpaceWebUrl._();

  static const String base = 'https://libspace.usst.edu.cn';

  /// 房间预约页：`/mStudent/room?roomId=..&date=..[&code=..]`
  static String room({
    required String roomId,
    required String date,
    String? code,
  }) {
    return Uri.parse('$base/mStudent/room')
        .replace(
          queryParameters: <String, String>{
            'roomId': roomId,
            'date': date,
            if (code != null && code.isNotEmpty) 'code': code,
          },
        )
        .toString();
  }

  /// 空间预约首页：`/mStudent/index[?code=..]`
  static String index({String? code}) {
    final uri = Uri.parse('$base/mStudent/index');
    // 没有 code 时不能走 replace(queryParameters: {})：那会留下一个空查询串，
    // 生成 `.../index?` 这种带裸问号的地址。
    if (code == null || code.isEmpty) return uri.toString();
    return uri
        .replace(queryParameters: <String, String>{'code': code})
        .toString();
  }
}
