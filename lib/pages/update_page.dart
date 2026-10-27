import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../services/update_service.dart';

/// 发现新版本时的提示 + 下载进度。
///
/// [mandatory] 不传时按 [UpdateInfo.mandatory] 处理；显式传值时以调用方为准。
/// 为 true 时弹窗不可关闭、也没有「稍后」——用于云端把
/// `minVersionCode` 抬高、要求旧版本必须升级的场景。
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateInfo info, {
  bool startup = false,
  bool? mandatory,
}) async {
  final force = mandatory ?? info.mandatory;
  final go = await showDialog<bool>(
    context: context,
    barrierDismissible: !force,
    builder: (dialogContext) => PopScope(
      canPop: !force,
      child: AlertDialog(
        title: Text(force ? '需要更新后才能继续' : '发现新版本 ${info.version}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                info.notes.isEmpty ? '建议更新到最新版本。' : info.notes,
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 12),
              Text(
                force
                    ? '当前版本 ${info.version} 已停止支持，更新完成前无法使用。'
                          '下载后会自动打开系统安装器。'
                    : '下载后会自动打开系统安装器；部分手机需要在系统设置里允许「安装未知应用」。',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => _openReleasePage(),
            child: const Text('手动下载'),
          ),
          if (!force)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(startup ? '稍后' : '取消'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('下载并更新'),
          ),
        ],
      ),
    ),
  );
  if (go != true || !context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateProgressDialog(info: info, mandatory: force),
  );
}

/// 自动下载失败时的兜底：直接开浏览器去 Release 页面下。
Future<void> _openReleasePage() async {
  try {
    await launchUrl(
      Uri.parse(UpdateService.releasePage),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    // 打不开就算了，用户还能自己搜
  }
}

class _UpdateProgressDialog extends StatefulWidget {
  const _UpdateProgressDialog({required this.info, this.mandatory = false});

  final UpdateInfo info;
  final bool mandatory;

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final path = await UpdateService.download(
        widget.info,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await UpdateService.install(path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().split('\n').first;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('正在下载更新'),
      content: _error != null
          ? Text(
              _error!,
              style: const TextStyle(fontSize: 13, color: AppColors.usstRed),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LinearProgressIndicator(
                  value: _progress <= 0 ? null : _progress,
                ),
                const SizedBox(height: 10),
                Text(
                  '${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
      actions: <Widget>[
        if (_error != null) ...<Widget>[
          TextButton(onPressed: _openReleasePage, child: const Text('手动下载')),
          TextButton(
            onPressed: () {
              setState(() {
                _error = null;
                _progress = 0;
              });
              _run();
            },
            child: const Text('重试'),
          ),
          if (!widget.mandatory)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
        ],
      ],
    );
  }
}
