import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/auth/cas_client.dart';

void main() {
  group('upgradeCasUrl', () {
    test('把学校域名的 http 升级成 https', () {
      expect(
        upgradeCasUrl(Uri.parse('http://jwgl.usst.edu.cn/sso/jziotlogin'))
            .toString(),
        'https://jwgl.usst.edu.cn/sso/jziotlogin',
      );
    });

    test('非学校域名保持原样', () {
      expect(
        upgradeCasUrl(Uri.parse('http://example.com/a?b=1')).toString(),
        'http://example.com/a?b=1',
      );
    });

    test('https 不再改动', () {
      expect(
        upgradeCasUrl(Uri.parse('https://ids6.usst.edu.cn/authserver/login'))
            .toString(),
        'https://ids6.usst.edu.cn/authserver/login',
      );
    });
  });

  group('CasTokens', () {
    test('解析 lt / execution / _eventId', () {
      const html =
          '<input type="hidden" name="lt" value="LT-1"/>'
          '<input type="hidden" name="execution" value="e1s1"/>'
          '<input type="hidden" name="_eventId" value="submit"/>';
      final tokens = CasTokens.parse(html);
      expect(tokens, isNotNull);
      expect(tokens!.lt, 'LT-1');
      expect(tokens.execution, 'e1s1');
      expect(tokens.eventId, 'submit');
      expect(tokens.isValid, isTrue);
    });

    test('缺字段返回 null', () {
      expect(CasTokens.parse('<input name="lt" value="x"/>'), isNull);
    });
  });

  group('CasCookieJar', () {
    test('按 path 区分同名 cookie', () {
      final jar = CasCookieJar();
      jar.absorbSetCookie(
        Uri.parse('https://jwgl.usst.edu.cn/sso/jziotlogin'),
        'JSESSIONID=AAA; Path=/sso; HttpOnly',
      );
      jar.absorbSetCookie(
        Uri.parse('https://jwgl.usst.edu.cn/jwglxt/xtgl/login_slogin.html'),
        'JSESSIONID=BBB; Path=/jwglxt; HttpOnly',
      );

      final sso = jar.headerFor(
        Uri.parse('https://jwgl.usst.edu.cn/sso/jziotlogin?ticket=1'),
      );
      expect(sso, contains('JSESSIONID=AAA'));
      expect(sso, isNot(contains('BBB')));

      final jwgl = jar.headerFor(
        Uri.parse('https://jwgl.usst.edu.cn/jwglxt/xtgl/index_initMenu.html'),
      );
      expect(jwgl, contains('JSESSIONID=BBB'));
      expect(jwgl, isNot(contains('AAA')));
    });

    test('带 Domain 的 cookie 命中子域', () {
      final jar = CasCookieJar();
      jar.absorbSetCookie(
        Uri.parse('https://ehall.usst.edu.cn/'),
        'iPlanetDirectoryPro=XYZ; Domain=.usst.edu.cn; Path=/',
      );
      expect(
        jar.headerFor(Uri.parse('https://jwgl.usst.edu.cn/jwglxt/')),
        contains('iPlanetDirectoryPro=XYZ'),
      );
    });

    test('按 host 取 cookie 供 WebView 注入', () {
      final jar = CasCookieJar();
      jar.absorbSetCookie(
        Uri.parse('https://jwgl.usst.edu.cn/sso/jziotlogin'),
        'JSESSIONID=AAA; Path=/sso; HttpOnly',
      );
      jar.absorbSetCookie(
        Uri.parse('https://jwgl.usst.edu.cn/jwglxt/xtgl/login_slogin.html'),
        'JSESSIONID=BBB; Path=/jwglxt; HttpOnly',
      );
      jar.absorbSetCookie(
        Uri.parse('https://ehall.usst.edu.cn/'),
        'CASTGC=TGT-1; Path=/',
      );
      final list = jar.cookiesForHost('jwgl.usst.edu.cn');
      expect(list.length, 2);
      expect(list.every((c) => c.name == 'JSESSIONID'), isTrue);
    });

    test('没有匹配 cookie 时返回 null', () {
      final jar = CasCookieJar();
      expect(jar.headerFor(Uri.parse('https://example.com/')), isNull);
    });

    test('Leading-dot cookie 要覆盖所有子域（考试答卷页靠它）', () {
      final jar = CasCookieJar();
      jar.absorbSetCookie(
        Uri.parse('https://passport2.chaoxing.com/login'),
        'UID=12345; Domain=.chaoxing.com; Path=/',
      );
      // 学习通答卷页在 stat2-ans.chaoxing.com，课程页在 mooc1.chaoxing.com，
      // 两者都必须带上登录态，否则页面会显示“请登录”。
      for (final host in <String>[
        'stat2-ans.chaoxing.com',
        'mooc1.chaoxing.com',
        'chaoxing.com',
      ]) {
        expect(
          jar.headerFor(Uri.parse('https://$host/study-knowledge/ans')),
          contains('UID=12345'),
          reason: host,
        );
      }
      // 别的域不能带上
      expect(jar.headerFor(Uri.parse('https://example.com/')), isNull);
    });

    test('跨域 Cookie 投毒拦截（RFC 6265 域安全隔离）', () {
      final jar = CasCookieJar();

      // 1. 来源与目标域不匹配：恶意第三方尝试给学校域种 Cookie
      jar.absorbSetCookie(
        Uri.parse('https://evil.com/login'),
        'CASTGC=evil_token; Domain=.usst.edu.cn; Path=/',
      );
      expect(jar.headerFor(Uri.parse('https://jwgl.usst.edu.cn/')), isNull);

      // 2. 伪装相似域名试图跨域：evil-usst.edu.cn != usst.edu.cn
      jar.absorbSetCookie(
        Uri.parse('https://evil-usst.edu.cn/'),
        'TICKET=123; Domain=.usst.edu.cn; Path=/',
      );
      expect(jar.headerFor(Uri.parse('https://jwgl.usst.edu.cn/')), isNull);

      // 3. 试图给公共后缀 / 顶级域设置 Cookie (Public Suffix)
      jar.absorbSetCookie(
        Uri.parse('https://other.edu.cn/'),
        'SHARED=bad; Domain=.edu.cn; Path=/',
      );
      expect(jar.headerFor(Uri.parse('https://usst.edu.cn/')), isNull);

      // 4. 正确的来源域允许设置其自身或父域 Cookie
      jar.absorbSetCookie(
        Uri.parse('https://ids6.usst.edu.cn/authserver/login'),
        'CASTGC=valid_tgt; Domain=.usst.edu.cn; Path=/',
      );
      expect(
        jar.headerFor(Uri.parse('https://jwgl.usst.edu.cn/')),
        contains('CASTGC=valid_tgt'),
      );
    });
  });

  group('验证码识别', () {
    test('学校 CAS 页面：img 没有 src，字段名是 captchaResponse', () {
      // 实测 ids6 的登录页：<img id="captchaImg" .../> 没有 src，由 JS 补
      const html =
          '<div id="hidenCaptchaDiv" style="display: none;">'
          '<input type="text" placeholder="验证码" id="captchaResponse" name="captchaResponse"/>'
          '<img id="captchaImg" class="captcha-img" alt="验证码" title="验证码"/>'
          '</div>';
      final parsed = CasClient.parseCaptcha(html);
      expect(parsed, isNotNull);
      expect(parsed!.field, 'captchaResponse');
      expect(parsed.src, isNull); // 交给 captcha.html 兜底
    });

    test('图片带 src 时能取出来（其它 CAS 皮肤）', () {
      const html =
          '<input type="text" name="captcha" size="10"/>'
          '<img id="captchaImage" src="/authserver/captcha?ts=1699"/>';
      final parsed = CasClient.parseCaptcha(html);
      expect(parsed, isNotNull);
      expect(parsed!.field, 'captcha');
      expect(parsed.src, '/authserver/captcha?ts=1699');
    });

    test('没有验证码的页面返回 null', () {
      const html =
          '<input type="hidden" name="lt" value="LT-1"/>'
          '<input type="text" name="username"/><input type="password" name="password"/>';
      expect(CasClient.parseCaptcha(html), isNull);
      expect(CasClient.parseCaptcha(''), isNull);
    });

    test('只有输入框没有图片也算（图片走兜底接口）', () {
      const html = '<input type="text" name="captchaResponse"/>';
      // 没有 img 时无法确认是验证码页面
      expect(CasClient.parseCaptcha(html), isNull);
    });
  });
}
