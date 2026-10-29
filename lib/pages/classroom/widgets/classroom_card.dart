import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../data/jwc/classroom_api.dart';

/// 单个教室状态卡片
class ClassroomCard extends StatelessWidget {
  const ClassroomCard({super.key, required this.room});

  final ClassroomInfo room;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: room.isFree
              ? const Color(0xFFBBF7D0)
              : const Color(0xFFE5E7EB),
          width: room.isFree ? 1 : 0.8,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: room.isFree
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              room.isFree ? Icons.meeting_room_outlined : Icons.lock_clock_outlined,
              size: 20,
              color: room.isFree ? const Color(0xFF16A34A) : AppColors.usstRed,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      room.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        room.building,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (room.isFree)
                  const Text(
                    '当前时段空闲 · 可自习',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF16A34A),
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else
                  Text(
                    '占用：${room.occupiedCourse} (${room.occupiedTeacher}) · ${room.timeRange}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.usstRed,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: room.isFree
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              room.isFree ? '可自习' : '有课',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: room.isFree
                    ? const Color(0xFF15803D)
                    : const Color(0xFFB91C1C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
