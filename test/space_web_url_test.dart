import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/jwc/space_web_url.dart';

void main() {
  group('SpaceWebUrl.room', () {
    test('不带授权码时只有 roomId 与 date', () {
      expect(
        SpaceWebUrl.room(roomId: '123', date: '2026-11-02'),
        'https://libspace.usst.edu.cn/mStudent/room?roomId=123&date=2026-11-02',
      );
    });

    test('带授权码时正确拼接', () {
      final url = SpaceWebUrl.room(
        roomId: '123',
        date: '2026-11-02',
        code: 'abc123',
      );
      final uri = Uri.parse(url);
      expect(uri.queryParameters['roomId'], '123');
      expect(uri.queryParameters['date'], '2026-11-02');
      expect(uri.queryParameters['code'], 'abc123');
    });

    test('授权码里的 + / = 必须被编码，解码后要能还原', () {
      // 这就是原来的 bug：手工拼接时 '+' 会被服务端解成空格、'=' 会截断参数
      const code = 'a+b/c==d';
      final url = SpaceWebUrl.room(roomId: '1', date: '2026-11-02', code: code);

      expect(url.contains('+'), isFalse, reason: '不应出现裸的 +');
      expect(Uri.parse(url).queryParameters['code'], code);
    });

    test('空授权码视同没有', () {
      expect(
        SpaceWebUrl.room(roomId: '1', date: '2026-11-02', code: ''),
        isNot(contains('code=')),
      );
    });
  });

  group('SpaceWebUrl.index', () {
    test('不带授权码', () {
      expect(
        SpaceWebUrl.index(),
        'https://libspace.usst.edu.cn/mStudent/index',
      );
    });

    test('带授权码且正确编码', () {
      const code = 'x/y+z==';
      final url = SpaceWebUrl.index(code: code);
      expect(url.contains('+'), isFalse);
      expect(Uri.parse(url).queryParameters['code'], code);
    });
  });
}
