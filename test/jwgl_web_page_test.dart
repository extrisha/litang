import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/pages/jwgl_web_page.dart';

void main() {
  group('JwglWebPage.isAllowedUrl', () {
    test('允许教务系统与统一认证主域名', () {
      expect(
        JwglWebPage.isAllowedUrl(
          'https://jwgl.usst.edu.cn/jwglxt/xtgl/index_initMenu.html',
        ),
        isTrue,
      );
      expect(
        JwglWebPage.isAllowedUrl('https://ids6.usst.edu.cn/authserver/login'),
        isTrue,
      );
      expect(
        JwglWebPage.isAllowedUrl('http://jwgl.usst.edu.cn/jwglxt/login'),
        isTrue,
      );
    });

    test('允许校内其他子域', () {
      expect(
        JwglWebPage.isAllowedUrl('https://cas.usst.edu.cn/login'),
        isTrue,
      );
      expect(
        JwglWebPage.isAllowedUrl('https://sso.usst.edu.cn/sso'),
        isTrue,
      );
    });

    test('拦截非校内外部域名', () {
      expect(
        JwglWebPage.isAllowedUrl('https://evil-usst.edu.cn/login'),
        isFalse,
      );
      expect(
        JwglWebPage.isAllowedUrl('https://usst.edu.cn.attacker.com/'),
        isFalse,
      );
      expect(
        JwglWebPage.isAllowedUrl('https://www.baidu.com/'),
        isFalse,
      );
    });

    test('拦截非 HTTP/HTTPS 协议与非法 URL', () {
      expect(
        JwglWebPage.isAllowedUrl('javascript:alert(1)'),
        isFalse,
      );
      expect(
        JwglWebPage.isAllowedUrl('file:///etc/passwd'),
        isFalse,
      );
      expect(
        JwglWebPage.isAllowedUrl('data:text/html,hello'),
        isFalse,
      );
      expect(
        JwglWebPage.isAllowedUrl(''),
        isFalse,
      );
    });
  });
}
