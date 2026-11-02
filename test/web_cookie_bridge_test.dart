import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/chaoxing/web_cookie_bridge.dart';

void main() {
  group('解析 Cookie 头', () {
    test('普通的 name=value 列表', () {
      final cookies = WebCookieBridge.parseCookieHeader(
        '_uid=123456; _d=abcdef; fid=207; uf=abc%2Bdef',
        domain: '.chaoxing.com',
      );
      expect(cookies.length, 4);
      expect(cookies.first.name, '_uid');
      expect(cookies.first.value, '123456');
      expect(cookies.first.domain, '.chaoxing.com');
      expect(cookies.first.path, '/');
      // 值里的 = 和 % 要原样保留
      expect(cookies.last.value, 'abc%2Bdef');
    });

    test('多余空格 / 空段 / 残缺项都跳过', () {
      final cookies = WebCookieBridge.parseCookieHeader(
        '  a=1 ;; b = 2 ; =oops; noequals ',
        domain: 'i.chaoxing.com',
      );
      expect(cookies.map((c) => c.name).toList(), ['a', 'b']);
      expect(cookies.last.value, '2');
    });

    test('空串返回空列表', () {
      expect(
        WebCookieBridge.parseCookieHeader('', domain: '.chaoxing.com'),
        isEmpty,
      );
    });
  });

  group('cookie 归属域', () {
    test('chaoxing 的子域统一记到 .chaoxing.com', () {
      expect(
        WebCookieBridge.cookieDomain('https://i.chaoxing.com/'),
        '.chaoxing.com',
      );
      expect(
        WebCookieBridge.cookieDomain('https://passport2.chaoxing.com/'),
        '.chaoxing.com',
      );
      expect(
        WebCookieBridge.cookieDomain('https://chaoxing.com/'),
        '.chaoxing.com',
      );
    });

    test('别的域名按 host-only，不能把 edu.cn 当成可共享域', () {
      expect(
        WebCookieBridge.cookieDomain('https://www.sbc.usst.edu.cn/'),
        'www.sbc.usst.edu.cn',
      );
      expect(
        WebCookieBridge.cookieDomain('https://jwgl.usst.edu.cn/'),
        'jwgl.usst.edu.cn',
      );
    });

    test('非法 URL 返回空串', () {
      expect(WebCookieBridge.cookieDomain('not a url'), '');
    });
  });

  group('匹配', () {
    test('解析出来的 cookie 能匹配 chaoxing 各子域', () {
      final cookie = WebCookieBridge.parseCookieHeader(
        '_uid=1',
        domain: '.chaoxing.com',
      ).single;
      expect(cookie.matchesHost('i.chaoxing.com'), isTrue);
      expect(cookie.matchesHost('mooc1.chaoxing.com'), isTrue);
      expect(cookie.matchesHost('example.com'), isFalse);
    });
  });
}
