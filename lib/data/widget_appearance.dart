import 'package:flutter/foundation.dart';

/// 桌面小组件的外观风格。
///
/// 对应 Android 侧 `WidgetBackground.STYLE_*`，两边的字符串必须一致：
/// `glass` / `clear` / `solid`。
enum WidgetStyle {
  /// 半透明磨砂玻璃：自上而下的高光渐变 + 细亮边。
  glass,

  /// 纯透明：只留一圈细边，文字靠阴影撑可读性。
  clear,

  /// 实心：不透明卡片，壁纸完全挡住。
  solid,
}

/// 小组件默认显示的内容。
enum WidgetViewMode {
  /// 今日课表。
  schedule,

  /// 待办作业。
  todo,
}

/// 小组件配色：跟随系统 / 强制浅色 / 强制深色。
enum WidgetTheme {
  system,
  light,
  dark,
}

/// 小组件设置：风格 + 不透明度 + 默认视图 + 提前提示量 + 主题。
@immutable
class WidgetAppearance {
  const WidgetAppearance({
    this.style = WidgetStyle.glass,
    this.alpha = 85,
    this.viewMode = WidgetViewMode.schedule,
    this.upcomingMinutes = 45,
    this.theme = WidgetTheme.system,
  });

  /// 默认：磨砂玻璃 85%。
  static const WidgetAppearance defaults = WidgetAppearance();

  /// 滑杆允许的范围。低于 40% 深色壁纸上深色字会看不清，所以从 40 起。
  static const int minAlpha = 40;
  static const int maxAlpha = 100;

  final WidgetStyle style;

  /// 0–100 的整数百分比。
  final int alpha;

  /// 打开桌面时先显示哪一栏。
  final WidgetViewMode viewMode;

  /// 「距上课 N 分钟」的提前量；0 表示不提示。
  final int upcomingMinutes;

  /// 小组件自身的深浅色。App 本身是浅色的，这个只作用于桌面组件。
  final WidgetTheme theme;

  /// 玻璃风格的有效不透明度；实心/纯透明不用它。
  int get effectiveAlpha => alpha.clamp(minAlpha, maxAlpha);

  /// 提前量允许的档位（分钟）。
  static const List<int> upcomingOptions = <int>[0, 15, 30, 45, 60];

  int get effectiveUpcoming => upcomingMinutes.clamp(0, 120);

  String get label => switch (style) {
    WidgetStyle.glass => '磨砂玻璃',
    WidgetStyle.clear => '纯透明',
    WidgetStyle.solid => '实心卡片',
  };

  String get description => switch (style) {
    WidgetStyle.glass => '半透明 + 顶部高光，能隐约看到壁纸（推荐）',
    WidgetStyle.clear => '只留一圈细边，文字浮在壁纸上，最挑壁纸',
    WidgetStyle.solid => '不透明白底，任何壁纸下都最清楚',
  };

  WidgetAppearance copyWith({
    WidgetStyle? style,
    int? alpha,
    WidgetViewMode? viewMode,
    int? upcomingMinutes,
    WidgetTheme? theme,
  }) => WidgetAppearance(
    style: style ?? this.style,
    alpha: (alpha ?? this.alpha).clamp(minAlpha, maxAlpha),
    viewMode: viewMode ?? this.viewMode,
    upcomingMinutes: (upcomingMinutes ?? this.upcomingMinutes).clamp(0, 120),
    theme: theme ?? this.theme,
  );

  /// 从 SharedPreferences 读到的原始值还原；脏数据退回默认。
  static WidgetAppearance fromPrefs(
    Object? rawStyle,
    Object? rawAlpha, {
    Object? rawViewMode,
    Object? rawUpcoming,
    Object? rawTheme,
  }) {
    final style = switch ('$rawStyle') {
      'clear' => WidgetStyle.clear,
      'solid' => WidgetStyle.solid,
      'glass' => WidgetStyle.glass,
      _ => WidgetStyle.glass,
    };
    final alpha = switch (rawAlpha) {
      final num value => value.toInt(),
      final String value => int.tryParse(value) ?? defaults.alpha,
      _ => defaults.alpha,
    };
    final viewMode = switch ('$rawViewMode') {
      'todo' => WidgetViewMode.todo,
      _ => WidgetViewMode.schedule,
    };
    final theme = switch ('$rawTheme') {
      'light' => WidgetTheme.light,
      'dark' => WidgetTheme.dark,
      _ => WidgetTheme.system,
    };
    final upcoming = switch (rawUpcoming) {
      final num value => value.toInt(),
      final String value => int.tryParse(value) ?? defaults.upcomingMinutes,
      _ => defaults.upcomingMinutes,
    };
    return WidgetAppearance(
      style: style,
      alpha: alpha.clamp(minAlpha, maxAlpha),
      viewMode: viewMode,
      upcomingMinutes: upcoming.clamp(0, 120),
      theme: theme,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetAppearance &&
      other.style == style &&
      other.alpha == alpha &&
      other.viewMode == viewMode &&
      other.upcomingMinutes == upcomingMinutes &&
      other.theme == theme;

  @override
  int get hashCode =>
      Object.hash(style, alpha, viewMode, upcomingMinutes, theme);
}
