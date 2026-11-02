import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/date_format.dart';

/// 日期展示格式的唯一实现，改动会同时影响 7 个页面的显示。
void main() {
  final t = DateTime(2026, 11, 2, 9, 5);

  test('ymd：补零到 4/2/2 位', () {
    expect(DateFmt.ymd(t), '2026-11-02');
    expect(DateFmt.ymd(DateTime(2026, 1, 2)), '2026-01-02');
  });

  test('md', () {
    expect(DateFmt.md(t), '11-02');
  });

  test('hm', () {
    expect(DateFmt.hm(t), '09:05');
    expect(DateFmt.hm(DateTime(2026, 1, 1, 13, 0)), '13:00');
  });

  test('mdHm（原 4 个页面各自抄的那份）', () {
    expect(DateFmt.mdHm(t), '11-02 09:05');
  });

  test('ymdHm', () {
    expect(DateFmt.ymdHm(t), '2026-11-02 09:05');
  });

  test('mdCn（桌面小组件）', () {
    expect(DateFmt.mdCn(t), '11月02日');
  });
}
