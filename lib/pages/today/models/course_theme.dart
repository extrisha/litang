import 'package:flutter/material.dart';

import '../../../data/models.dart';

/// 课程莫兰迪主题色配置
class CourseTheme {
  const CourseTheme({
    required this.bg,
    required this.border,
    required this.text,
    required this.subText,
    required this.accent,
  });

  final Color bg;
  final Color border;
  final Color text;
  final Color subText;
  final Color accent;
}

const List<CourseTheme> coursePalettes = <CourseTheme>[
  CourseTheme(
    bg: Color(0xFFFFF1F0), // 1. 上理薄樱红
    border: Color(0xFFFFCCC7),
    text: Color(0xFFA8071A),
    subText: Color(0xFFCF1322),
    accent: Color(0xFFA31C1C),
  ),
  CourseTheme(
    bg: Color(0xFFE6F4FF), // 2. 天青蓝
    border: Color(0xFFBAE0FF),
    text: Color(0xFF003EB3),
    subText: Color(0xFF0958D9),
    accent: Color(0xFF1677FF),
  ),
  CourseTheme(
    bg: Color(0xFFF6FFED), // 3. 青竹绿
    border: Color(0xFFD9F7BE),
    text: Color(0xFF135200),
    subText: Color(0xFF389E0D),
    accent: Color(0xFF52C41A),
  ),
  CourseTheme(
    bg: Color(0xFFFFF7E6), // 4. 暖杏橙
    border: Color(0xFFFFE7BA),
    text: Color(0xFF873800),
    subText: Color(0xFFD46B08),
    accent: Color(0xFFFA8C16),
  ),
  CourseTheme(
    bg: Color(0xFFF9F0FF), // 5. 薰衣草紫
    border: Color(0xFFEFDBFF),
    text: Color(0xFF391085),
    subText: Color(0xFF531DAB),
    accent: Color(0xFF722ED1),
  ),
  CourseTheme(
    bg: Color(0xFFE6FFFB), // 6. 浅湖青
    border: Color(0xFFB5F5EC),
    text: Color(0xFF00474F),
    subText: Color(0xFF08979C),
    accent: Color(0xFF13C2C2),
  ),
  CourseTheme(
    bg: Color(0xFFFFF0F6), // 7. 山茶粉
    border: Color(0xFFFFD6E7),
    text: Color(0xFF780650),
    subText: Color(0xFFC41D7F),
    accent: Color(0xFFEB2F96),
  ),
  CourseTheme(
    bg: Color(0xFFFEFFE6), // 8. 浅柠黄
    border: Color(0xFFFFFFB8),
    text: Color(0xFF614700),
    subText: Color(0xFFAD8B00),
    accent: Color(0xFFD4B106),
  ),
  CourseTheme(
    bg: Color(0xFFE6FFED), // 9. 碧水荷绿
    border: Color(0xFFB7EB8F),
    text: Color(0xFF0C6B58),
    subText: Color(0xFF1D9C73),
    accent: Color(0xFF20B2AA),
  ),
  CourseTheme(
    bg: Color(0xFFF0F5FF), // 10. 极光晴蓝
    border: Color(0xFFD6E4FF),
    text: Color(0xFF1D39C4),
    subText: Color(0xFF2F54EB),
    accent: Color(0xFF597EF7),
  ),
  CourseTheme(
    bg: Color(0xFFFFF2E8), // 11. 赤陶赭红
    border: Color(0xFFFFD8BF),
    text: Color(0xFF871400),
    subText: Color(0xFFD4380D),
    accent: Color(0xFFFA541C),
  ),
  CourseTheme(
    bg: Color(0xFFF3E8FF), // 12. 丁香紫
    border: Color(0xFFD8B4FE),
    text: Color(0xFF4C1D95),
    subText: Color(0xFF6B21A8),
    accent: Color(0xFF9333EA),
  ),
  CourseTheme(
    bg: Color(0xFFF4F7E6), // 13. 苔藓绿
    border: Color(0xFFD3E0A3),
    text: Color(0xFF3B5323),
    subText: Color(0xFF4D6E30),
    accent: Color(0xFF6B8E23),
  ),
  CourseTheme(
    bg: Color(0xFFFFF0ED), // 14. 珊瑚粉
    border: Color(0xFFFFD4CC),
    text: Color(0xFF8C2210),
    subText: Color(0xFFC43D27),
    accent: Color(0xFFE25238),
  ),
  CourseTheme(
    bg: Color(0xFFEDF2F7), // 15. 苍暮黛蓝
    border: Color(0xFFCBD5E0),
    text: Color(0xFF1A365D),
    subText: Color(0xFF2B6CB0),
    accent: Color(0xFF3182CE),
  ),
  CourseTheme(
    bg: Color(0xFFFFFBE6), // 16. 晨曦金杏
    border: Color(0xFFFFE58F),
    text: Color(0xFF874D00),
    subText: Color(0xFFD48806),
    accent: Color(0xFFFAAD14),
  ),
];

int nameHash(String name) {
  var h = 0;
  for (final code in name.codeUnits) {
    h = (h * 31 + code) & 0x7FFFFFFF;
  }
  return h;
}

CourseTheme themeForCourse(String name) {
  return coursePalettes[nameHash(name) % coursePalettes.length];
}

/// 同一界面课程颜色分配器：保证当周同屏出现的不同课程颜色尽量不重复
Map<String, CourseTheme> buildCourseThemeMap(List<Course> courses) {
  final distinctNames = <String>[];
  for (final c in courses) {
    if (!distinctNames.contains(c.name)) {
      distinctNames.add(c.name);
    }
  }

  final assignedThemes = <String, CourseTheme>{};
  final usedPaletteIndices = <int>{};

  for (final name in distinctNames) {
    final idealSlot = nameHash(name) % coursePalettes.length;
    var chosenSlot = idealSlot;

    // 若理想色槽已被当周其他课程占用，则线性探测下一个空闲色槽，实现同屏零重复
    if (usedPaletteIndices.contains(chosenSlot) && usedPaletteIndices.length < coursePalettes.length) {
      for (var offset = 1; offset < coursePalettes.length; offset++) {
        final candidate = (idealSlot + offset) % coursePalettes.length;
        if (!usedPaletteIndices.contains(candidate)) {
          chosenSlot = candidate;
          break;
        }
      }
    }

    usedPaletteIndices.add(chosenSlot);
    assignedThemes[name] = coursePalettes[chosenSlot];
  }

  return assignedThemes;
}
