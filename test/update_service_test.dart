import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/services/update_service.dart';

void main() {
  group('UpdateInfo.fromJson', () {
    Map<String, dynamic> base() => <String, dynamic>{
      'version': '0.4.1',
      'versionCode': 15,
      'notes': '修了几个 bug',
      'apk_github': 'https://example.com/a.apk',
      'apk_gitee': 'https://example.com/g.apk',
      'sha256': 'ABCDEF',
    };

    test('没有 minVersionCode 时默认不强制', () {
      final info = UpdateInfo.fromJson(base())!;
      expect(info.version, '0.4.1');
      expect(info.versionCode, 15);
      expect(info.minVersionCode, 0);
      expect(info.mandatory, isFalse);
      expect(info.sha256, 'abcdef'); // 统一小写
    });

    test('带 minVersionCode 时能读出来', () {
      final json = base()..['minVersionCode'] = 16;
      expect(UpdateInfo.fromJson(json)!.minVersionCode, 16);
    });

    test('version / versionCode 缺失或非法时返回 null', () {
      expect(UpdateInfo.fromJson(<String, dynamic>{}), isNull);
      expect(UpdateInfo.fromJson(<String, dynamic>{'version': '0.4.1'}), isNull);
      expect(
        UpdateInfo.fromJson(<String, dynamic>{'versionCode': 15}),
        isNull,
      );
    });
  });

  group('是否强制更新', () {
    test('低于云端最低版本必须更新', () {
      expect(UpdateService.isMandatory(current: 14, min: 15), isTrue);
      expect(UpdateService.isMandatory(current: 15, min: 15), isFalse);
      expect(UpdateService.isMandatory(current: 16, min: 15), isFalse);
    });

    test('min 为 0 或负数一律不强制（默认行为）', () {
      expect(UpdateService.isMandatory(current: 1, min: 0), isFalse);
      expect(UpdateService.isMandatory(current: 1, min: -5), isFalse);
    });

    test('withMandatory 只改标志位，其它字段不变', () {
      final info = UpdateInfo.fromJson(<String, dynamic>{
        'version': '0.4.1',
        'versionCode': 15,
        'notes': 'n',
        'apk_github': 'g',
        'apk_gitee': 't',
        'sha256': 'x',
        'minVersionCode': 15,
      })!;
      final forced = info.withMandatory(true);
      expect(forced.mandatory, isTrue);
      expect(forced.version, info.version);
      expect(forced.versionCode, info.versionCode);
      expect(forced.minVersionCode, 15);
      expect(info.withMandatory(false).mandatory, isFalse);
    });
  });

  group('下载地址候选', () {
    UpdateInfo info(String gitee) => UpdateInfo(
      version: '0.4.2',
      versionCode: 16,
      notes: '',
      githubUrl: 'https://github.com/o/r/releases/latest/download/app-release.apk',
      giteeUrl: gitee,
      sha256: 'x',
    );

    test('Gitee 优先，然后是它的 v 前缀备选，最后才是 GitHub', () {
      final urls = UpdateService.candidateUrls(
        info('https://gitee.com/o/r/releases/download/0.4.2/app-release.apk'),
      );
      expect(urls.length, 3);
      expect(urls[0], contains('gitee.com'));
      expect(urls[0], contains('/download/0.4.2/'));
      expect(urls[1], contains('/download/v0.4.2/'));
      expect(urls[2], contains('latest/download'));
    });

    test('Gitee tag 带 v 时，反过来补一个不带 v 的', () {
      final urls = UpdateService.candidateUrls(
        info('https://gitee.com/o/r/releases/download/v0.4.2/app-release.apk'),
      );
      expect(urls.length, 3);
      expect(urls[0], contains('/download/v0.4.2/'));
      expect(urls[1], contains('/download/0.4.2/'));
      expect(urls[1], isNot(contains('v0.4.2')));
    });

    test('没有 download 段的地址不会凭空造备选', () {
      final urls = UpdateService.candidateUrls(info('https://example.com/a.apk'));
      expect(urls.length, 2);
    });

    test('空地址只留下有值的那些', () {
      final urls = UpdateService.candidateUrls(
        const UpdateInfo(
          version: '1',
          versionCode: 1,
          notes: '',
          githubUrl: '',
          giteeUrl: 'https://gitee.com/o/r/releases/download/1.0/a.apk',
          sha256: '',
        ),
      );
      expect(urls.first, contains('gitee.com'));
      expect(urls.every((u) => u.isNotEmpty), isTrue);
    });
  });
}
