import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/pages/map_page.dart';

void main() {
  testWidgets('地图页能渲染底图并显示搜索入口', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapPage()));
    await tester.pump();

    expect(find.text('校园地图'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('搜索“一教”能命中第一教学楼', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapPage()));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '一教');
    await tester.pump();

    expect(find.text('第一教学楼'), findsWidgets);
  });
}
