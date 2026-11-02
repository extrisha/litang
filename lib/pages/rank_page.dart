import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/date_format.dart';
import '../data/jwc/rank_api.dart';
import '../data/jwc/rank_repository.dart';
import '../widgets/async_state.dart';

/// 专业排名：从教务「专业排名证明」PDF 里解析出的名次。
class RankPage extends StatefulWidget {
  const RankPage({super.key});

  @override
  State<RankPage> createState() => _RankPageState();
}

class _RankPageState extends State<RankPage> {
  RankInfo? _info;
  bool _loading = false;

  /// 失败原因。之前没有这个字段，请求失败会和「还没有排名数据」长得一模一样。
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final cached = await RankRepository.loadCache();
    if (!mounted) {
      return;
    }
    setState(() => _info = cached);

    final auth = JwglAuth.instance;
    if (!auth.isLoggedIn) {
      await auth.restore();
      if (!mounted) {
        return;
      }
      setState(() {});
    }
    if (auth.isLoggedIn) {
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await auth.ensureSession();
      if (!ok) {
        if (mounted) {
          const message = '登录已过期，请回「我的」重新登录';
          setState(() => _error = message);
          if (!silent) {
            _toast(message);
          }
        }
        return;
      }
      final info = await RankRepository.refresh(auth.client!);
      if (!mounted) {
        return;
      }
      setState(() {
        _info = info;
        _error = null;
      });
    } on RankException catch (error) {
      if (mounted) {
        // 静默刷新失败也必须留下错误状态，否则界面会显示成「还没有排名数据」
        setState(() => _error = error.message);
        if (!silent) {
          _toast(error.message);
        }
      }
    } catch (_) {
      if (mounted) {
        const message = '获取排名失败，请稍后重试';
        setState(() => _error = message);
        if (!silent) {
          _toast(message);
        }
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

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('专业排名'),
        actions: <Widget>[
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: '刷新排名',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => _refresh(),
            ),
        ],
      ),
      body: info == null
          ? Center(
              child: AsyncStateView(
                loading: _loading,
                error: _error,
                emptyText: JwglAuth.instance.isLoggedIn
                    ? '还没有排名数据，点右上角刷新'
                    : '登录后自动同步排名',
                onRetry: () => _refresh(),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: <Widget>[
                _rankCard(info),
                const SizedBox(height: 12),
                _hintCard(info),
              ],
            ),
    );
  }

  Widget _rankCard(RankInfo info) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: <Widget>[
          if (info.major.isNotEmpty)
            Text(
              info.major,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                '${info.rank}',
                style: const TextStyle(
                  fontSize: 52,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: AppColors.usstRed,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '/ ${info.total} 名',
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '专业排名 · 超过 ${info.percentile.toStringAsFixed(1)}% 的同学',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hintCard(RankInfo info) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '数据来源',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            '由教务「专业排名证明」PDF 现场生成后解析得到，证明文件本身是一次性的，'
            '这里只保存排名数字。',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '更新于 ${_formatTime(info.updatedAt)}',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) => DateFmt.mdHm(time);
}
