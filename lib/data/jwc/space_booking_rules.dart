import 'dart:math' as math;

/// 空间预约的时间规则（纯函数，便于单元测试）。
///
/// 原先这些计算散在两个页面里，彼此口径不一致：
/// - 时段网格按 `reservationMaxTime / 60` 算上限，预约抽屉却硬夹 `clamp(1, 4)`；
/// - 结束时间用 `num.clamp(sH + 1, openEndH)`，当「开始时间 + 1」超过闭馆时间
///   时 `lower > upper`，`clamp` 直接抛 `ArgumentError`；
/// - 确认条显示的时长取自用户点选的小时数，结束时间却可能被闭馆时间夹短，
///   两者会自相矛盾。
/// 统一收敛到这里，页面只负责展示。
class SpaceBookingRules {
  SpaceBookingRules._();

  /// 最短时长（小时）：不足 1 小时按 1 小时算；75 分钟按 2 小时算，
  /// 宁可多留一点，也不能提交比服务端下限更短的预约。
  static int minHoursFromMinutes(int minutes) =>
      math.max(1, (minutes / 60).ceil());

  /// 最长时长（小时）：向下取整；90 分钟只按 1 小时算，
  /// 避免整点预约超出服务端上限。
  static int maxHoursFromMinutes(int minutes) =>
      math.max(1, (minutes / 60).floor());

  /// 当天 [hour] 点这一整小时是否已经过去。
  ///
  /// 与服务端口径一致：整点后 [graceMinutes] 分钟内仍算可约。
  static bool isPastHour(
    int hour,
    DateTime date,
    DateTime now, {
    int graceMinutes = 10,
  }) {
    if (date.year != now.year ||
        date.month != now.month ||
        date.day != now.day) {
      return false;
    }
    if (hour < now.hour) return true;
    return hour == now.hour && now.minute >= graceMinutes;
  }
}

/// 当前选中的预约区间（整点，包含 [startHour]、不包含 [endHour]）。
///
/// 之前页面只存了两个字符串，选中的判定和“再点一次取消”都散落在点击回调里，
/// 很难保证和申请表单用同一套区间。收成一个不可变对象后，页面、表单、提交
/// 都从它取值。
class SpaceSlotSelection {
  const SpaceSlotSelection({required this.startHour, required this.endHour});

  final int startHour;
  final int endHour;

  int get durationHours => endHour - startHour;

  String get startLabel => labelOf(startHour);

  String get endLabel => labelOf(endHour);

  bool containsHour(int hour) => hour >= startHour && hour < endHour;

  /// `HH:00` 形式的整点标签
  static String labelOf(int hour) => '${hour.toString().padLeft(2, '0')}:00';

  /// 处理一次点击，返回新选择与提示语。
  ///
  /// 规则（与页面提示一致）：
  /// - 点中当前选择范围内的任意整点 → 取消选择；
  /// - 点中当前选择的**结束整点** → 向后延长 1 小时；
  /// - 其余情况（未选择 / 更早 / 与已选区间有空档）→ 以点击处为新起点，
  ///   自动补足最短时长。
  ///
  /// [isRangeFree] 由调用方判断区间内每个整点是否可约（已占用/已过时）。
  static ({SpaceSlotSelection? selection, String? error}) tap({
    required SpaceSlotSelection? current,
    required int tappedHour,
    required int openEndHour,
    required int minDurationHours,
    required int maxDurationHours,
    required bool Function(int startHour, int endHour) isRangeFree,
  }) {
    final minH = math.max(1, minDurationHours);
    final maxH = math.max(minH, maxDurationHours);

    // 再点已选范围内的任意整点 → 取消选中（不必去下面点「重置」）
    if (current != null && current.containsHour(tappedHour)) {
      return (selection: null, error: null);
    }

    // 点中结束整点 → 向后延长 1 小时
    if (current != null && tappedHour == current.endHour) {
      final end = tappedHour + 1;
      if (end > openEndHour) {
        return (selection: null, error: '已超出当天开放时间');
      }
      if (end - current.startHour > maxH) {
        return (selection: null, error: '单次预约最多允许 $maxH 小时');
      }
      if (!isRangeFree(current.startHour, end)) {
        return (selection: null, error: '所选区间包含不可约时段，无法选择');
      }
      return (
        selection: SpaceSlotSelection(
          startHour: current.startHour,
          endHour: end,
        ),
        error: null,
      );
    }

    // 新起点：自动补足最短时长
    final end = tappedHour + minH;
    if (end > openEndHour) {
      return (selection: null, error: '该时段起不足最短预约时长（$minH 小时）');
    }
    if (!isRangeFree(tappedHour, end)) {
      return (selection: null, error: '该时段起连续 $minH 小时内包含不可约时段，请换个开始时间');
    }
    return (
      selection: SpaceSlotSelection(startHour: tappedHour, endHour: end),
      error: null,
    );
  }
}
