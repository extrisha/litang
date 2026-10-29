import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../data/lms/todo_api.dart';

/// 考试安排列表卡片
class LifeExamCard extends StatelessWidget {
  const LifeExamCard({super.key, required this.exams});

  final List<LmsExam> exams;

  @override
  Widget build(BuildContext context) {
    if (exams.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                Icons.event_note_outlined,
                size: 18,
                color: AppColors.usstRed,
              ),
              const SizedBox(width: 8),
              const Text(
                '考试安排',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${exams.length} 场',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          SizedBox(
            height: 150,
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 8),
              itemCount: exams.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _examTile(exams[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _examTile(LmsExam exam) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            exam.courseName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            <String>[
              if (exam.termLabel.isNotEmpty) exam.termLabel,
              exam.timePending ? '时间待公布' : exam.timeText,
              if (exam.location.isNotEmpty) exam.location,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
