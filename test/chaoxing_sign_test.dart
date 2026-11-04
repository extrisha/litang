import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/chaoxing/chaoxing_client.dart';

/// 学习通扫码签到：把「签到结果」页翻译成状态。
/// 这些 HTML 片段取自 2026-10-28 的真实响应。
void main() {
  test('已签到过的二维码 → 成功（回显原来的签到时间）', () {
    const html =
        '<html><body><div class="title">签到结果</div>'
        '<div class="status">签到成功</div>'
        '<div class="time">10-28 09:48</div></body></html>';
    final result = ChaoxingClient.parseSignResult(html);
    expect(result.status, ChaoxingSignStatus.success);
    expect(result.success, isTrue);
    expect(result.message, '签到成功');
  });

  test('签到已结束', () {
    const html = '<div>该签到已结束</div>';
    final result = ChaoxingClient.parseSignResult(html);
    expect(result.status, ChaoxingSignStatus.ended);
    expect(result.success, isFalse);
  });

  test('二维码无效', () {
    const html = '<div>二维码无效，请重新扫码</div>';
    final result = ChaoxingClient.parseSignResult(html);
    expect(result.status, ChaoxingSignStatus.invalid);
  });

  test('桌面 UA 被服务端拦下时给出可读提示', () {
    const html = '<div>提示信息</div><div>请使用客户端进行扫码签到</div>';
    final result = ChaoxingClient.parseSignResult(html);
    expect(result.status, ChaoxingSignStatus.unknown);
    expect(result.message, contains('客户端'));
  });

  test('空响应不会抛异常', () {
    final result = ChaoxingClient.parseSignResult('');
    expect(result.status, ChaoxingSignStatus.unknown);
    expect(result.success, isFalse);
  });

  group('ChaoxingClient.parseAjaxSignResult（stuSignajax 纯文本）', () {
    test('success / success2 都算成功', () {
      expect(
        ChaoxingClient.parseAjaxSignResult('success').status,
        ChaoxingSignStatus.success,
      );
      expect(
        ChaoxingClient.parseAjaxSignResult('success2').status,
        ChaoxingSignStatus.success,
      );
      expect(
        ChaoxingClient.parseAjaxSignResult(' success2 \n').success,
        isTrue,
      );
    });

    test('已经签过到算成功（重复扫码不报错）', () {
      final result = ChaoxingClient.parseAjaxSignResult('您已签到');
      expect(result.status, ChaoxingSignStatus.alreadySigned);
      expect(result.success, isTrue);
    });

    test('签到已结束 / 过期', () {
      expect(
        ChaoxingClient.parseAjaxSignResult('签到已结束').status,
        ChaoxingSignStatus.ended,
      );
      expect(
        ChaoxingClient.parseAjaxSignResult('二维码已过期').status,
        ChaoxingSignStatus.ended,
      );
    });

    test('不在签到范围 / 无效码给出可读错误', () {
      final out = ChaoxingClient.parseAjaxSignResult('您不在签到范围内');
      expect(out.status, ChaoxingSignStatus.invalid);
      expect(out.success, isFalse);
      expect(out.message, contains('不在签到范围'));
    });

    test('HTML 包装的响应也能认出来', () {
      final result = ChaoxingClient.parseAjaxSignResult(
        '<html><body><p>签到成功</p></body></html>',
      );
      expect(result.success, isTrue);
    });
  });

  group('ChaoxingClient.parseActivities（学习通签到列表）', () {
    const course = ChaoxingCourse(
      courseId: 'c1',
      classId: 'k1',
      cpi: 'p1',
      name: '高等数学',
    );

    test('data.activeList 结构，保留官方 url', () {
      const raw =
          '{"result":1,"data":{"activeList":['
          '{"id":"a1","activeType":2,"status":"1","nameOne":"签到",'
          '"url":"https://mobilelearn.chaoxing.com/widget/sign/e?id=a1&enc=E"}'
          ']}}';
      final list = ChaoxingClient.parseActivities(raw, course);
      expect(list.length, 1);
      expect(list.single.id, 'a1');
      expect(list.single.name, '签到');
      expect(list.single.url, contains('enc=E'));
      expect(list.single.courseName, '高等数学');
    });

    test('activeList 在顶层也能解析', () {
      const raw =
          '{"status":1,"activeList":['
          '{"id":"a2","activeType":2,"status":1,"name":"测验签到"}'
          ']}';
      final list = ChaoxingClient.parseActivities(raw, course);
      expect(list.single.id, 'a2');
    });

    test('已结束 / 非签到活动被过滤', () {
      const raw =
          '{"result":1,"data":{"activeList":['
          '{"id":"a1","activeType":2,"status":2},'
          '{"id":"a2","activeType":3,"status":1},'
          '{"id":"a3","activeType":2,"status":1}'
          ']}}';
      final list = ChaoxingClient.parseActivities(raw, course);
      expect(list.map((e) => e.id).toList(), <String>['a3']);
    });

    test('HTML / 空响应返回空列表，不抛异常', () {
      expect(
        ChaoxingClient.parseActivities('<html>login</html>', course),
        isEmpty,
      );
      expect(ChaoxingClient.parseActivities('', course), isEmpty);
    });
  });

  group('ChaoxingClient.isValidSignQrUrl 安全校验', () {
    test('合法的超星签到二维码 URL', () {
      expect(
        ChaoxingClient.isValidSignQrUrl(
          Uri.parse(
            'https://mobilelearn.chaoxing.com/widget/sign/e?id=123&enc=ABC',
          ),
        ),
        isTrue,
      );
      expect(
        ChaoxingClient.isValidSignQrUrl(
          Uri.parse('https://chaoxing.com/widget/sign/p?enc=XYZ'),
        ),
        isTrue,
      );
    });

    test('防止 Host 后缀绕过与恶意仿冒域名（防 SSRF / Cookie 窃取）', () {
      // 1. 相似域名仿冒：evilchaoxing.com
      expect(
        ChaoxingClient.isValidSignQrUrl(
          Uri.parse('https://evilchaoxing.com/widget/sign/e?enc=ABC'),
        ),
        isFalse,
      );

      // 2. 伪造连字符域：attack-chaoxing.com
      expect(
        ChaoxingClient.isValidSignQrUrl(
          Uri.parse('https://attack-chaoxing.com/widget/sign/e?enc=ABC'),
        ),
        isFalse,
      );

      // 3. 缺少 enc 签到参数
      expect(
        ChaoxingClient.isValidSignQrUrl(
          Uri.parse('https://mobilelearn.chaoxing.com/widget/sign/e?id=123'),
        ),
        isFalse,
      );

      // 4. 非签到路由
      expect(
        ChaoxingClient.isValidSignQrUrl(
          Uri.parse('https://mobilelearn.chaoxing.com/other/path?enc=ABC'),
        ),
        isFalse,
      );
    });
  });
}
