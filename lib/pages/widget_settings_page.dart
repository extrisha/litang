import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../app_theme.dart';
import '../data/widget_appearance.dart';
import '../services/widget_sync_service.dart';

/// 桌面小组件外观设置：三种风格 + 不透明度。
///
/// 只写 SharedPreferences 并触发一次 `updateWidget`，真正的绘制在 Android 侧
/// （`WidgetBackground.kt`），这里不碰任何布局像素。
class WidgetSettingsPage extends StatefulWidget {
  const WidgetSettingsPage({super.key});

  @override
  State<WidgetSettingsPage> createState() => _WidgetSettingsPageState();
}

class _WidgetSettingsPageState extends State<WidgetSettingsPage> {
  WidgetAppearance _appearance = WidgetAppearance.defaults;
  bool _loading = true;

  /// 上次天气抓取成功的时间戳（毫秒）与最近一次失败原因。
  int? _weatherSyncedAt;
  String? _weatherError;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var appearance = WidgetAppearance.defaults;
    try {
      final rawStyle = await HomeWidget.getWidgetData<String>('widget_style');
      final rawAlpha = await HomeWidget.getWidgetData<int>('widget_alpha');
      final rawMode = await HomeWidget.getWidgetData<String>('widget_view_mode');
      final rawUpcoming = await HomeWidget.getWidgetData<int>(
        'widget_upcoming_minutes',
      );
      final rawTheme = await HomeWidget.getWidgetData<String>('widget_theme');
      _weatherSyncedAt = await HomeWidget.getWidgetData<int>(
        'weather_synced_at',
      );
      _weatherError = await HomeWidget.getWidgetData<String>(
        'weather_last_error',
      );

      appearance = WidgetAppearance.fromPrefs(
        rawStyle,
        rawAlpha,
        rawViewMode: rawMode,
        rawUpcoming: rawUpcoming,
        rawTheme: rawTheme,
      );
    } catch (_) {
      // 读不到就用默认值（桌面端 / 测试环境没有插件实现）
    }
    if (!mounted) return;
    setState(() {
      _appearance = appearance;
      _loading = false;
    });
  }

  /// 触发一次原生抓取：把「上次成功时间」清零，Provider 的 onUpdate 就会去抓。
  Future<void> _refreshWeatherNow() async {
    setState(() => _refreshing = true);
    try {
      await HomeWidget.saveWidgetData<int>('weather_synced_at', 0);
      await HomeWidget.updateWidget(
        name: WidgetSyncService.androidWidgetProvider,
        androidName: WidgetSyncService.androidWidgetProvider,
      );
    } catch (_) {}
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted) return;
    final syncedAt = await HomeWidget.getWidgetData<int>('weather_synced_at');
    final error = await HomeWidget.getWidgetData<String>('weather_last_error');
    if (!mounted) return;
    setState(() {
      _weatherSyncedAt = syncedAt;
      _weatherError = error;
      _refreshing = false;
    });
  }

  Future<void> _apply(WidgetAppearance next) async {
    setState(() => _appearance = next);
    try {
      await HomeWidget.saveWidgetData<String>(
        'widget_style',
        next.style.name,
      );
      await HomeWidget.saveWidgetData<int>('widget_alpha', next.effectiveAlpha);
      await HomeWidget.saveWidgetData<String>(
        'widget_view_mode',
        next.viewMode == WidgetViewMode.todo ? 'todo' : 'schedule',
      );
      await HomeWidget.saveWidgetData<int>(
        'widget_upcoming_minutes',
        next.effectiveUpcoming,
      );
      await HomeWidget.saveWidgetData<String>('widget_theme', next.theme.name);
      await HomeWidget.updateWidget(
        name: WidgetSyncService.androidWidgetProvider,
        androidName: WidgetSyncService.androidWidgetProvider,
      );
    } catch (_) {
      // 保存失败不回滚 UI：下次进页面会重新从磁盘读
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('桌面小组件'),
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: <Widget>[
                _preview(),
                const SizedBox(height: 16),
                _card(
                  title: '风格',
                  children: <Widget>[
                    for (final style in WidgetStyle.values)
                      _styleTile(style),
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  title: '主题',
                  children: <Widget>[
                    for (final theme in WidgetTheme.values) _themeTile(theme),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Text(
                        '只影响桌面小组件。App 本身保持浅色。',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  title: '不透明度',
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Slider(
                              value: _appearance.effectiveAlpha.toDouble(),
                              min: WidgetAppearance.minAlpha.toDouble(),
                              max: WidgetAppearance.maxAlpha.toDouble(),
                              divisions:
                                  WidgetAppearance.maxAlpha -
                                  WidgetAppearance.minAlpha,
                              label: '${_appearance.effectiveAlpha}%',
                              onChanged: _appearance.style == WidgetStyle.glass
                                  ? (value) => _apply(
                                      _appearance.copyWith(alpha: value.round()),
                                    )
                                  : null,
                            ),
                          ),
                          SizedBox(
                            width: 44,
                            child: Text(
                              '${_appearance.effectiveAlpha}%',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Text(
                        _appearance.style == WidgetStyle.glass
                            ? '越低越透，壁纸越花越难读。实心风格不受这个值影响。'
                            : '当前风格不受不透明度影响。',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  title: '默认显示',
                  children: <Widget>[
                    for (final mode in WidgetViewMode.values)
                      _modeTile(mode),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Text(
                        '小组件右上角的按钮仍可临时切换，切完会记住；这里决定的是打开时的默认值。',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  title: '到点提示',
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Wrap(
                        spacing: 8,
                        children: <Widget>[
                          for (final minutes
                              in WidgetAppearance.upcomingOptions)
                            ChoiceChip(
                              label: Text(
                                minutes == 0 ? '不提示' : '$minutes 分钟',
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected:
                                  _appearance.effectiveUpcoming == minutes,
                              selectedColor: AppColors.redTint,
                              onSelected: (_) => _apply(
                                _appearance.copyWith(upcomingMinutes: minutes),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Text(
                        '上课/下课/跨天的那一刻小组件会自动刷新一次，状态不会停在上一节。'
                        '「距上课」提前量只影响文案，不影响刷新。',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  title: '天气',
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Text(
                        _weatherStatusText(),
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _refreshing ? null : _refreshWeatherNow,
                          icon: _refreshing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh, size: 18),
                          label: Text(_refreshing ? '正在抓取…' : '立即抓取天气'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  title: '说明',
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        '桌面小组件拿不到壁纸做实时模糊，所以「玻璃」是用半透明 + 高光渐变近似出来的。\n'
                        '部分桌面（MIUI、ColorOS 等）会给小组件加自己的白底或裁圆角，透明度看起来会打折扣。\\n'
                        '上课/下课/零点会自动刷新一次，其余时间跟系统 30 分钟的刷新周期走。',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () =>
                        _apply(WidgetAppearance.defaults),
                    child: const Text('恢复默认（磨砂 85%）'),
                  ),
                ),
              ],
            ),
    );
  }

  String _weatherStatusText() {
    final syncedAt = _weatherSyncedAt;
    final buffer = StringBuffer();
    if (syncedAt == null || syncedAt == 0) {
      buffer.write('还没有成功抓取过天气。');
    } else {
      final at = DateTime.fromMillisecondsSinceEpoch(syncedAt);
      String two(int v) => v.toString().padLeft(2, '0');
      buffer.write('上次成功：${two(at.month)}-${two(at.day)} '
          '${two(at.hour)}:${two(at.minute)}');
    }
    final error = _weatherError;
    if (error != null && error.isNotEmpty) {
      buffer.write('\n最近一次失败：$error');
    }
    return buffer.toString();
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _modeTile(WidgetViewMode mode) {
    final selected = _appearance.viewMode == mode;
    final label = mode == WidgetViewMode.todo ? '待办作业' : '今日课表';
    final hint = mode == WidgetViewMode.todo
        ? '打开就看到未交作业与截止时间'
        : '打开就看到今天的课与「进行中」状态';
    return ListTile(
      dense: true,
      leading: Icon(
        mode == WidgetViewMode.todo
            ? Icons.checklist_rounded
            : Icons.calendar_today_rounded,
        size: 20,
        color: selected ? AppColors.usstRed : AppColors.textSecondary,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? AppColors.usstRed : AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        hint,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        size: 20,
        color: selected ? AppColors.usstRed : AppColors.textMuted,
      ),
      onTap: () => _apply(_appearance.copyWith(viewMode: mode)),
    );
  }

  Widget _themeTile(WidgetTheme theme) {
    final selected = _appearance.theme == theme;
    final (label, hint, icon) = switch (theme) {
      WidgetTheme.system => (
        '跟随系统',
        '系统切深色时小组件一起变',
        Icons.brightness_auto_outlined,
      ),
      WidgetTheme.light => (
        '浅色',
        '始终浅色玻璃，白底深字',
        Icons.light_mode_outlined,
      ),
      WidgetTheme.dark => (
        '深色',
        '始终深色玻璃，深底浅字',
        Icons.dark_mode_outlined,
      ),
    };
    return ListTile(
      dense: true,
      leading: Icon(
        icon,
        size: 20,
        color: selected ? AppColors.usstRed : AppColors.textSecondary,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? AppColors.usstRed : AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        hint,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        size: 20,
        color: selected ? AppColors.usstRed : AppColors.textMuted,
      ),
      onTap: () => _apply(_appearance.copyWith(theme: theme)),
    );
  }

  Widget _styleTile(WidgetStyle style) {
    final selected = _appearance.style == style;
    final sample = WidgetAppearance(style: style, alpha: _appearance.alpha);
    return ListTile(
      dense: true,
      leading: _swatch(sample),
      title: Text(
        sample.label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? AppColors.usstRed : AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        sample.description,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        size: 20,
        color: selected ? AppColors.usstRed : AppColors.textMuted,
      ),
      onTap: () => _apply(_appearance.copyWith(style: style)),
    );
  }

  /// 小色块：用和桌面一致的思路（半透明 + 渐变）画一个 40×40 的近似。
  Widget _swatch(WidgetAppearance appearance) {
    final alpha = appearance.effectiveAlpha / 100;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF7FA8D9), Color(0xFF3C5A99)],
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
          color: switch (appearance.style) {
            WidgetStyle.solid => Colors.white,
            WidgetStyle.clear => Colors.white.withValues(alpha: 0.12),
            WidgetStyle.glass => Colors.white.withValues(alpha: alpha),
          },
        ),
      ),
    );
  }

  Widget _preview() {
    final alpha = _appearance.effectiveAlpha / 100;
    return Container(
      height: 132,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        // 假的「花壁纸」，用来看透明度
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFF6D365),
            Color(0xFFFDA085),
            Color(0xFF6A85B6),
          ],
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.5),
            width: 1,
          ),
          gradient: switch (_appearance.style) {
            WidgetStyle.solid => null,
            WidgetStyle.clear => null,
            WidgetStyle.glass => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.white.withValues(alpha: alpha),
                Colors.white.withValues(alpha: alpha * 0.82),
              ],
            ),
          },
          color: switch (_appearance.style) {
            WidgetStyle.solid => Colors.white,
            WidgetStyle.clear => Colors.white.withValues(alpha: 0.10),
            WidgetStyle.glass => null,
          },
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.usstRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '第 9 周',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.usstRed,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '11月14日 周五',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A202C),
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Text(
              '高等数学 (下)   08:00-09:25',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A202C),
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              '卓越楼 405 · 张老师',
              style: TextStyle(fontSize: 10, color: Color(0xFF4A5568)),
            ),
          ],
        ),
      ),
    );
  }
}
