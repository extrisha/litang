import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/calendar/calendar_service.dart';
import '../data/campus_places.dart';
import '../data/jwc/course_repository.dart';
import '../data/jwc/course_api.dart';
import '../data/jwc/jwgl_schedule.dart';
import '../data/map_focus.dart';
import '../data/models.dart';
import 'login_page.dart';
import 'map_page.dart';

/// 莫兰迪高质感配色方案（柔和浅色背景 + 高对比度深色文本 + 重点色）
class _CourseTheme {
  final Color bg;
  final Color border;
  final Color text;
  final Color subText;
  final Color accent;

  const _CourseTheme({
    required this.bg,
    required this.border,
    required this.text,
    required this.subText,
    required this.accent,
  });
}

const List<_CourseTheme> _coursePalettes = <_CourseTheme>[
  _CourseTheme(
    bg: Color(0xFFFFF1F0), // 上理红/薄樱
    border: Color(0xFFFFCCC7),
    text: Color(0xFFA8071A),
    subText: Color(0xFFCF1322),
    accent: Color(0xFFA31C1C),
  ),
  _CourseTheme(
    bg: Color(0xFFE6F4FF), // 天青蓝
    border: Color(0xFFBAE0FF),
    text: Color(0xFF003EB3),
    subText: Color(0xFF0958D9),
    accent: Color(0xFF1677FF),
  ),
  _CourseTheme(
    bg: Color(0xFFF6FFED), // 青竹绿
    border: Color(0xFFD9F7BE),
    text: Color(0xFF135200),
    subText: Color(0xFF389E0D),
    accent: Color(0xFF52C41A),
  ),
  _CourseTheme(
    bg: Color(0xFFFFF7E6), // 暖杏橙
    border: Color(0xFFFFE7BA),
    text: Color(0xFF873800),
    subText: Color(0xFFD46B08),
    accent: Color(0xFFFA8C16),
  ),
  _CourseTheme(
    bg: Color(0xFFF9F0FF), // 薰衣草紫
    border: Color(0xFFEFDBFF),
    text: Color(0xFF391085),
    subText: Color(0xFF531DAB),
    accent: Color(0xFF722ED1),
  ),
  _CourseTheme(
    bg: Color(0xFFE6FFFB), // 浅湖蓝
    border: Color(0xFFB5F5EC),
    text: Color(0xFF00474F),
    subText: Color(0xFF08979C),
    accent: Color(0xFF13C2C2),
  ),
  _CourseTheme(
    bg: Color(0xFFFFF0F6), // 山茶粉
    border: Color(0xFFFFD6E7),
    text: Color(0xFF780650),
    subText: Color(0xFFC41D7F),
    accent: Color(0xFFEB2F96),
  ),
  _CourseTheme(
    bg: Color(0xFFFEFFE6), // 浅柠黄
    border: Color(0xFFFFFFB8),
    text: Color(0xFF614700),
    subText: Color(0xFFAD8B00),
    accent: Color(0xFFD4B106),
  ),
];

_CourseTheme _themeForCourse(String name) {
  var h = 0;
  for (final code in name.codeUnits) {
    h = (h * 31 + code) & 0x7FFFFFFF;
  }
  return _coursePalettes[h % _coursePalettes.length];
}

/// 「今日」独立课表主页
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  CourseSnapshot? _snapshot;
  bool _loading = false;
  int _selectedWeek = 1;
  bool _showWeekSelector = false;

  static const double _periodWidth = 36.0;
  static const double _headerHeight = 36.0;
  static const List<String> _dayNames = <String>['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    JwglAuth.instance.addListener(_onAuthChanged);
    _initSchedule();
  }

  @override
  void dispose() {
    JwglAuth.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) {
      if (!JwglAuth.instance.isLoggedIn) {
        setState(() => _snapshot = null);
      } else {
        _loadCacheAndRefresh(silent: true);
      }
    }
  }

  Future<void> _initSchedule() async {
    final cached = await CourseRepository.loadCache();
    final curWeek = CalendarService.instance.currentWeek ?? cached?.currentWeek ?? 1;
    if (mounted) {
      setState(() {
        _snapshot = cached;
        _selectedWeek = curWeek;
      });
    }
    if (JwglAuth.instance.isLoggedIn) {
      final fresh = await CourseRepository.isFresh();
      if (!fresh) {
        await _refresh(silent: true);
      }
    }
  }

  Future<void> _loadCacheAndRefresh({bool silent = false}) async {
    final cached = await CourseRepository.loadCache();
    if (mounted && cached != null) {
      setState(() {
        _snapshot = cached;
        _selectedWeek = CalendarService.instance.currentWeek ?? cached.currentWeek ?? _selectedWeek;
      });
    }
    await _refresh(silent: silent);
  }

  Future<void> _refresh({bool silent = false}) async {
    final auth = JwglAuth.instance;
    if (!auth.isLoggedIn) {
      if (!silent) {
        _showToast('请先登录教务系统');
      }
      return;
    }
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final fresh = await CourseRepository.refresh(auth.client!);
      if (mounted) {
        setState(() {
          _snapshot = fresh;
          _selectedWeek = CalendarService.instance.currentWeek ?? fresh.currentWeek ?? _selectedWeek;
        });
        if (!silent) {
          _showToast('课表同步完成');
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        _showToast('课表更新失败，请重试');
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  int get _maxWeek {
    final termMax = CalendarService.instance.currentTerm?.totalWeeks ?? 20;
    var maxW = termMax;
    final courses = _snapshot?.courses ?? const <Course>[];
    for (final c in courses) {
      for (final w in [c.weeks]) {
        if (w != null && w.isNotEmpty && w.last > maxW) {
          maxW = w.last;
        }
      }
    }
    return maxW;
  }

  int get _currentWeek =>
      CalendarService.instance.currentWeek ?? _snapshot?.currentWeek ?? 1;

  DateTime? _dateForDay(int week, int dayIndex) {
    final term = CalendarService.instance.currentTerm;
    if (term == null) return null;
    return term.week1Monday.add(Duration(days: (week - 1) * 7 + dayIndex));
  }

  bool _isToday(int dayIndex) {
    if (_selectedWeek != _currentWeek) return false;
    final now = DateTime.now();
    return (now.weekday - 1) == dayIndex;
  }

  int? _activePeriod() {
    final now = DateTime.now();
    final curM = now.hour * 60 + now.minute;
    for (final p in JwglSchedule.periods) {
      final s = p.start.split(':');
      final e = p.end.split(':');
      final startM = int.parse(s[0]) * 60 + int.parse(s[1]);
      final endM = int.parse(e[0]) * 60 + int.parse(e[1]);
      if (curM >= startM && curM <= endM) {
        return p.period;
      }
    }
    return null;
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _locateCourseOnMap(Course course) {
    final place = placeForRoom(course.room);
    if (place == null) {
      _showToast('未在校园地图找到【${course.room}】对应楼栋');
      return;
    }
    MapFocus.focus(place);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MapPage()),
    );
  }

  void _showCourseDetailModal(Course course) {
    final theme = _themeForCourse(course.name);
    final place = placeForRoom(course.room);
    final activeInThisWeek = course.activeInWeek(_selectedWeek);
    final timeStr = JwglSchedule.rangeOf(course.start, course.span) ?? '';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
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
                _detailTile(
                  icon: Icons.access_time_rounded,
                  title: '上课时间',
                  content: '周${_dayNames[course.day]} 第${course.start + 1}~${course.start + course.span}节 ($timeStr)',
                ),
                _detailTile(
                  icon: Icons.location_on_outlined,
                  title: '教室地点',
                  content: course.room.isEmpty ? '待定' : course.room,
                  subtitle: place != null ? '属于【${place.name}】' : null,
                ),
                if (course.teacher != null && course.teacher!.isNotEmpty)
                  _detailTile(
                    icon: Icons.person_outline,
                    title: '授课教师',
                    content: course.teacher!,
                  ),
                _detailTile(
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
                            Navigator.of(context).pop();
                            _locateCourseOnMap(course);
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

  Widget _detailTile({
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

  @override
  Widget build(BuildContext context) {
    final auth = JwglAuth.instance;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                _appBar(),
                Expanded(
                  child: !auth.isLoggedIn && _snapshot == null
                      ? _unloggedPlaceholder()
                      : _snapshot == null
                          ? _emptyPlaceholder()
                          : _scheduleGrid(),
                ),
              ],
            ),
            // 向下展开的周次选项栏
            if (_showWeekSelector) ...<Widget>[
              Positioned.fill(
                top: 56,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _showWeekSelector = false),
                  child: Container(
                    color: const Color(0x33000000),
                  ),
                ),
              ),
              Positioned(
                top: 56,
                left: 14,
                child: _weekDropdownPanel(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _appBar() {
    final term = CalendarService.instance.termLabel.isNotEmpty
        ? CalendarService.instance.termLabel
        : (_snapshot?.termLabel ?? '本学期');
    final isCur = _selectedWeek == _currentWeek;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      color: Colors.white,
      child: Row(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              InkWell(
                onTap: () => setState(() => _showWeekSelector = !_showWeekSelector),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  child: Row(
                    children: <Widget>[
                      Text(
                        '第$_selectedWeek周${isCur ? ' (本周)' : ''}',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _showWeekSelector
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  term,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          if (!isCur)
            TextButton.icon(
              onPressed: () => setState(() => _selectedWeek = _currentWeek),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.usstRed,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.today, size: 16),
              label: const Text('回到本周', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          IconButton(
            tooltip: '校园地图',
            icon: const Icon(Icons.map_outlined, size: 21, color: AppColors.textPrimary),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const MapPage()),
              );
            },
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: '同步课表',
              icon: const Icon(Icons.refresh, size: 21, color: AppColors.textPrimary),
              onPressed: () => _refresh(),
            ),
        ],
      ),
    );
  }

  Widget _weekDropdownPanel() {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 190,
        constraints: const BoxConstraints(maxHeight: 270),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEEEEE)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x26000000),
              offset: Offset(0, 8),
              blurRadius: 20,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 6),
            shrinkWrap: true,
            itemCount: _maxWeek,
            separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF5F5F5)),
            itemBuilder: (context, index) {
              final week = index + 1;
              final isSelected = week == _selectedWeek;
              final isCur = week == _currentWeek;

              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedWeek = week;
                    _showWeekSelector = false;
                  });
                },
                child: Container(
                  color: isSelected ? const Color(0xFFFFF1F0) : Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: <Widget>[
                      Text(
                        '第$week周',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: isSelected || isCur ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? AppColors.usstRed
                              : AppColors.textPrimary,
                        ),
                      ),
                      if (isCur) ...<Widget>[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDE8E8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '本周',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.usstRed,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (isSelected)
                        const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: AppColors.usstRed,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _unloggedPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.calendar_month_outlined,
                size: 48,
                color: AppColors.usstRed,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '登录教务，一键同步课表',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '自动同步全学期作息、教室楼栋与任课教师\n随时掌握每日日程',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.usstRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final ok = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(builder: (_) => const LoginPage()),
                );
                if (ok == true && mounted) {
                  _loadCacheAndRefresh();
                }
              },
              icon: const Icon(Icons.login, size: 18),
              label: const Text('立即登录教务'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.event_busy_outlined, size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          const Text('暂无课表数据', style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => _refresh(),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重新获取'),
          ),
        ],
      ),
    );
  }

  Widget _scheduleGrid() {
    final activePer = _activePeriod();
    final shown = _snapshot?.courses
            .where((c) => c.activeInWeek(_selectedWeek))
            .toList() ??
        <Course>[];

    // 默认隐藏周末；若检测到周六有课则在右侧展开周六；若周日有课则在周一左侧展开周日
    final hasSaturday = shown.any((c) => c.day == 5);
    final hasSunday = shown.any((c) => c.day == 6);

    final visibleDays = <int>[];
    if (hasSunday) visibleDays.add(6); // 周日置于周一左侧
    visibleDays.addAll(<int>[0, 1, 2, 3, 4]); // 周一至周五
    if (hasSaturday) visibleDays.add(5); // 周六置于周五右侧

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;

        // 单元格横向宽度均分（根据可见星期数 5~7 动态伸缩，充满屏幕）
        final dayWidth = (availableWidth - _periodWidth) / visibleDays.length;

        // 用户要求：让第十一节课与第十二节课的分界线与导航栏齐平！
        // 也就是说，默认视口刚好容纳第 1 至 11 节课，11 节下边线恰好对齐底部导航栏
        final rowHeight = math.max((availableHeight - _headerHeight - 2.0) / 11.0, 42.0);

        // 13 节课全天总高度 + 36dp 底部安全滚动边距，保证下拉滑动能完整看清 19:30 后的晚课（12~13节）
        final totalGridHeight = 13 * rowHeight + 36.0;

        return Column(
          children: <Widget>[
            // 顶部固定星期表头 (吸顶固定，横向与每一列精确对齐)
            Row(
              children: <Widget>[
                Container(
                  width: _periodWidth,
                  height: _headerHeight,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFAFAFA),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFEDEDED)),
                      right: BorderSide(color: Color(0xFFEDEDED), width: 0.6),
                    ),
                  ),
                  child: const Text(
                    '节次',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                for (final dayIndex in visibleDays)
                  _dayHeaderCell(dayIndex, dayWidth),
              ],
            ),
            // 垂直滚动区域：左侧节次列与右侧课程网格同属同一垂直滚动视图，彻底修复节次不同步bug
            Expanded(
              child: RefreshIndicator(
                color: AppColors.usstRed,
                onRefresh: () => _refresh(),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // 左侧节次时间列 (随课表整体上下滚动)
                      _periodNumbersColumn(activePer, rowHeight, totalGridHeight),
                      // 右侧课程网格
                      SizedBox(
                        width: dayWidth * visibleDays.length,
                        height: totalGridHeight,
                        child: Stack(
                          children: <Widget>[
                            // 网格底图
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _GridPainter(
                                  periods: JwglSchedule.periodCount,
                                  activePeriod: activePer,
                                  visibleDays: visibleDays,
                                  isTodayCol: (d) => _isToday(d),
                                  dayWidth: dayWidth,
                                  rowHeight: rowHeight,
                                ),
                              ),
                            ),
                            // 课程色块
                            for (final course in shown)
                              if (visibleDays.contains(course.day))
                                _courseCard(
                                  course,
                                  dayWidth,
                                  rowHeight,
                                  visibleDays.indexOf(course.day),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _dayHeaderCell(int dayIndex, double dayWidth) {
    final isT = _isToday(dayIndex);
    final date = _dateForDay(_selectedWeek, dayIndex);
    final dateStr = date != null ? '${date.month}/${date.day}' : '';

    return Container(
      width: dayWidth,
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isT ? const Color(0xFFFFF2F0) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isT ? AppColors.usstRed : const Color(0xFFEDEDED),
            width: isT ? 2 : 1,
          ),
          right: const BorderSide(color: Color(0xFFF2F2F2), width: 0.5),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            padding: EdgeInsets.symmetric(horizontal: isT ? 6 : 0, vertical: 1),
            decoration: isT
                ? BoxDecoration(
                    color: AppColors.usstRed,
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            child: Text(
              '周${_dayNames[dayIndex]}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isT ? FontWeight.w700 : FontWeight.w600,
                color: isT ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
          if (dateStr.isNotEmpty) ...<Widget>[
            Text(
              dateStr,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isT ? FontWeight.w600 : FontWeight.w400,
                color: isT ? AppColors.usstRed : AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _periodNumbersColumn(int? activePeriod, double rowHeight, double totalHeight) {
    return Container(
      width: _periodWidth,
      height: totalHeight,
      color: const Color(0xFFFAFAFA),
      child: Column(
        children: <Widget>[
          for (var p = 1; p <= JwglSchedule.periodCount; p++)
            _periodCell(p, activePeriod == p, rowHeight),
        ],
      ),
    );
  }

  Widget _periodCell(int period, bool isActive, double rowHeight) {
    final timeStr = JwglSchedule.periodAt(period);
    return Container(
      width: _periodWidth,
      height: rowHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFFF1F0) : const Color(0xFFFAFAFA),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFEDEDED), width: 0.5),
          right: BorderSide(color: Color(0xFFEDEDED), width: 0.6),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
            decoration: isActive
                ? BoxDecoration(
                    color: AppColors.usstRed,
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
            child: Text(
              '$period',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: isActive ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
          if (timeStr != null) ...<Widget>[
            const SizedBox(height: 1),
            Text(
              timeStr.start,
              style: TextStyle(
                fontSize: 7.5,
                color: isActive ? AppColors.usstRed : AppColors.textSecondary,
              ),
            ),
            Text(
              timeStr.end,
              style: TextStyle(
                fontSize: 7.5,
                color: isActive ? AppColors.usstRed : AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _courseCard(Course course, double dayWidth, double rowHeight, int colIndex) {
    final theme = _themeForCourse(course.name);
    final cardHeight = rowHeight * course.span - 3.5;
    final compact = course.span <= 1;

    return Positioned(
      left: colIndex * dayWidth + 1.5,
      top: course.start * rowHeight + 1.5,
      width: dayWidth - 3.0,
      height: cardHeight,
      child: GestureDetector(
        onTap: () {
          unawaited(HapticFeedback.lightImpact());
          _showCourseDetailModal(course);
        },
        onDoubleTap: () {
          unawaited(HapticFeedback.mediumImpact());
          _locateCourseOnMap(course);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3.0, vertical: 3.0),
          decoration: BoxDecoration(
            color: theme.bg,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: theme.border, width: 0.7),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x08000000),
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                course.name,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 9.5 : 10.5,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: theme.text,
                ),
              ),
              if (course.room.isNotEmpty) ...<Widget>[
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.location_on_rounded,
                      size: 8.5,
                      color: theme.subText,
                    ),
                    const SizedBox(width: 1),
                    Expanded(
                      child: Text(
                        course.room,
                        maxLines: compact ? 1 : 2,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 8.5,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                          color: theme.subText,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.periods,
    required this.activePeriod,
    required this.visibleDays,
    required this.isTodayCol,
    required this.dayWidth,
    required this.rowHeight,
  });

  final int periods;
  final int? activePeriod;
  final List<int> visibleDays;
  final bool Function(int dayIndex) isTodayCol;
  final double dayWidth;
  final double rowHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFFEDEDED)
      ..strokeWidth = 0.6;

    // 今天所在的列涂淡淡的高亮背景
    for (var c = 0; c < visibleDays.length; c++) {
      if (isTodayCol(visibleDays[c])) {
        final todayBg = Paint()..color = const Color(0x06A31C1C);
        canvas.drawRect(
          Rect.fromLTWH(c * dayWidth, 0, dayWidth, size.height),
          todayBg,
        );
      }
    }

    // 横向网格线 (13节)
    for (var i = 0; i <= periods; i++) {
      final y = i * rowHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // 纵向网格线
    for (var c = 0; c <= visibleDays.length; c++) {
      final x = c * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.periods != periods ||
        oldDelegate.activePeriod != activePeriod ||
        oldDelegate.visibleDays != visibleDays ||
        oldDelegate.dayWidth != dayWidth ||
        oldDelegate.rowHeight != rowHeight;
  }
}
