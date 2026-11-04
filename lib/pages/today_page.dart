import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

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

  /// 上一次刷新高亮时的时间状态。
  ///
  /// 定时器的目的是「跨节次/跨日自动更新高亮」，但它原来每分钟无条件
  /// `setState(() {})`——一天白重建 1440 次整张课表（含主题色映射和每张卡片）。
  /// 现在只有「当前节次」或「日期」真的变了才重建，一天约 30 次。
  int? _lastActivePeriod;
  int _lastDayStamp = 0;

  /// 手动同步进行中：用于显示顶部细进度线
  bool _syncing = false;

  /// 最近一次同步是否失败（包含静默同步），用于区分「没课」和「取不到」
  bool _syncFailed = false;

  /// 主题色映射缓存：按**周次**分桶。
  ///
  /// 左右滑动时相邻两页会同时构建，若只缓存「当前周」这一格，两页会互相把
  /// 缓存挤掉、每帧重算两次 `buildCourseThemeMap`（内部有 O(n²) 的 contains）。
  /// 快照换了就整表清空，最多也就 20 项。
  CourseSnapshot? _themeSnapshot;
  final Map<int, Map<String, CourseTheme>> _themeByWeek =
      <int, Map<String, CourseTheme>>{};

  /// 周次翻页控制器。第一帧就用 `_selectedWeek` 建，避免加载缓存后页面
  /// 还停在第 1 周、而顶栏已经显示第 8 周。
  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    JwglAuth.instance.addListener(_onAuthChanged);
    _initSchedule();
    // 每分钟自检，跨节次或跨日无需手动刷新即可实时高亮
    _lastActivePeriod = _activePeriod();
    _lastDayStamp = _dayStamp(DateTime.now());
    _minuteTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _tickClock(),
    );
  }

  static int _dayStamp(DateTime t) => t.year * 10000 + t.month * 100 + t.day;

  void _tickClock() {
    if (!mounted) return;
    final now = DateTime.now();
    final period = _activePeriod();
    final stamp = _dayStamp(now);
    // 什么都没变就不重建，避免无谓的整页刷新
    if (period == _lastActivePeriod && stamp == _lastDayStamp) return;
    _lastActivePeriod = period;
    _lastDayStamp = stamp;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台切回（如第二天早上解锁唤醒）：立即刷新当天和当前节次高亮
    if (state == AppLifecycleState.resumed && mounted) {
      _lastActivePeriod = _activePeriod();
      _lastDayStamp = _dayStamp(DateTime.now());
      setState(() {});
    }
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    _pageController?.dispose();
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
    final curWeek =
        CalendarService.instance.currentWeek ?? cached?.currentWeek ?? 1;
    if (mounted) {
      setState(() {
        _snapshot = cached;
        _selectedWeek = curWeek;
      });
      // 缓存里的「当前周」可能不是第 1 周：把翻页视图对齐过去
      _syncPageToWeek(curWeek);
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
      final week =
          CalendarService.instance.currentWeek ??
          cached.currentWeek ??
          _selectedWeek;
      setState(() {
        _snapshot = cached;
        _selectedWeek = week;
      });
      _syncPageToWeek(week);
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
    // 手动刷新时给一条细进度线：原来这里是两个空的 `if (!silent) {}`，
    // 点完按钮到 toast 出现之间界面毫无反应。
    if (!silent && mounted) {
      setState(() => _syncing = true);
    }
    try {
      final fresh = await CourseRepository.refresh(auth.client!);
      if (mounted) {
        setState(() {
          _snapshot = fresh;
          _selectedWeek =
              CalendarService.instance.currentWeek ??
              fresh.currentWeek ??
              _selectedWeek;
          _syncFailed = false;
          _syncing = false;
        });
        if (!silent) {
          _showToast('课表同步完成');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncFailed = true;
          _syncing = false;
        });
        if (!silent) {
          _showToast('课表更新失败，请重试');
        }
      }
    }
  }

  int get _maxWeek => 20;

  /// 切换周次的唯一入口（下拉面板、「回到本周」按钮都走这里）。
  /// 左右滑动不经过它——拖拽由 PageView 自己处理，停下后回调 `_onPageChanged`。
  void _goWeek(int week) {
    if (week < 1 || week > _maxWeek || week == _selectedWeek) return;
    final distance = (week - _selectedWeek).abs();
    HapticFeedback.selectionClick();
    setState(() => _selectedWeek = week);
    // 相邻周平滑滑过去；从面板直接跳很远时用跳转，避免滚过中间每一页
    _syncPageToWeek(week, animate: distance == 1);
  }

  PageController get _page =>
      _pageController ??= PageController(initialPage: _selectedWeek - 1);

  /// 让翻页视图对齐到指定周（controller 还没挂载时直接跳过）。
  void _syncPageToWeek(int week, {bool animate = false}) {
    final target = (week - 1).clamp(0, _maxWeek - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _pageController;
      if (controller == null || !controller.hasClients) return;
      final current = controller.page?.round() ?? target;
      if (current == target) return;
      if (animate) {
        controller.animateToPage(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        controller.jumpToPage(target);
      }
    });
  }

  /// 拖拽翻页停下后，把顶栏与状态切到目标周。
  void _onPageChanged(int index) {
    final week = index + 1;
    if (week == _selectedWeek) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedWeek = week);
  }

  int get _currentWeek =>
      CalendarService.instance.currentWeek ?? _snapshot?.currentWeek ?? 1;

  DateTime? _dateForDay(int week, int dayIndex) {
    final term = CalendarService.instance.currentTerm;
    if (term == null) return null;
    return term.week1Monday.add(Duration(days: (week - 1) * 7 + dayIndex));
  }

  bool _isToday(int dayIndex) {
    // 是否"本周"由调用方（表头的 displayedWeek / 页的 isCurrentWeek）判断，
    // 这里只管"今天星期几"。带上 _selectedWeek 判断的话，翻页过渡期间
    // 旧页会因为 _selectedWeek 已经变了而突然失去今天高亮。
    final now = DateTime.now();
    return (now.weekday - 1) == dayIndex;
  }

  int? _activePeriod() {
    // 只有正在看「本周」时才有"当前节次"概念。
    // 原来不判这一条，加上翻页后每一周都会被画上那条红色高亮。
    if (_selectedWeek != _currentWeek) return null;
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
    if (!kMapFeatureEnabled) {
      _showToast('校园地图升级维护中，暂未开放');
      return;
    }
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
                // 手动同步时的细进度线（原来点击后到 toast 出现之间毫无反馈）
                if (_syncing)
                  const LinearProgressIndicator(
                    minHeight: 2,
                    color: AppColors.usstRed,
                    backgroundColor: Color(0xFFF5F5F5),
                  ),
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
                  child: Container(color: const Color(0x33000000)),
                ),
              ),
              Positioned(top: 56, left: 14, child: _weekDropdownPanel()),
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
                onTap: () =>
                    setState(() => _showWeekSelector = !_showWeekSelector),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 2,
                    horizontal: 4,
                  ),
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
              onPressed: () => _goWeek(_currentWeek),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.usstRed,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.today, size: 16),
              label: const Text(
                '回到本周',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          IconButton(
            tooltip: '校园地图',
            icon: const Icon(
              Icons.map_outlined,
              size: 21,
              color: AppColors.textPrimary,
            ),
            onPressed: () {
              if (!kMapFeatureEnabled) {
                _showToast('校园地图升级维护中，暂未开放');
                return;
              }
              Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => const MapPage()));
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
        setState(() => _showWeekSelector = false);
        _goWeek(week);
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
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
    // 没数据时要区分「真的没课」和「同步失败」——原来两者都显示「暂无课表数据」
    final failed = _syncFailed;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            failed ? Icons.cloud_off_rounded : Icons.event_busy_outlined,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            failed ? '课表同步失败，请检查网络后重试' : '暂无课表数据',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _syncing ? null : () => _refresh(),
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(failed ? '重新同步' : '重新获取'),
          ),
        ],
      ),
    );
  }

  /// 课表：节次列与星期表头固定，只有右侧课程区左右翻页。
  ///
  /// 翻页交给 `ScheduleGrid` 内部的 `PageView`，好处是纵向滚动视图只有**一个**，
  /// 不再每翻一页就换一个新的滚动视图（那样滑动后第一下纵向拖动常常没反应）。
  Widget _scheduleGrid() {
    final all = _snapshot?.courses ?? const <Course>[];
    // 周末列按全部周判断：否则翻到某周时列数变化，整张表会横向跳动
    return ScheduleGrid(
      weekCount: _maxWeek,
      pageOf: _pageOf,
      pageController: _page,
      onPageChanged: _onPageChanged,
      activePeriod: _activePeriod(),
      hasSaturday: all.any((c) => c.day == 5),
      hasSunday: all.any((c) => c.day == 6),
      displayedWeek: _selectedWeek,
      currentWeek: _currentWeek,
      isToday: _isToday,
      dateForDay: _dateForDay,
      onRefresh: () => _refresh(),
      onCourseTap: _showCourseDetailModal,
      onCourseDoubleTap: _locateCourseOnMap,
      periodWidth: _periodWidth,
      headerHeight: _headerHeight,
    );
  }

  /// 某一周的课表数据（`PageView` 只对实际构建的页调用）。
  WeekPage _pageOf(int week) {
    final courses = (_snapshot?.courses ?? const <Course>[])
        .where((c) => c.activeInWeek(week))
        .toList();
    return WeekPage(
      week: week,
      courses: courses,
      themeMap: _themeMapFor(_snapshot, week),
      isCurrentWeek: week == _currentWeek,
    );
  }

  /// 同一份快照下的每个周次只算一次主题色映射。
  ///
  /// `buildCourseThemeMap` 内部有 O(n²) 的 `contains` 去重，原来每次 build
  /// 都要重算一遍；配合上面「每分钟一次重建」就是白烧 CPU。
  /// 拖拽翻页时相邻两页会同时构建，所以必须按周次分桶缓存，不能只留一格。
  Map<String, CourseTheme> _themeMapFor(CourseSnapshot? snapshot, int week) {
    if (!identical(_themeSnapshot, snapshot)) {
      _themeSnapshot = snapshot;
      _themeByWeek.clear();
    }
    return _themeByWeek.putIfAbsent(
      week,
      () => buildCourseThemeMap(
        (snapshot?.courses ?? const <Course>[])
            .where((c) => c.activeInWeek(week))
            .toList(),
      ),
    );
  }
}
