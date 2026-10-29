import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../classroom_query_page.dart';
import '../../space_booking_page.dart';

/// 校园生活服务快捷入口行（空间预约 + 教室与排课）
class QuickToolsRow extends StatelessWidget {
  const QuickToolsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _quickToolTile(
            context: context,
            icon: Icons.event_seat_outlined,
            title: '空间预约',
            desc: '图书馆 · 自习室座席',
            color: const Color(0xFF1E88E5),
            bgColor: const Color(0xFFE8F3FC),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SpaceBookingPage(),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _quickToolTile(
            context: context,
            icon: Icons.meeting_room_outlined,
            title: '教室与排课',
            desc: '空教室 · 全校课表',
            color: AppColors.usstRed,
            bgColor: const Color(0xFFFDE8E8),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ClassroomQueryPage(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _quickToolTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String desc,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEDEDED), width: 0.8),
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
