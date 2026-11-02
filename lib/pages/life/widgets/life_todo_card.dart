import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../data/chaoxing/chaoxing_client.dart';
import '../../../data/course_name.dart';
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

  /// 保留这个静态入口给 `WidgetSyncService` 用，实现统一在 [CourseName]。
  static String cleanCourseName(String raw) => CourseName.clean(raw);

  static DateTime? parseTaskDeadline(String raw, {DateTime? now}) {
    final current = now ?? DateTime.now();
    var s = raw
        .replaceAll(RegExp(r'^(?:提交)?截[止至](?:时间)?[:：]\s*'), '')
        .replaceAll(RegExp(r'^有效时间[:：]\s*'), '')
        .replaceAll('/', '-')
        .replaceAll('.', '-')
        .trim();
    if (s.isEmpty) return null;
    final direct = DateTime.tryParse(s);
    if (direct != null) {
      // 纯日期（2026-03-05）要按当天 23:59 算，否则截止日当天 00:01 就被判
      // 「已逾期」。带时间的写法（含 T 或 HH:mm）保持不变。
      final hasTime = s.contains('T') || RegExp(r'\d{1,2}:\d{2}').hasMatch(s);
      if (hasTime) return direct;
      return DateTime(direct.year, direct.month, direct.day, 23, 59);
    }

    // YYYY年MM月DD日 [HH:mm]
    final ymdCn = RegExp(
      r'^(\d{4})年(\d{1,2})月(\d{1,2})日(?:\s+(\d{1,2}):(\d{2}))?',
    ).firstMatch(s);
    if (ymdCn != null) {
      final y = int.parse(ymdCn.group(1)!);
      final m = int.parse(ymdCn.group(2)!);
      final d = int.parse(ymdCn.group(3)!);
      final h = ymdCn.group(4) != null ? int.parse(ymdCn.group(4)!) : 23;
      final min = ymdCn.group(5) != null ? int.parse(ymdCn.group(5)!) : 59;
      return DateTime(y, m, d, h, min);
    }

    // MM月DD日 [HH:mm]
    final mdCn = RegExp(r'^(\d{1,2})月(\d{1,2})日(?:\s+(\d{1,2}):(\d{2}))?')
        .firstMatch(s);
    if (mdCn != null) {
      final m = int.parse(mdCn.group(1)!);
      final d = int.parse(mdCn.group(2)!);
      final h = mdCn.group(3) != null ? int.parse(mdCn.group(3)!) : 23;
      final min = mdCn.group(4) != null ? int.parse(mdCn.group(4)!) : 59;
      return _withYearRollover(current, m, d, h, min);
    }

    // YYYY-MM-DD [HH:mm]
    final ymd = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{2}))?')
        .firstMatch(s);
    if (ymd != null) {
      final y = int.parse(ymd.group(1)!);
      final m = int.parse(ymd.group(2)!);
      final d = int.parse(ymd.group(3)!);
      final h = ymd.group(4) != null ? int.parse(ymd.group(4)!) : 23;
      final min = ymd.group(5) != null ? int.parse(ymd.group(5)!) : 59;
      return DateTime(y, m, d, h, min);
    }

    // MM-DD [HH:mm]
    final md = RegExp(r'^(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{2}))?')
        .firstMatch(s);
    if (md != null) {
      final m = int.parse(md.group(1)!);
      final d = int.parse(md.group(2)!);
      final h = md.group(3) != null ? int.parse(md.group(3)!) : 23;
      final min = md.group(4) != null ? int.parse(md.group(4)!) : 59;
      return _withYearRollover(current, m, d, h, min);
    }

    final dur = ReminderService.parseRemaining(s);
    if (dur != null) {
      return current.add(dur);
    }
    return null;
  }

  /// 只有「月日」时按最近的一次理解：12 月看到「1月5日」是明年 1 月 5 日，
  /// 而不是今年已经过去的那个 1 月 5 日（否则会被判成「已逾期」标红）。
  ///
  /// 只回卷过去超过 30 天的日期：上个月的截止时间大概率是真的过期了，
  /// 盲目 +1 年会让早已截止的作业重新变成「还有 300 天」。
  static DateTime _withYearRollover(
    DateTime current,
    int month,
    int day,
    int hour,
    int minute,
  ) {
    final thisYear = DateTime(current.year, month, day, hour, minute);
    if (current.difference(thisYear) > const Duration(days: 30)) {
      return DateTime(current.year + 1, month, day, hour, minute);
    }
    return thisYear;
  }

  static String _humanRemaining(Duration diff) {
    if (diff.isNegative) return '已逾期';
    if (diff.inMinutes < 1) return '即将截止';
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
    final items =
        <
          ({
            String id,
            String title,
            String course,
            String source,
            DateTime? deadline,
            String deadlineText,
            VoidCallback onTap,
          })
        >[];

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
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: isTron
                                    ? const Color(0xFFE8F0FE)
                                    : const Color(0xFFFDE8E8),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.source,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: isTron
                                      ? const Color(0xFF1967D2)
                                      : AppColors.usstRed,
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
