import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/widgets/async_state.dart';

void main() {
  Future<void> pump(WidgetTester tester, AsyncStateView view) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: view)),
      ),
    );
  }

  testWidgets('加载中显示转圈，不显示空态文案', (tester) async {
    await pump(
      tester,
      const AsyncStateView(loading: true, emptyText: '还没有排名数据'),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('还没有排名数据'), findsNothing);
  });

  testWidgets('有错误时显示错误文案和重试按钮', (tester) async {
    var retried = 0;
    await pump(
      tester,
      AsyncStateView(
        error: '获取排名失败，请稍后重试',
        emptyText: '还没有排名数据',
        onRetry: () => retried++,
      ),
    );
    // 错误优先于空态：绝不能把失败显示成「没有数据」
    expect(find.text('获取排名失败，请稍后重试'), findsOneWidget);
    expect(find.text('还没有排名数据'), findsNothing);

    await tester.tap(find.text('重试'));
    expect(retried, 1);
  });

  testWidgets('既没加载也没错误时显示空态，且没有重试按钮', (tester) async {
    await pump(tester, const AsyncStateView(emptyText: '还没有排名数据'));
    expect(find.text('还没有排名数据'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('三个参数都不给时什么都不渲染', (tester) async {
    await pump(tester, const AsyncStateView());
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('错误但没有 onRetry 时不显示按钮', (tester) async {
    await pump(tester, const AsyncStateView(error: '出错了'));
    expect(find.text('出错了'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('第二动作：重试和兜底按钮同时显示且各自可点', (tester) async {
    var retried = 0;
    var openedWeb = 0;
    await pump(
      tester,
      AsyncStateView(
        error: '没取到作业详情',
        onRetry: () => retried++,
        secondaryLabel: '在网页中打开',
        onSecondary: () => openedWeb++,
      ),
    );

    expect(find.text('重试'), findsOneWidget);
    expect(find.text('在网页中打开'), findsOneWidget);

    await tester.tap(find.text('重试'));
    expect(retried, 1);
    expect(openedWeb, 0);

    await tester.tap(find.text('在网页中打开'));
    expect(openedWeb, 1);
  });

  testWidgets('只给 onSecondary 不给 label 时不渲染第二按钮', (tester) async {
    await pump(tester, AsyncStateView(error: '出错了', onSecondary: () {}));
    // 没有 label 就没有可点的按钮，不应该出现空白按钮
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });
}
