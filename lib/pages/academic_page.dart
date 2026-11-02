import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/date_format.dart';
import '../data/jwc/academic_api.dart';
import '../data/jwc/academic_repository.dart';

/// 学业情况：培养计划（占位）+ 学分要求完成情况。
class AcademicPage extends StatefulWidget {
  const AcademicPage({super.key});

  @override
  State<AcademicPage> createState() => _AcademicPageState();
}

class _AcademicPageState extends State<AcademicPage> {
  AcademicProgress? _progress;
  bool _loading = false;
  final Map<String, List<AcademicCourse>> _courses =
      <String, List<AcademicCourse>>{};
  final Set<String> _expanded = <String>{};
  final Set<String> _courseLoading = <String>{};
  final Set<String> _courseError = <String>{};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final cached = await AcademicRepository.loadCache();
    if (!mounted) {
      return;
    }
    setState(() => _progress = cached);

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
      final progress = await AcademicRepository.refresh(auth.client!);
      if (!mounted) {
        return;
      }
      setState(() => _progress = progress);
    } catch (_) {
      if (mounted && !silent) {
        _toast('学业情况更新失败，请稍后重试');
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
    final progress = _progress;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('学业情况'),
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
              tooltip: '刷新学业情况',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => _refresh(),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          _planCard(),
          const SizedBox(height: 12),
          if (progress == null)
            _hintCard(
              JwglAuth.instance.isLoggedIn
                  ? (_loading ? '正在同步学业情况…' : '还没有数据，点右上角刷新')
                  : '登录后自动同步学业情况',
            )
          else ...<Widget>[
            _overallCard(progress),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                '按培养方案分类',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            for (final category in progress.categories) _nodeCard(category, 0),
            const SizedBox(height: 8),
            Text(
              '更新于 ${_formatTime(progress.updatedAt)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _planCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          const CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.redTint,
            child: Icon(Icons.description_outlined, color: AppColors.usstRed),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '查看培养计划',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  '各专业培养计划以 PDF 发布，正在整理专业映射，暂以教务网站为准',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: _toastPlan, child: const Text('说明')),
        ],
      ),
    );
  }

  void _toastPlan() {
    _toast('培养计划：教务网站 → 培养计划（https://jwc.usst.edu.cn/pyjh/list.htm）');
  }

  Widget _overallCard(AcademicProgress progress) {
    final percent = (progress.progress * 100).toStringAsFixed(1);
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
              Expanded(
                child: Text(
                  progress.majorName.isEmpty ? '培养方案' : progress.majorName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.usstRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFF0F0F2),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.usstRed,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              _stat('已修学分', progress.earned.toStringAsFixed(1)),
              _stat('要求学分', progress.required.toStringAsFixed(1)),
              _stat('未获得', progress.missing.toStringAsFixed(1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    ),
  );

  Future<void> _toggleCategory(CreditCategory category) async {
    if (category.id.isEmpty) {
      return;
    }
    if (_expanded.contains(category.id)) {
      setState(() => _expanded.remove(category.id));
      return;
    }
    setState(() => _expanded.add(category.id));
    if (_courses.containsKey(category.id) ||
        _courseLoading.contains(category.id)) {
      return;
    }
    final auth = JwglAuth.instance;
    final client = auth.client;
    final xh = auth.studentId ?? '';
    if (client == null || xh.isEmpty) {
      setState(() => _courseError.add(category.id));
      return;
    }
    setState(() {
      _courseLoading.add(category.id);
      _courseError.remove(category.id);
    });
    try {
      final list = await AcademicApi(client).fetchCourses(category.id, xh);
      if (!mounted) {
        return;
      }
      setState(() => _courses[category.id] = list);
    } catch (_) {
      if (mounted) {
        setState(() => _courseError.add(category.id));
      }
    } finally {
      if (mounted) {
        setState(() => _courseLoading.remove(category.id));
      }
    }
  }

  Widget _courseRow(AcademicCourse course) {
    final color = switch (course.status) {
      'passed' => const Color(0xFF2E8B57),
      'inProgress' => AppColors.usstRed,
      'failed' => const Color(0xFFB03A2E),
      _ => AppColors.textSecondary,
    };
    final detail = <String>[
      if (course.term.isNotEmpty) course.term,
      if (course.score.isNotEmpty) '成绩 ${course.score}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  course.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${course.credits.toStringAsFixed(1)} 学分',
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              course.statusLabel,
              style: TextStyle(fontSize: 10, color: color),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleNode(CreditCategory node) {
    setState(() {
      if (!_expanded.add(node.id)) {
        _expanded.remove(node.id);
      }
    });
  }

  Widget _nodeCard(CreditCategory node, int depth) {
    final expanded = _expanded.contains(node.id);
    final isLeaf = node.isLeaf;
    final courses = _courses[node.id];
    final card = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => isLeaf ? _toggleCategory(node) : _toggleNode(node),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    node.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (node.passed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x1F2E8B57),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '已达标',
                      style: TextStyle(fontSize: 10, color: Color(0xFF2E8B57)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: node.progress,
                minHeight: 5,
                backgroundColor: const Color(0xFFF0F0F2),
                valueColor: AlwaysStoppedAnimation<Color>(
                  node.passed ? const Color(0xFF2E8B57) : AppColors.usstRed,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '已修 ${node.earned.toStringAsFixed(1)} / 要求 ${node.required.toStringAsFixed(1)} 学分'
              '${node.missing > 0 ? ' · 还差 ${node.missing.toStringAsFixed(1)}' : ''}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            if (isLeaf && node.id.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                expanded ? '收起课程' : '查看课程明细',
                style: const TextStyle(fontSize: 11, color: AppColors.usstRed),
              ),
            ],
            if (expanded && isLeaf) ...<Widget>[
              const SizedBox(height: 6),
              if (_courseLoading.contains(node.id))
                const LinearProgressIndicator(minHeight: 2)
              else if (_courseError.contains(node.id))
                const Text(
                  '教务暂未返回这个分类的课程明细，稍后再试',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                )
              else if ((courses ?? const <AcademicCourse>[]).isEmpty)
                const Text(
                  '这个分类下暂无课程明细',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                )
              else
                Column(
                  children: <Widget>[
                    for (final course in courses ?? const <AcademicCourse>[])
                      _courseRow(course),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0),
      child: Column(
        children: <Widget>[
          card,
          if (expanded && !isLeaf)
            for (final child in node.children) _nodeCard(child, depth + 1),
        ],
      ),
    );
  }

  Widget _hintCard(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
    ),
  );

  String _formatTime(DateTime time) => DateFmt.mdHm(time);
}
