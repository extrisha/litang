import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/chaoxing/chaoxing_client.dart';

/// 学习通扫码签到：把「签到结果」页翻译成状态。
/// 这些 HTML 片段取自 2026-10-28 的真实响应。
void main() {
  test('已签到过的二维码 → 成功（回显原来的签到时间）', () {
    const html = '<html><body><div class="title">签到结果</div>'
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
}
