import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/chaoxing/chaoxing_sso.dart';

/// 超星的 SSO 入口不是 302，而是返回一个「跳转中」页面，
/// JS 里写着 `window.location = "..."`（URL 里的斜杠还是转义的）。
/// 这段解析是整个静默登录的关键，单独测一下。
void main() {
  test('能解析超星「跳转中」页里的 CAS 地址', () {
    // 真实响应的片段（2026-10-28 抓取）
    const html =
        '<!DOCTYPE html> <html><head><meta charset="utf-8">'
        '<title>跳转中...</title></head><body></body>'
        '<script> window.location = '
        '"https:\\/\\/ids6.usst.edu.cn\\/authserver\\/login?'
        'service=https%3A%2F%2Ftyrzfw.chaoxing.com%2Fauth3%2Fusst%2Fcas%2Findex";'
        ' </script> </html>';

    final target = ChaoxingSso.parseJsRedirect(html);
    expect(target, isNotNull);
    expect(target, startsWith('https://ids6.usst.edu.cn/authserver/login'));
    expect(target, contains('service=https%3A%2F%2Ftyrzfw.chaoxing.com'));
    // JSON 转义的 `\/` 必须还原，否则 URI 解析会炸
    expect(target, isNot(contains(r'\/')));
  });

  test('window.location.href 写法也能认', () {
    const html =
        '<script>window.location.href = "https://i.chaoxing.com/";</script>';
    expect(ChaoxingSso.parseJsRedirect(html), 'https://i.chaoxing.com/');
  });

  test('能还原 \\u0026 这类转义（否则查询参数会串成一坨）', () {
    // 真实片段：casreceive 的 URL 用 \u0026 表示 &
    const html =
        r'''<script>window.location = "https:\/\/passport2-api.chaoxing.com\/api\/v2\/casreceive?thirdinfo=ABC\u0026refer=https%3A%2F%2Fi.chaoxing.com\u0026setmain=true\u0026time=1793176206338";</script>''';

    final target = ChaoxingSso.parseJsRedirect(html);
    expect(target, isNotNull);
    expect(target, isNot(contains(r'\u0026')));
    expect(target, contains('thirdinfo=ABC'));
    expect(target, contains('&time=1793176206338'));

    // 还原后 URI 应该能正确拆出 5 个参数
    final uri = Uri.parse(target!);
    expect(
      uri.queryParameters.keys,
      containsAll(<String>['thirdinfo', 'refer', 'setmain', 'time']),
    );
  });

  test('普通页面返回 null（不要误判成跳转）', () {
    expect(
      ChaoxingSso.parseJsRedirect('<html><body>hello</body></html>'),
      isNull,
    );
    expect(ChaoxingSso.parseJsRedirect(''), isNull);
  });

  test('入口地址包含上理的 CAS 路径', () {
    expect(ChaoxingSso.entryUrl, contains('/auth3/usst/cas/init'));
  });

  test('CASTGC 判断只认 ids6 的有效 cookie', () {
    final cas = CasClient();
    expect(ChaoxingSso.hasCastgc(cas), isFalse);
    cas.jar.cookies.add(
      const CasCookie(
        name: 'CASTGC',
        value: 'TGT-1',
        domain: '.usst.edu.cn',
        path: '/',
      ),
    );
    expect(ChaoxingSso.hasCastgc(cas), isTrue);
    expect(ChaoxingSso.hasCastgc(null), isFalse);
  });
}
