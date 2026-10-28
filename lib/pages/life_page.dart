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
import 'chaoxing_course_detail_page.dart';
import 'course_detail_page.dart';
import 'homework_page.dart';
import 'login_page.dart';
import 'map_page.dart';
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
        _dormError = e.message;
        _dormLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _dormError = '查询失败：$e';
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

  String _signLabel(Rollcall rollcall) {
    if (rollcall.isSigned) {
      return '已签到';
    }
    if (rollcall.isExpired) {
      return '已结束';
    }
    if (rollcall.isNumberRollcall) {
      return '输入口令';
    }
    if (rollcall.isRadarRollcall) {
      return '雷达签到';
    }
    if (rollcall.isQrRollcall) {
      return '扫码签到';
    }
    return '去签到';
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => HomeworkPage(todo: todo)));
  }

  Future<List<CasCookie>> _lmsCookies() async {
    final tronclass = await TronclassAuth.instance.loadCookies();
    final cas = JwglAuth.instance.client?.jar.cookies ?? const <CasCookie>[];
    final cookies = <CasCookie>[];
    final seen = <String>{};
    for (final cookie in <CasCookie>[...cas, ...tronclass]) {
      if (seen.add('${cookie.name}|${cookie.domain}|${cookie.path}')) {
        cookies.add(cookie);
      }
    }
    return cookies;
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text(
                  '校园服务',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: '刷新',
                    onPressed: () async {
                      await _refresh();
                      await _refreshChaoxing(
                        withWorks: true,
                        autoLogin: true,
                      );
                    },
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _quickToolsRow(),
            const SizedBox(height: 12),
            _rollcallCard(),
            if (_exams.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _examCard(),
            ],
            const SizedBox(height: 12),
            _todoCard(),
            const SizedBox(height: 12),
            _courseCard(),
            const SizedBox(height: 12),
            _dormElectricityCard(),
          ],
        ),
      ),
    );
  }

  
  Widget _quickToolsRow() {
    return Row(
      children: <Widget>[
        Expanded(
          child: _quickToolTile(
            icon: Icons.map_outlined,
            title: '校园地图',
            desc: '自绘瓦片 · 楼栋定位',
            color: const Color(0xFF1E88E5),
            bgColor: const Color(0xFFE8F3FC),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const MapPage()),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _quickToolTile(
            icon: Icons.meeting_room_outlined,
            title: '教室查询',
            desc: '教学楼 · 自习空间',
            color: AppColors.usstRed,
            bgColor: const Color(0xFFFDE8E8),
            onTap: () {
              _toast('空教室功能正在接入中，可先通过「校园地图」查看教学楼分布');
            },
          ),
        ),
      ],
    );
  }

  Widget _quickToolTile({
    required IconData icon,
    required String title,
    required String desc,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEDEDED), width: 0.8),
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _courseCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
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
                Icons.menu_book_outlined,
                size: 18,
                color: AppColors.usstRed,
              ),
              const SizedBox(width: 8),
              const Text(
                '课程信息',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${_courseInfos.length} 门',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              _courseSourceSwitch(),
            ],
          ),
          const SizedBox(height: 10),
          if (_coursesLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_coursesError != null)
            // 学习通没登录时，「重试」点了也没用，直接给登录入口
            _showChaoxingCourses && !ChaoxingAuth.instance.isLoggedIn
                ? _chaoxingLoginHint(_coursesError!)
                : Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _coursesError!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _loadCourses,
                        child: const Text('重试', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  )
          else if (_courseInfos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '本学期暂无课程',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            )
          else
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _courseInfos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _courseTile(_courseInfos[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _courseSourceSwitch() {
    final isCx = _showChaoxingCourses;
    final color = isCx ? AppColors.usstRed : const Color(0xFF3B5BDB);
    return GestureDetector(
      onTap: _toggleCourseSource,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isCx ? AppColors.redTint : const Color(0xFFE3EAFE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Image.asset(
              isCx
                  ? 'assets/sources/chaoxing_tab.png'
                  : 'assets/sources/tronclass_tab.png',
              width: 13,
              height: 13,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(width: 4),
            Text(
              isCx ? '学习通' : '一网畅学',
              style: TextStyle(
                fontSize: 10.5,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.swap_horiz, size: 13, color: color),
          ],
        ),
      ),
    );
  }

  Widget _courseTile(LmsCourseInfo course) {
    final color = _showChaoxingCourses
        ? const Color(0xFFFDF2F2)
        : const Color(0xFFEFF5FF);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (_showChaoxingCourses) {
          final match = _cxCourses.where((c) => c.courseId == course.id);
          if (match.isEmpty) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChaoxingCourseDetailPage(
                courseName: course.name,
                course: match.first,
              ),
            ),
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TronCourseDetailPage(
              courseName: course.name,
              courseId: course.id,
            ),
          ),
        );
      },
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              course.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const Spacer(),
            Text(
              course.teacher.isEmpty ? '教师待补充' : course.teacher,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rollcallCard() {
    return Container(
      padding: const EdgeInsets.all(16),
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
                Icons.how_to_reg_outlined,
                size: 18,
                color: AppColors.usstRed,
              ),
              const SizedBox(width: 8),
              const Text(
                '进行中的签到',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (_rollcalls.isNotEmpty || _cxActivities.isNotEmpty)
                Text(
                  '${_rollcalls.length + _cxActivities.length} 个',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_error != null && _rollcalls.isEmpty && _cxActivities.isEmpty)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                TextButton(onPressed: _retryTronclass, child: const Text('重试')),
              ],
            )
          else if (_rollcalls.isEmpty && _cxActivities.isEmpty)
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '暂无进行中的签到',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '老师发起签到后，点右上角刷新按钮即可看到',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            )
          else
            Column(
              children: <Widget>[
                for (final rollcall in _rollcalls) _rollcallTile(rollcall),
                for (final activity in _cxActivities) _cxActivityTile(activity),
              ],
            ),
        ],
      ),
    );
  }

  Widget _rollcallTile(Rollcall rollcall) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF5FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE3EAFE),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '一网畅学',
              style: TextStyle(fontSize: 10, color: Color(0xFF3B5BDB)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  rollcall.courseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${rollcall.typeLabel}'
                  '${rollcall.timeText.isEmpty ? '' : ' · ${rollcall.timeText}'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: _signAction(rollcall),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 32),
            ),
            child: Text(
              _signLabel(rollcall),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cxActivityTile(ChaoxingActivity activity) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF2F2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.redTint,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '学习通',
              style: TextStyle(fontSize: 10, color: AppColors.usstRed),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  activity.courseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${activity.typeLabel} · ${activity.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _signChaoxingByQr(activity),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('扫码签到', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  int _todoFilter = 0; // 0: 全部合流, 1: 一网畅学, 2: 学习通

  Widget _todoCard() {
    final cxActive = _cxWorks.where((w) => !w.finished && !w.expired).length;
    final tronActive = _todos.length;
    final total = cxActive + tronActive;

    final String countLabel;
    if (_todoFilter == 0) {
      countLabel = '$total 个';
    } else if (_todoFilter == 1) {
      countLabel = '$tronActive 个';
    } else {
      countLabel = '$cxActive 个';
    }

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
                countLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              _todoSourceSwitch(),
            ],
          ),
          if (_todoFilter == 0)
            _unifiedTodoBody()
          else if (_todoFilter == 1)
            _lmsTodoBody()
          else
            _cxTodoBody(),
        ],
      ),
    );
  }

  Widget _todoSourceSwitch() {
    final String label;
    final Color color;
    final Color bgColor;

    if (_todoFilter == 0) {
      label = '全部合流';
      color = const Color(0xFF2E7D32);
      bgColor = const Color(0xFFE8F5E9);
    } else if (_todoFilter == 1) {
      label = '一网畅学';
      color = const Color(0xFF3B5BDB);
      bgColor = const Color(0xFFE3EAFE);
    } else {
      label = '学习通';
      color = AppColors.usstRed;
      bgColor = AppColors.redTint;
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _todoFilter = (_todoFilter + 1) % 3;
        });
        if (_todoFilter == 2 && ChaoxingAuth.instance.isLoggedIn && _cxWorks.isEmpty) {
          _refreshChaoxing(withWorks: true);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.swap_horiz, size: 13, color: color),
          ],
        ),
      ),
    );
  }

  Widget _unifiedTodoBody() {
    final items = <({
      String id,
      String title,
      String course,
      String source,
      DateTime? deadline,
      String deadlineText,
      VoidCallback onTap,
    })>[];

    for (final t in _todos) {
      items.add((
        id: 'tron_${t.id}',
        title: t.title,
        course: _cleanCourseName(t.courseName),
        source: '一网畅学',
        deadline: t.deadline,
        deadlineText: _ddlCountdown(t.deadline),
        onTap: () => _openTodo(t),
      ));
    }

    for (final w in _cxWorks) {
      if (w.finished || w.expired) continue;
      final clean = w.deadline.replaceAll('截止时间：', '').replaceAll('截止：', '').trim();
      final dt = DateTime.tryParse(clean);
      items.add((
        id: 'cx_${w.workId}',
        title: w.title,
        course: _cleanCourseName(w.courseName),
        source: '学习通',
        deadline: dt,
        deadlineText: dt != null ? _ddlCountdown(dt) : w.deadline,
        onTap: () => _openCxWork(w),
      ));
    }

    items.sort((a, b) {
      if (a.deadline == null && b.deadline == null) return 0;
      if (a.deadline == null) return 1;
      if (b.deadline == null) return -1;
      return a.deadline!.compareTo(b.deadline!);
    });

    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            '暂无待办作业，尽情享受自由时光 ☕',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return SizedBox(
      height: 180,
      child: ListView.separated(
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

  Widget _lmsTodoBody() {
    if (_todosError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _todosError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _refresh(),
              child: const Text('重试', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }
    if (_todos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text(
          '暂无待办',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }
    return SizedBox(
      height: 168,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 8),
        itemCount: _todos.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _todoTile(_todos[i]),
      ),
    );
  }

  /// 「学习通未登录 / 登录失效」统一提示 + 登录按钮（待办和课程信息共用）。
  Widget _chaoxingLoginHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          FilledButton(
            onPressed: _loginChaoxing,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text('登录', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _cxTodoBody() {
    final auth = ChaoxingAuth.instance;
    if (!auth.isLoggedIn) {
      return _chaoxingLoginHint('学习通未登录');
    }
    if (_cxLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_cxError != null) {
      // 会话过期时 ensureSession 会把登录态清掉，这里直接把「重试」换成「重新登录」，
      // 免得用户点半天重试都不知道要重新走一次网页登录
      final needLogin = !ChaoxingAuth.instance.isLoggedIn;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _cxError!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: needLogin
                  ? _loginChaoxing
                  : () => _refreshChaoxing(withWorks: true),
              child: Text(
                needLogin ? '重新登录' : '重试',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
    final pending = _cxWorks.where((w) => !w.finished && !w.expired).toList();
    final expired = _cxWorks.where((w) => !w.finished && w.expired).length;
    final expiredHint = expired == 0
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '另有 $expired 个已截止未交',
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
              ),
            ),
          );
    if (pending.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '暂无待交作业',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            ?expiredHint,
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 168,
          child: ListView.separated(
            padding: const EdgeInsets.only(top: 8),
            itemCount: pending.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _cxWorkTile(pending[i]),
          ),
        ),
        ?expiredHint,
      ],
    );
  }

  Widget _cxWorkTile(ChaoxingWork work) {
    // 学习通给的是「剩余91小时40分钟」这种文本，转成更好读的倒计时
    final remaining = ReminderService.parseRemaining(work.deadline);
    final countdown = work.expired
        ? '已截止'
        : (remaining == null ? '' : _humanRemaining(remaining));
    return GestureDetector(
      onTap: () => _openCxWork(work),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8FA),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.redTint,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '作业',
                style: TextStyle(fontSize: 10, color: AppColors.usstRed),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    work.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    work.courseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (countdown.isNotEmpty) ...<Widget>[
              const SizedBox(width: 8),
              Text(
                countdown,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: work.expired
                      ? AppColors.textSecondary
                      : _urgencyColor(remaining),
                ),
              ),
            ],
            const Icon(
              Icons.chevron_right,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  void _openCxWork(ChaoxingWork work) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChaoxingHomeworkPage(work: work)),
    );
  }

  Widget _todoTile(LmsTodo todo) {
    final deadline = todo.deadline;
    final absolute = deadline == null ? '' : _formatDateTime(deadline);
    final countdown = _ddlCountdown(deadline);
    // 接口给的课程名带学期和课程代码（工程力学C(2026-2027-1)-14000282-01），
    // 原来和截止时间拼在一行被省略号吃掉，这里先清洗，再把时间单独摆开。
    final course = _cleanCourseName(todo.courseName);
    return GestureDetector(
      onTap: () => _openTodo(todo),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8FA),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE3EAFE),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                todo.typeLabel,
                style: const TextStyle(fontSize: 10, color: Color(0xFF3B5BDB)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    todo.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: <Widget>[
                      // 课程名可以被截断，截止时间不能
                      if (course.isNotEmpty)
                        Flexible(
                          child: Text(
                            course,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      if (absolute.isNotEmpty) ...<Widget>[
                        if (course.isNotEmpty)
                          const Text(
                            ' · ',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        Text(
                          '截止 $absolute',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (countdown.isNotEmpty) ...<Widget>[
              const SizedBox(width: 8),
              Text(
                countdown,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _ddlColor(deadline),
                ),
              ),
            ],
            const Icon(
              Icons.chevron_right,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  /// 待办里的剩余时间提示：还有 5 小时 / 还有 3 天 / 已逾期。
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

  Widget _examCard() {
    if (_exams.isEmpty) {
      return const SizedBox.shrink();
    }
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
                Icons.event_note_outlined,
                size: 18,
                color: AppColors.usstRed,
              ),
              const SizedBox(width: 8),
              const Text(
                '考试安排',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${_exams.length} 场',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          SizedBox(
            height: 150,
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 8),
              itemCount: _exams.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _examTile(_exams[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _examTile(LmsExam exam) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            exam.courseName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            <String>[
              if (exam.termLabel.isNotEmpty) exam.termLabel,
              exam.timePending ? '时间待公布' : exam.timeText,
              if (exam.location.isNotEmpty) exam.location,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
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

  String _formatDateTime(DateTime time) {
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    return '$m-$d $h:$min';
  }

  // ------------------------------------------------------------ 宿舍电费

  Widget _dormElectricityCard() {
    final info = _dormElect;
    final hasPwd = JwglAuth.instance.hasSavedPassword;
    // 有教务 CAS 会话也能 SSO 到 ssgl，不一定要保存密码。
    final canFetch = JwglAuth.instance.client != null || hasPwd;
    final title = _dormFetchedAt == null
        ? '宿舍电费 · 未刷新'
        : '宿舍电费 · ${_formatDormTime(_dormFetchedAt!)} 更新';
    final subtitle = info != null
        ? info.dormAddress
        : canFetch
        ? '点右上角刷新'
        : '登录后可查询照明 / 空调余量';

    return GestureDetector(
      onTap: canFetch
          ? () => _loadDormElectricity(force: true)
          : _loginThenLoadDorm,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.redTint,
                  child: Icon(Icons.bolt, color: AppColors.usstRed),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                if (_dormLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 6),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    tooltip: '刷新电费',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: canFetch
                        ? () => _loadDormElectricity(force: true)
                        : _loginThenLoadDorm,
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
              ],
            ),
            if (info != null) ...<Widget>[
              const SizedBox(height: 12),
              _electricityRow(
                '照明',
                info.zmKwh,
                info.zmMoney,
                info.zmMoneyValue,
              ),
              if (info.hasAirConditioner) ...<Widget>[
                const SizedBox(height: 6),
                _electricityRow(
                  '空调',
                  info.ktKwh,
                  info.ktMoney,
                  info.ktMoneyValue,
                ),
              ],
            ],
            if (_dormError != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _dormError!,
                style: const TextStyle(fontSize: 11, color: AppColors.usstRed),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDormTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  Widget _electricityRow(
    String label,
    String kwh,
    String money,
    double? moneyValue,
  ) {
    final arrears = moneyValue != null && moneyValue < 0;
    final color = arrears ? AppColors.usstRed : AppColors.textPrimary;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            kwh,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        Text(
          money,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        if (arrears)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Text(
              '欠费',
              style: TextStyle(fontSize: 10, color: AppColors.usstRed),
            ),
          ),
      ],
    );
  }
}
