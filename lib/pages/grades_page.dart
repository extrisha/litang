import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/jwc/grade_api.dart';
import '../data/jwc/grade_repository.dart';

/// 成绩总览：按学期筛选、绩点配色、平时/期末分项。
class GradesPage extends StatefulWidget {
  const GradesPage({super.key});

  @override
  State<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> {
  GradeSnapshot? _snapshot;
  bool _loading = false;

  /// null = 全部学期。
  String? _term;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final cached = await GradeRepository.loadCache();
    if (!mounted) {
      return;
    }
    setState(() => _snapshot = cached);

    final auth = JwglAuth.instance;
    if (!auth.isLoggedIn) {
      await auth.restore();
      if (!mounted) {
        return;
      }
      setState(() {});
    }
    if (auth.isLoggedIn) {
      await _refresh(silent: true);
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_loading) {
      return;
    }
    final auth = JwglAuth.instance;
    if (!auth.isLoggedIn) {
      if (!silent) {
        _toast('请先登录教务系统');
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final ok = await auth.ensureSession();
      if (!ok) {
        if (mounted) {
          _toast('登录已过期，请回「我的」重新登录');
          setState(() {});
        }
        return;
      }
      final snapshot = await GradeRepository.refresh(auth.client!);
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        if (_term != null && !snapshot.terms.contains(_term)) {
          _term = null;
        }
      });
    } catch (_) {
      if (mounted && !silent) {
        _toast('成绩更新失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('成绩总览'),
        actions: <Widget>[
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: '刷新成绩',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => _refresh(),
            ),
        ],
      ),
      body: snapshot == null ? _empty() : _content(snapshot),
    );
  }

  Widget _content(GradeSnapshot snapshot) {
    final summary = snapshot.summaryForTerm(_term);
    final grades = _term == null
        ? snapshot.grades
        : snapshot.gradesInTerm(_term!);
    final grouped = <String, List<Grade>>{};
    for (final g in grades) {
      final key = g.termLabel.isEmpty ? '未知学期' : g.termLabel;
      grouped.putIfAbsent(key, () => <Grade>[]).add(g);
    }
    final terms = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        _termSelector(snapshot),
        const SizedBox(height: 12),
        _summaryCard(summary, label: _term ?? '全部学期'),
        const SizedBox(height: 8),
        for (final term in terms) ...<Widget>[
          _sectionHeader(term, grouped[term]!.length),
          for (final grade in grouped[term]!) _gradeCard(grade),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 8),
        const Text(
          '分项成绩来自教务「学生分项成绩查询」；带 * 的为接口未返回时按总评推算',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
        Text(
          '更新于 ${_formatTime(snapshot.updatedAt)}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _termSelector(GradeSnapshot snapshot) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.filter_list,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: _term,
                hint: const Text('全部学期'),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('全部学期（总绩点）'),
                  ),
                  for (final term in snapshot.terms)
                    DropdownMenuItem<String?>(value: term, child: Text(term)),
                ],
                onChanged: (value) => setState(() => _term = value),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(GradeSummary summary, {required String label}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${summary.courseCount} 门课 · ${summary.totalCredits.toStringAsFixed(1)} 学分',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      summary.weightedGpa?.toStringAsFixed(2) ?? '--',
                      style: TextStyle(
                        fontSize: 30,
                        height: 1.0,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gradeColor(summary.weightedGpa),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '加权绩点',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      summary.weightedAverage?.toStringAsFixed(1) ?? '--',
                      style: const TextStyle(
                        fontSize: 30,
                        height: 1.0,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '加权平均分',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String term, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(
        children: <Widget>[
          Text(
            term,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Text(
            '$count 门',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradeCard(Grade grade) {
    final gpa = grade.gradePoint;
    final color = AppColors.gradeColor(gpa);
    final breakdown = <Widget>[
      for (final detail in grade.details.take(3))
        if (detail.name != '总评' && detail.score.isNotEmpty)
          _chip(
            '${detail.name} ${detail.score}'
            '${detail.ratio.isEmpty ? '' : '（${detail.ratio}）'}',
            AppColors.textSecondary,
          ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  grade.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${grade.credit == null ? '' : '${grade.credit} 学分'}'
                  '${grade.courseKind.isEmpty ? '' : ' · ${grade.courseKind}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (breakdown.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: breakdown),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                grade.scoreText.isEmpty ? '--' : grade.scoreText,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Text(
                  gpa == null ? '绩点 --' : '绩点 ${gpa.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F4F6),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(text, style: TextStyle(fontSize: 10, color: color)),
  );

  Widget _empty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        JwglAuth.instance.isLoggedIn
            ? (_loading ? '正在加载成绩…' : '还没有成绩数据，点右上角刷新')
            : '登录后自动同步成绩',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    ),
  );

  String _formatTime(DateTime time) {
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    return '$m-$d $h:$min';
  }
}
