import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../data/chaoxing/chaoxing_auth.dart';
import '../../../data/chaoxing/chaoxing_client.dart';
import '../../../data/lms/todo_api.dart';
import '../../chaoxing_course_detail_page.dart';
import '../../course_detail_page.dart';

/// 课程信息横向滑动卡片（支持一网畅学 / 学习通切换）
class LifeCourseCard extends StatelessWidget {
  const LifeCourseCard({
    super.key,
    required this.courseInfos,
    required this.cxCourses,
    required this.coursesLoading,
    required this.coursesError,
    required this.showChaoxingCourses,
    required this.onToggleSource,
    required this.onRetry,
    required this.onLoginChaoxing,
  });

  final List<LmsCourseInfo> courseInfos;
  final List<ChaoxingCourse> cxCourses;
  final bool coursesLoading;
  final String? coursesError;
  final bool showChaoxingCourses;
  final VoidCallback onToggleSource;
  final VoidCallback onRetry;
  final VoidCallback onLoginChaoxing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
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
                Icons.menu_book_outlined,
                size: 18,
                color: AppColors.usstRed,
              ),
              const SizedBox(width: 8),
              const Text(
                '课程信息',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${courseInfos.length} 门',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              _buildCourseSourceSwitch(),
            ],
          ),
          const SizedBox(height: 10),
          if (coursesLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (coursesError != null)
            // 学习通没登录时，「重试」点了也没用，直接给登录入口
            showChaoxingCourses && !ChaoxingAuth.instance.isLoggedIn
                ? _buildChaoxingLoginHint(coursesError!)
                : Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          coursesError!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: onRetry,
                        child: const Text('重试', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  )
          else if (courseInfos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '本学期暂无课程',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            )
          else
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: courseInfos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _buildCourseTile(context, courseInfos[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCourseSourceSwitch() {
    final isCx = showChaoxingCourses;
    final color = isCx ? AppColors.usstRed : const Color(0xFF3B5BDB);
    return GestureDetector(
      onTap: onToggleSource,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isCx ? AppColors.redTint : const Color(0xFFE3EAFE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Image.asset(
              isCx
                  ? 'assets/sources/chaoxing_tab.png'
                  : 'assets/sources/tronclass_tab.png',
              width: 13,
              height: 13,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(width: 4),
            Text(
              isCx ? '学习通' : '一网畅学',
              style: TextStyle(
                fontSize: 10.5,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.swap_horiz, size: 13, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildChaoxingLoginHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          FilledButton(
            onPressed: onLoginChaoxing,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text('登录', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseTile(BuildContext context, LmsCourseInfo course) {
    final color = showChaoxingCourses
        ? const Color(0xFFFDF2F2)
        : const Color(0xFFEFF5FF);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (showChaoxingCourses) {
          final match = cxCourses.where((c) => c.courseId == course.id);
          if (match.isEmpty) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChaoxingCourseDetailPage(
                courseName: course.name,
                course: match.first,
              ),
            ),
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TronCourseDetailPage(
              courseName: course.name,
              courseId: course.id,
            ),
          ),
        );
      },
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              course.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const Spacer(),
            Text(
              course.teacher.isEmpty ? '教师待补充' : course.teacher,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
