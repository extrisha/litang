import 'package:flutter/widgets.dart';

/// 首次访问才挂载页面；已访问页面保留状态。
///
/// 隐藏时用 `TickerMode` 停掉**动画**（ticker），页面里的 `Timer`
/// （如课表的分钟刷新）仍会继续跑——需要省电时得在页面内部自己控制。
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
  }) : assert(index >= 0 && index < children.length);

  final int index;
  final List<Widget> children;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  final Set<int> _visited = <int>{};

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          TickerMode(
            enabled: i == widget.index,
            child: _visited.contains(i)
                ? widget.children[i]
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}
