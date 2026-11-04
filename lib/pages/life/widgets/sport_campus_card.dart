import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../data/auth/sport_campus_auth.dart';
import '../../../data/date_format.dart';
import '../../../services/sport_campus_service.dart';
import '../sport_campus_login_page.dart';

/// 校园跑（高校体育）次数卡片。
///
/// 纯展示组件：数据、加载态、错误都由外面传，方便单测和复用。
class SportCampusCard extends StatelessWidget {
  const SportCampusCard({
    super.key,
    required this.progress,
    required this.fetchedAt,
    required this.loading,
    required this.error,
    required this.bound,
    required this.onRefresh,
    required this.onLogin,
    this.onUnbind,
  });

  final SportCampusProgress? progress;
  final DateTime? fetchedAt;
  final bool loading;
  final String? error;

  /// 是否绑定过高校体育账号。
  final bool bound;

  final VoidCallback onRefresh;
  final VoidCallback onLogin;

  /// 长按解绑（换账号 / 换手机号）。没绑定时不需要。
  final VoidCallback? onUnbind;

  bool get _canRefresh => bound;

  @override
  Widget build(BuildContext context) {
    final title = fetchedAt == null
        ? '校园跑 · 未同步'
        : '校园跑 · ${DateFmt.mdHm(fetchedAt!)} 更新';

    return GestureDetector(
      onTap: _canRefresh ? onRefresh : onLogin,
      onLongPress: bound ? onUnbind : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.redTint,
                  child: Icon(
                    Icons.directions_run,
                    size: 20,
                    color: AppColors.usstRed,
                  ),
                ),
                const SizedBox(width: 10),
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
                      // 只有未绑定时才需要这一行引导；绑定后不显示学校/老师等信息
                      if (!bound) ...<Widget>[
                        const SizedBox(height: 2),
                        const Text(
                          '点此绑定高校体育账号',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    tooltip: bound ? '刷新次数' : '绑定高校体育',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: _canRefresh ? onRefresh : onLogin,
                    icon: Icon(
                      _canRefresh ? Icons.refresh : Icons.link,
                      size: 20,
                    ),
                  ),
              ],
            ),
            if (progress != null && progress!.hasData) ...<Widget>[
              const SizedBox(height: 10),
              _progressBar(progress!),
              const SizedBox(height: 6),
              _countsRow(progress!),
            ],
            if (bound &&
                progress == null &&
                !loading &&
                error == null) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                '已绑定，点右上角刷新获取次数',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
            if (error != null) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.info_outline,
                      size: 13,
                      color: AppColors.usstRed,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      error!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.usstRed,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _progressBar(SportCampusProgress info) {
    final ratio = info.ratio ?? 0;
    final color = info.finished ? AppColors.success : AppColors.usstRed;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: ratio,
        minHeight: 8,
        backgroundColor: AppColors.surfaceMuted,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }

  Widget _countsRow(SportCampusProgress info) {
    final done = info.done;
    final goal = info.goal;
    final surplus = info.surplus;
    final color = info.finished ? AppColors.success : AppColors.textPrimary;
    return Row(
      children: <Widget>[
        Text(
          done == null || goal == null ? '目标 $goal 次' : '已跑 $done / $goal 次',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const Spacer(),
        Text(
          surplus == null ? '—' : (info.finished ? '已跑够' : '还差 $surplus 次'),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// 把 [SportCampusAuth] 接到卡片上：负责冷启动恢复、登录页跳转和状态订阅。
///
/// 这样「校园」页只需要一行 `const SportCampusSection()`，
/// 不用再往已经很大的 `life_page` 里塞一套 state。
class SportCampusSection extends StatefulWidget {
  const SportCampusSection({super.key});

  @override
  State<SportCampusSection> createState() => _SportCampusSectionState();
}

class _SportCampusSectionState extends State<SportCampusSection> {
  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = SportCampusAuth.instance;
    await auth.restore();
    if (!mounted) {
      return;
    }
    // 有账号且缓存过期时才真的发请求；没绑定就是一次空转
    await auth.refresh();
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const SportCampusLoginPage()),
    );
    if (ok == true && mounted) {
      await SportCampusAuth.instance.refresh(force: true);
    }
  }

  Future<void> _confirmUnbind() async {
    final auth = SportCampusAuth.instance;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('解绑高校体育'),
        content: Text('确定要解绑 ${auth.maskedMobile} 吗？解绑后次数卡片会清空。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('解绑'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = SportCampusAuth.instance;
    return ListenableBuilder(
      listenable: auth,
      builder: (BuildContext context, Widget? _) {
        return SportCampusCard(
          progress: auth.progress,
          fetchedAt: auth.fetchedAt,
          loading: auth.loading,
          error: auth.error,
          bound: auth.bound,
          onRefresh: () => auth.refresh(force: true),
          onLogin: _openLogin,
          onUnbind: _confirmUnbind,
        );
      },
    );
  }
}
