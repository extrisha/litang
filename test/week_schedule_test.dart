import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/jwc/jwgl_schedule.dart';
import 'package:project_usst/data/models.dart';

void main() {
  group('parseCourseWeeks', () {
    test('连续周次', () {
      final weeks = parseCourseWeeks('3-18周');
      expect(weeks, isNotNull);
      expect(weeks!.first, 3);
      expect(weeks.last, 18);
      expect(weeks.length, 16);
    });

    test('单周', () {
      final weeks = parseCourseWeeks('1-16周(单)');
      expect(weeks, isNotNull);
      expect(weeks!.every((w) => w.isOdd), isTrue);
      expect(weeks.length, 8);
    });

    test('双周', () {
      final weeks = parseCourseWeeks('2-16周(双)');
      expect(weeks, isNotNull);
      expect(weeks!.every((w) => w.isEven), isTrue);
    });

    test('多段周次', () {
      final weeks = parseCourseWeeks('6-9周,14-17周');
      expect(weeks, isNotNull);
      expect(weeks!.length, 8);
      expect(weeks, contains(7));
      expect(weeks, contains(15));
    });

    test('空文本返回 null', () {
      expect(parseCourseWeeks(''), isNull);
    });
  });

  group('Course.activeInWeek', () {
    const course = Course(
      name: '高等数学',
      day: 0,
      start: 0,
      span: 2,
      room: '一教146',
      weeks: <int>[3, 4, 5],
    );

    test('在周次范围内显示', () {
      expect(course.activeInWeek(4), isTrue);
    });

    test('不在周次范围不显示', () {
      expect(course.activeInWeek(2), isFalse);
      expect(course.activeInWeek(6), isFalse);
    });

    test('没有周次信息时每周都显示', () {
      const everyWeek = Course(
        name: '讲座',
        day: 1,
        start: 2,
        span: 2,
        room: '三教',
      );
      expect(everyWeek.activeInWeek(1), isTrue);
      expect(everyWeek.activeInWeek(18), isTrue);
    });
  });

  group('JwglSchedule', () {
    test('节次时间区间', () {
      expect(JwglSchedule.rangeOf(0, 2), '08:00-09:25');
      expect(JwglSchedule.rangeOf(2, 3), '09:45-11:55');
      expect(JwglSchedule.rangeOf(10, 3), '18:00-20:10');
    });

    test('13 节全部覆盖，每节 40 分钟', () {
      expect(JwglSchedule.periodCount, 13);
      for (var p = 1; p <= JwglSchedule.periodCount; p++) {
        expect(JwglSchedule.timeOfPeriod(p), isNotNull);
      }
      expect(JwglSchedule.timeOfPeriod(1), '08:00-08:40');
      expect(JwglSchedule.timeOfPeriod(5), '11:15-11:55');
      expect(JwglSchedule.timeOfPeriod(6), '13:00-13:40');
      expect(JwglSchedule.timeOfPeriod(13), '19:30-20:10');
      expect(JwglSchedule.sessionOf(1), '上午');
      expect(JwglSchedule.sessionOf(6), '下午');
      expect(JwglSchedule.sessionOf(11), '晚上');
      expect(JwglSchedule.rangeOf(1, 2), '08:45-10:25');
    });

    test('给 Android 小组件的作息格式（原生层按这个解析）', () {
      final strings = JwglSchedule.periodStrings;
      expect(strings.length, 13);
      for (final item in strings) {
        expect(item, matches(RegExp(r'^\d{2}:\d{2}-\d{2}:\d{2}$')));
        final parts = item.split('-');
        expect(parts[0].compareTo(parts[1]), lessThan(0));
      }
      expect(strings.first, '08:00-08:40');
      expect(strings.last, '19:30-20:10');
      // 和主课表必须完全一致：原生层就是拿这份去算「进行中 / 距上课」
      for (var i = 0; i < strings.length; i++) {
        final p = JwglSchedule.periods[i];
        expect(strings[i], '${p.start}-${p.end}');
      }
    });
  });

  // 原 `CourseWeekTable` 组已随该组件删除：
  // 它只被测试引用、没有任何页面使用，实际渲染逻辑由
  // `test/schedule_grid_test.dart` 覆盖。`Course.activeInWeek` 的过滤语义
  // 上面已有独立用例，无需通过组件间接测。
}
