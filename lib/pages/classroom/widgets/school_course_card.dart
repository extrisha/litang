import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../data/jwc/classroom_api.dart';

/// 全校排课结果卡片
class SchoolCourseCard extends StatelessWidget {
  const SchoolCourseCard({
    super.key,
    required this.course,
    required this.currentWeek,
  });

  final SchoolCourse course;
  final int currentWeek;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 顶部：课程名 + 本研标签 + 课程类型
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  course.courseName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 本研标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: course.isGraduate
                      ? const Color(0xFFF3E8FF)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  course.isGraduate ? '研究生' : '本科',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: course.isGraduate
                        ? const Color(0xFF7E22CE)
                        : const Color(0xFF1D4ED8),
                  ),
                ),
              ),
              if (course.courseType.isNotEmpty) ...<Widget>[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F4F5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    course.courseType,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF52525B),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // 教师与学院
          Row(
            children: <Widget>[
              const Icon(Icons.person_outline, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                course.teacherDisplay,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              if (course.college.isNotEmpty) ...<Widget>[
                const Icon(Icons.apartment_outlined, size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    course.college,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),

          // 学分与班级名
          Row(
            children: <Widget>[
              if (course.creditHoursDisplay.isNotEmpty) ...<Widget>[
                const Icon(Icons.credit_card_outlined, size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  course.creditHoursDisplay,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  course.className.isNotEmpty
                      ? course.className
                      : (course.classCode.isNotEmpty ? '班级：${course.classCode}' : ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 排课时段明细框
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB), width: 0.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: course.slots.map((slot) {
                final isThisWeek = slot.isActiveInWeek(currentWeek);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: <Widget>[
                      // 星期与节次
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFE5E7EB), width: 0.6),
                        ),
                        child: Text(
                          '${slot.dayOfWeekName} ${slot.sectionDesc}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 上课地点
                      const Icon(Icons.place_outlined, size: 13, color: AppColors.usstRed),
                      const SizedBox(width: 2),
                      Text(
                        slot.classroom.isNotEmpty ? slot.classroom : '待定',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 周次区间
                      Text(
                        '(${slot.weeksText.isNotEmpty ? slot.weeksText : "${slot.startWeek}-${slot.endWeek}"}周)',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),

                      // 本周有课徽章
                      if (isThisWeek)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '本周有课',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF15803D),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
