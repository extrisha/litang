import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app_theme.dart';
import '../data/auth/cas_client.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/calendar/calendar_service.dart';
import '../data/chaoxing/chaoxing_auth.dart';
import '../data/chaoxing/chaoxing_client.dart';
import '../data/jwc/course_repository.dart';
import '../data/lms/rollcall_api.dart';
import '../data/lms/course_info_cache.dart';
import '../data/lms/todo_api.dart';
import '../data/lms/tronclass_auth.dart';
import '../services/reminder_service.dart';
import 'chaoxing_homework_page.dart';
import 'chaoxing_login_page.dart';
import 'chaoxing_course_detail_page.dart';
import 'course_detail_page.dart';
import 'homework_page.dart';
import 'qr_scan_page.dart';
import 'simple_web.dart';

/// 生活：签到（一网畅学）+ 一网畅学入口 + 校园卡（占位）。
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
  bool _showChaoxingTodos = false;
  bool _cxLoading = false;
  String? _cxError;
  List<ChaoxingCourse> _cxCourses = const <ChaoxingCourse>[];
  List<ChaoxingActivity> _cxActivities = const <ChaoxingActivity>[];
  List<ChaoxingWork> _cxWorks = const <ChaoxingWork>[];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final snapshot = await CourseRepository.loadCache();
    _currentTerm =
        CalendarService.instance.currentTerm?.id ?? snapshot?.termLabel ?? '';
    _timetableNames
      ..clear()
      ..addAll(
        snapshot?.courses.map((c) => _cleanCourseName(c.name)) ??
            const <String>[],
      );
    // 生活页是启动时就存在的 tab，可能比「我的」页更早初始化，
    // 这里必须先恢复登录态，否则一网畅学接口会以未登录状态返回空。
    final auth = JwglAuth.instance;
    if (!auth.isLoggedIn) {
      await auth.restore();
    }
    var ok = await TronclassAuth.instance.ensureLoggedIn();
    if (!ok) {
      // 教务会话可能刚过期，刷新一次再重试
      await JwglAuth.instance.ensureSession();
      ok = await TronclassAuth.instance.ensureLoggedIn();
    }
    if (!mounted) {
      return;
    }
    if (!ok) {
      setState(() {
        _error = '一网畅学登录失败，点「重试」重新登录';
      });
    }
    // 即使静默登录判定失败也尝试拉一次，避免误判导致整页空白
    await _refresh();
    await _refreshChaoxing();
    await _loadCourses();
  }

  /// 拉取学习通数据。cookie 失效时会用保存的密码后台重登。
  Future<void> _refreshChaoxing({bool withWorks = false}) async {
    if (_cxLoading) {
      return;
    }
    setState(() {
      _cxLoading = true;
      _cxError = null;
    });
    try {
      final auth = ChaoxingAuth.instance;
      if (!auth.isLoggedIn) {
        await auth.restore();
      }
      if (!auth.isLoggedIn) {
        return;
      }
      if (!await auth.ensureSession()) {
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
      final courses = _cxCourses.isNotEmpty
          ? _cxCourses
          : await client.fetchCourses();
      final activities = await client.fetchActivities(courses);
      final works = (withWorks || _cxWorks.isNotEmpty)
          ? await client.fetchWorks(courses)
          : _cxWorks;
      if (!mounted) {
        return;
      }
      setState(() {
        _cxCourses = courses;
        _cxActivities = activities;
        _cxWorks = works;
      });
      // 学习通只有「剩余 X 小时」这种相对时间，拉到列表时换算成绝对时间排提醒
      if (works.isNotEmpty) {
        await ReminderService.instance.syncChaoxingWorks(works);
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

  Future<void> _loginChaoxing() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const ChaoxingLoginPage()),
    );
    if (ok != true) return;
    await _refreshChaoxing(withWorks: true);
    // 当前如果停在「学习通」课程源，登录完直接把课程列表拉出来
    if (_showChaoxingCourses) {
      await _loadCourses(force: true);
    }
  }

  void _toggleTodoSource() {
    setState(() => _showChaoxingTodos = !_showChaoxingTodos);
    if (_showChaoxingTodos &&
        ChaoxingAuth.instance.isLoggedIn &&
        _cxWorks.isEmpty) {
      _refreshChaoxing(withWorks: true);
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_loading) {
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
      try {
        rollcalls = await RollcallApi(client).fetchOngoing();
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
      if (!mounted) {
        return;
      }
      setState(() {
        _rollcalls = rollcalls;
        _todos = todos;
        _exams = _filterExams(exams);
        _todosError = todosError;
        _error = null;
      });
      // 已提交的作业不再提醒（内部会按课程查一遍「我的提交」）
      await ReminderService.instance.syncHomework(
        todos: _todos,
        submittedActivityIds: await ReminderService.instance.fetchSubmittedIds(
          client,
          _todos,
        ),
      );
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

  Future<void> _loadCourses({bool force = false}) async {
    if (_coursesLoading) return;
    final termKey = _currentTerm.isNotEmpty
        ? _currentTerm
        : CalendarService.fallbackTermId();
    final source = _showChaoxingCourses ? 'chaoxing' : 'tronclass';
    // 缓存优先：有缓存先渲染；缓存过期就不显示加载态、后台静默刷一遍。
    var silent = false;
    if (!force) {
      final cached = await CourseInfoCache.load(termKey, source);
      if (cached != null) {
        if (mounted) {
          setState(() {
            _courseInfos = cached;
            _coursesError = null;
          });
        }
        if (await CourseInfoCache.isFresh(termKey, source)) {
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
        if (mounted) setState(() => _courseInfos = filtered);
        // 缓存课程列表：下次进页面先用缓存渲染，不必等网络。
        // 学习通那边点课程要依赖 _cxCourses，先不缓存，避免列表能看却点不开。
        await CourseInfoCache.save(termKey, source, filtered);
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
        final filtered = courses
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
            .where((c) => _isCurrentCourse(c.name, c.termCode))
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
      late final Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } catch (_) {
        if (mounted) {
          _toast('定位失败，请到空旷处重试');
        }
        return;
      }
      final SignResult result;
      try {
        result = await RollcallApi(client).reportRadarPosition(
          rollcall,
          position.latitude,
          position.longitude,
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
                  '生活学习',
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
                    tooltip: '刷新签到',
                    onPressed: () async {
                      await _refresh();
                      await _refreshChaoxing(withWorks: _showChaoxingTodos);
                    },
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 8),
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
            _campusCard(),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _openLms,
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('一网畅学网页版', style: TextStyle(fontSize: 12)),
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
          const Icon(
            Icons.chevron_right,
            size: 16,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _todoCard() {
    final isCx = _showChaoxingTodos;
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
                isCx
                    ? '${_cxWorks.where((w) => !w.finished && !w.expired).length} 个'
                    : '${_todos.length} 个',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              _sourceSwitch(),
            ],
          ),
          if (isCx) _cxTodoBody() else _lmsTodoBody(),
        ],
      ),
    );
  }

  Widget _sourceSwitch() {
    final isCx = _showChaoxingTodos;
    final color = isCx ? AppColors.usstRed : const Color(0xFF3B5BDB);
    return GestureDetector(
      onTap: _toggleTodoSource,
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

  Widget _campusCard() {
    return GestureDetector(
      onTap: () => _toast('校园卡功能还在逆向中，先用 WeLink 出示二维码'),
      child: Container(
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
              child: Icon(Icons.credit_card, color: AppColors.usstRed),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '校园卡',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '余额 / 出示二维码（暂未接入，占位）',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F4F6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '敬请期待',
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
