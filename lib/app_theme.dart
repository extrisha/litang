import 'package:flutter/material.dart';

/// 上理红白配色。主色为占位的绛红，后续按校徽实际取色微调。
class AppColors {
  static const Color usstRed = Color(0xFFA31C1C);
  static const Color bg = Color(0xFFF6F6F8);
  static const Color card = Colors.white;
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF8A8A8E);
  static const Color redTint = Color(0x1FA31C1C); // 12% 红，用于标签底 / 选中态

  /// 绩点颜色分级（参考 Osu! 评级体系：S 金、A 绿、B 蓝、C 紫、D 红）
  /// - S (≥3.7): 金色，卓越表现
  /// - A (≥3.0): 绿色，优秀良好
  /// - B (≥2.0): 蓝色，稳定中等
  /// - C (≥1.0): 紫色，达标及格
  /// - D (<1.0): 红色，警示/不及格
  static Color gradeColor(double? gpa) {
    if (gpa == null) {
      return const Color(0xFF8A8A8E);
    }
    if (gpa >= 3.7) {
      return const Color(0xFFD48806); // Osu! S 级 金色
    }
    if (gpa >= 3.0) {
      return const Color(0xFF389E0D); // Osu! A 级 翠绿
    }
    if (gpa >= 2.0) {
      return const Color(0xFF1677FF); // Osu! B 级 亮蓝
    }
    if (gpa >= 1.0) {
      return const Color(0xFF722ED1); // Osu! C 级 幽紫
    }
    return const Color(0xFFCF1322); // Osu! D 级 警示红
  }

  /// Osu! Rank 评级字母
  static String gradeRank(double? gpa) {
    if (gpa == null) return '--';
    if (gpa >= 3.7) return 'S';
    if (gpa >= 3.0) return 'A';
    if (gpa >= 2.0) return 'B';
    if (gpa >= 1.0) return 'C';
    return 'D';
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
