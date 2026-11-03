import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
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

  group('WebView cookie 注入计划', () {
    test('同站的兄弟域也要注入（CAS 的 ids6 一跳靠它）', () {
      final cookies = <CasCookie>[
        // CAS 会话：host-only 落在 ids6 上
        const CasCookie(
          name: 'CASTGC',
          value: 'tgt-1',
          path: '/',
          domain: 'ids6.usst.edu.cn',
        ),
        // 父域 cookie
        const CasCookie(
          name: 'JSESSIONID',
          value: 'sess-1',
          path: '/',
          domain: '.usst.edu.cn',
        ),
      ];

      // 目标是 libspace —— 和 ids6 是兄弟域，旧逻辑会把 CASTGC 整条丢掉
      final plan = WebCookieBridge.buildInjection(
        cookies,
        'https://libspace.usst.edu.cn/student/studentIndex',
      );

      expect(plan.length, 2);
      expect(
        plan.map((e) => e.url),
        containsAll(<String>[
          'https://ids6.usst.edu.cn/',
          'https://usst.edu.cn/',
        ]),
      );

      final castgc = plan.firstWhere((e) => e.cookie.contains('CASTGC'));
      expect(castgc.cookie, contains('Path=/'));
      // host-only cookie 不该写 Domain（写了会扩大作用域）
      expect(castgc.cookie, isNot(contains('Domain=')));

      final parent = plan.firstWhere((e) => e.cookie.contains('JSESSIONID'));
      // 父域 cookie 必须带 Domain，才能被兄弟域命中
      expect(parent.cookie, contains('Domain=.usst.edu.cn'));
    });

    test('绝不把 usst 的会话注入到 chaoxing', () {
      final plan = WebCookieBridge.buildInjection(<CasCookie>[
        const CasCookie(
          name: 'CASTGC',
          value: 'tgt-1',
          path: '/',
          domain: 'ids6.usst.edu.cn',
        ),
      ], 'https://i.chaoxing.com/');
      expect(plan, isEmpty);
    });

    test('chaoxing 站内各子域互相注入', () {
      final plan = WebCookieBridge.buildInjection(<CasCookie>[
        const CasCookie(
          name: '_uid',
          value: '1',
          path: '/',
          domain: '.chaoxing.com',
        ),
        const CasCookie(
          name: 'fid',
          value: '42',
          path: '/',
          domain: 'passport2.chaoxing.com',
        ),
      ], 'https://i.chaoxing.com/');
      expect(plan.length, 2);
      expect(
        plan.map((e) => e.url),
        contains('https://passport2.chaoxing.com/'),
      );
    });

    test('站点判定：edu.cn 是二级后缀', () {
      expect(WebCookieBridge.siteOf('libspace.usst.edu.cn'), 'usst.edu.cn');
      expect(WebCookieBridge.siteOf('ids6.usst.edu.cn'), 'usst.edu.cn');
      expect(WebCookieBridge.siteOf('i.chaoxing.com'), 'chaoxing.com');
      expect(WebCookieBridge.siteOf('chaoxing.com'), 'chaoxing.com');
      expect(WebCookieBridge.siteOf('localhost'), 'localhost');
    });

    test('非法目标地址返回空计划', () {
      expect(
        WebCookieBridge.buildInjection(<CasCookie>[
          const CasCookie(
            name: 'a',
            value: '1',
            path: '/',
            domain: '.usst.edu.cn',
          ),
        ], 'not a url'),
        isEmpty,
      );
    });
  });
}
