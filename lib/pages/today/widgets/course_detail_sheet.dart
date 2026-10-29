import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../data/campus_places.dart';
import '../../../data/jwc/jwgl_schedule.dart';
import '../../../data/models.dart';
import '../models/course_theme.dart';

/// 课程详情弹窗
void showCourseDetailModal(
  BuildContext context, {
  required Course course,
  required CourseTheme theme,
  required bool activeInThisWeek,
  required VoidCallback onLocateOnMap,
}) {
  const dayNames = <String>['一', '二', '三', '四', '五', '六', '日'];
  final place = placeForRoom(course.room);
  final timeStr = JwglSchedule.rangeOf(course.start, course.span) ?? '';

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (modalContext) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: theme.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      course.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (activeInThisWeek)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.bg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: theme.border),
                      ),
                      child: Text(
                        '本周有课',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.subText,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _buildDetailTile(
                icon: Icons.access_time_rounded,
                title: '上课时间',
                content: '周${dayNames[course.day]} 第${course.start + 1}~${course.start + course.span}节 ($timeStr)',
              ),
              _buildDetailTile(
                icon: Icons.location_on_outlined,
                title: '教室地点',
                content: course.room.isEmpty ? '待定' : course.room,
                subtitle: place != null ? '属于【${place.name}】' : null,
              ),
              if (course.teacher != null && course.teacher!.isNotEmpty)
                _buildDetailTile(
                  icon: Icons.person_outline,
                  title: '授课教师',
                  content: course.teacher!,
                ),
              _buildDetailTile(
                icon: Icons.date_range_outlined,
                title: '周次安排',
                content: course.weeksText.isNotEmpty ? course.weeksText : '全学期',
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  if (place != null || course.room.isNotEmpty)
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.usstRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(modalContext).pop();
                          onLocateOnMap();
                        },
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text('在地图中定位教室'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _buildDetailTile({
  required IconData icon,
  required String title,
  required String content,
  String? subtitle,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                content,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.usstRed,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
