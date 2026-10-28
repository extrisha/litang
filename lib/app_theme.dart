import 'package:flutter/material.dart';

/// 上理红白配色。主色为占位的绛红，后续按校徽实际取色微调。
class AppColors {
  static const Color usstRed = Color(0xFFA31C1C);
  static const Color bg = Color(0xFFF6F6F8);
  static const Color card = Colors.white;
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF8A8A8E);
  static const Color redTint = Color(0x1FA31C1C); // 12% 红，用于标签底 / 选中态

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
