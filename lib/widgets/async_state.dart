import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 统一的「加载中 / 失败 / 空」三态占位。
///
/// 之所以要统一：多个页面在没有错误状态的情况下，把「请求失败」直接渲染成
/// 「暂无数据」——用户看到的是「你没有成绩/没有排名」，而真相是没取到。
/// 这种误导没法靠看代码发现，只能靠统一的结构强制区分。
///
/// 判定优先级：`loading` → `error` → `emptyText`。页面在开始请求时应先清空
/// `error`，否则会出现「正在加载但还显示上一次的错误」。
class AsyncStateView extends StatelessWidget {
  const AsyncStateView({
    super.key,
    this.loading = false,
    this.error,
    this.emptyText,
    this.onRetry,
    this.retryLabel = '重试',
    this.secondaryLabel,
    this.onSecondary,
    this.errorIcon = Icons.cloud_off_rounded,
    this.emptyIcon = Icons.inbox_outlined,
    this.compact = false,
  });

  /// 正在加载
  final bool loading;

  /// 失败原因；非空时优先于空态展示
  final String? error;

  /// 确实没有数据时的文案；为 null 表示不展示空态
  final String? emptyText;

  /// 失败时的重试回调；为 null 则不显示按钮
  final VoidCallback? onRetry;

  final String retryLabel;

  /// 第二动作（如「在网页中打开」）。和 [onSecondary] 都存在时才显示。
  ///
  /// 有些页面的失败态除了重试还提供一条兜底路径，硬塞进 [onRetry] 会丢功能。
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final IconData errorIcon;
  final IconData emptyIcon;

  /// 嵌在卡片内部时用更紧凑的间距
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 20 : 48),
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: AppColors.usstRed,
            ),
          ),
        ),
      );
    }

    final message = error ?? emptyText;
    if (message == null) {
      return const SizedBox.shrink();
    }

    final isError = error != null;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 24,
        vertical: compact ? 16 : 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isError ? errorIcon : emptyIcon,
            size: compact ? 32 : 48,
            color: AppColors.textSecondary,
          ),
          SizedBox(height: compact ? 8 : 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 12 : 14,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (isError && (onRetry != null || onSecondary != null)) ...<Widget>[
            SizedBox(height: compact ? 10 : 16),
            // 用 Wrap 而不是 Row：窄屏 + 两个按钮时不会溢出
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (onRetry != null)
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(retryLabel),
                  ),
                if (onSecondary != null && secondaryLabel != null)
                  FilledButton(
                    onPressed: onSecondary,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.usstRed,
                    ),
                    child: Text(secondaryLabel!),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
