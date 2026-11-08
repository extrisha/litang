import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';

import 'package:package_info_plus/package_info_plus.dart';

import '../data/attachment_cache.dart';
import '../data/auth/cas_client.dart';
import '../data/calendar/calendar_service.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/auth/session_store.dart';
import '../data/auth/xuegong_auth.dart';
import '../data/chaoxing/chaoxing_auth.dart';
import '../data/jwc/course_api.dart';
import '../data/jwc/course_repository.dart';
import '../data/jwc/academic_repository.dart';
import '../data/jwc/grade_repository.dart';
import '../data/jwc/rank_repository.dart';
import '../data/profile_store.dart';
import 'academic_page.dart';
import 'grades_page.dart';
import 'jwgl_web.dart';
import 'rank_page.dart';
import 'simple_web.dart';
import 'login_page.dart';
import 'update_page.dart';
import '../services/update_service.dart';

/// 我的：个人信息 + 学业查询 + 网页入口（上理体育 / 学工 / 教务）。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.auth});

  final JwglAuth? auth;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  JwglAuth get _auth => widget.auth ?? JwglAuth.instance;

  CourseSnapshot? _snapshot;
  UserProfile? _profile;
  String? _profileUserId;
  CasClient? _profileClient;
  int _generation = 0;
  int _localLoadGeneration = 0;
  bool _loading = false;
  bool _openingXuegong = false;
  int _week = 1;

  /// 版本信息只取一次（`PackageInfo.fromPlatform()` 走 platform channel，
  /// 放在 build 里会每次重建都重新查一遍）。
  final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  void initState() {
    super.initState();
    AttachmentCache.refreshSize();
    final account = _authAccount;
    if (account.isNotEmpty) _profileUserId = account;
    _profileClient = _auth.client;
    _auth.addListener(_onAuthChanged);
    CourseRepository.changes.addListener(_onCoursesChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    CourseRepository.changes.removeListener(_onCoursesChanged);
    super.dispose();
  }

  String get _authAccount {
    final saved = _auth.savedUsername.trim();
    return saved.isNotEmpty ? saved : (_auth.studentId ?? '').trim();
  }

  bool _isCurrent(int generation, String account) =>
      mounted &&
      generation == _generation &&
      _profileUserId == account &&
      identical(_profileClient, _auth.client) &&
      (_authAccount.isEmpty || _authAccount == account);

  /// 本地身份不依赖校园网会话；同账号恢复也要补齐缺失的姓名。
  void _onAuthChanged() {
    if (!mounted) return;
    final id = _authAccount;
    final accountChanged = id != _profileUserId;
    if (accountChanged || !identical(_profileClient, _auth.client)) {
      _generation++;
      _localLoadGeneration++;
      setState(() {
        _profileUserId = id;
        _profileClient = _auth.client;
        _loading = false;
        if (accountChanged) {
          _profile = null;
          _snapshot = null;
        }
      });
    }
    if (id.isNotEmpty) unawaited(_loadLocalAndRefresh());
  }

  void _onCoursesChanged() {
    // 今日页同步后只重读本地，避免保存通知再次触发网络同步。
    unawaited(_loadLocal());
  }

  Future<void> _loadLocal() async {
    final account = _profileUserId;
    if (account == null) return;
    final generation = _generation;
    final loadGeneration = ++_localLoadGeneration;
    final profileFuture = ProfileStore.load(username: account);
    final cached = await CourseRepository.loadCache(username: account);
    final profile = await profileFuture;
    if (!_isCurrent(generation, account) ||
        loadGeneration != _localLoadGeneration) {
      return;
    }
    setState(() {
      _profile = profile;
      if (cached != null) _snapshot = cached;
      _week =
          CalendarService.instance.currentWeek ??
          _snapshot?.currentWeek ??
          _week;
    });
  }

  Future<void> _loadLocalAndRefresh() async {
    final account = _profileUserId;
    if (account == null || account.isEmpty) return;
    final generation = _generation;
    await _loadLocal();
    if (!_isCurrent(generation, account)) return;
    if (_auth.isLoggedIn &&
        (_snapshot == null ||
            _snapshot!.collegeName.trim().isEmpty ||
            _snapshot!.studentName.trim().isEmpty)) {
      await _refresh(silent: true);
    }
  }

  Future<void> _bootstrap() async {
    final generation = _generation;
    if (_profileUserId == null) {
      String account;
      try {
        account = await SessionStore().loadUsername();
      } catch (_) {
        account = '';
      }
      if (!mounted || generation != _generation) return;
      _profileUserId = account;
    }
    await _loadLocal();
    if (!mounted) return;
    try {
      if (!_auth.isLoggedIn) await _auth.restore();
    } catch (_) {
      // 网络恢复失败不影响已经显示的本地姓名。
      return;
    }
    if (mounted) _onAuthChanged();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_loading) {
      return;
    }
    final auth = _auth;
    final account = _profileUserId;
    final generation = _generation;
    if (account == null || account.isEmpty) return;
    if (!auth.isLoggedIn) {
      if (!silent) {
        _toast('请先登录教务系统');
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final ok = await auth.ensureSession();
      if (!_isCurrent(generation, account)) return;
      if (!ok) {
        if (!silent) {
          _toast('登录已过期，请重新登录');
        }
        return;
      }
      final client = auth.client;
      if (client == null) return;
      final snapshot = await CourseRepository.refresh(client, auth: auth);
      if (!_isCurrent(generation, account)) return;
      setState(() {
        _snapshot = snapshot;
        _week =
            CalendarService.instance.currentWeek ??
            snapshot.currentWeek ??
            _week;
      });
    } catch (_) {
      if (_isCurrent(generation, account) && !silent) {
        _toast('课表更新失败，请检查网络后重试');
      }
    } finally {
      if (_isCurrent(generation, account)) {
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

  /// 用当前会话 cookie 免密打开教务系统网页版。
  Future<void> _openJwglWeb() async {
    final auth = _auth;
    if (!auth.isLoggedIn) {
      _toast('请先登录教务系统');
      return;
    }
    final ok = await auth.ensureSession();
    if (!mounted) {
      return;
    }
    if (!ok) {
      _toast('登录已过期，请重新登录');
      setState(() {});
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const JwglWebPage()));
  }

  Future<void> _openRank() async {
    final auth = _auth;
    if (!auth.isLoggedIn) {
      _toast('请先登录教务系统');
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const RankPage()));
  }

  Future<void> _openAcademic() async {
    final auth = _auth;
    if (!auth.isLoggedIn) {
      _toast('请先登录教务系统');
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const AcademicPage()));
  }

  Future<void> _openGrades() async {
    final auth = _auth;
    if (!auth.isLoggedIn) {
      _toast('请先登录教务系统');
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const GradesPage()));
  }

  Future<void> _handleAuth() async {
    final auth = _auth;
    if (auth.isLoggedIn) {
      final username = auth.savedUsername;
      await auth.logout();
      await CourseRepository.clear(username: username);
      await GradeRepository.clear();
      await AcademicRepository.clear();
      await RankRepository.clear();
      await XuegongAuth.instance.clear();
      // 学习通是独立账号，退出教务时必须一起清，否则下一个人会看到上一个人的课程。
      await ChaoxingAuth.instance.logout();
      if (mounted && _authAccount.isEmpty) {
        setState(() {
          _snapshot = null;
          _profile = null;
          _profileUserId = '';
        });
      }
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => LoginPage(auth: auth)),
    );
    if (!mounted) {
      return;
    }
    setState(() {});
    if (ok == true) {
      final account = _profileUserId;
      final generation = _generation;
      if (account == null || account.isEmpty) return;
      await GradeRepository.clear();
      await AcademicRepository.clear();
      if (!_isCurrent(generation, account)) return;
      _toast('已登录教务系统');
      // adopt 通知可能已同步成功，保留按账号隔离的课表和姓名。
      await _loadLocalAndRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: <Widget>[
            _userCard(),
            const SizedBox(height: 16),
            _sectionTitle('学业'),
            _grid(<Widget>[
              _entry(Icons.assessment_outlined, '成绩总览', onTap: _openGrades),
              _entry(Icons.school_outlined, '学业情况', onTap: _openAcademic),
              _entry(
                Icons.workspace_premium_outlined,
                '专业排名',
                onTap: _openRank,
              ),
            ]),
            const SizedBox(height: 16),
            _sectionTitle('网页入口'),
            _grid(<Widget>[
              _entry(Icons.sports_outlined, '上理体育', onTap: _openSport),
              _entry(Icons.badge_outlined, '学工一体化', onTap: _openXuegong),
              _entry(Icons.language_outlined, '教务网页版', onTap: _openJwglWeb),
            ]),
            const SizedBox(height: 16),
            _sectionTitle('存储'),
            _cacheTile(),
            const SizedBox(height: 16),
            _sectionTitle('关于'),
            _updateTile(),
          ],
        ),
      ),
    );
  }

  Widget _cacheTile() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: AttachmentCache.sizeNotifier,
        builder: (context, bytes, _) {
          final label = bytes <= 0
              ? '暂无文件'
              : bytes < 1024 * 1024
              ? '${(bytes / 1024).toStringAsFixed(0)} KB'
              : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
          return ListTile(
            leading: const Icon(
              Icons.cleaning_services_outlined,
              size: 20,
              color: AppColors.usstRed,
            ),
            title: const Text('清理下载文件', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              '下载文件夹：$label',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            trailing: TextButton(
              onPressed: () => _clearCache(),
              child: const Text('清理', style: TextStyle(fontSize: 12)),
            ),
          );
        },
      ),
    );
  }

  Future<void> _clearCache() async {
    await AttachmentCache.clear();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('下载文件已清理')));
    }
  }

  Widget _updateTile() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: FutureBuilder<PackageInfo>(
        // 必须缓存这个 Future：在 build 里直接 `PackageInfo.fromPlatform()`
        // 会每次重建都重新走一次 platform channel。
        future: _packageInfo,
        builder: (context, snap) {
          final version = snap.data == null ? '' : '当前版本 ${snap.data!.version}';
          return ListTile(
            leading: const Icon(
              Icons.system_update_alt,
              size: 20,
              color: AppColors.usstRed,
            ),
            title: const Text('检查更新', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              version,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            trailing: TextButton(
              onPressed: _checkUpdate,
              child: const Text('检查', style: TextStyle(fontSize: 12)),
            ),
          );
        },
      ),
    );
  }

  Future<void> _checkUpdate() async {
    // 用 checkWithStatus：check() 把「检查失败」和「已是最新」都返回 null，
    // 直接用它会把断网显示成「当前已是最新版本」。
    final result = await UpdateService.checkWithStatus();
    if (!mounted) return;
    final info = result.info;
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.failed ? '检查更新失败，请检查网络后重试' : '当前已是最新版本')),
      );
      return;
    }
    await showUpdateDialog(context, info, mandatory: info.mandatory);
  }

  Widget _userCard() {
    return AnimatedBuilder(
      animation: _auth,
      builder: (context, _) {
        final auth = _auth;
        final loggedIn = auth.isLoggedIn;
        final profile = _profile;
        final nickname = (profile?.nickname.isNotEmpty ?? false)
            ? profile!.nickname
            : (_snapshot?.studentName.isNotEmpty ?? false)
            ? _snapshot!.studentName
            : '同学';
        final avatar = profile?.avatar ?? '🎓';
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: <Widget>[
              GestureDetector(
                onTap: _editProfile,
                child: CircleAvatar(
                  radius: 27,
                  backgroundColor: AppColors.redTint,
                  child: Text(avatar, style: const TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _editProfile,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (!loggedIn)
                        const Text(
                          '未登录 · 点击登录教务系统',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        )
                      else ...<Widget>[
                        Text(
                          '学号 ${auth.studentId ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _collegeLine(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              TextButton(
                onPressed: _handleAuth,
                child: Text(
                  loggedIn ? '退出' : '登录',
                  style: TextStyle(
                    fontSize: 13,
                    color: loggedIn
                        ? AppColors.textSecondary
                        : AppColors.usstRed,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _collegeLine() {
    final college = _snapshot?.collegeName ?? '';
    final className = _snapshot?.className ?? '';
    if (college.isEmpty && className.isEmpty) {
      return _snapshot?.majorName ?? '已登录教务系统';
    }
    if (className.isEmpty) {
      return college;
    }
    return '$college · $className';
  }

  /// 编辑论坛用的昵称和头像，按当前教务账号存本地。
  Future<void> _editProfile() async {
    final account = _profileUserId ?? '';
    final generation = _generation;
    final current = _profile;
    final nicknameController = TextEditingController(
      text: (current?.nickname.isNotEmpty ?? false)
          ? current!.nickname
          : (_snapshot?.studentName ?? ''),
    );
    var avatar = current?.avatar ?? '🎓';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('编辑个人信息'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: nicknameController,
                  maxLength: 12,
                  decoration: const InputDecoration(
                    labelText: '昵称',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('头像', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final item in ProfileStore.avatars)
                      GestureDetector(
                        onTap: () => setDialogState(() => avatar = item),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: item == avatar
                                ? AppColors.redTint
                                : const Color(0xFFF4F4F6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: item == avatar
                                  ? AppColors.usstRed
                                  : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            item,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final input = nicknameController.text.trim();
    nicknameController.dispose();
    if (saved != true || !_isCurrent(generation, account)) {
      return;
    }
    final profile = UserProfile(
      nickname: input.isEmpty ? (_snapshot?.studentName ?? '同学') : input,
      avatar: avatar,
    );
    await ProfileStore.save(profile, username: account);
    if (_isCurrent(generation, account)) {
      setState(() => _profile = profile);
    }
  }

  /// 上理体育是第三方 SaaS（智慧体育 ydmap），没有可复用的学校会话，
  /// 只能在 WebView 里用手机号登录一次；登录态由 WebView 自己保留，下次直接进。
  ///
  /// 登录态（`Access-Token`）在 WebView 的 localStorage 里，落在应用私有目录
  /// `app_webview/`，由应用沙箱 + 系统整盘加密保护。**不要自己再存一份**：
  /// 写普通文件是明文泄露，写 Keystore 也只是多一份可解密副本，而 WebView 里
  /// 那份依然在。退出登录时由 `WebCookieBridge.clear()` 连同 localStorage 一起清。
  void _openSport() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SimpleWebPage(
          title: '上理体育',
          url: 'https://usst.ydmap.cn/_/usst.html',
        ),
      ),
    );
  }

  Future<void> _openXuegong() async {
    if (_openingXuegong) {
      return;
    }
    final auth = _auth;
    if (!auth.isLoggedIn) {
      _toast('请先登录教务系统');
      return;
    }
    _openingXuegong = true;
    try {
      // 先读一次缓存：10 分钟内的会话直接开，不弹“正在登录”也不走网络。
      await XuegongAuth.instance.loadCookies();
      if (!mounted) {
        return;
      }
      if (!XuegongAuth.instance.hasFreshSession) {
        _toast('正在登录学工…');
      }
      // 复用教务 CAS 会话静默登录学工，用户不需要在页面里再登一次。
      // 重登/WebVPN 兜底都在 XuegongAuth 内部做，这里不再重复一遍。
      final ok = await XuegongAuth.instance.ensureLoggedIn();
      final cookies = ok
          ? await XuegongAuth.instance.loadCookies()
          : <CasCookie>[];
      if (!mounted) {
        return;
      }
      if (!ok) {
        final go = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('学工自动登录失败'),
            content: const Text('是否打开网页，在页面里手动登录一次？'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('打开网页'),
              ),
            ],
          ),
        );
        if (go != true || !mounted) {
          return;
        }
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SimpleWebPage(
            title: '学工一体化',
            // 校外兜底走 WebVPN 时，cookie 属于 webvpn 域名；
            // 必须打开对应地址，否则注入了 cookie 也会被当成未登录。
            url: XuegongAuth.instance.homeUrlForSession,
            cookies: cookies,
          ),
        ),
      );
    } finally {
      _openingXuegong = false;
    }
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 4),
    child: Text(
      t,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
  );

  Widget _grid(List<Widget> children) {
    return Wrap(spacing: 12, runSpacing: 12, children: children);
  }

  Widget _entry(IconData icon, String label, {VoidCallback? onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 104,
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: AppColors.usstRed, size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
