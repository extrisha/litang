import 'package:flutter/material.dart';

import '../../../app_theme.dart';

/// 课表教学周快速切换下拉面板
class WeekDropdownPanel extends StatelessWidget {
  const WeekDropdownPanel({
    super.key,
    required this.selectedWeek,
    required this.currentWeek,
    required this.maxWeek,
    required this.onSelectWeek,
  });

  final int selectedWeek;
  final int? currentWeek;
  final int maxWeek;
  final ValueChanged<int> onSelectWeek;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 190,
        constraints: const BoxConstraints(maxHeight: 270),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEEEEE)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x26000000),
              offset: Offset(0, 8),
              blurRadius: 20,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 6),
            shrinkWrap: true,
            itemCount: maxWeek,
            separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF5F5F5)),
            itemBuilder: (context, index) {
              final week = index + 1;
              final isSelected = week == selectedWeek;
              final isCur = week == currentWeek;

              return InkWell(
                onTap: () => onSelectWeek(week),
                child: Container(
                  color: isSelected ? const Color(0xFFFFF1F0) : Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: <Widget>[
                      Text(
                        '第$week周',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: isSelected || isCur ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? AppColors.usstRed
                              : AppColors.textPrimary,
                        ),
                      ),
                      if (isCur) ...<Widget>[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDE8E8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '本周',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.usstRed,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (isSelected)
                        const Icon(Icons.check, size: 16, color: AppColors.usstRed),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
