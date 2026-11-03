import 'package:flutter/material.dart';

/// 上理红白配色。主色为占位的绛红，后续按校徽实际取色微调。
class AppColors {
  static const Color usstRed = Color(0xFFA31C1C);
  static const Color bg = Color(0xFFF6F6F8);
  static const Color card = Colors.white;
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF8A8A8E);
  static const Color border = Color(0xFFE5E7EB);
  static const Color redTint = Color(0x1FA31C1C); // 12% 红，用于标签底 / 选中态

  // ---------------------------------------------------------------------------
  // 语义色板
  //
  // 页面里原本直接写 `Color(0xFFF3F4F6)` 这类 Tailwind 色值，全项目 493 处、
  // 227 种。这里把**高频且有明确语义**的收成 token；一次性调色板
  // （`today/models/course_theme.dart` 的 16 套课程色）保持原样不动，
  // 它们是数据不是主题。
  // ---------------------------------------------------------------------------

  /// 中性面：浅灰底（列表项、未选中 chip）
  static const Color surfaceMuted = Color(0xFFF3F4F6);

  /// 中性面：更浅的卡片/分组底
  static const Color surfaceSubtle = Color(0xFFF9FAFB);
  static const Color surfaceFaint = Color(0xFFFAFAFA);

  /// 分隔线（比 [border] 更淡）
  static const Color divider = Color(0xFFEDEDED);

  /// 边框：比 [border] 深一档
  static const Color borderStrong = Color(0xFFD1D5DB);

  /// 三级文字（占位、弱提示）
  static const Color textMuted = Color(0xFF9CA3AF);

  /// 成功（已完成 / 已提交 / 通过）
  static const Color success = Color(0xFF2E8B57);
  static const Color successText = Color(0xFF15803D);
  static const Color successBg = Color(0xFFDCFCE7);
  static const Color successBorder = Color(0xFFB7EB8F);
  static const Color successFaint = Color(0xFFF0FDF4);
  static const Color successBorderSoft = Color(0xFFBBF7D0);

  /// 警告（须审核 / 即将截止 / 暂离）
  static const Color warning = Color(0xFFD97706);
  static const Color warningText = Color(0xFF92400E);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color warningFaint = Color(0xFFFFFBEB);
  static const Color warningBorder = Color(0xFFFDE68A);

  /// 危险 / 错误 / 欠费 / 已截止
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerBg = Color(0xFFFEE2E2);
  static const Color dangerBorder = Color(0xFFFECACA);

  /// 信息 / 中性强调（非上理红的入口色）
  static const Color info = Color(0xFF3B5BDB);
  static const Color infoBg = Color(0xFFEFF5FF);

  /// 主色浅底：选中态背景
  static const Color redTintBg = Color(0xFFFEF2F2);

  /// 绩点颜色分级（0.5 一档细分，莫兰迪护眼低焦虑配色）：
  /// - ≥4.0: 麦芽流金（Gold 4.0~4.5）
  /// - ≥3.5: 暖金杏橙（Amber 3.5~3.99）
  /// - ≥3.0: 青竹翠绿（Green 3.0~3.49）
  /// - ≥2.5: 湖水青碧（Teal 2.5~2.99）
  /// - ≥2.0: 静谧雾蓝（Blue 2.0~2.49）
  /// - ≥1.5: 幽兰灰紫（Purple 1.5~1.99）
  /// - ≥1.0: 珊瑚赤红（Red 1.0~1.49）
  /// - <1.0: 赭褐暗红（Deep Crimson）
  static Color gradeColor(double? gpa) {
    if (gpa == null) {
      return const Color(0xFF8A8A8E);
    }
    if (gpa >= 4.0) {
      return const Color(0xFFC6903D); // 4.0~4.5 麦芽流金
    }
    if (gpa >= 3.5) {
      return const Color(0xFFD48235); // 3.5~3.99 暖金杏橙
    }
    if (gpa >= 3.0) {
      return const Color(0xFF389E0D); // 3.0~3.49 青竹翠绿
    }
    if (gpa >= 2.5) {
      return const Color(0xFF0D828A); // 2.5~2.99 湖水青碧
    }
    if (gpa >= 2.0) {
      return const Color(0xFF2B6CB0); // 2.0~2.49 静谧雾蓝
    }
    if (gpa >= 1.5) {
      return const Color(0xFF7551A6); // 1.5~1.99 幽兰灰紫
    }
    if (gpa >= 1.0) {
      return const Color(0xFFCF1322); // 1.0~1.49 珊瑚赤红
    }
    return const Color(0xFF8C1D24); // <1.0 赭褐暗红
  }
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.usstRed)
        .copyWith(primary: AppColors.usstRed);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.redTint,
      ),
    );
  }
}
