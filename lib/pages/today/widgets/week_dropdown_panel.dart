import 'package:flutter/material.dart';

import '../../../app_theme.dart';

/// 课表教学周快速切换下拉面板
///
/// 打开时要直接定位到当前选中的那一周。原来的实现是裸 `ListView.separated`
/// （懒构建 + 视口 270px），第 12 周连 widget 都不会被创建，用户只能看到
/// 第 1~7 周、且连勾选标记都找不到。
///
/// 定位需要知道每行高度，所以这里：
///   1. 用固定 `itemExtent` 取代变高的 `separatorBuilder`（分隔线画进行内），
///   2. 用 `ScrollController.initialScrollOffset` 把选中周滚到可见位置。
class WeekDropdownPanel extends StatefulWidget {
  const WeekDropdownPanel({
    super.key,
    required this.selectedWeek,
    required this.currentWeek,
    required this.maxWeek,
    required this.onSelectWeek,
  });

  final int selectedWeek;
  final int? currentWeek;
  final int maxWeek;
  final ValueChanged<int> onSelectWeek;

  /// 每行固定高度（含 1px 分隔线）。
  static const double itemExtent = 40.0;

  @override
  State<WeekDropdownPanel> createState() => _WeekDropdownPanelState();
}

class _WeekDropdownPanelState extends State<WeekDropdownPanel> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(initialScrollOffset: _initialOffset());
  }

  /// 把选中周滚到「从上往下第三个」附近，这样上下都还能看到相邻周。
  double _initialOffset() {
    final index = (widget.selectedWeek - 1).clamp(0, widget.maxWeek - 1);
    return (index * WeekDropdownPanel.itemExtent -
            WeekDropdownPanel.itemExtent * 2)
        .clamp(0.0, double.infinity);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 190,
        constraints: const BoxConstraints(maxHeight: 270),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEEEEE)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x26000000),
              offset: Offset(0, 8),
              blurRadius: 20,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.symmetric(vertical: 6),
            shrinkWrap: true,
            itemExtent: WeekDropdownPanel.itemExtent,
            itemCount: widget.maxWeek,
            itemBuilder: (context, index) {
              final week = index + 1;
              final isSelected = week == widget.selectedWeek;
              final isCur = week == widget.currentWeek;

              return InkWell(
                onTap: () => widget.onSelectWeek(week),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFFF1F0)
                        : Colors.transparent,
                    border: const Border(
                      bottom: BorderSide(color: Color(0xFFF5F5F5)),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: <Widget>[
                      Text(
                        '第$week周',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: isSelected || isCur
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? AppColors.usstRed
                              : AppColors.textPrimary,
                        ),
                      ),
                      if (isCur) ...<Widget>[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDE8E8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '本周',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.usstRed,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (isSelected)
                        const Icon(
                          Icons.check,
                          size: 16,
                          color: AppColors.usstRed,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
