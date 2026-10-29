import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../data/chaoxing/chaoxing_client.dart';
import '../../../data/lms/todo_api.dart';
import '../../../services/reminder_service.dart';

/// 待办事项卡片（整合一网畅学待办与学习通作业）
class LifeTodoCard extends StatelessWidget {
  const LifeTodoCard({
    super.key,
    required this.todos,
    required this.cxWorks,
    this.todosError,
    this.cxError,
    required this.onOpenTodo,
    required this.onOpenCxWork,
  });

  final List<LmsTodo> todos;
  final List<ChaoxingWork> cxWorks;
  final String? todosError;
  final String? cxError;
  final void Function(LmsTodo todo) onOpenTodo;
  final void Function(ChaoxingWork work) onOpenCxWork;

  static String cleanCourseName(String raw) {
    return raw
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll(RegExp(r'\(\d{4}-\d{4}-\d\)-.*$'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  static DateTime? parseTaskDeadline(String raw) {
    final s = raw
        .replaceAll('截止时间：', '')
        .replaceAll('截止：', '')
        .replaceAll('/', '-')
        .trim();
    if (s.isEmpty) return null;
    final direct = DateTime.tryParse(s);
    if (direct != null) return direct;

    final md = RegExp(r'^(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})').firstMatch(s);
    if (md != null) {
      final now = DateTime.now();
      final m = int.parse(md.group(1)!);
      final d = int.parse(md.group(2)!);
      final h = int.parse(md.group(3)!);
      final min = int.parse(md.group(4)!);
      return DateTime(now.year, m, d, h, min);
    }

    final dur = ReminderService.parseRemaining(s);
    if (dur != null) {
      return DateTime.now().add(dur);
    }
    return null;
  }

  static String _humanRemaining(Duration diff) {
    if (diff.isNegative) return '已逾期';
    if (diff.inMinutes < 60) return '还有 ${diff.inMinutes} 分钟';
    if (diff.inHours < 24) return '还有 ${diff.inHours} 小时';
    return '还有 ${diff.inDays} 天';
  }

  static String _ddlCountdown(DateTime? deadline) => deadline == null
      ? ''
      : _humanRemaining(deadline.difference(DateTime.now()));

  static Color _urgencyColor(Duration? diff) {
    if (diff == null) return AppColors.textSecondary;
    if (diff.isNegative || diff.inHours < 24) return AppColors.usstRed;
    if (diff.inDays < 3) return const Color(0xFFB8860B);
    return AppColors.textSecondary;
  }

  static Color _ddlColor(DateTime? deadline) =>
      _urgencyColor(deadline?.difference(DateTime.now()));

  @override
  Widget build(BuildContext context) {
    final cxActive = cxWorks.where((w) => !w.finished && !w.expired).length;
    final tronActive = todos.length;
    final total = cxActive + tronActive;

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
                Icons.assignment_outlined,
                size: 18,
                color: AppColors.usstRed,
              ),
              const SizedBox(width: 8),
              const Text(
                '待办事项',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '$total 项',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          _buildUnifiedTodoBody(),
        ],
      ),
    );
  }

  Widget _buildUnifiedTodoBody() {
    final items = <({
      String id,
      String title,
      String course,
      String source,
      DateTime? deadline,
      String deadlineText,
      VoidCallback onTap,
    })>[];

    for (final t in todos) {
      items.add((
        id: 'tron_${t.id}',
        title: t.title,
        course: cleanCourseName(t.courseName),
        source: '一网畅学',
        deadline: t.deadline,
        deadlineText: _ddlCountdown(t.deadline),
        onTap: () => onOpenTodo(t),
      ));
    }

    for (final w in cxWorks) {
      if (w.finished || w.expired) continue;
      final dt = parseTaskDeadline(w.deadline);
      items.add((
        id: 'cx_${w.workId}',
        title: w.title,
        course: cleanCourseName(w.courseName),
        source: '学习通',
        deadline: dt,
        deadlineText: dt != null ? _ddlCountdown(dt) : w.deadline,
        onTap: () => onOpenCxWork(w),
      ));
    }

    items.sort((a, b) {
      if (a.deadline == null && b.deadline == null) return 0;
      if (a.deadline == null) return 1;
      if (b.deadline == null) return -1;
      return a.deadline!.compareTo(b.deadline!);
    });

    if (items.isEmpty) {
      final err = todosError ?? cxError;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            err ?? '暂无待办作业，尽情享受自由时光 ☕',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.only(top: 8),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final item = items[i];
          final isTron = item.source == '一网畅学';
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: item.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8FA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isTron ? const Color(0xFFE8F0FE) : const Color(0xFFFDE8E8),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.source,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: isTron ? const Color(0xFF1967D2) : AppColors.usstRed,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.course,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (item.deadlineText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        item.deadlineText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _ddlColor(item.deadline),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
