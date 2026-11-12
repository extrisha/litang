import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/auth/cas_client.dart';
import '../data/app_exception.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/calendar/calendar_service.dart';
import '../data/chaoxing/chaoxing_auth.dart';
import '../data/chaoxing/chaoxing_cache.dart';
import '../data/chaoxing/chaoxing_client.dart';
import '../data/chaoxing/chaoxing_sso.dart';
import '../data/course_name.dart';
import '../data/geo/radar_location.dart';
import '../data/internal/internal_settings.dart';
import '../data/jwc/course_repository.dart';
import '../data/life_cache.dart';
import '../data/lms/radar_target.dart';
import '../data/lms/rollcall_api.dart';
import '../data/lms/course_info_cache.dart';
import '../data/lms/course_visit_history.dart';
import '../data/lms/todo_api.dart';
import '../data/lms/tronclass_auth.dart';
import '../data/request_guard.dart';
import '../services/dorm_electricity_service.dart';
import '../services/reminder_service.dart';
import 'chaoxing_homework_page.dart';
import 'chaoxing_course_detail_page.dart';
import 'chaoxing_login_page.dart';
import 'course_detail_page.dart';
import 'homework_page.dart';
import 'tron_exam_detail_page.dart';
import 'life/widgets/dorm_electricity_card.dart';
import 'life/widgets/life_course_card.dart';
import 'life/widgets/life_exam_card.dart';
import 'life/widgets/life_todo_card.dart';
import 'life/widgets/quick_tools_row.dart';
import 'life/widgets/rollcall_card.dart';
import 'life/widgets/sign_number_dialog.dart';
import 'login_page.dart';
import 'qr_scan_page.dart';
import 'simple_web.dart';

/// 校园服务：签到（一网畅学）+ 一网畅学入口 + 宿舍电费。
class LifePage extends StatefulWidget {
  const LifePage({super.key});

  @override
  State<LifePage> createState() => _LifePageState();
}

class _LifePageState extends State<LifePage> {
  bool _loading = false;
  String? _error;
  List<Rollcall> _rollcalls = const <Rollcall>[];
  List<LmsTodo> _todos = const <LmsTodo>[];
  List<LmsExam> _exams = const <LmsExam>[];
  String _currentTerm = '';
  String? _todosError;

  // 课程信息
  final Set<String> _timetableNames = <String>{};
  final Map<String, String> _timetableTeachers = <String, String>{};
  bool _showChaoxingCourses = false;
  bool _rollcallsRefreshing = false;
  bool _coursesLoading = false;
  String? _coursesError;
  List<LmsCourseInfo> _courseInfos = const <LmsCourseInfo>[];
  List<String> _recentCourseIds = const <String>[];
  final RequestGuard _coursesGuard = RequestGuard();
  final RequestGuard _lifeGuard = RequestGuard();
  final RequestGuard _rollcallsGuard = RequestGuard();
  String? _courseRequestKey;

  // 学习通
  /// 学习通请求是否在途（纯互斥锁，不参与渲染）
  bool _cxLoading = false;
  final RequestGuard _cxGuard = RequestGuard();
  String? _cxRequestUser;
  String? _cxError;
  List<ChaoxingCourse> _cxCourses = const <ChaoxingCourse>[];
  List<ChaoxingActivity> _cxActivities = const <ChaoxingActivity>[];
  List<ChaoxingWork> _cxWorks = const <ChaoxingWork>[];

  // 宿舍电费
  DormElectricity? _dormElect;
  DateTime? _dormFetchedAt;
  DormElectricityService? _dormService;

  /// [_dormService] 绑定的那个会话。教务静默重登会换掉 `JwglAuth.client`，
  /// 旧 service 还连着旧 jar 的 cookie，继续用只会一直失败。
  CasClient? _dormServiceClient;
  bool _dormLoading = false;
  String? _dormError;

  static const Duration _dormCacheTtl = Duration(minutes: 10);

  String? _lastAuthStudentId;
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    _lastAuthStudentId = JwglAuth.instance.studentId;
    JwglAuth.instance.addListener(_onAuthChanged);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _cxGuard.invalidate();
    _coursesGuard.invalidate();
    _lifeGuard.invalidate();
    _rollcallsGuard.invalidate();
    JwglAuth.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// 换教务账号后，生活页是 IndexedStack 里的常驻页面，不会自动 initState。
  /// 这里监听登录态变化，把上一个账号的课程/待办/电费一起清掉并重拉。
  void _onAuthChanged() {
    final id = JwglAuth.instance.studentId;
    if (id == _lastAuthStudentId) {
      return;
    }
    _lastAuthStudentId = id;
    _cxGuard.invalidate();
    _coursesGuard.invalidate();
    _lifeGuard.invalidate();
    _rollcallsGuard.invalidate();
    _rollcallsRefreshing = false;
    if (!mounted || !_bootstrapped) {
      return;
    }
    setState(() {
      _courseInfos = const <LmsCourseInfo>[];
      _recentCourseIds = const <String>[];
      _timetableNames.clear();
      _timetableTeachers.clear();
      _cxCourses = const <ChaoxingCourse>[];
      _cxActivities = const <ChaoxingActivity>[];
      _cxWorks = const <ChaoxingWork>[];
      _todos = const <LmsTodo>[];
      _exams = const <LmsExam>[];
      _rollcalls = const <Rollcall>[];
      _dormElect = null;
      _dormFetchedAt = null;
      _dormError = null;
      _dormService = null;
      _dormServiceClient = null;
      _dormLoading = false;
      _loading = false;
      _coursesLoading = false;
      _cxLoading = false;
      // 上一个账号的错误提示不能留给下一个账号
      _error = null;
      _todosError = null;
      _coursesError = null;
      _cxError = null;
    });
    if (id == null || id.isEmpty) {
      return;
    }
    unawaited(_warmupAfterLogin(id));
  }

  /// 登录/换账号后的固定顺序：
  ///   1. 拉本学期课表（课程过滤的基准）
  ///   2. 登录一网畅学，拉待办/考试/签到
  ///   3. 隐藏 WebView SSO 登录学习通，拉课程/作业
  ///   4. 最后拉电费
  ///
  /// 这些步骤都有转圈提示，串行执行比并行更容易保证“先有课表，再登录两个
  /// 教学平台”的顺序，也避免两个登录同时抢 CAS 会话。
  Future<void> _warmupAfterLogin(String id) async {
    final auth = JwglAuth.instance;
    final client = auth.client;
    if (client == null) return;
    if (mounted) {
      setState(() => _loading = true);
    }

    // 1) 本学期课表：既是课程信息基准，也决定 Chaoxing 过滤范围。
    try {
      final snapshot = await CourseRepository.refresh(client);
      if (!mounted || auth.studentId != id) return;
      _currentTerm =
          CalendarService.instance.currentTerm?.id ??
          (snapshot.termLabel.isNotEmpty ? snapshot.termLabel : _currentTerm);
      _timetableNames.clear();
      _timetableTeachers.clear();
      for (final course in snapshot.courses) {
        final name = _cleanCourseName(course.name);
        if (name.isEmpty) continue;
        _timetableNames.add(name);
        final teacher = course.teacher;
        if (teacher != null && teacher.isNotEmpty) {
          _timetableTeachers[name] = teacher;
        }
      }
    } catch (_) {
      // 课表失败不阻断后续；_ensureCurrentCourseNames 还会再兜一次。
    }
    if (!mounted || auth.studentId != id) return;

    // 2) 一网畅学登录由 _refresh 内部完成；先贴缓存，再拉生活页数据。
    await _restoreCachedLifeData(id);
    await _refresh(force: true);
    if (!mounted || auth.studentId != id) return;

    if (!_showChaoxingCourses) {
      await _loadCourses(force: true);
      if (!mounted || auth.studentId != id) return;
    }

    // 3) 学习通：隐藏 SSO，成功后拉课程/作业。
    await _refreshChaoxing(
      withWorks: true,
      autoLogin: true,
      allowVisibleFallback: false,
    );
    if (!mounted || auth.studentId != id) return;

    if (_showChaoxingCourses) {
      await _loadCourses(force: true);
      if (!mounted || auth.studentId != id) return;
    }

    // 4) 电费独立，放最后。
    await _loadDormElectricity(force: true);
  }

  Future<void> _refreshRollcallsOnly() async {
    if (_rollcallsRefreshing) return;
    final auth = JwglAuth.instance;
    final request = _rollcallsGuard.begin();
    final username = auth.savedUsername;
    bool current() =>
        mounted &&
        _rollcallsGuard.isCurrent(request) &&
        auth.savedUsername == username;
    setState(() => _rollcallsRefreshing = true);
    try {
      if (auth.isLoggedIn && auth.client != null) {
        try {
          await TronclassAuth.instance.ensureLoggedIn();
          if (!current()) return;
          final client = auth.client;
          if (client == null) return;
          final rc = await RollcallApi(client).fetchOngoing();
          if (current() && identical(client, auth.client)) {
            setState(() {
              _rollcalls = rc;
              _error = null;
            });
          }
        } catch (e) {
          // 以前这里用 `catch (_) {}` 静默吞掉，用户点刷新后完全没反馈。
          debugPrint('[rollcall] 刷新失败: $e');
          if (current()) {
            setState(() {
              // 接口层已经能区分「登录失效 / 网络失败」，直接用它的人话文案
              _error = e is AppException ? e.message : '签到信息拉取失败，请稍后重试';
            });
          }
        }
      }
      if (!current()) return;
      await _refreshChaoxing(withWorks: false, autoLogin: true);
    } finally {
      if (current()) {
        setState(() => _rollcallsRefreshing = false);
      }
    }
  }

  Future<void> _refreshAllServices() async {
    await Future.wait<void>(<Future<void>>[
      _refresh(force: true),
      _refreshChaoxing(withWorks: true, autoLogin: true),
      _loadCourses(force: true),
      _loadDormElectricity(force: true),
    ]);
  }

  /// 初始化外壳：`_bootstrapInner` 里任何一处抛出（安全存储读失败、
  /// 缓存解析失败、单例初始化异常）都不该变成未捕获的异步异常，
  /// 也不该让 `_bootstrapped` 永远为 false —— 那会让换账号的清理逻辑失效。
  Future<void> _bootstrap() async {
    try {
      await _bootstrapInner();
    } catch (e, stack) {
      debugPrint('[bootstrap] 初始化失败: $e\n$stack');
      if (mounted) {
        setState(() => _error = '初始化失败，下拉刷新重试');
      }
    } finally {
      _bootstrapped = true;
    }
  }

  Future<void> _bootstrapInner() async {
    // 缓存读取和登录互不依赖，同时启动，省掉一次串行等待
    final snapshotFuture = CourseRepository.loadCache();

    // 生活页是启动时就存在的 tab，可能比「我的」页更早初始化，
    // 这里必须先恢复登录态，否则一网畅学接口会以未登录状态返回空。
    final auth = JwglAuth.instance;
    if (!auth.isLoggedIn) {
      await auth.restore();
    }
    // 知道当前学号后才能读对应用户的缓存，避免换账号时串数据。
    final username = auth.savedUsername;
    if (username.isNotEmpty) {
      unawaited(_restoreCachedLifeData(username));
    }
    var ok = await TronclassAuth.instance.ensureLoggedIn();
    if (!ok) {
      // 教务会话可能刚过期，刷新一次再重试
      await JwglAuth.instance.ensureSession();
      ok = await TronclassAuth.instance.ensureLoggedIn();
    }

    final snapshot = await snapshotFuture;
    if (!mounted) {
      return;
    }
    _currentTerm =
        CalendarService.instance.currentTerm?.id ?? snapshot?.termLabel ?? '';
    _timetableNames
      ..clear()
      ..addAll(
        snapshot?.courses.map((c) => _cleanCourseName(c.name)) ??
            const <String>[],
      );
    if (!ok) {
      setState(() {
        _error = '一网畅学登录失败，点「重试」重新登录';
      });
    }
    // 签到 / 学习通 / 课程三个数据源互不依赖，并行拉取：
    // 首屏耗时从「三者之和」变成「最慢的那个」。
    await Future.wait<void>(<Future<void>>[
      _guardTask(_refresh),
      _guardTask(_refreshChaoxing),
      _guardTask(_loadCourses),
    ]);
    // 先把上次落盘的电费读回来，冷启动也能直接显示
    if (username.isNotEmpty) {
      await DormElectricityCache.load(username);
    }
    final cached = DormElectricityCache.dataFor(username);
    // 有缓存先展示；缓存超过 10 分钟再静默刷新，没有缓存也拉一次。
    final age = DormElectricityCache.ageFor(username);
    final stale = cached == null || age == null || age >= _dormCacheTtl;
    // 有教务会话（可走 SSO）或有保存的密码，才值得去刷新
    final canFetch = JwglAuth.instance.client != null || auth.hasSavedPassword;
    // 必须走 setState：这段赋值发生在本轮所有 setState 之后，不主动刷新的话，
    // 缓存新鲜（不触发网络刷新）时电费卡片会一直停在「未刷新」。
    if (cached != null && mounted) {
      setState(() {
        _dormElect = cached;
        _dormFetchedAt = DormElectricityCache.fetchedAtFor(username);
      });
    }
    if (canFetch && stale) {
      unawaited(_loadDormElectricity());
    }
  }

  /// 并行任务的错误隔离：某一个失败只影响自己那块，不中断整页初始化。
  /// （[Future.wait] 默认 fail-fast，会连带丢掉其它任务已经拿到的数据。）
  static Future<void> _guardTask(Future<void> Function() task) async {
    try {
      await task();
    } catch (e, stack) {
      debugPrint('[bootstrap] 任务失败: $e\n$stack');
    }
  }

  /// 冷启动时把上次的待办 / 考试 / 签到贴到界面上（stale-while-revalidate）。
  /// 只在对应列表仍为空时填充，不会覆盖已经拿到的新数据。
  Future<void> _restoreCachedLifeData(String username) async {
    final results = await Future.wait<Object?>(<Future<Object?>>[
      LifeCache.readTodos(username: username),
      LifeCache.readExams(username: username),
      LifeCache.readRollcalls(username: username),
    ]);
    if (!mounted) {
      return;
    }
    final todos = results[0] as List<LmsTodo>?;
    final exams = results[1] as List<LmsExam>?;
    final rollcalls = results[2] as List<Rollcall>?;
    if (todos == null && exams == null && rollcalls == null) {
      return;
    }
    setState(() {
      if (todos != null && _todos.isEmpty) {
        _todos = todos;
      }
      if (exams != null && _exams.isEmpty) {
        _exams = _filterExams(exams);
      }
      if (rollcalls != null && _rollcalls.isEmpty) {
        _rollcalls = rollcalls;
      }
    });
  }

  /// 拉取宿舍电费。ssgl 走独立 CAS 登录，用保存的学号密码。
  ///
  /// [force] 为 true 时跳过缓存（右上角刷新/点卡片）。
  Future<void> _loadDormElectricity({bool force = false}) async {
    if (_dormLoading) {
      return;
    }
    final auth = JwglAuth.instance;
    final username = auth.savedUsername;
    final cached = DormElectricityCache.dataFor(username);
    final age = DormElectricityCache.ageFor(username);

    if (!force && cached != null && age != null && age < _dormCacheTtl) {
      if (!mounted) {
        return;
      }
      setState(() {
        _dormElect = cached;
        _dormFetchedAt = DormElectricityCache.fetchedAtFor(username);
        _dormError = null;
      });
      return;
    }

    // 有教务会话就能靠 CAS 单点登录拿电费，不必存密码
    final hasSession = JwglAuth.instance.client != null;
    if (!hasSession && !auth.hasSavedPassword) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (cached != null) {
          _dormElect = cached;
          _dormFetchedAt = DormElectricityCache.fetchedAtFor(username);
        }
        _dormError = cached == null ? '需要先登录才能查询电费' : null;
      });
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _dormLoading = true;
      _dormError = null;
    });
    try {
      final info = await _fetchDormElectricity(username, auth);
      if (!mounted || JwglAuth.instance.savedUsername != username) {
        return;
      }
      DormElectricityCache.put(username, info);
      setState(() {
        _dormElect = info;
        _dormFetchedAt = DateTime.now();
      });
    } on DormElectricityException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _dormError = '${e.message}（请使用校园网访问）');
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _dormError = '查询失败，请使用校园网访问');
    } finally {
      // 每条 return / 异常路径都必须复位：`_dormLoading` 卡在 true 时，
      // 函数开头的互斥判断会让之后所有刷新（含下拉刷新）被静默跳过。
      if (mounted) {
        setState(() => _dormLoading = false);
      }
    }
  }

  Future<void> _loginThenLoadDorm() async {
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute<bool>(builder: (_) => const LoginPage()));
    if (ok == true && mounted) {
      _dormService = null;
      _dormServiceClient = null;
      await _loadDormElectricity(force: true);
    }
  }

  /// 取电费：优先复用教务的 CAS 会话（走单点登录，不需要密码），
  /// 会话里没有可用 TGT 时再退回账号密码登录。
  Future<DormElectricity> _fetchDormElectricity(
    String username,
    JwglAuth auth,
  ) async {
    final client = JwglAuth.instance.client;
    if (client != null) {
      // 教务静默重登（reauthenticate）会换一个新的 CasClient，而 savedUsername
      // 不变、不会触发 `_onAuthChanged`。这里比对绑定关系，换过就重建 service。
      if (!identical(_dormServiceClient, client)) {
        _dormService = null;
      }
      _dormServiceClient = client;
      final service = _dormService ??= DormElectricityService.withSession(
        client.jar.headerFor,
        client.jar.absorbSetCookie,
      );
      try {
        return await service.refresh();
      } catch (_) {
        if (!auth.hasSavedPassword) {
          rethrow;
        }
        // 单独建实例走完整登录，避免污染会话模式的那份 cookie
        final fallback = DormElectricityService();
        final info = await fallback.fetch(
          username: username,
          password: auth.savedPassword!,
        );
        _dormService = fallback;
        return info;
      }
    }

    final service = _dormService ??= DormElectricityService();
    if (service.isLoggedIn) {
      try {
        return await service.refresh();
      } catch (_) {
        // 会话过期，落到下面重新登录
      }
    }
    return service.fetch(username: username, password: auth.savedPassword!);
  }

  /// 拉取学习通数据。cookie 失效时会用保存的密码后台重登。
  ///
  /// [autoLogin] 为 true 时，如果当前没登录，会直接拉起 CAS SSO 登录页
  /// （优先复用教务登录态），不再要求用户另点一次「登录学习通」。
  Future<void> _refreshChaoxing({
    bool withWorks = false,
    bool autoLogin = false,
    bool allowVisibleFallback = true,
  }) async {
    final cacheUser = JwglAuth.instance.savedUsername;
    if (_cxLoading && _cxRequestUser == cacheUser) {
      return;
    }
    final request = _cxGuard.begin();
    _cxRequestUser = cacheUser;
    bool current() =>
        mounted &&
        _cxGuard.isCurrent(request) &&
        JwglAuth.instance.savedUsername == cacheUser;
    if (!current()) return;
    // 纯互斥锁：没有接到任何 UI 上，不能走 setState（否则每学习通刷新都白重建整页）
    _cxLoading = true;
    setState(() {
      _cxError = null;
    });
    if (cacheUser.isNotEmpty && JwglAuth.instance.isLoggedIn) {
      final cached = await ChaoxingCache.read(cacheUser);
      if (current() &&
          cached != null &&
          JwglAuth.instance.savedUsername == cacheUser) {
        setState(() {
          if (cached.failedCourses.isNotEmpty) {
            _cxError = '上次部分课程未更新：${cached.failedCourses.join('、')}（保留旧数据）';
          }
          if (_cxCourses.isEmpty && cached.courses.isNotEmpty) {
            _cxCourses = cached.courses;
          }
          if (_cxWorks.isEmpty && cached.works.isNotEmpty) {
            _cxWorks = cached.works;
          }
          if (_cxActivities.isEmpty && cached.activities.isNotEmpty) {
            _cxActivities = cached.activities;
          }
        });
      }
    }
    try {
      final auth = ChaoxingAuth.instance;
      // 本地 cookie → 教务 CAS 静默 SSO，两者都不弹界面。
      // 以前这里会在 cookie 失效时直接叫出网页登录，现在先让 SSO 试一次。
      var ready = await auth.ensureSession();
      if (!current()) return;
      final cas = JwglAuth.instance.client;
      if (!ready && autoLogin && cas != null) {
        // CAS 也换不到（多半是教务会话过期），退回网页登录。
        // 没有 CASTGC 时隐藏 WebView 同样换不到 SSO，直接走可见页，避免白等。
        var ok = false;
        if (ChaoxingSso.hasCastgc(cas)) {
          ok = await _promptChaoxingLogin(hidden: true);
        }
        if (!ok && allowVisibleFallback) {
          ok = await _promptChaoxingLogin();
        }
        ready = ok && auth.isLoggedIn;
      }
      if (!ready || !current()) {
        if (current()) {
          setState(() {
            // 别只是清空：清空后待办卡片会显示「暂无待办作业」，
            // 让"没登录上"看起来像"确实没有作业"。
            _cxError = '学习通未登录或登录已过期，点上方按钮重新登录';
          });
        }
        return;
      }
      final client = auth.client;
      if (client == null) {
        return;
      }
      final rawCourses = _cxCourses.isNotEmpty
          ? _cxCourses
          : await client.fetchCourses();
      await _ensureCurrentCourseNames();
      if (!current()) return;
      final currentCourses = _timetableNames.isEmpty
          ? rawCourses
          : rawCourses
                .where(
                  (c) => _timetableNames.contains(_cleanCourseName(c.name)),
                )
                .toList();
      final needWorks = withWorks || _cxWorks.isEmpty;
      // 作业只看当前学期的课：往期课的作业早就截止了，放进待办只会干扰。
      // 签到活动不能跟着这个过滤走——`status == 1` 的签到本来就只有正在上课
      // 的课程才会有；而课表课程名和超星课程名经常对不上（后缀、简写），
      // 一旦按名字过滤就会把真正进行中的签到静默丢掉。这是「学习通签到
      // 不可用」的另一半原因。
      final activitiesFuture = client.fetchActivitiesBatch(rawCourses);
      final worksFuture = needWorks
          ? client.fetchWorksBatch(currentCourses)
          : null;
      final activityBatch = await activitiesFuture;
      final workBatch = await worksFuture;
      if (!current()) {
        return;
      }
      final activities = activityBatch.merge(
        _cxActivities,
        (a) => '${a.courseId}:${a.classId}',
      );
      final works = workBatch?.merge(_cxWorks, (w) => w.courseKey) ?? _cxWorks;
      final failures = {
        ...activityBatch.failed.values,
        ...?workBatch?.failed.values,
      };
      setState(() {
        // 这里必须存**全部**课程：作业过滤只作用于 `currentCourses`，
        // 但下一次刷新签到还要拿全量课程。以前存的是过滤后的列表，
        // 结果第二次刷新开始，课表里没匹配上的课程就被永久丢掉。
        _cxCourses = rawCourses;
        _cxActivities = activities;
        _cxWorks = works;
        _cxError = failures.isEmpty
            ? null
            : '部分课程未更新：${failures.join('、')}（保留旧数据）';
      });
      if (cacheUser.isNotEmpty &&
          JwglAuth.instance.savedUsername == cacheUser) {
        unawaited(ChaoxingCache.writeCourses(cacheUser, rawCourses));
        unawaited(
          ChaoxingCache.writeActivities(
            cacheUser,
            activities,
            failedCourses: activityBatch.failed.values.toList(),
          ),
        );
        if (workBatch != null) {
          unawaited(
            ChaoxingCache.writeWorks(
              cacheUser,
              works,
              failedCourses: workBatch.failed.values.toList(),
            ),
          );
        }
      }
      // 学习通只有「剩余 X 小时」这种相对时间，拉到列表时换算成绝对时间排提醒
      if (workBatch != null && current()) {
        await ReminderService.instance.syncChaoxingWorks(works);
      }
      // 自动登录完成后，如果当前正停在学习通课程源，把课程卡片也刷新掉
      if (_showChaoxingCourses && current()) {
        unawaited(_loadCourses(force: true));
      }
    } catch (e) {
      if (current()) {
        setState(() => _cxError = '学习通数据拉取失败，请稍后重试');
      }
    } finally {
      if (current()) {
        _cxLoading = false;
      }
    }
  }

  /// 打开学习通登录页；优先走 CAS SSO，失败时页面会自动填充教务账号。
  Future<bool> _promptChaoxingLogin({bool hidden = false}) async {
    final jwgl = JwglAuth.instance;
    final canAuto = jwgl.hasSavedPassword;
    final page = ChaoxingLoginPage(
      username: canAuto ? jwgl.savedUsername : null,
      password: canAuto ? jwgl.savedPassword : null,
      hidden: hidden,
    );
    final route = hidden
        ? PageRouteBuilder<bool>(
            opaque: false,
            barrierDismissible: false,
            barrierColor: Colors.transparent,
            transitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => page,
          )
        : MaterialPageRoute<bool>(builder: (_) => page);
    final ok = await Navigator.of(context).push<bool>(route);
    return ok == true;
  }

  Future<void> _loginChaoxing() async {
    if (!await _promptChaoxingLogin()) return;
    await _refreshChaoxing(withWorks: true);
    // 当前如果停在「学习通」课程源，登录完直接把课程列表拉出来
    if (_showChaoxingCourses) {
      await _loadCourses(force: true);
    }
  }

  Future<void> _refresh({bool force = false}) async {
    if (_loading && !force) {
      return;
    }
    final auth = JwglAuth.instance;
    if (!auth.isLoggedIn) {
      if (mounted) {
        setState(() => _error = '未登录教务系统');
      }
      return;
    }
    setState(() => _loading = true);
    final requestId = _lifeGuard.begin();
    final requestUser = JwglAuth.instance.savedUsername;
    bool isCurrent() =>
        mounted &&
        _lifeGuard.isCurrent(requestId) &&
        JwglAuth.instance.savedUsername == requestUser;
    try {
      // 每次刷新前确认一网畅学会话；半失效时内部会自动重登
      await TronclassAuth.instance.ensureLoggedIn();
      if (!isCurrent()) return;
      final client = auth.client;
      if (client == null) {
        return;
      }
      var rollcalls = _rollcalls;
      var todos = _todos;
      var exams = _exams;
      var todosFetched = false;
      var examsFetched = false;
      var rollcallsFetched = false;
      try {
        rollcalls = await RollcallApi(client).fetchOngoing();
        rollcallsFetched = true;
      } catch (_) {
        // 签到失败保留旧数据
      }
      String? todosError;
      try {
        final fetched = await LmsApi(client).fetchTodos();
        todos = fetched;
        todosFetched = true;
      } catch (e) {
        todosError = '待办拉取失败：${e.toString().split("\n").first}';
      }
      try {
        final fetched = await LmsApi(client).fetchExams();
        exams = fetched;
        examsFetched = true;
      } catch (_) {
        // 考试安排失败保留旧数据
      }
      if (!isCurrent()) {
        return;
      }
      // 两个都失败且无数据时给个提示。注意要写进 `_todosError`：
      // 下面这次 setState 会把 `_error` 置空，写 `_error` 会被同一个同步片段
      // 立刻覆盖掉，用户永远看不到（这是原来的 bug）。
      final bothFailed = !todosFetched && !examsFetched;
      setState(() {
        _rollcalls = rollcalls;
        _todos = todos;
        _exams = _filterExams(exams);
        _todosError = bothFailed && _todos.isEmpty && _exams.isEmpty
            ? '学习数据拉取失败，请稍后重试'
            : todosError;
        _error = null;
      });
      // 只写成功拉到的部分，避免把「保留的旧数据」当成新数据盖上时间戳
      final cacheUser = requestUser;
      if (rollcallsFetched) {
        unawaited(LifeCache.writeRollcalls(rollcalls, username: cacheUser));
      }
      if (todosFetched) {
        unawaited(LifeCache.writeTodos(todos, username: cacheUser));
      }
      if (examsFetched) {
        unawaited(LifeCache.writeExams(_exams, username: cacheUser));
      }
      // 作业提醒同步是「锦上添花」：它内部要逐课程查一遍「我的提交」，
      // 会多花一次网络往返。放在后台跑，别拖住 loading 转圈，
      // 失败了也不该把整页标成错误。
      unawaited(_syncHomeworkReminders(client, _todos));
    } catch (e) {
      if (isCurrent()) {
        setState(() {
          // 接口层已区分「登录失效 / 网络失败 / 解析失败」，直接用它的文案
          _error = e is AppException ? e.message : '签到信息拉取失败，请稍后重试';
        });
      }
    } finally {
      if (isCurrent()) {
        setState(() => _loading = false);
      }
    }
  }

  /// 后台同步作业提醒；失败只记日志，不影响页面状态。
  Future<void> _syncHomeworkReminders(
    CasClient client,
    List<LmsTodo> todos,
  ) async {
    try {
      final submitted = await ReminderService.instance.fetchSubmittedIds(
        client,
        todos,
      );
      await ReminderService.instance.syncHomework(
        todos: todos,
        submittedActivityIds: submitted,
      );
    } catch (e) {
      debugPrint('[reminders] 同步失败: $e');
    }
  }

  /// 实现统一在 [CourseName]；`LifeTodoCard` 也调同一份，
  /// 免得待办卡片和课程卡片用的归一化规则跑偏。
  static String _cleanCourseName(String raw) => CourseName.clean(raw);

  bool _isCurrentCourse(String name, String termCode) {
    final clean = _cleanCourseName(name);
    if (_timetableNames.isNotEmpty && _timetableNames.contains(clean)) {
      return true;
    }
    final effectiveTerm = _currentTerm.isNotEmpty
        ? _currentTerm
        : CalendarService.fallbackTermId();
    if (termCode.isNotEmpty &&
        _normalizeTerm(termCode) == _normalizeTerm(effectiveTerm)) {
      return true;
    }
    return false;
  }

  /// 学习通课程没有 termCode，只能拿「本学期课表课程名」做过滤。
  /// 优先用教务课表；课表没缓存时退到一网畅学的当前课程列表。
  Future<void> _ensureCurrentCourseNames() async {
    if (_timetableNames.isNotEmpty) return;
    final client = JwglAuth.instance.client;
    if (client == null) return;
    try {
      final snapshot = await CourseRepository.refresh(client);
      final names = snapshot.courses
          .map((c) => _cleanCourseName(c.name))
          .where((n) => n.isNotEmpty)
          .toSet();
      if (names.isNotEmpty) {
        _timetableNames.addAll(names);
      }
    } catch (_) {
      // 课表失败时再试一网畅学当前课程
    }
    if (_timetableNames.isNotEmpty) return;
    try {
      final list = await LmsApi(client).fetchCourseInfos();
      _timetableNames.addAll(
        list.map((c) => _cleanCourseName(c.name)).where((n) => n.isNotEmpty),
      );
    } catch (_) {
      // 两边都失败就只能不过滤，至少别把课程藏起来
    }
  }

  Future<void> _loadCourses({bool force = false}) async {
    final termKey = _currentTerm.isNotEmpty
        ? _currentTerm
        : CalendarService.fallbackTermId();
    final source = _showChaoxingCourses ? 'chaoxing' : 'tronclass';
    final cacheUser = JwglAuth.instance.savedUsername;
    final requestKey = '$cacheUser|$source|$termKey';
    if (_courseRequestKey == requestKey && !force) return;
    _courseRequestKey = requestKey;
    final requestId = _coursesGuard.begin();
    bool isCurrent() =>
        mounted &&
        _coursesGuard.isCurrent(requestId) &&
        JwglAuth.instance.savedUsername == cacheUser &&
        _showChaoxingCourses == (source == 'chaoxing');
    if (!isCurrent()) return;
    setState(() {
      _coursesLoading = true;
      _coursesError = null;
    });
    final recent = await CourseVisitHistory.load(cacheUser, source);
    if (!isCurrent()) return;
    _recentCourseIds = recent;
    if (source == 'chaoxing' && _cxCourses.isEmpty) {
      final cached = await ChaoxingCache.read(cacheUser);
      if (!isCurrent()) return;
      _cxCourses = cached?.courses ?? const <ChaoxingCourse>[];
    }
    // 缓存优先：有缓存先渲染；缓存过期就不显示加载态、后台静默刷一遍。
    var silent = false;
    if (!force) {
      final cached = await CourseInfoCache.load(
        termKey,
        source,
        username: cacheUser,
      );
      if (!isCurrent()) return;
      if (cached != null) {
        setState(() {
          _courseInfos = CourseVisitHistory.sort(cached, _recentCourseIds);
          _coursesLoading = false;
          _coursesError = null;
        });
        final fresh = await CourseInfoCache.isFresh(
          termKey,
          source,
          username: cacheUser,
        );
        if (!isCurrent()) return;
        if (fresh && (source == 'tronclass' || _cxCourses.isNotEmpty)) {
          _courseRequestKey = null;
          return;
        }
        silent = true;
      }
    }
    try {
      if (source == 'tronclass') {
        final auth = JwglAuth.instance;
        if (!auth.isLoggedIn) {
          await auth.restore();
        }
        await TronclassAuth.instance.ensureLoggedIn();
        if (!isCurrent()) return;
        final client = auth.client;
        if (client == null) {
          if (!silent && mounted) {
            setState(() => _coursesError = '请先登录教务系统');
          }
          return;
        }
        final list = await LmsApi(client).fetchCourseInfos();
        if (!isCurrent()) return;
        final filtered = list
            .where((c) => _isCurrentCourse(c.name, c.termCode))
            .map(
              (c) => LmsCourseInfo(
                id: c.id,
                name: c.name,
                teacher: c.teacher.isNotEmpty
                    ? c.teacher
                    : (_timetableTeachers[_cleanCourseName(c.name)] ?? ''),
                termCode: c.termCode,
              ),
            )
            .toList();
        if (isCurrent()) {
          setState(
            () => _courseInfos = CourseVisitHistory.sort(
              filtered,
              _recentCourseIds,
            ),
          );
          await CourseInfoCache.save(
            termKey,
            source,
            filtered,
            username: cacheUser,
          );
        }
      } else {
        final auth = ChaoxingAuth.instance;
        final hadSession = auth.isLoggedIn;
        if (!hadSession) {
          await auth.restore();
        }
        if (!await auth.ensureSession()) {
          if (isCurrent() && !silent) {
            setState(() {
              _courseInfos = const <LmsCourseInfo>[];
              _coursesError = hadSession ? '学习通登录已失效' : '学习通未登录';
            });
          }
          return;
        }
        if (!isCurrent()) return;
        final client = auth.client;
        if (client == null) return;
        final courses = _cxCourses.isNotEmpty
            ? _cxCourses
            : await client.fetchCourses();
        // 学习通列表没有 termCode，用本学期课表课程名过滤掉往期课程；
        // 课表/一网畅学都拿不到时才退回全量（至少不误藏当前课程）。
        await _ensureCurrentCourseNames();
        if (!isCurrent()) return;
        final filtered = courses
            .where(
              (c) =>
                  _timetableNames.isEmpty ||
                  _timetableNames.contains(_cleanCourseName(c.name)),
            )
            .map(
              (c) => LmsCourseInfo(
                id: c.courseId,
                name: c.name,
                teacher: c.teacher.isNotEmpty
                    ? c.teacher
                    : (_timetableTeachers[_cleanCourseName(c.name)] ?? ''),
                termCode: '',
              ),
            )
            .toList();
        // `_cxCourses` 也放进 setState：直接赋值属于构建期外的状态突变，
        // 一旦上面的 await 期间页面被销毁就会留下不一致的状态。
        if (isCurrent()) {
          setState(() {
            _cxCourses = courses;
            _courseInfos = CourseVisitHistory.sort(filtered, _recentCourseIds);
          });
          await CourseInfoCache.save(
            termKey,
            source,
            filtered,
            username: cacheUser,
          );
          await ChaoxingCache.writeCourses(cacheUser, courses);
        }
      }
    } catch (e) {
      // 静默刷新失败就保持缓存内容，不打扰用户
      if (isCurrent() && !silent) {
        setState(() {
          _coursesError = e is AppException ? e.message : '课程信息拉取失败';
        });
      }
    } finally {
      if (isCurrent()) {
        _courseRequestKey = null;
        setState(() => _coursesLoading = false);
      }
    }
  }

  void _toggleCourseSource() {
    setState(() {
      _showChaoxingCourses = !_showChaoxingCourses;
      _courseInfos = const <LmsCourseInfo>[];
      _coursesError = null;
    });
    _loadCourses();
  }

  void _openCourse(LmsCourseInfo course) {
    final isChaoxing = _showChaoxingCourses;
    ChaoxingCourse? cxCourse;
    if (isChaoxing) {
      final matches = _cxCourses.where((item) => item.courseId == course.id);
      if (matches.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('正在补全课程信息，请稍后重试')));
        unawaited(_loadCourses(force: true));
        return;
      }
      cxCourse = matches.first;
    }
    final username = JwglAuth.instance.savedUsername;
    final source = isChaoxing ? 'chaoxing' : 'tronclass';
    setState(() {
      _recentCourseIds = CourseVisitHistory.promote(
        _recentCourseIds,
        course.id,
      );
      _courseInfos = CourseVisitHistory.sort(_courseInfos, _recentCourseIds);
    });
    unawaited(CourseVisitHistory.record(username, source, course.id));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => cxCourse != null
            ? ChaoxingCourseDetailPage(
                courseName: course.name,
                course: cxCourse,
              )
            : TronCourseDetailPage(
                courseName: course.name,
                courseId: course.id,
              ),
      ),
    );
  }

  Future<void> _retryTronclass() async {
    if (_loading) return;
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await JwglAuth.instance.reauthenticate();
      final ok = await TronclassAuth.instance.ensureLoggedIn();
      if (!mounted) return;
      if (!ok) {
        setState(() => _error = '一网畅学登录失败，请先到「我的」重新登录教务');
        return;
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  VoidCallback? _signAction(Rollcall rollcall) {
    // 已经签过 / 已结束的签到不再给按钮，避免点了没反应或者重复提交
    if (!rollcall.isSignable) {
      return null;
    }
    if (rollcall.isSelfRollcall) {
      return () => _signBySelfRegistration(rollcall);
    }
    if (rollcall.isNumberRollcall) {
      return () => _signByNumber(rollcall);
    }
    if (rollcall.isRadarRollcall) {
      return () => _signByRadar(rollcall);
    }
    if (rollcall.isQrRollcall) {
      return () => _signByQr(rollcall);
    }
    // 类型识别不出来时不再直接跳网页，给用户自己选一次
    return () => _chooseSignMethod(rollcall);
  }

  /// 服务端没给出签到类型时的兜底：让用户选口令还是扫码。
  Future<void> _chooseSignMethod(Rollcall rollcall) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('输入数字口令'),
              subtitle: const Text('老师在课堂上念的 4~6 位数字'),
              onTap: () => Navigator.pop(sheetContext, 'number'),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('扫二维码'),
              subtitle: const Text('对准老师屏幕上的签到二维码'),
              onTap: () => Navigator.pop(sheetContext, 'qr'),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('打开一网畅学网页'),
              subtitle: const Text('类型识别不出来时的兜底入口'),
              onTap: () => Navigator.pop(sheetContext, 'web'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) {
      return;
    }
    if (picked == 'number') {
      await _signByNumber(rollcall);
    } else if (picked == 'qr') {
      await _signByQr(rollcall);
    } else if (picked == 'web') {
      await _openLms();
    }
  }

  /// 自主签到：官方接口发空 `{}` 就行，不需要口令/坐标/二维码。
  Future<void> _signBySelfRegistration(Rollcall rollcall) async {
    final client = JwglAuth.instance.client;
    if (client == null) {
      _toast('请先登录教务系统');
      return;
    }
    setState(() => _loading = true);
    var success = false;
    try {
      final SignResult result;
      try {
        result = await RollcallApi(client).answerSelfRegistration(rollcall);
      } catch (_) {
        if (mounted) {
          _toast('签到请求失败，请稍后重试');
        }
        return;
      }
      success = result.success;
      if (mounted) {
        _toast(result.success ? '已自主签到' : (result.message ?? '自主签到失败'));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
    if (success) {
      await _refresh();
    }
  }

  /// 数字口令签到：输入老师给的口令后直接提交。
  Future<void> _signByNumber(Rollcall rollcall) async {
    final client = JwglAuth.instance.client;
    if (client == null) {
      _toast('请先登录教务系统');
      return;
    }
    // controller 由 dialog 组件自己持有并释放：在这里 `showDialog` 返回后
    // 立刻 dispose，会和 dialog 的退场动画抢 TextField，偶发
    // 「TextEditingController used after being disposed」。
    final input = await showDialog<String>(
      context: context,
      builder: (_) => SignNumberDialog(courseName: rollcall.courseName),
    );
    if (input == null || input.isEmpty || !mounted) {
      return;
    }
    setState(() => _loading = true);
    var success = false;
    try {
      final result = await RollcallApi(client).answerNumber(rollcall, input);
      success = result.success;
      if (mounted) {
        _toast(result.success ? '签到成功' : (result.message ?? '签到失败'));
      }
    } catch (_) {
      if (mounted) {
        _toast('签到请求失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
    if (success) {
      await _refresh();
    }
  }

  /// 扫码签到：把扫到的二维码内容提交给一网畅学。
  Future<void> _signByQr(Rollcall rollcall) async {
    final client = JwglAuth.instance.client;
    if (client == null) {
      _toast('请先登录教务系统');
      return;
    }
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const QrScanPage()),
    );
    if (raw == null || raw.isEmpty || !mounted) {
      return;
    }
    setState(() => _loading = true);
    var success = false;
    try {
      final result = await RollcallApi(client).answerQr(rollcall, raw);
      success = result.success;
      if (mounted) {
        _toast(result.success ? '签到成功' : (result.message ?? '签到失败'));
      }
    } catch (_) {
      if (mounted) {
        _toast('签到请求失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
    if (success) {
      await _refresh();
    }
  }

  /// 学习通扫码签到：扫老师屏幕上的二维码，用它自带的 id/enc 直接完成签到。
  ///
  /// 和一网畅学的签到是两套系统：一网畅学要 POST 到 RollcallApi，
  /// 学习通则是「GET 那个二维码地址」本身就算签到（详见 ChaoxingClient.signByQr）。
  /// 学习通签到入口：支持「拍照/直接签到」与「扫码签到」双通道
  Future<void> _handleChaoxingSign(ChaoxingActivity activity) async {
    final client = ChaoxingAuth.instance.client;
    if (client == null) {
      _toast('请先登录学习通');
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.how_to_reg_outlined,
                      color: AppColors.usstRed,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${activity.courseName} · 签到',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFF1F0),
                  child: Icon(
                    Icons.camera_alt_outlined,
                    color: AppColors.usstRed,
                  ),
                ),
                title: const Text(
                  '拍照 / 直接签到',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('支持拍照上传、普通签到、手势及位置签到'),
                onTap: () => Navigator.of(ctx).pop('web'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE6F4FF),
                  child: Icon(Icons.qr_code_scanner, color: Color(0xFF1677FF)),
                ),
                title: const Text(
                  '扫描二维码签到',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('扫描教师投影屏幕上展示的签到二维码'),
                onTap: () => Navigator.of(ctx).pop('qr'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == 'web') {
      final signUrl = _chaoxingSignPageUrl(activity, client);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SimpleWebPage(
            title: '${activity.courseName} · 签到',
            url: signUrl,
            cookies: client.jar.cookies,
          ),
        ),
      );
      if (mounted) {
        await _refreshChaoxing();
      }
    } else if (choice == 'qr') {
      await _signChaoxingByQr(activity);
    }
  }

  /// 学习通签到页地址。
  ///
  /// 优先用活动列表返回的 `url`——官方客户端就是把这个地址交给 WebView。
  /// 之前自己拼 `widget/sign/e?id=..&c=<活动ID>` 是错的：二维码里的 `c` 是
  /// 每 10 秒轮换的校验值，不是活动 id，拼出来必然打不开或提示已失效。
  String _chaoxingSignPageUrl(
    ChaoxingActivity activity,
    ChaoxingClient client,
  ) {
    final raw = activity.url.trim();
    if (raw.isNotEmpty) {
      final uri = Uri.tryParse(raw);
      if (uri != null) {
        if (uri.hasScheme) {
          return raw;
        }
        return Uri.parse('https://mobilelearn.chaoxing.com/')
            .resolve(raw)
            .toString();
      }
    }

    String cookie(String name) {
      for (final item in client.jar.cookies) {
        if (item.name == name && item.value.isNotEmpty) {
          return item.value;
        }
      }
      return '';
    }

    final uid = cookie('_uid').isNotEmpty ? cookie('_uid') : cookie('UID');
    final fid = cookie('fid');
    return Uri.parse('https://mobilelearn.chaoxing.com/newsign/preSign')
        .replace(
          queryParameters: <String, String>{
            'general': '1',
            'sys': '1',
            'ls': '1',
            'appType': '15',
            'tid': '',
            'ut': 's',
            'activePrimaryId': activity.id,
            'courseId': activity.courseId,
            'classId': activity.classId,
            if (uid.isNotEmpty) 'uid': uid,
            if (fid.isNotEmpty) 'fid': fid,
          },
        )
        .toString();
  }

  Future<void> _signChaoxingByQr(ChaoxingActivity activity) async {
    final client = ChaoxingAuth.instance.client;
    if (client == null) {
      _toast('请先登录学习通');
      return;
    }
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const QrScanPage()),
    );
    if (raw == null || raw.isEmpty || !mounted) {
      return;
    }
    _cxLoading = true;
    var signed = false;
    try {
      final result = await client.signByQr(raw);
      signed = result.success;
      if (mounted) {
        _toast(result.message);
      }
    } catch (e) {
      if (mounted) {
        _toast('签到请求失败：$e');
      }
    } finally {
      if (mounted) {
        _cxLoading = false;
      }
    }
    if (signed) {
      await _refreshChaoxing();
    }
  }

  /// 雷达签到。
  ///
  /// 正常模式固定用本机室内 GPS（WGS-84 转 GCJ-02）上报；只有内部模式打开后
  /// 才按「选定基准点」换成教师基准点/教学楼。坐标解析见 [resolveRadarTarget]。
  Future<void> _signByRadar(Rollcall rollcall) async {
    final client = JwglAuth.instance.client;
    if (client == null) {
      _toast('请先登录教务系统');
      return;
    }
    setState(() => _loading = true);
    var success = false;
    try {
      await InternalMode.instance.ensureLoaded();
      final settings = InternalMode.instance.settings.value;
      final internal = settings.enabled;
      final mode = internal ? settings.radarMode : RadarLocationMode.device;
      final buildingId = internal ? settings.buildingId : null;

      // 教师基准点 / 教学楼基准点不需要定位权限，先不申请。
      var target = resolveRadarTarget(
        rollcall: rollcall,
        mode: mode,
        preferredBuildingId: buildingId,
      );
      if (target == null &&
          (mode == RadarLocationMode.device ||
              mode == RadarLocationMode.auto)) {
        final device = await _deviceRadarLocation();
        if (device == null) {
          return;
        }
        target = resolveRadarTarget(
          rollcall: rollcall,
          mode: mode,
          preferredBuildingId: buildingId,
          devicePosition: device,
        );
      }
      if (target == null) {
        _toast(
          mode == RadarLocationMode.teacher
              ? '这次点名平台没有下发教师基准点，请在内部模式改成「自动」或「本机定位」'
              : '定位失败：没能确定签到基准点，请到教室后重试',
        );
        return;
      }
      final SignResult result;
      try {
        result = await RollcallApi(client).reportRadarPosition(
          rollcall,
          target.latitude,
          target.longitude,
          accuracy: target.accuracy,
        );
      } catch (_) {
        if (mounted) {
          _toast('签到请求失败，请稍后重试');
        }
        return;
      }
      success = result.success;
      if (mounted) {
        // 正常模式只说「已上报」，内部模式才显示用的是哪个基准点
        final basis = target.source == RadarTargetSource.device || !internal
            ? ''
            : '（${target.label}）';
        _toast(result.success ? '雷达签到已上报$basis' : (result.message ?? '雷达签到失败'));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
    if (success) {
      await _refresh();
    }
  }

  /// 取本机定位（WGS-84）；失败时提示（必要时跳系统设置）并返回 null。
  Future<DeviceLocation?> _deviceRadarLocation() async {
    final result = await RadarLocationService.instance.locate();
    if (result.ok) {
      return result.location;
    }
    if (mounted && result.message != null) {
      _toast(result.message!);
    }
    return null;
  }
  Future<void> _openTodo(LmsTodo todo) async {
    if (todo.type == 'exam' || todo.type == 'quiz') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TronExamDetailPage(
            courseId: todo.courseId.toString(),
            examId: todo.id,
            courseName: todo.courseName,
          ),
        ),
      );
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => HomeworkPage(todo: todo)));
  }

  Future<List<CasCookie>> _lmsCookies() async {
    return TronclassAuth.instance.getMergedCookies();
  }

  Future<void> _openLms() async {
    final cookies = await _lmsCookies();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimpleWebPage(
          title: '一网畅学',
          url: 'https://1906.usst.edu.cn/user/index',
          cookies: cookies,
        ),
      ),
    );
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.usstRed,
          onRefresh: _refreshAllServices,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '校园服务',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              RollcallCard(
                rollcalls: _rollcalls,
                cxActivities: _cxActivities,
                error: _error,
                refreshing: _rollcallsRefreshing || _loading,
                onRefresh: _refreshRollcallsOnly,
                onRetry: _retryTronclass,
                onSignRollcall: (rollcall) => _signAction(rollcall)?.call(),
                onSignChaoxing: _handleChaoxingSign,
              ),
              if (_exams.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                LifeExamCard(exams: _exams),
              ],
              const SizedBox(height: 12),
              LifeTodoCard(
                todos: _todos,
                cxWorks: _cxWorks,
                todosError: _todosError,
                cxError: _cxError,
                onOpenTodo: _openTodo,
                onOpenCxWork: _openCxWork,
              ),
              const SizedBox(height: 12),
              LifeCourseCard(
                courseInfos: _courseInfos,
                onOpenCourse: _openCourse,
                coursesLoading: _coursesLoading,
                coursesError: _coursesError,
                showChaoxingCourses: _showChaoxingCourses,
                onToggleSource: _toggleCourseSource,
                onRetry: () => _loadCourses(),
                onLoginChaoxing: () => _loginChaoxing(),
              ),
              const SizedBox(height: 12),
              DormElectricityCard(
                info: _dormElect,
                fetchedAt: _dormFetchedAt,
                loading: _dormLoading,
                error: _dormError,
                canFetch:
                    JwglAuth.instance.client != null ||
                    JwglAuth.instance.hasSavedPassword,
                onRefresh: () => _loadDormElectricity(force: true),
                onLogin: _loginThenLoadDorm,
              ),
              const SizedBox(height: 12),
              const QuickToolsRow(),
            ],
          ),
        ),
      ),
    );
  }

  void _openCxWork(ChaoxingWork work) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChaoxingHomeworkPage(work: work)),
    );
  }

  List<LmsExam> _filterExams(List<LmsExam> exams) {
    if (exams.isEmpty) {
      return exams;
    }
    final target = _normalizeTerm(
      _currentTerm.isNotEmpty ? _currentTerm : CalendarService.fallbackTermId(),
    );
    // 只显示目标学期；没有该学期考试时宁可隐藏，也不退回去显示旧学期。
    return exams.where((e) => _normalizeTerm(e.termLabel) == target).toList();
  }

  static String _normalizeTerm(String raw) {
    var s = raw.replaceAll(' ', '').replaceAll('学年', '');
    s = s.replaceAll('第一学期', '1').replaceAll('第二学期', '2');
    s = s.replaceAll('第1学期', '1').replaceAll('第2学期', '2');
    s = s.replaceAll('第', '-').replaceAll('学期', '');
    return s;
  }
}

/// 数字口令签到输入框。
///
/// 单独做成 StatefulWidget，由它自己持有并释放 `TextEditingController`。
