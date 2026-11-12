import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import 'section_card.dart';

/// 内部模式页底部的监控日志（新的在最上面）。
class MonitorLogCard extends StatelessWidget {
  const MonitorLogCard({super.key, required this.lines});

  static const double maxVisibleHeight = 220;

  final ValueListenable<List<String>> lines;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: lines,
      builder: (context, items, _) {
        return SectionCard(
          title: '日志',
          children: <Widget>[
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  '还没有记录。',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: maxVisibleHeight),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  itemCount: items.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      items[index],
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
