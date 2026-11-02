/// 日期/时间格式化。
///
/// 项目里手写的 `toString().padLeft(2, '0')` 拼接曾散落在 7 个页面、30 余处，
/// 且至少 4 个页面各抄了一份语义完全相同的 `_formatTime`（输出 `MM-dd HH:mm`）。
/// 这里作为唯一实现，新代码直接用。
class DateFmt {
  DateFmt._();

  /// `2026-11-02`
  static String ymd(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${_two(dt.month)}-${_two(dt.day)}';

  /// `11-02`
  static String md(DateTime dt) => '${_two(dt.month)}-${_two(dt.day)}';

  /// `09:05`
  static String hm(DateTime dt) => '${_two(dt.hour)}:${_two(dt.minute)}';

  /// `11-02 09:05`
  static String mdHm(DateTime dt) => '${md(dt)} ${hm(dt)}';

  /// `2026-11-02 09:05`
  static String ymdHm(DateTime dt) => '${ymd(dt)} ${hm(dt)}';

  /// `11月02日`（桌面小组件用）
  static String mdCn(DateTime dt) => '${_two(dt.month)}月${_two(dt.day)}日';

  static String _two(int n) => n.toString().padLeft(2, '0');
}
