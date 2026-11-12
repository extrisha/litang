import 'package:flutter/material.dart';

import '../../../app_theme.dart';

/// 内部模式页里的白色分组卡片（标题 + 若干行控件）。
///
/// 单独抽出来是因为这个页面有六七组设置，重复写一遍 `Container + BorderRadius`
/// 很容易改了一处忘另一处。
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}
