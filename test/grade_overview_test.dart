import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/app_theme.dart';
import 'package:project_usst/data/jwc/grade_api.dart';

const String _detailHtml =
    '<table><tbody>'
    '<tr><td valign="middle">【 平时 】</td><td valign="middle">40%</td><td valign="middle">85&nbsp;</td></tr>'
    '<tr><td valign="middle">【 期末 】</td><td valign="middle">60%</td><td valign="middle">78&nbsp;</td></tr>'
    '<tr><td valign="middle">【 总评 】</td><td valign="middle">&nbsp;</td><td valign="middle">81&nbsp;</td></tr>'
    '</tbody></table>';

Grade _grade(
  String name,
  String term,
  double credit,
  double gpa,
  String score,
  double value,
) {
  return Grade(
    name: name,
    code: 'x',
    termLabel: term,
    credit: credit,
    gradePoint: gpa,
    scoreText: score,
    scoreValue: value,
    courseKind: '学科基础课程',
    teacher: '老师',
    key: 'k',
    kchId: 'kch',
    jxbId: 'jxb',
    xnm: '2026',
    xqm: '3',
  );
}

void main() {
  group('GradeApi.parseDetail', () {
    test('解析平时 / 期末 / 总评', () {
      final items = GradeApi.parseDetail(_detailHtml);
      expect(items.length, 3);
      expect(items[0].name, '平时');
      expect(items[0].ratio, '40%');
      expect(items[0].score, '85');
      expect(items[1].name, '期末');
      expect(items[2].name, '总评');
    });

    test('没有任何分项时返回空列表', () {
      expect(GradeApi.parseDetail('<table><tbody></tbody></table>'), isEmpty);
    });
  });

  group('Grade.detailOf', () {
    test('按关键字找分项', () {
      final grade = _grade(
        '高等数学',
        '2025-2026 第2学期',
        4,
        3.5,
        '88',
        88,
      ).copyWith(details: GradeApi.parseDetail(_detailHtml));
      expect(grade.hasDetail, isTrue);
      expect(grade.detailOf('平时')!.score, '85');
      expect(grade.detailOf('期末')!.score, '78');
      expect(grade.detailOf('不存在的分项'), isNull);
    });
  });

  group('GradeSnapshot 学期筛选', () {
    final snapshot = GradeSnapshot(
      updatedAt: DateTime(2026, 10, 22),
      grades: <Grade>[
        _grade('大学物理', '2025-2026 第2学期', 4, 3.0, '80', 80),
        _grade('高等数学', '2025-2026 第2学期', 4, 4.0, '90', 90),
        _grade('学科导论', '2025-2026 第1学期', 2, 4.0, '92', 92),
        _grade('体育', '2025-2026 第1学期', 1, 2.0, '70', 70),
      ],
    );

    test('学期列表按最新在前排序', () {
      expect(snapshot.terms, <String>['2025-2026 第2学期', '2025-2026 第1学期']);
    });

    test('选中学期只用该学期课程计算绩点', () {
      final summary = snapshot.summaryForTerm('2025-2026 第2学期');
      expect(summary.weightedGpa, closeTo(3.5, 0.0001));
      expect(summary.weightedAverage, closeTo(85.0, 0.0001));
      expect(summary.courseCount, 2);
      expect(summary.totalCredits, closeTo(8.0, 0.0001));
    });

    test('不选学期时是全部课程的总绩点', () {
      final summary = snapshot.summaryForTerm(null);
      // (3*4 + 4*4 + 4*2 + 2*1) / 11 = 3.4545...
      expect(summary.weightedGpa, closeTo((12 + 16 + 8 + 2) / 11, 0.0001));
      expect(summary.totalCredits, closeTo(11.0, 0.0001));
      expect(summary.courseCount, 4);
    });

    test('快照序列化保留分项成绩', () {
      final withDetail = GradeSnapshot(
        updatedAt: DateTime(2026, 10, 22, 8, 0),
        grades: <Grade>[
          _grade(
            '高等数学',
            '2025-2026 第2学期',
            4,
            3.5,
            '88',
            88,
          ).copyWith(details: GradeApi.parseDetail(_detailHtml)),
        ],
      );
      final restored = GradeSnapshot.fromJson(withDetail.toJson());
      expect(restored.grades.length, 1);
      expect(restored.grades.first.details.length, 3);
      expect(restored.grades.first.detailOf('期末')!.score, '78');
    });
  });

  group('AppColors.gradeColor', () {
    test('按绩点区间给颜色（0.5 细分档，莫兰迪低焦虑配色）', () {
      expect(AppColors.gradeColor(4.3), const Color(0xFFC6903D)); // >=4.0 麦芽金
      expect(AppColors.gradeColor(3.7), const Color(0xFFD48235)); // 3.5~3.99 暖金橙
      expect(AppColors.gradeColor(3.2), const Color(0xFF389E0D)); // 3.0~3.49 青竹翠绿
      expect(AppColors.gradeColor(2.6), const Color(0xFF0D828A)); // 2.5~2.99 湖水青碧
      expect(AppColors.gradeColor(2.1), const Color(0xFF2B6CB0)); // 2.0~2.49 静谧雾蓝
      expect(AppColors.gradeColor(1.6), const Color(0xFF7551A6)); // 1.5~1.99 幽兰灰紫
      expect(AppColors.gradeColor(1.2), const Color(0xFFCF1322)); // 1.0~1.49 珊瑚赤红
      expect(AppColors.gradeColor(0.8), const Color(0xFF8C1D24)); // <1.0 赭褐暗红
      expect(AppColors.gradeColor(null), const Color(0xFF8A8A8E));
    });
  });
}
