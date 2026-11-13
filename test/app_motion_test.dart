import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/app_theme.dart';
import 'package:project_usst/widgets/app_motion.dart';

Widget _host(Widget child, {bool reduceMotion = false}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

double _scale(WidgetTester tester) =>
    tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

void main() {
  test('主题里 Android 用的是自定义转场', () {
    final theme = AppTheme.light();
    expect(
      theme.pageTransitionsTheme.builders[TargetPlatform.android],
      isA<AppPageTransitionsBuilder>(),
    );
    // iOS 不覆盖，保留系统默认（边缘返回手势）
    expect(
      theme.pageTransitionsTheme.builders[TargetPlatform.iOS],
      isNull,
    );
  });

  group('PressableScale', () {
    testWidgets('按下缩小，抬起回弹', (tester) async {
      await tester.pumpWidget(
        _host(
          PressableScale(
            child: Material(
              color: Colors.white,
              child: InkWell(
                onTap: () {},
                child: const SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PressableScale)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(_scale(tester), lessThan(1));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_scale(tester), 1);
    });

    testWidgets('点击回调仍然能触发（不抢手势）', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _host(
          PressableScale(
            child: Material(
              color: Colors.white,
              child: InkWell(
                onTap: () => tapped++,
                child: const SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });

    testWidgets('系统开了「移除动画」就不缩放', (tester) async {
      await tester.pumpWidget(
        _host(
          PressableScale(
            child: const SizedBox(width: 120, height: 60),
          ),
          reduceMotion: true,
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PressableScale)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(_scale(tester), 1);
      await gesture.up();
    });

    testWidgets('enabled=false 时不响应按压', (tester) async {
      await tester.pumpWidget(
        _host(
          PressableScale(
            enabled: false,
            child: const SizedBox(width: 120, height: 60),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PressableScale)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(_scale(tester), 1);
      await gesture.up();
    });
  });

  test('动效参数是统一常量，别处不要另写字面量', () {
    expect(AppMotion.press, const Duration(milliseconds: 120));
    expect(AppMotion.entrance, Curves.easeOutCubic);
    expect(AppMotion.pageOffset.dx, greaterThan(0));
  });
}
