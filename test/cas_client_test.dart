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
  });

  group('验证码识别', () {
    test('标准 CAS 验证码页：能找到图片和输入框名', () {
      const html = '''
        <form id="fm1" method="post">
          <input type="hidden" name="lt" value="LT-1"/>
          <input type="hidden" name="execution" value="e1s1"/>
          <input type="text" name="captcha" size="10"/>
          <img id="captchaImage" src="/authserver/captcha?ts=1699"/>
        </form>''';
      final parsed = CasClient.parseCaptcha(html);
      expect(parsed, isNotNull);
      expect(parsed!.field, 'captcha');
      expect(parsed.imageUrl, '/authserver/captcha?ts=1699');
    });

    test('图片在输入框前面、属性顺序不同也能认', () {
      const html =
          '<img alt="验证码" class="code" src="https://ids6.usst.edu.cn/authserver/kaptcha?x=1">'
          '<input id="codeInput" type="text" name="validateCode">';
      final parsed = CasClient.parseCaptcha(html);
      expect(parsed, isNotNull);
      expect(parsed!.field, 'validateCode');
      expect(parsed.imageUrl, contains('kaptcha'));
    });

    test('没有验证码的普通登录页返回 null', () {
      const html =
          '<input type="hidden" name="lt" value="LT-1"/>'
          '<input type="text" name="username"/><input type="password" name="password"/>';
      expect(CasClient.parseCaptcha(html), isNull);
      expect(CasClient.parseCaptcha(''), isNull);
    });

    test('只有图片没有输入框时，字段名用默认的 captcha', () {
      const html = '<img src="/authserver/captcha">';
      final parsed = CasClient.parseCaptcha(html);
      expect(parsed, isNotNull);
      expect(parsed!.field, 'captcha');
    });
  });
}
