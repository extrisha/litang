import 'package:flutter/material.dart';

/// 全 App 共用的动效参数。
///
/// 之前项目里几乎没有主动动画（只有地图飞行、一处 AnimatedSize 等 4 处），
/// 页面切换全靠 Material 默认转场。这里把时长/曲线集中成一处，避免以后
/// 每个页面各写一套 `Duration(milliseconds: 250)`。
class AppMotion {
  AppMotion._();

  /// 按压反馈：按下 0.97，抬起回弹。
  static const Duration press = Duration(milliseconds: 120);

  /// 页面转场。MaterialPageRoute 的时长由框架固定 300ms，
  /// 这里只用曲线让它「前快后慢」，看起来更利落。
  static const Curve entrance = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;

  /// 页面入场位移（占屏宽 6%），比默认的整屏滑入轻。
  static const Offset pageOffset = Offset(0.06, 0);

  /// 系统开了「移除动画」时用这个判断，别自己读无障碍设置。
  static bool reduce(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}

/// 页面转场：淡入 + 轻微右滑。
///
/// 通过 `ThemeData.pageTransitionsTheme` 全局生效，**调用点不用改**——
/// 现有的 `Navigator.push(MaterialPageRoute(...))` 全部自动套用。
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reduce(context) || route.isFirst) {
      return child;
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.entrance,
      reverseCurve: AppMotion.exit,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: AppMotion.pageOffset,
        end: Offset.zero,
      ).animate(curved),
      child: FadeTransition(opacity: curved, child: child),
    );
  }
}

/// 按一下缩一点，松手回弹。
///
/// 用 `Listener` 而不是 `GestureDetector`：不参与手势竞争，包在 `InkWell`
/// 外面也不会把点击抢走。
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.97,
  });

  final Widget child;
  final bool enabled;
  final double pressedScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reduce(context);
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed && !reduce ? widget.pressedScale : 1,
        duration: reduce ? Duration.zero : AppMotion.press,
        curve: AppMotion.entrance,
        child: widget.child,
      ),
    );
  }
}
