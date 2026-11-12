import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../data/geo/campus_buildings.dart';
import '../../data/lms/radar_target.dart';

/// 「选定基准点」的结果。
class RadarBaselineChoice {
  const RadarBaselineChoice({required this.mode, this.buildingId});

  final RadarLocationMode mode;
  final String? buildingId;
}

/// 选定基准点弹层（移植参考项目 `RadarRollcallBottomSheetDialog` 的定位部分）。
///
/// 四种模式：自动 / 教师基准点 / 教学楼 / 本机定位；选教学楼时给出全部 22 个
/// 上理基准点。只在内部模式里能打开。
Future<RadarBaselineChoice?> showRadarBaselineSheet(
  BuildContext context, {
  required RadarLocationMode mode,
  String? buildingId,
}) {
  return showModalBottomSheet<RadarBaselineChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) =>
        _RadarBaselineSheet(initialMode: mode, initialBuildingId: buildingId),
  );
}

class _RadarBaselineSheet extends StatefulWidget {
  const _RadarBaselineSheet({
    required this.initialMode,
    this.initialBuildingId,
  });

  final RadarLocationMode initialMode;
  final String? initialBuildingId;

  @override
  State<_RadarBaselineSheet> createState() => _RadarBaselineSheetState();
}

class _RadarBaselineSheetState extends State<_RadarBaselineSheet> {
  late RadarLocationMode _mode = widget.initialMode;
  late String? _buildingId = widget.initialBuildingId;

  static const Map<RadarLocationMode, (String, String)> _descriptions =
      <RadarLocationMode, (String, String)>{
        RadarLocationMode.auto: ('自动', '教师基准点 → 教室匹配教学楼 → 定位吸附最近教学楼 → 本机定位'),
        RadarLocationMode.teacher: ('教师基准点', '平台随点名下发的教师端坐标，误差最小'),
        RadarLocationMode.building: ('教学楼', '用固定的教学楼基准点，适合室内 GPS 飘的教室'),
        RadarLocationMode.device: ('本机定位', '只用手机室内 GPS（正常情况下就是这个）'),
      };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    '选定基准点',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            const Text(
              '只影响雷达签到上报的坐标，不改变签到类型判断。',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final mode in RadarLocationMode.values) _modeRow(mode),
                  if (_mode == RadarLocationMode.building) ...<Widget>[
                    const Divider(height: 24),
                    const Text(
                      '教学楼基准点',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    for (final building in kUsstBuildings)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          building.name,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          building.campus,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        trailing: _buildingId == building.id
                            ? const Icon(
                                Icons.check_circle,
                                color: AppColors.usstRed,
                                size: 20,
                              )
                            : null,
                        onTap: () => setState(() => _buildingId = building.id),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.usstRed,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.of(context).pop(
                  RadarBaselineChoice(mode: _mode, buildingId: _buildingId),
                ),
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeRow(RadarLocationMode mode) {
    final (title, subtitle) = _descriptions[mode]!;
    final selected = _mode == mode;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? AppColors.usstRed : AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        size: 20,
        color: selected ? AppColors.usstRed : AppColors.textMuted,
      ),
      onTap: () => setState(() => _mode = mode),
    );
  }
}
