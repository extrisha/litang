import 'package:flutter_test/flutter_test.dart';

import '../tools/runtime_acceptance.dart';

void main() {
  test('帧窗口保留实际样本分位数及独立UI和光栅超预算数', () {
    final window = RuntimeFrameWindow();
    for (var i = 1; i <= 20; i++) {
      window.record(i * 1000, i * 2000);
    }
    final result = window.take();
    expect(result['sampledFrames'], 20);
    expect(result['buildP50Us'], 10000);
    expect(result['buildP95Us'], 19000);
    expect(result['rasterP95Us'], 38000);
    expect(result['buildOverBudget'], 4);
    expect(result['rasterOverBudget'], 12);
    expect(window.take()['observedFrames'], 0);
    expect(window.take()['buildP95Us'], 0);
  });

  test('采样有容量边界，溢出有明确计数且下一窗口重新采集', () {
    final window = RuntimeFrameWindow(capacity: 2);
    window.record(10, 20);
    window.record(30, 40);
    window.record(50, 60);
    final result = window.take();
    expect(result['observedFrames'], 3);
    expect(result['sampledFrames'], 2);
    expect(result['buildP95Us'], 30);
    window.record(70, 80);
    expect(window.take()['buildP95Us'], 70);
  });
}
