import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/jwc/training_plan_repository.dart';
import 'package:project_usst/pages/training_plan_page.dart';

TrainingPlan plan(String title) => TrainingPlan(
  title: title,
  url: Uri.parse(
    'https://jwc.usst.edu.cn/_upload/${Uri.encodeComponent(title)}.pdf',
  ),
);

class _Repository extends TrainingPlanRepository {
  final response = Completer<List<TrainingPlan>>();
  final cached = [plan('2024级计算机科学与技术培养计划'), plan('2025级机械工程培养计划')];
  final documentResponse = <TrainingPlan>[];
  TrainingPlan? opened;
  CancelToken? cancel;
  @override
  Future<List<TrainingPlan>> loadCached() async => cached;
  @override
  Future<List<TrainingPlan>> fetchCatalog({CancelToken? cancelToken}) {
    cancel = cancelToken;
    return response.future;
  }

  @override
  Future<List<TrainingPlan>> documents(
    TrainingPlan plan, {
    CancelToken? cancelToken,
  }) async {
    opened = plan;
    return documentResponse;
  }
}

void main() {
  testWidgets('缓存立即显示，专业筛选可切换，搜索不串专业，离线保留列表', (tester) async {
    final repository = _Repository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainingPlanPage(major: '计算机科学与技术', repository: repository),
      ),
    );
    await tester.pump();
    expect(find.text('2024级计算机科学与技术培养计划'), findsOneWidget);
    expect(find.text('2025级机械工程培养计划'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.text('2025级机械工程培养计划'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '机械');
    await tester.pump();
    expect(find.text('2024级计算机科学与技术培养计划'), findsNothing);
    expect(find.text('2025级机械工程培养计划'), findsOneWidget);
    repository.response.completeError(const TrainingPlanException('请连接校园网'));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前显示已缓存目录'), findsOneWidget);
    expect(find.text('2025级机械工程培养计划'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('小屏双倍字体、受限网络与搜索键盘不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _Repository()..cached.clear();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: TrainingPlanPage(
          major: '计算机科学与技术（中外合作办学）',
          repository: repository,
        ),
      ),
    );
    repository.response.completeError(
      const TrainingPlanException(
        '培养计划目录仅限校内访问。请连接校园网或学校授权 VPN 后重试，也可在学校网页中查看。',
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('本专业筛选保留未知专业汇总，展开后只按实际 PDF 名称标匹配', (tester) async {
    final summary = TrainingPlan(
      title: '2024级各专业培养方案汇总',
      url: Uri.parse('https://jwc.usst.edu.cn/2024/page.htm'),
    );
    final otherArticle = TrainingPlan(
      title: '2024级机械工程培养方案',
      url: Uri.parse('https://jwc.usst.edu.cn/mechanical/page.htm'),
    );
    final ownPdf = plan('2024级计算机科学与技术培养计划');
    final mechanicalPdf = plan('2024级机械工程培养计划');
    final otherDirection = plan('2024级计算机科学与技术（中外合作）培养计划');
    final repository = _Repository();
    repository.cached
      ..clear()
      ..addAll([summary, ownPdf, otherArticle, otherDirection]);
    repository.documentResponse.addAll([mechanicalPdf, otherDirection, ownPdf]);
    repository.response.complete(repository.cached);
    await tester.pumpWidget(
      MaterialApp(
        home: TrainingPlanPage(major: '计算机科学与技术', repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(summary.title), findsOneWidget);
    expect(find.textContaining('专业待核对，展开查看 PDF'), findsOneWidget);
    expect(find.text(ownPdf.title), findsOneWidget);
    expect(find.text(otherArticle.title), findsNothing);
    expect(find.text(otherDirection.title), findsNothing);

    await tester.tap(find.text(summary.title));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.opened, same(summary));
    expect(find.byType(SimpleDialog), findsOneWidget);
    expect(find.text('专业名称匹配，仍请核对年级与方向'), findsOneWidget);
    expect(find.text('适用专业待核对，请以 PDF 原文为准'), findsNWidgets(2));
    final firstOption = find.byType(SimpleDialogOption).first;
    expect(
      find.descendant(of: firstOption, matching: find.text(ownPdf.title)),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);
    expect(find.text(summary.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('汇总只有一个未指定专业 PDF 也先展示待核对选择', (tester) async {
    final summary = TrainingPlan(
      title: '2024级培养方案',
      url: Uri.parse('https://jwc.usst.edu.cn/2024/page.htm'),
    );
    final repository = _Repository();
    repository.cached
      ..clear()
      ..add(summary);
    repository.documentResponse.add(plan('培养方案'));
    repository.response.complete(repository.cached);
    await tester.pumpWidget(
      MaterialApp(
        home: TrainingPlanPage(major: '计算机科学与技术', repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(summary.title));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SimpleDialog), findsOneWidget);
    expect(find.text('适用专业待核对，请以 PDF 原文为准'), findsOneWidget);
    expect(find.text('专业名称匹配，仍请核对年级与方向'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('离开页面会取消请求，迟到的失败不会触发页面更新', (tester) async {
    final repository = _Repository();
    await tester.pumpWidget(
      MaterialApp(home: TrainingPlanPage(repository: repository)),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(repository.cancel!.isCancelled, isTrue);
    repository.response.completeError(Exception('late failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
