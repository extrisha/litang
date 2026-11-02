import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/pages/today/widgets/week_dropdown_panel.dart';

/// 回归测试：周次面板必须直接定位到当前选中的那一周。
///
/// 原来的实现是裸 `ListView.separated`（懒构建 + 视口 270px），
/// 选中第 12 周时只会构建出第 1~7 周，第 12 周连 widget 都不存在，
/// 用户既看不到它、也看不到勾选标记。
void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required int selectedWeek,
    int? currentWeek,
    int maxWeek = 20,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 190,
              height: 270,
              child: WeekDropdownPanel(
                selectedWeek: selectedWeek,
                currentWeek: currentWeek ?? selectedWeek,
                maxWeek: maxWeek,
                onSelectWeek: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('选中第 12 周时该行直接可见', (tester) async {
    await pumpPanel(tester, selectedWeek: 12);
    expect(find.text('第12周').hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.check).hitTestable(), findsOneWidget);
  });

  testWidgets('选中第 1 周时不会莫名其妙往下滚', (tester) async {
    await pumpPanel(tester, selectedWeek: 1);
    expect(find.text('第1周').hitTestable(), findsOneWidget);
  });

  testWidgets('选中最后一周时该行可见', (tester) async {
    await pumpPanel(tester, selectedWeek: 20);
    expect(find.text('第20周').hitTestable(), findsOneWidget);
  });
}
