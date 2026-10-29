import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../services/dorm_electricity_service.dart';

/// 宿舍电费状态与余量卡片
class DormElectricityCard extends StatelessWidget {
  const DormElectricityCard({
    super.key,
    required this.info,
    required this.fetchedAt,
    required this.loading,
    required this.error,
    required this.canFetch,
    required this.onRefresh,
    required this.onLogin,
  });

  final DormElectricity? info;
  final DateTime? fetchedAt;
  final bool loading;
  final String? error;
  final bool canFetch;
  final VoidCallback onRefresh;
  final VoidCallback onLogin;

  String _formatDormTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final title = fetchedAt == null
        ? '宿舍电费 · 未刷新'
        : '宿舍电费 · ${_formatDormTime(fetchedAt!)} 更新';
    final subtitle = info != null
        ? info!.dormAddress
        : canFetch
        ? '点右上角刷新'
        : '登录后可查询照明 / 空调余量';

    return GestureDetector(
      onTap: canFetch ? onRefresh : onLogin,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.redTint,
                  child: Icon(Icons.bolt, color: AppColors.usstRed),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 6),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    tooltip: '刷新电费',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: canFetch ? onRefresh : onLogin,
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
              ],
            ),
            if (info != null) ...<Widget>[
              const SizedBox(height: 12),
              _electricityRow(
                '照明',
                info!.zmKwh,
                info!.zmMoney,
                info!.zmMoneyValue,
              ),
              if (info!.hasAirConditioner) ...<Widget>[
                const SizedBox(height: 6),
                _electricityRow(
                  '空调',
                  info!.ktKwh,
                  info!.ktMoney,
                  info!.ktMoneyValue,
                ),
              ],
            ],
            if (error != null) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.info_outline, size: 13, color: AppColors.usstRed),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      error!.contains('校园网') || error!.contains('登录')
                          ? error!
                          : '$error（请使用校园网访问）',
                      style: const TextStyle(fontSize: 11, color: AppColors.usstRed),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _electricityRow(
    String label,
    String kwh,
    String money,
    double? moneyValue,
  ) {
    final arrears = moneyValue != null && moneyValue < 0;
    final color = arrears ? AppColors.usstRed : AppColors.textPrimary;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            kwh,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        Text(
          money,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        if (arrears)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Text(
              '欠费',
              style: TextStyle(fontSize: 10, color: AppColors.usstRed),
            ),
          ),
      ],
    );
  }
}
