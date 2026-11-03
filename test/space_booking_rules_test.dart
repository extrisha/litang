import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/jwc/space_booking_rules.dart';

void main() {
  group('SpaceBookingRules', () {
    test('时长换算：最短向上取整、最长向下取整', () {
      expect(SpaceBookingRules.minHoursFromMinutes(60), 1);
      expect(SpaceBookingRules.minHoursFromMinutes(75), 2);
      expect(SpaceBookingRules.minHoursFromMinutes(30), 1);
      expect(SpaceBookingRules.maxHoursFromMinutes(90), 1);
      expect(SpaceBookingRules.maxHoursFromMinutes(120), 2);
      expect(SpaceBookingRules.maxHoursFromMinutes(240), 4);
    });

    test('isPastHour 只影响当天，且整点后 10 分钟才算过期', () {
      final now = DateTime(2026, 11, 3, 10, 5);
      final today = DateTime(2026, 11, 3);
      final tomorrow = DateTime(2026, 11, 4);

      expect(SpaceBookingRules.isPastHour(9, today, now), isTrue);
      expect(SpaceBookingRules.isPastHour(10, today, now), isFalse);
      expect(
        SpaceBookingRules.isPastHour(10, today, DateTime(2026, 11, 3, 10, 10)),
        isTrue,
      );
      expect(SpaceBookingRules.isPastHour(10, tomorrow, now), isFalse);
    });
  });

  group('SpaceSlotSelection', () {
    bool free(int start, int end) => true;

    test('未选中时点一下，选中该整点并自动补足最短时长', () {
      final result = SpaceSlotSelection.tap(
        current: null,
        tappedHour: 10,
        openEndHour: 21,
        minDurationHours: 1,
        maxDurationHours: 4,
        isRangeFree: free,
      );
      expect(result.error, isNull);
      expect(result.selection!.startHour, 10);
      expect(result.selection!.endHour, 11);
      expect(result.selection!.startLabel, '10:00');
      expect(result.selection!.endLabel, '11:00');
    });

    test('再点一次已选中的时段 → 取消选中', () {
      final current = SpaceSlotSelection(startHour: 10, endHour: 12);
      final result = SpaceSlotSelection.tap(
        current: current,
        tappedHour: 11, // 选中范围内任意整点
        openEndHour: 21,
        minDurationHours: 1,
        maxDurationHours: 4,
        isRangeFree: free,
      );
      expect(result.selection, isNull);
      expect(result.error, isNull);
    });

    test('点结束整点向后延长，点空档处另起新选择', () {
      final current = SpaceSlotSelection(startHour: 10, endHour: 11);
      final extended = SpaceSlotSelection.tap(
        current: current,
        tappedHour: 11,
        openEndHour: 21,
        minDurationHours: 1,
        maxDurationHours: 4,
        isRangeFree: free,
      );
      expect(extended.selection!.startHour, 10);
      expect(extended.selection!.endHour, 12);

      final moved = SpaceSlotSelection.tap(
        current: SpaceSlotSelection(startHour: 10, endHour: 12),
        tappedHour: 14,
        openEndHour: 21,
        minDurationHours: 1,
        maxDurationHours: 4,
        isRangeFree: free,
      );
      expect(moved.selection!.startHour, 14);
      expect(moved.selection!.endHour, 15);
    });

    test('最短时长放不下时给出提示而不是选中半截', () {
      final ok = SpaceSlotSelection.tap(
        current: null,
        tappedHour: 19,
        openEndHour: 21,
        minDurationHours: 2,
        maxDurationHours: 4,
        isRangeFree: free,
      );
      expect(ok.selection!.startHour, 19);
      expect(ok.selection!.endHour, 21);

      final bad = SpaceSlotSelection.tap(
        current: null,
        tappedHour: 20,
        openEndHour: 21,
        minDurationHours: 2,
        maxDurationHours: 4,
        isRangeFree: free,
      );
      expect(bad.selection, isNull);
      expect(bad.error, contains('最短预约时长'));
    });

    test('超过最长时长 / 区间被占用时给出提示', () {
      final tooLong = SpaceSlotSelection.tap(
        current: SpaceSlotSelection(startHour: 10, endHour: 12),
        tappedHour: 12,
        openEndHour: 21,
        minDurationHours: 1,
        maxDurationHours: 2,
        isRangeFree: free,
      );
      expect(tooLong.selection, isNull);
      expect(tooLong.error, contains('最多允许 2 小时'));

      final occupied = SpaceSlotSelection.tap(
        current: null,
        tappedHour: 10,
        openEndHour: 21,
        minDurationHours: 2,
        maxDurationHours: 4,
        isRangeFree: (start, end) => false,
      );
      expect(occupied.selection, isNull);
      expect(occupied.error, contains('不可约'));
    });
  });
}
