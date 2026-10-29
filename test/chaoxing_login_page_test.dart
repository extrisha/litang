import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/pages/chaoxing_login_page.dart';

void main() {
  group('ChaoxingLoginPage.isOfficialLoginPage', () {
    test('合法官方登录地址返回 true', () {
      expect(
        ChaoxingLoginPage.isOfficialLoginPage('https://passport2.chaoxing.com/login'),
        isTrue,
      );
      expect(
        ChaoxingLoginPage.isOfficialLoginPage(
          'https://passport2.chaoxing.com/login?fid=207&newversion=true',
        ),
        isTrue,
      );
    });

    test('钓鱼 / 仿冒 URL 伪造查询参数防御（防止注入密码到恶意站点）', () {
      // 1. 攻击者将合法地址作为 query 参数放入恶意域
      expect(
        ChaoxingLoginPage.isOfficialLoginPage(
          'https://attacker.com/steal?fake=passport2.chaoxing.com/login',
        ),
        isFalse,
      );

      // 2. 伪造子域名：passport2.chaoxing.com.attacker.com
      expect(
        ChaoxingLoginPage.isOfficialLoginPage(
          'https://passport2.chaoxing.com.attacker.com/login',
        ),
        isFalse,
      );

      // 3. 官方域下的非登录路由不匹配自动注入
      expect(
        ChaoxingLoginPage.isOfficialLoginPage(
          'https://passport2.chaoxing.com/register',
        ),
        isFalse,
      );

      // 4. 非法或空 URL
      expect(ChaoxingLoginPage.isOfficialLoginPage(''), isFalse);
      expect(ChaoxingLoginPage.isOfficialLoginPage('not-a-valid-url'), isFalse);
    });
  });

  group('ChaoxingLoginPage.isAllowedNavigation', () {
    test('允许白名单域：超星体系与上理体系', () {
      expect(
        ChaoxingLoginPage.isAllowedNavigation('https://passport2.chaoxing.com/login'),
        isTrue,
      );
      expect(
        ChaoxingLoginPage.isAllowedNavigation('https://i.chaoxing.com/'),
        isTrue,
      );
      expect(
        ChaoxingLoginPage.isAllowedNavigation('https://ids6.usst.edu.cn/authserver/login'),
        isTrue,
      );
      expect(
        ChaoxingLoginPage.isAllowedNavigation('about:blank'),
        isTrue,
      );
    });

    test('拒绝未经允许的外部域与恶意跳转', () {
      expect(
        ChaoxingLoginPage.isAllowedNavigation('https://evil.com/phishing'),
        isFalse,
      );
      expect(
        ChaoxingLoginPage.isAllowedNavigation('https://evil-chaoxing.com/login'),
        isFalse,
      );
      expect(
        ChaoxingLoginPage.isAllowedNavigation('https://usst.edu.cn.attacker.org/'),
        isFalse,
      );
      expect(
        ChaoxingLoginPage.isAllowedNavigation('javascript:alert(1)'),
        isFalse,
      );
    });
  });

  group('ChaoxingLoginPage.looksLoggedIn', () {
    test('超星业务页命中', () {
      expect(ChaoxingLoginPage.looksLoggedIn('https://i.chaoxing.com/'), isTrue);
      expect(
        ChaoxingLoginPage.looksLoggedIn('https://mooc1.chaoxing.com/visit/courses'),
        isTrue,
      );
      expect(
        ChaoxingLoginPage.looksLoggedIn('https://mooc2-ans.chaoxing.com/mooc2-ans/mycourse/stu'),
        isTrue,
      );
    });

    test('登录页或钓鱼页不会被误判为已登录', () {
      expect(
        ChaoxingLoginPage.looksLoggedIn('https://passport2.chaoxing.com/login'),
        isFalse,
      );
      // 包含业务域名关键字的外部攻击者页面
      expect(
        ChaoxingLoginPage.looksLoggedIn('https://attacker.com/fake?dummy=i.chaoxing.com'),
        isFalse,
      );
    });
  });
}
