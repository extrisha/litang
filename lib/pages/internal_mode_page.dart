import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/internal/internal_settings.dart';
import '../data/internal/rollcall_watch_store.dart';
import '../data/lms/radar_target.dart';
import '../services/rollcall_monitor.dart';
import 'internal/radar_baseline_sheet.dart';
import 'internal/widgets/monitor_log_card.dart';
import 'internal/widgets/section_card.dart';

/// 内部模式：签到监控 + 自动雷达签到 + 选定基准点。
///
/// 入口在「我的 → 关于 → 长按检查更新」，普通用户看不到。
class InternalModePage extends StatefulWidget {
  const InternalModePage({super.key});

  @override
  State<InternalModePage> createState() => _InternalModePageState();
}

class _InternalModePageState extends State<InternalModePage> {
  @override
  void initState() {
    super.initState();
    // 进页面时按当前配置对齐一次监控状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RollcallMonitor.instance.syncWithSettings();
    });
  }

  InternalMode get _mode => InternalMode.instance;

  Future<void> _save(InternalSettings next) => _mode.save(next);

  String _modeLabel(InternalSettings settings) {
    switch (settings.radarMode) {
      case RadarLocationMode.auto:
        return '自动（教师点 → 教学楼 → 定位）';
      case RadarLocationMode.teacher:
        return '教师基准点';
      case RadarLocationMode.building:
        final building = settings.building;
        return building == null
            ? '教学楼（未选，按教室名匹配）'
            : '${building.name}（${building.campus}）';
      case RadarLocationMode.device:
        return '本机定位（室内 GPS）';
    }
  }

  String _timeText(DateTime? time) {
    if (time == null) return '还没检查过';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('内部模式'),
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
      ),
      body: ValueListenableBuilder<InternalSettings>(
        valueListenable: _mode.settings,
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              _statusCard(settings),
              const SizedBox(height: 12),
              _monitorCard(settings),
              const SizedBox(height: 12),
              _autoSignCard(settings),
              const SizedBox(height: 12),
              _baselineCard(settings),
              const SizedBox(height: 12),
              MonitorLogCard(lines: RollcallMonitor.instance.log),
              const SizedBox(height: 12),
              _dangerZone(),
            ],
          );
        },
      ),
    );
  }

  Widget _statusCard(InternalSettings settings) {
    return ValueListenableBuilder<RollcallMonitorState>(
      valueListenable: RollcallMonitor.instance.state,
      builder: (context, state, _) {
        final running = state.running && settings.monitor;
        final color = state.lastError != null
            ? AppColors.danger
            : running
            ? AppColors.successText
            : AppColors.textSecondary;
        return SectionCard(
          title: '状态',
          children: <Widget>[
            ListTile(
              dense: true,
              leading: Icon(
                running ? Icons.sensors : Icons.sensors_off,
                color: color,
                size: 20,
              ),
              title: Text(
                state.checking
                    ? '正在检查…'
                    : running
                    ? '监控中${settings.dryRun ? '（演练）' : ''}'
                    : '未在监控',
                style: TextStyle(fontSize: 14, color: color),
              ),
              subtitle: Text(
                '上次检查：${_timeText(state.lastCheckAt)}'
                '${state.lastMessage == null ? '' : ' · ${state.lastMessage}'}'
                '${state.lastError == null ? '' : '\n${state.lastError}'}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              trailing: TextButton(
                onPressed: settings.monitor && !state.checking
                    ? () => RollcallMonitor.instance.checkNow()
                    : null,
                child: const Text('立即检查', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _monitorCard(InternalSettings settings) {
    return SectionCard(
      title: '签到监控',
      children: <Widget>[
        SwitchListTile(
          dense: true,
          value: settings.monitor,
          activeThumbColor: AppColors.usstRed,
          title: const Text('开启监控', style: TextStyle(fontSize: 14)),
          subtitle: const Text(
            '只在 App 前台时轮询；锁屏或切后台会停。',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          onChanged: (value) => _save(settings.copyWith(monitor: value)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            children: <Widget>[
              for (final seconds in InternalSettings.allowedIntervals)
                ChoiceChip(
                  label: Text(
                    '$seconds 秒',
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: settings.intervalSeconds == seconds,
                  selectedColor: AppColors.redTint,
                  onSelected: (_) =>
                      _save(settings.copyWith(intervalSeconds: seconds)),
                ),
            ],
          ),
        ),
        SwitchListTile(
          dense: true,
          value: settings.notify,
          activeThumbColor: AppColors.usstRed,
          title: const Text('本地通知', style: TextStyle(fontSize: 14)),
          subtitle: const Text(
            '发现新签到时弹通知（需要通知权限）。',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          onChanged: (value) => _save(settings.copyWith(notify: value)),
        ),
      ],
    );
  }

  Widget _autoSignCard(InternalSettings settings) {
    return SectionCard(
      title: '自动签到',
      children: <Widget>[
        SwitchListTile(
          dense: true,
          value: settings.autoSign,
          activeThumbColor: AppColors.usstRed,
          title: const Text('自动提交签到', style: TextStyle(fontSize: 14)),
          subtitle: const Text(
            '总开关。雷达/数字口令各自再单独打开；自主签到直接提交；二维码仍需手动扫。',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          onChanged: (value) => _save(settings.copyWith(autoSign: value)),
        ),
        SwitchListTile(
          dense: true,
          value: settings.autoNumber,
          activeThumbColor: AppColors.usstRed,
          title: const Text('自动数字口令', style: TextStyle(fontSize: 14)),
          subtitle: const Text(
            '从点名花名册里读口令（一次请求），读不到就退回通知手动输入。',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          onChanged: settings.autoSign
              ? (value) => _save(settings.copyWith(autoNumber: value))
              : null,
        ),
        SwitchListTile(
          dense: true,
          value: settings.dryRun,
          activeThumbColor: AppColors.usstRed,
          title: const Text('演练模式（只通知不提交）', style: TextStyle(fontSize: 14)),
          subtitle: const Text(
            '建议先开着观察几节课，确认能稳定拿到坐标再关掉。',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          onChanged: settings.autoSign
              ? (value) => _save(settings.copyWith(dryRun: value))
              : null,
        ),
        SwitchListTile(
          dense: true,
          value: settings.waitForMajority,
          activeThumbColor: AppColors.usstRed,
          title: const Text('等签到人数过半再提交', style: TextStyle(fontSize: 14)),
          subtitle: const Text(
            '每轮先读花名册，已签人数超过一半才动手；读不到名单就不提交。',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          onChanged: settings.autoSign
              ? (value) => _save(settings.copyWith(waitForMajority: value))
              : null,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '每个点名只会提交一次；提交失败或结果未知都不会自动重试，'
            '避免消耗服务端的出错次数。',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _baselineCard(InternalSettings settings) {
    return SectionCard(
      title: '雷达基准点',
      children: <Widget>[
        ListTile(
          dense: true,
          leading: const Icon(
            Icons.my_location,
            size: 20,
            color: AppColors.usstRed,
          ),
          title: const Text('选定基准点', style: TextStyle(fontSize: 14)),
          subtitle: Text(
            _modeLabel(settings),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () async {
            final choice = await showRadarBaselineSheet(
              context,
              mode: settings.radarMode,
              buildingId: settings.buildingId,
            );
            if (choice == null) return;
            await _save(
              settings.copyWith(
                radarMode: choice.mode,
                buildingId: choice.buildingId,
              ),
            );
          },
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '教学楼点位来自参考项目的 22 个固定基准点（GCJ-02）。'
            '正常模式的雷达签到不读这里，固定用本机定位。',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _dangerZone() {
    return SectionCard(
      title: '维护',
      children: <Widget>[
        ListTile(
          dense: true,
          title: const Text('清空已处理记录', style: TextStyle(fontSize: 14)),
          subtitle: const Text(
            '清空后，进行中的点名会被当成新的再处理一次。',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          onTap: () async {
            await RollcallWatchStore.instance.clear();
            if (!mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已清空处理记录')));
          },
        ),
        ListTile(
          dense: true,
          title: const Text(
            '关闭内部模式',
            style: TextStyle(fontSize: 14, color: AppColors.danger),
          ),
          subtitle: const Text(
            '同时停止监控、关掉自动签到，入口会隐藏。',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          onTap: () async {
            await _mode.setEnabled(false);
            await RollcallMonitor.instance.stop();
            if (!mounted) return;
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
