import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../data/chaoxing/chaoxing_client.dart';
import '../../../data/lms/rollcall_api.dart';

/// 进行中的签到卡片（支持一网畅学 / 学习通签到展示与触发）
class RollcallCard extends StatelessWidget {
  const RollcallCard({
    super.key,
    required this.rollcalls,
    required this.cxActivities,
    required this.error,
    required this.refreshing,
    required this.onRefresh,
    required this.onRetry,
    required this.onSignRollcall,
    required this.onSignChaoxing,
  });

  final List<Rollcall> rollcalls;
  final List<ChaoxingActivity> cxActivities;
  final String? error;
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback onRetry;
  final void Function(Rollcall rollcall) onSignRollcall;
  final void Function(ChaoxingActivity activity) onSignChaoxing;

  VoidCallback? _signAction(Rollcall rollcall) {
    if (!rollcall.isSignable) {
      return null;
    }
    return () => onSignRollcall(rollcall);
  }

  String _signLabel(Rollcall rollcall) {
    if (rollcall.isSigned) {
      return '已签到';
    }
    if (rollcall.isExpired) {
      return '已结束';
    }
    if (rollcall.isNumberRollcall) {
      return '输入口令';
    }
    if (rollcall.isRadarRollcall) {
      return '雷达签到';
    }
    if (rollcall.isQrRollcall) {
      return '扫码签到';
    }
    return '去签到';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.how_to_reg_outlined,
                size: 18,
                color: AppColors.usstRed,
              ),
              const SizedBox(width: 8),
              const Text(
                '进行中的签到',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (rollcalls.isNotEmpty || cxActivities.isNotEmpty) ...<Widget>[
                Text(
                  '${rollcalls.length + cxActivities.length} 个',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              if (refreshing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                InkWell(
                  onTap: onRefresh,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.refresh, size: 18, color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (error != null && rollcalls.isEmpty && cxActivities.isEmpty)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    error!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                TextButton(onPressed: onRetry, child: const Text('重试')),
              ],
            )
          else if (rollcalls.isEmpty && cxActivities.isEmpty)
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '暂无进行中的签到',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '老师发起签到后，点右上角刷新按钮即可看到',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            )
          else
            Column(
              children: <Widget>[
                for (final rollcall in rollcalls) _buildRollcallTile(rollcall),
                for (final activity in cxActivities) _buildCxActivityTile(activity),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRollcallTile(Rollcall rollcall) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF5FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE3EAFE),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '一网畅学',
              style: TextStyle(fontSize: 10, color: Color(0xFF3B5BDB)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  rollcall.courseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${rollcall.typeLabel}'
                  '${rollcall.timeText.isEmpty ? '' : ' · ${rollcall.timeText}'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: _signAction(rollcall),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 32),
            ),
            child: Text(
              _signLabel(rollcall),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCxActivityTile(ChaoxingActivity activity) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF2F2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.redTint,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '学习通',
              style: TextStyle(fontSize: 10, color: AppColors.usstRed),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  activity.courseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${activity.typeLabel} · ${activity.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => onSignChaoxing(activity),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('去签到', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
