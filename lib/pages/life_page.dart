import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app_theme.dart';
import '../data/auth/cas_client.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/calendar/calendar_service.dart';
import '../data/chaoxing/chaoxing_auth.dart';
import '../data/chaoxing/chaoxing_cache.dart';
import '../data/chaoxing/chaoxing_client.dart';
import '../data/chaoxing/chaoxing_sso.dart';
import '../data/geo/coordinate_utils.dart';
import '../data/jwc/course_repository.dart';
import '../data/life_cache.dart';
import '../data/lms/rollcall_api.dart';
import '../data/lms/course_info_cache.dart';
import '../data/lms/todo_api.dart';
import '../data/lms/tronclass_auth.dart';
import '../services/dorm_electricity_service.dart';
import '../services/reminder_service.dart';
import 'chaoxing_homework_page.dart';
import 'chaoxing_login_page.dart';
import 'homework_page.dart';
import 'tron_exam_detail_page.dart';
import 'life/widgets/dorm_electricity_card.dart';
import 'life/widgets/life_course_card.dart';
import 'life/widgets/life_exam_card.dart';
import 'life/widgets/life_todo_card.dart';
import 'life/widgets/quick_tools_row.dart';
import 'life/widgets/rollcall_card.dart';
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

  // 学习通
  bool _cxLoading = false;
  String? _cxError;
  List<ChaoxingCourse> _cxCourses = const <ChaoxingCourse>[];
  List<ChaoxingActivity> _cxActivities = const <ChaoxingActivity>[];
  List<ChaoxingWork> _cxWorks = const <ChaoxingWork>[];

  // 宿舍电费
  DormElectricity? _dormElect;
  DateTime? _dormFetchedAt;
  DormElectricityService? _dormService;
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
    _bootstrap();
  }

  @override
  void dispose() {
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
    if (!mounted || !_bootstrapped) {
      return;
    }
    setState(() {
      _courseInfos = const <LmsCourseInfo>[];
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
      _dormLoading = false;
      _loading = false;
      _coursesLoading = false;
      _cxLoading = false;
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
    setState(() => _rollcallsRefreshing = true);
    try {
      final auth = JwglAuth.instance;
      if (auth.isLoggedIn && auth.client != null) {
        try {
          await TronclassAuth.instance.ensureLoggedIn();
          final rc = await RollcallApi(auth.client!).fetchOngoing();
          if (mounted) {
            setState(() => _rollcalls = rc);
          }
        } catch (_) {}
      }
      await _refreshChaoxing(withWorks: false, autoLogin: true);
    } finally {
      if (mounted) {
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

  Future<void> _bootstrap() async {
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
    if (cached != null) {
      _dormElect = cached;
      _dormFetchedAt = DormElectricityCache.fetchedAtFor(username);
    }
    // 有缓存先展示；缓存超过 10 分钟再静默刷新，没有缓存也拉一次。
    final age = DormElectricityCache.ageFor(username);
    final stale = cached == null || age == null || age >= _dormCacheTtl;
    // 有教务会话（可走 SSO）或有保存的密码，才值得去刷新
    final canFetch = JwglAuth.instance.client != null || auth.hasSavedPassword;
    if (canFetch && stale) {
      unawaited(_loadDormElectricity());
    }
    _bootstrapped = true;
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
        _dormLoading = false;
      });
    } on DormElectricityException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _dormError = '${e.message}（请使用校园网访问）';
        _dormLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _dormError = '查询失败，请使用校园网访问';
        _dormLoading = false;
      });
    }
  }

  Future<void> _loginThenLoadDorm() async {
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute<bool>(builder: (_) => const LoginPage()));
    if (ok == true && mounted) {
      _dormService = null;
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
    if (_cxLoading) {
      return;
    }
    setState(() {
      _cxLoading = true;
      _cxError = null;
    });
    final cacheUser = JwglAuth.instance.savedUsername;
    if (cacheUser.isNotEmpty && JwglAuth.instance.isLoggedIn) {
      final cached = await ChaoxingCache.read(cacheUser);
      if (mounted &&
          cached != null &&
          JwglAuth.instance.savedUsername == cacheUser) {
        setState(() {
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
      if (!ready || !mounted) {
        if (mounted) {
          setState(() {
            _cxActivities = const <ChaoxingActivity>[];
            _cxWorks = const <ChaoxingWork>[];
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
      final currentCourses = _timetableNames.isEmpty
          ? rawCourses
          : rawCourses
                .where(
                  (c) => _timetableNames.contains(_cleanCourseName(c.name)),
                )
                .toList();
      final needWorks = withWorks || _cxWorks.isEmpty;
      // 签到和作业都只看当前学期的课：
      // 往期课的作业早就截止了，放进待办只会干扰当前任务。
      final activitiesFuture = client.fetchActivities(currentCourses);
      final worksFuture = needWorks
          ? client.fetchWorks(currentCourses)
          : Future<List<ChaoxingWork>>.value(_cxWorks);
      final activities = await activitiesFuture;
      final works = await worksFuture;
      if (!mounted) {
        return;
      }
      setState(() {
        _cxCourses = currentCourses;
        _cxActivities = activities;
        _cxWorks = works;
      });
      if (cacheUser.isNotEmpty &&
          JwglAuth.instance.savedUsername == cacheUser) {
        unawaited(ChaoxingCache.writeCourses(cacheUser, currentCourses));
        unawaited(ChaoxingCache.writeActivities(cacheUser, activities));
        unawaited(ChaoxingCache.writeWorks(cacheUser, works));
      }
      // 学习通只有「剩余 X 小时」这种相对时间，拉到列表时换算成绝对时间排提醒
      if (works.isNotEmpty) {
        await ReminderService.instance.syncChaoxingWorks(works);
      }
      // 自动登录完成后，如果当前正停在学习通课程源，把课程卡片也刷新掉
      if (_showChaoxingCourses && mounted) {
        unawaited(_loadCourses(force: true));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cxError = '学习通数据拉取失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        setState(() => _cxLoading = false);
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

  Future<void> _refresh({bool silent = false, bool force = false}) async {
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
    final requestUser = JwglAuth.instance.savedUsername;
    try {
      // 每次刷新前确认一网畅学会话；半失效时内部会自动重登
      await TronclassAuth.instance.ensureLoggedIn();
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
        // 接口偶发返回空时保留旧数据，避免界面突然「全没了」
        if (fetched.isNotEmpty || _todos.isEmpty) {
          todos = fetched;
        }
        todosFetched = true;
      } catch (e) {
        todosError = '待办拉取失败：${e.toString().split("\n").first}';
      }
      try {
        final fetched = await LmsApi(client).fetchExams();
        if (fetched.isNotEmpty || _exams.isEmpty) {
          exams = fetched;
        }
        examsFetched = true;
      } catch (_) {
        // 考试安排失败保留旧数据
      }
      if (!todosFetched && !examsFetched && _todos.isEmpty && _exams.isEmpty) {
        // 两个都失败且无数据时给个提示
        if (mounted) {
          setState(() => _error = '学习数据拉取失败，请稍后重试');
        }
      }
      if (!mounted || JwglAuth.instance.savedUsername != requestUser) {
        return;
      }
      setState(() {
        _rollcalls = rollcalls;
        _todos = todos;
        _exams = _filterExams(exams);
        _todosError = todosError;
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
    } catch (_) {
      if (mounted && !silent) {
        setState(() => _error = '签到信息拉取失败，请稍后重试');
      }
    } finally {
      if (mounted) {
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

  static String _cleanCourseName(String raw) {
    return raw
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        // 只去掉 (2026-2027-1) 这种学期后缀，保留课程本身的 (1)/(2)
        .replaceAll(RegExp(r'\(\d{4}-\d{4}-\d\)-.*$'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

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
    if (_coursesLoading) return;
    final termKey = _currentTerm.isNotEmpty
        ? _currentTerm
        : CalendarService.fallbackTermId();
    final source = _showChaoxingCourses ? 'chaoxing' : 'tronclass';
    final cacheUser = JwglAuth.instance.savedUsername;
    // 缓存优先：有缓存先渲染；缓存过期就不显示加载态、后台静默刷一遍。
    var silent = false;
    if (!force) {
      final cached = await CourseInfoCache.load(
        termKey,
        source,
        username: cacheUser,
      );
      if (cached != null) {
        if (mounted) {
          setState(() {
            _courseInfos = cached;
            _coursesError = null;
          });
        }
        if (await CourseInfoCache.isFresh(
          termKey,
          source,
          username: cacheUser,
        )) {
          return;
        }
        silent = true;
      }
    }
    if (!silent) {
      setState(() {
        _coursesLoading = true;
        _coursesError = null;
      });
    }
    try {
      if (!_showChaoxingCourses) {
        final auth = JwglAuth.instance;
        if (!auth.isLoggedIn) {
          await auth.restore();
        }
        await TronclassAuth.instance.ensureLoggedIn();
        final client = auth.client;
        if (client == null) {
          if (!silent) setState(() => _coursesError = '请先登录教务系统');
          return;
        }
        final list = await LmsApi(client).fetchCourseInfos();
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
        if (mounted && JwglAuth.instance.savedUsername == cacheUser) {
          setState(() => _courseInfos = filtered);
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
          if (mounted && !silent) {
            setState(() {
              _courseInfos = const <LmsCourseInfo>[];
              _coursesError = hadSession ? '学习通登录已失效' : '学习通未登录';
            });
          }
          return;
        }
        final client = auth.client;
        if (client == null) return;
        final courses = _cxCourses.isNotEmpty
            ? _cxCourses
            : await client.fetchCourses();
        _cxCourses = courses;
        // 学习通列表没有 termCode，用本学期课表课程名过滤掉往期课程；
        // 课表/一网畅学都拿不到时才退回全量（至少不误藏当前课程）。
        await _ensureCurrentCourseNames();
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
        if (mounted) setState(() => _courseInfos = filtered);
      }
    } catch (_) {
      // 静默刷新失败就保持缓存内容，不打扰用户
      if (mounted && !silent) {
        setState(() => _coursesError = '课程信息拉取失败');
      }
    } finally {
      if (mounted && !silent) setState(() => _coursesLoading = false);
    }
  }

  void _toggleCourseSource() {
    setState(() {
      _showChaoxingCourses = !_showChaoxingCourses;
      _courseInfos = const <LmsCourseInfo>[];
    });
    _loadCourses();
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
              subtitle: const Text('自主签到等暂不支持的类型'),
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

  /// 数字口令签到：输入老师给的口令后直接提交。
  Future<void> _signByNumber(Rollcall rollcall) async {
    final client = JwglAuth.instance.client;
    if (client == null) {
      _toast('请先登录教务系统');
      return;
    }
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${rollcall.courseName} · 数字口令'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: '输入老师给出的签到口令',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('签到'),
          ),
        ],
      ),
    );
    controller.dispose();
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
                    const Icon(Icons.how_to_reg_outlined, color: AppColors.usstRed, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${activity.courseName} · 签到',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
                  child: Icon(Icons.camera_alt_outlined, color: AppColors.usstRed),
                ),
                title: const Text('拍照 / 直接签到', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('支持拍照上传、普通签到、手势及位置签到'),
                onTap: () => Navigator.of(ctx).pop('web'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE6F4FF),
                  child: Icon(Icons.qr_code_scanner, color: Color(0xFF1677FF)),
                ),
                title: const Text('扫描二维码签到', style: TextStyle(fontWeight: FontWeight.w600)),
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
      final signUrl =
          'https://mobilelearn.chaoxing.com/widget/sign/e?id=${activity.id}&c=${activity.id}&classId=${activity.classId}&courseId=${activity.courseId}';
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
    setState(() => _cxLoading = true);
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
        setState(() => _cxLoading = false);
      }
    }
    if (signed) {
      await _refreshChaoxing();
    }
  }

  /// 雷达签到：用系统定位上报当前位置。
  ///
  /// 只上报真实坐标，不提供选教学楼/手填坐标的入口。
  Future<void> _signByRadar(Rollcall rollcall) async {
    final client = JwglAuth.instance.client;
    if (client == null) {
      _toast('请先登录教务系统');
      return;
    }
    setState(() => _loading = true);
    var success = false;
    try {
      final allowed = await _ensureLocationPermission();
      if (!allowed) {
        _toast('雷达签到需要定位权限，请在系统设置里允许定位');
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('系统定位服务未开启，请打开 GPS/定位开关');
        return;
      }
      try {
        if (await Geolocator.getLocationAccuracy() ==
            LocationAccuracyStatus.reduced) {
          _toast('当前只给了「大致位置」，雷达签到需要精确位置，请到系统设置里改为「精确」');
          return;
        }
      } catch (_) {
        // 部分平台不支持查询精度，继续尝试定位。
      }
      late final Position position;
      try {
        position = await _getRadarPosition();
      } catch (e) {
        if (mounted) {
          _toast(_radarLocationError(e));
        }
        return;
      }
      final SignResult result;
      try {
        // 一网畅学雷达接口要 GCJ-02；系统定位给的是 WGS-84，直接上报会偏几百米。
        final (gcjLat, gcjLng) = CoordinateUtils.wgs84ToGcj02(
          position.latitude,
          position.longitude,
        );
        result = await RollcallApi(client).reportRadarPosition(
          rollcall,
          gcjLat,
          gcjLng,
          accuracy: position.accuracy,
          altitude: position.altitude,
          altitudeAccuracy: position.altitudeAccuracy,
          heading: position.heading,
          speed: position.speed,
        );
      } catch (_) {
        if (mounted) {
          _toast('签到请求失败，请稍后重试');
        }
        return;
      }
      success = result.success;
      if (mounted) {
        _toast(result.success ? '雷达签到已上报' : (result.message ?? '雷达签到失败'));
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

  Future<bool> _ensureLocationPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// 雷达签到取坐标：先复用系统最近一次有效定位，再尝试实时高精度定位。
  ///
  /// Android 上强制走 LocationManager，避免部分机器（无 GMS / 国内 ROM）
  /// 的 FusedLocationProvider 一直不回调，最后只能超时。
  Future<Position> _getRadarPosition() async {
    try {
      final last = await Geolocator.getLastKnownPosition(
        forceAndroidLocationManager: true,
      );
      if (_isUsableLastKnown(last)) {
        return last!;
      }
    } catch (_) {
      // 忽略，继续实时定位
    }
    final android = defaultTargetPlatform == TargetPlatform.android;
    final high = android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 20),
            forceLocationManager: true,
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          );
    try {
      return await Geolocator.getCurrentPosition(locationSettings: high);
    } catch (_) {
      final medium = android
          ? AndroidSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: const Duration(seconds: 12),
              forceLocationManager: true,
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 12),
            );
      return Geolocator.getCurrentPosition(locationSettings: medium);
    }
  }

  /// 最近一次定位要够新、够准才用于签到，避免拿着上节课的旧坐标。
  bool _isUsableLastKnown(Position? position) {
    if (position == null) return false;
    final age = DateTime.now().difference(position.timestamp);
    return !age.isNegative &&
        age <= const Duration(minutes: 5) &&
        position.accuracy > 0 &&
        position.accuracy <= 100;
  }

  String _radarLocationError(Object error) {
    if (error is TimeoutException) {
      return '定位超时：请到室外/窗边，确认 GPS 已开启后重试';
    }
    if (error is LocationServiceDisabledException) {
      return '系统定位服务未开启，请打开 GPS/定位开关';
    }
    if (error is PermissionDeniedException) {
      return '定位权限被拒绝，请在系统设置里允许定位';
    }
    return '定位失败，请确认在室外并开启 GPS 后重试';
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
              const QuickToolsRow(),
              const SizedBox(height: 12),
              RollcallCard(
                rollcalls: _rollcalls,
                cxActivities: _cxActivities,
                error: _error,
                refreshing: _rollcallsRefreshing,
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
                cxCourses: _cxCourses,
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
                canFetch: JwglAuth.instance.client != null || JwglAuth.instance.hasSavedPassword,
                onRefresh: () => _loadDormElectricity(force: true),
                onLogin: _loginThenLoadDorm,
              ),
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
