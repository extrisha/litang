import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/course_name.dart';
import 'package:project_usst/pages/life/widgets/life_todo_card.dart';

void main() {
  group('CourseName.clean', () {
    test('全角括号转半角并去掉学期后缀', () {
      expect(CourseName.clean('高等数学（1）(2026-2027-1)-李四'), '高等数学(1)');
    });

    test('保留课程本身的分册编号', () {
      // (1)/(2) 是两门不同的课，合并会让课表定位错到另一门课上
      expect(CourseName.clean('大学物理(2)'), '大学物理(2)');
      expect(CourseName.clean('大学物理(1)'), isNot(CourseName.clean('大学物理(2)')));
    });

    test('压缩所有空白', () {
      expect(CourseName.clean('  形势 与\n政策  '), '形势与政策');
    });

    test('空值安全', () {
      expect(CourseName.clean(''), '');
      expect(CourseName.clean('   '), '');
    });

    test('学习通与教务的同一门课归一化后一致', () {
      expect(
        CourseName.clean('高等数学（1）'),
        CourseName.clean('高等数学(1)(2026-2027-1)'),
      );
    });
  });

  group('LifeTodoCard.cleanCourseName', () {
    test('与 CourseName.clean 保持一致（避免两份实现漂移）', () {
      const samples = <String>[
        '高等数学（1）(2026-2027-1)-李四',
        '大学物理(2)',
        '  形势 与 政策 ',
      ];
      for (final raw in samples) {
        expect(LifeTodoCard.cleanCourseName(raw), CourseName.clean(raw));
      }
    });
  });

  group('LifeTodoCard.parseTaskDeadline', () {
    test('完整日期时间', () {
      expect(
        LifeTodoCard.parseTaskDeadline('2026-12-31 23:59'),
        DateTime(2026, 12, 31, 23, 59),
      );
    });

    test('中文日期', () {
      expect(
        LifeTodoCard.parseTaskDeadline('2026年3月5日 08:00'),
        DateTime(2026, 3, 5, 8, 0),
      );
    });

    test('只给日期时默认当天 23:59（截止日当天仍可提交）', () {
      expect(
        LifeTodoCard.parseTaskDeadline('2026-03-05'),
        DateTime(2026, 3, 5, 23, 59),
      );
    });

    test('只有月日且已过去超过 30 天时回卷到明年', () {
      // 12 月看到的「1月5日」是明年 1 月 5 日，不是今年已经过去的那个
      expect(
        LifeTodoCard.parseTaskDeadline(
          '1月5日 10:00',
          now: DateTime(2026, 12, 20),
        ),
        DateTime(2027, 1, 5, 10, 0),
      );
    });

    test('只有月日时不做无谓回卷：上个月的截止时间保持今年', () {
      // 早就该交的作业不能被 +1 年变成「还有 300 天」
      expect(
        LifeTodoCard.parseTaskDeadline(
          '10月15日 10:00',
          now: DateTime(2026, 11, 2),
        ),
        DateTime(2026, 10, 15, 10, 0),
      );
    });

    test('同年内的未来日期不回卷', () {
      expect(
        LifeTodoCard.parseTaskDeadline(
          '1月20日 10:00',
          now: DateTime(2027, 1, 5),
        ),
        DateTime(2027, 1, 20, 10, 0),
      );
    });

    test('认不出日期时返回 null', () {
      expect(LifeTodoCard.parseTaskDeadline(''), isNull);
      expect(LifeTodoCard.parseTaskDeadline('请按时提交'), isNull);
    });
  });
}
