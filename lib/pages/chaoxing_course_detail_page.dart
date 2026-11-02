import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/chaoxing/chaoxing_auth.dart';
import '../data/chaoxing/chaoxing_client.dart';
import '../data/chaoxing/chaoxing_course_detail.dart';
import 'chaoxing_content_page.dart';
import 'chaoxing_exam_detail_page.dart';
import 'chaoxing_homework_page.dart';

/// 学习通课程详情（原生页面，先接章节）。
class ChaoxingCourseDetailPage extends StatefulWidget {
  const ChaoxingCourseDetailPage({
    super.key,
    required this.courseName,
    required this.course,
  });

  final String courseName;
  final ChaoxingCourse course;

  @override
  State<ChaoxingCourseDetailPage> createState() =>
      _ChaoxingCourseDetailPageState();
}

class _ChaoxingCourseDetailPageState extends State<ChaoxingCourseDetailPage> {
  List<ChaoxingChapterUnit>? _units;
  // ignore: prefer_final_fields
  List<ChaoxingWork> _homeworks = const <ChaoxingWork>[];
  // ignore: prefer_final_fields
  List<ChaoxingExam> _exams = const <ChaoxingExam>[];
  String? _error;

  /// 三个请求各自失败时留痕。原来它们被 `catch (_) {}` 吞掉、列表留空，
  /// 对应 tab 就显示「暂无作业 / 暂无考试」——把"没取到"说成了"没有"。
  bool _chaptersFailed = false;
  bool _homeworksFailed = false;
  bool _examsFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 重试时必须把 `_units` 清回 null，否则会先显示上一次的空列表而不是转圈
    setState(() {
      _error = null;
      _units = null;
      _chaptersFailed = false;
      _homeworksFailed = false;
      _examsFailed = false;
    });
    try {
      final auth = ChaoxingAuth.instance;
      if (!auth.isLoggedIn) await auth.restore();
      if (!await auth.ensureSession()) {
        setState(() => _error = '学习通登录已失效');
        return;
      }
      final client = auth.client;
      if (client == null) {
        setState(() => _error = '学习通登录已失效');
        return;
      }
      final api = ChaoxingCourseDetailApi(client);
      // 三个请求互不依赖，并发拉，减少白屏时间
      final unitsFuture = api.fetchChapters(widget.course);
      final homeworksFuture = api.fetchHomeworks(
        widget.course,
        withScores: true,
      );
      final examsFuture = api.fetchExams(widget.course);
      List<ChaoxingChapterUnit> units = const <ChaoxingChapterUnit>[];
      List<ChaoxingWork> homeworks = const <ChaoxingWork>[];
      List<ChaoxingExam> exams = const <ChaoxingExam>[];
      var chaptersFailed = false;
      var homeworksFailed = false;
      var examsFailed = false;
      try {
        units = await unitsFuture;
      } catch (e) {
        chaptersFailed = true;
        debugPrint('[chaoxing] 章节拉取失败: $e');
      }
      try {
        homeworks = await homeworksFuture;
      } catch (e) {
        homeworksFailed = true;
        debugPrint('[chaoxing] 作业拉取失败: $e');
      }
      try {
        exams = await examsFuture;
      } catch (e) {
        examsFailed = true;
        debugPrint('[chaoxing] 考试拉取失败: $e');
      }
      if (mounted) {
        setState(() {
          _units = units;
          _homeworks = homeworks;
          _exams = exams;
          _chaptersFailed = chaptersFailed;
          _homeworksFailed = homeworksFailed;
          _examsFailed = examsFailed;
        });
      }
    } catch (e) {
      debugPrint('[chaoxing] 课程详情加载失败: $e');
      if (mounted) setState(() => _error = '学习通数据加载失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.courseName, overflow: TextOverflow.ellipsis),
          bottom: TabBar(
            labelColor: AppColors.usstRed,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.usstRed,
            tabs: <Widget>[
              Tab(
                text:
                    '章节 ${_units?.fold<int>(0, (sum, unit) => sum + unit.chapters.length) ?? ''}'
                        .trim(),
              ),
              Tab(text: '作业 ${_homeworks.length}'),
              Tab(text: '考试 ${_exams.length}'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[_chapterList(), _homeworkList(), _examList()],
        ),
      ),
    );
  }

  /// 空状态 vs 拉取失败：两者绝不能长一样。
  Widget _emptyOrFailed({
    required bool failed,
    required String emptyText,
    required String failedText,
  }) {
    if (!failed) {
      return Center(
        child: Text(
          emptyText,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            failedText,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _chapterList() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _error!,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final units = _units;
    if (units == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (units.isEmpty) {
      return _emptyOrFailed(
        failed: _chaptersFailed,
        emptyText: '暂无章节',
        failedText: '章节拉取失败',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: units.length,
      itemBuilder: (context, i) {
        final unit = units[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExpansionTile(
            initiallyExpanded: i == 0,
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F2F4),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            title: Text(
              unit.title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${unit.chapters.length} 个章节',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
            children: <Widget>[
              for (final chapter in unit.chapters)
                ListTile(
                  dense: true,
                  leading: Icon(
                    chapter.completed
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: chapter.completed
                        ? const Color(0xFF2E9E5B)
                        : const Color(0xFFF0A23B),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChaoxingContentPage(
                        course: widget.course,
                        chapterId: chapter.id,
                        title: chapter.title,
                      ),
                    ),
                  ),
                  title: Row(
                    children: <Widget>[
                      if (chapter.number.isNotEmpty) ...<Widget>[
                        Text(
                          chapter.number,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          chapter.title,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _homeworkList() {
    if (_homeworks.isEmpty) {
      return _emptyOrFailed(
        failed: _homeworksFailed,
        emptyText: '暂无作业',
        failedText: '作业拉取失败',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _homeworks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final work = _homeworks[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChaoxingHomeworkPage(work: work),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  work.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Text(
                      work.score.isEmpty
                          ? work.statusText
                          : '${work.statusText} · ${work.score} 分',
                      style: TextStyle(
                        fontSize: 10,
                        color: work.score.isEmpty
                            ? AppColors.usstRed
                            : const Color(0xFF2E8B57),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      work.deadline,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
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

  Widget _examList() {
    if (_exams.isEmpty) {
      return _emptyOrFailed(
        failed: _examsFailed,
        emptyText: '暂无考试',
        failedText: '考试拉取失败',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _exams.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final exam = _exams[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ChaoxingExamDetailPage(exam: exam, course: widget.course),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.redTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.assignment_outlined,
                    size: 19,
                    color: AppColors.usstRed,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        exam.title,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (exam.remaining.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          exam.remaining,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      exam.status,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.usstRed,
                      ),
                    ),
                    if (exam.score.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        '${exam.score} 分',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
