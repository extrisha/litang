import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/pages/life/widgets/sport_campus_card.dart';
import 'package:project_usst/services/sport_campus_service.dart';

/// 卡片三态的渲染：未绑定 / 有数据 / 失败。
///
/// 项目最高优先级规则是「取不到不能显示成没有」，所以这里断言的是
/// 「错误必须显示出来」「未绑定必须引导去绑定」，而不是好看不好看。
void main() {
  SportCampusProgress progress({String goal = '30', String surplus = '18'}) =>
      SportCampusProgress.parse(<String, dynamic>{
        'username': '陈宇喆',
        'school': '上海理工大学',
        'teacher': '王老师',
        'course': '羽毛球',
        'goal': goal,
        'surplus': surplus,
      })!;

  Future<void> pump(
    WidgetTester tester, {
    SportCampusProgress? data,
    bool bound = false,
    bool loading = false,
    String? error,
    VoidCallback? onUnbind,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              SportCampusCard(
                progress: data,
                fetchedAt: data == null ? null : DateTime(2026, 11, 4, 12, 30),
                loading: loading,
                error: error,
                bound: bound,
                onRefresh: () {},
                onLogin: () {},
                onUnbind: onUnbind,
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('未绑定时引导去绑定，不显示次数', (tester) async {
    await pump(tester);
    expect(find.text('点此绑定高校体育账号'), findsOneWidget);
    expect(find.text('校园跑 · 未同步'), findsOneWidget);
  });

  testWidgets('有数据时显示已跑 / 目标 / 还差几次', (tester) async {
    await pump(tester, data: progress(), bound: true);
    expect(find.text('已跑 12 / 30 次'), findsOneWidget);
    expect(find.text('还差 18 次'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('跑够时显示「已跑够」而不是负数', (tester) async {
    await pump(tester, data: progress(surplus: '0'), bound: true);
    expect(find.text('已跑 30 / 30 次'), findsOneWidget);
    expect(find.text('已跑够'), findsOneWidget);
  });

  testWidgets('失败时把错误显示出来，不显示成「暂无数据」', (tester) async {
    await pump(tester, bound: true, error: '连不上高校体育服务，请检查网络后重试');
    expect(find.text('连不上高校体育服务，请检查网络后重试'), findsOneWidget);
  });

  testWidgets('长按可解绑，方便换手机号', (tester) async {
    var unbound = 0;
    await pump(
      tester,
      data: progress(),
      bound: true,
      onUnbind: () => unbound++,
    );
    await tester.longPress(find.byType(SportCampusCard));
    expect(unbound, 1);
  });

  testWidgets('未绑定时长按不触发解绑', (tester) async {
    var unbound = 0;
    await pump(tester, onUnbind: () => unbound++);
    await tester.longPress(find.byType(SportCampusCard));
    expect(unbound, 0);
  });
}
