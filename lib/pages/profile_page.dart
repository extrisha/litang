import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';

import 'package:package_info_plus/package_info_plus.dart';

import '../data/attachment_cache.dart';
import '../data/auth/cas_client.dart';
import '../data/calendar/calendar_service.dart';
import '../data/auth/jwgl_auth.dart';
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
import 'today_page.dart';
import '../services/update_service.dart';

/// 我的：个人信息 + 查询入口（学业 / 空间）+ 课表（自动同步 + 手动刷新）。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  CourseSnapshot? _snapshot;
  UserProfile? _profile;
  String? _profileUserId;
  bool _loading = false;
  bool _openingXuegong = false;
  int _week = 1;

  @override
  void initState() {
    super.initState();
    AttachmentCache.refreshSize();
    _profileUserId = JwglAuth.instance.studentId;
    JwglAuth.instance.addListener(_onAuthChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    JwglAuth.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// 教务账号切换后，重新读当前账号的本地资料；没有自定义昵称就显示真实姓名。
  void _onAuthChanged() {
    final id = JwglAuth.instance.studentId;
    if (id == _profileUserId) {
      return;
    }
    _profileUserId = id;
    if (!mounted) {
      return;
    }
    setState(() {
      _profile = null;
      _snapshot = null;
    });
    if (id == null || id.isEmpty) {
      return;
    }
    unawaited(_loadProfile());
    unawaited(_refresh(silent: true));
  }

  Future<void> _loadProfile() async {
    final id = JwglAuth.instance.studentId ?? '';
    final profile = await ProfileStore.load(username: id);
    if (!mounted || JwglAuth.instance.studentId != id) {
      return;
    }
    setState(() => _profile = profile);
  }

  Future<void> _bootstrap() async {
    final cached = await CourseRepository.loadCache();
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = cached;
      _week =
          CalendarService.instance.currentWeek ?? cached?.currentWeek ?? _week;
    });

    final auth = JwglAuth.instance;
    if (!auth.isLoggedIn) {
      await auth.restore();
      if (!mounted) {
        return;
      }
      setState(() {});
    }
    _profileUserId = auth.studentId;
    await _loadProfile();
    if (!mounted) {
      return;
    }
    // 旧缓存没有学院信息时，后台补拉一次（静默，不打断用户）
    if (auth.isLoggedIn &&
        (_snapshot == null || _snapshot!.collegeName.isEmpty)) {
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
          _toast('登录已过期，请重新登录');
          setState(() {});
        }
        return;
      }
      final snapshot = await CourseRepository.refresh(auth.client!);
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _week =
            CalendarService.instance.currentWeek ??
            snapshot.currentWeek ??
            _week;
      });
      if (snapshot.courses.isEmpty && !silent) {
        _toast('没取到课表，请稍后重试');
      }
    } catch (_) {
      if (mounted && !silent) {
        _toast('课表更新失败，请检查网络后重试');
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

  /// 用当前会话 cookie 免密打开教务系统网页版。
  Future<void> _openJwglWeb() async {
    final auth = JwglAuth.instance;
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
    final auth = JwglAuth.instance;
    if (!auth.isLoggedIn) {
      _toast('请先登录教务系统');
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const RankPage()));
  }

  Future<void> _openAcademic() async {
    final auth = JwglAuth.instance;
    if (!auth.isLoggedIn) {
      _toast('请先登录教务系统');
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const AcademicPage()));
  }

  Future<void> _openGrades() async {
    final auth = JwglAuth.instance;
    if (!auth.isLoggedIn) {
      _toast('请先登录教务系统');
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const GradesPage()));
  }

  Future<void> _handleAuth() async {
    final auth = JwglAuth.instance;
    if (auth.isLoggedIn) {
      await auth.logout();
      await CourseRepository.clear();
      await GradeRepository.clear();
      await AcademicRepository.clear();
      await RankRepository.clear();
      await XuegongAuth.instance.clear();
      // 学习通是独立账号，退出教务时必须一起清，否则下一个人会看到上一个人的课程。
      await ChaoxingAuth.instance.logout();
      if (mounted) {
        setState(() {
          _snapshot = null;
          _profile = null;
          _profileUserId = null;
        });
      }
      return;
    }
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute<bool>(builder: (_) => const LoginPage()));
    if (!mounted) {
      return;
    }
    setState(() {});
    if (ok == true) {
      // 换账号后旧缓存不能留
      await CourseRepository.clear();
      await GradeRepository.clear();
      await AcademicRepository.clear();
      _snapshot = null;
      _profileUserId = auth.studentId;
      await _loadProfile();
      if (mounted) {
        setState(() {});
      }
      _toast('已登录教务系统');
      await _refresh(silent: true);
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
            _sectionTitle('空间'),
            _grid(<Widget>[
              _entry(
                Icons.meeting_room_outlined,
                '教室查询',
                onTap: _openClassroom,
              ),
              _entry(Icons.badge_outlined, '学工一体化', onTap: _openXuegong),
              _entry(Icons.language_outlined, '教务网页版', onTap: _openJwglWeb),
            ]),
            const SizedBox(height: 16),
            _timetableSection(),
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
        future: PackageInfo.fromPlatform(),
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
    final info = await UpdateService.check();
    if (!mounted) return;
    if (info == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
      return;
    }
    await showUpdateDialog(context, info, mandatory: info.mandatory);
  }

  Widget _userCard() {
    return AnimatedBuilder(
      animation: JwglAuth.instance,
      builder: (context, _) {
        final auth = JwglAuth.instance;
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
                          '学号 ${JwglAuth.instance.studentId ?? ''}',
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

  /// 编辑论坛用的昵称和头像（只存本地，和教务账号无关）。
  Future<void> _editProfile() async {
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
    if (saved != true) {
      return;
    }
    final profile = UserProfile(
      nickname: input.isEmpty ? (_snapshot?.studentName ?? '同学') : input,
      avatar: avatar,
    );
    await ProfileStore.save(
      profile,
      username: JwglAuth.instance.studentId ?? '',
    );
    if (mounted) {
      setState(() => _profile = profile);
    }
  }

  void _openClassroom() {
    _toast('教室查询正在接入：以后既能查空教室，也能看某间教室在上什么课');
  }

  Future<void> _openXuegong() async {
    if (_openingXuegong) {
      return;
    }
    final auth = JwglAuth.instance;
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

  Widget _timetableSection() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFDE8E8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.calendar_today_outlined,
            size: 20,
            color: AppColors.usstRed,
          ),
        ),
        title: const Text('全学期课表', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: const Text(
          '课表已移至底栏中间「今日」，支持周次切换与教室定位',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TodayPage()),
          );
        },
      ),
    );
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
        child: SizedBox(
          width: 104,
          height: 88,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: AppColors.usstRed, size: 26),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
