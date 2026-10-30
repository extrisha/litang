import 'dart:async';

import 'package:flutter/material.dart';

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
import 'today/models/course_theme.dart';
import 'today/widgets/course_detail_sheet.dart';
import 'today/widgets/schedule_grid.dart';
import 'today/widgets/week_dropdown_panel.dart';

/// 「今日」独立课表主页
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> with WidgetsBindingObserver {
  CourseSnapshot? _snapshot;
  int _selectedWeek = 1;
  bool _showWeekSelector = false;

  static const double _periodWidth = 36.0;
  static const double _headerHeight = 36.0;

  Timer? _minuteTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    JwglAuth.instance.addListener(_onAuthChanged);
    _initSchedule();
    // 每分钟自检，跨节次或跨日无需手动刷新即可实时高亮
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台切回（如第二天早上解锁唤醒）：立即刷新当天和当前节次高亮
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
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
      }
    }
  }

  int get _maxWeek => 20;

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
  }

  void _showCourseDetailModal(Course course) {
    showCourseDetailModal(
      context,
      course: course,
      theme: themeForCourse(course.name),
      activeInThisWeek: course.activeInWeek(_selectedWeek),
      onLocateOnMap: () => _locateCourseOnMap(course),
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

        ],
      ),
    );
  }

  Widget _weekDropdownPanel() {
    return WeekDropdownPanel(
      selectedWeek: _selectedWeek,
      currentWeek: _currentWeek,
      maxWeek: _maxWeek,
      onSelectWeek: (week) {
        setState(() {
          _selectedWeek = week;
          _showWeekSelector = false;
        });
      },
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
    final courses = _snapshot?.courses ?? <Course>[];
    return ScheduleGrid(
      courses: courses,
      selectedWeek: _selectedWeek,
      themeMap: buildCourseThemeMap(courses.where((c) => c.activeInWeek(_selectedWeek)).toList()),
      activePeriod: _activePeriod(),
      isToday: (d) => _isToday(d),
      dateForDay: (w, d) => _dateForDay(w, d),
      onRefresh: () => _refresh(),
      onCourseTap: _showCourseDetailModal,
      onCourseDoubleTap: _locateCourseOnMap,
      periodWidth: _periodWidth,
      headerHeight: _headerHeight,
    );
  }





}
