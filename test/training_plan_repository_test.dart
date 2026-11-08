import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/jwc/training_plan_repository.dart';

// 人工契约样本，不声称来自尚未能访问的校内培养计划目录。
const catalog = '''<ul class="wp_article_list">
<li><a href="/2026/1105/c1a123/page.htm" title="2024级计算机科学与技术专业本科人才培养方案">计算机</a></li>
<li><a href="/_upload/plan.pdf">2025级信息管理与信息系统培养计划.pdf</a></li>
</ul><a href="list2.htm">下一页</a><a href="/pyjh/list.htm">培养计划</a>''';

class _Adapter implements HttpClientAdapter {
  final bodies = <String, List<int>>{};
  final calls = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options.uri.path);
    final body = bodies[options.uri.path];
    return ResponseBody.fromBytes(
      body ?? utf8.encode('not found'),
      body == null ? 404 : 200,
      headers: {
        Headers.contentLengthHeader: ['${body?.length ?? 9}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('litang-plan-test-');
    CacheStore.directoryOverride = () async => directory;
    CacheStore.clearMemory();
  });
  tearDown(() async {
    CacheStore.directoryOverride = null;
    CacheStore.clearMemory();
    await directory.delete(recursive: true);
  });

  test('目录提取文章、相对 PDF、分页，专业方向严格匹配且不猜年级', () {
    final links = TrainingPlanRepository.parseLinks(
      catalog,
      TrainingPlanRepository.catalogUrl,
    );
    expect(links.plans, hasLength(2));
    expect(links.nextPage!.path, '/pyjh/list2.htm');
    expect(links.plans.first.matchesMajor('计算机科学与技术'), isTrue);
    expect(links.plans.first.matchesMajor('计算机科学与技术（中外合作）'), isFalse);
    expect(links.plans.first.cohort, 2024);
    expect(TrainingPlan(title: '2025版计算机科学与技术培养方案', url: Uri()).cohort, isNull);
  });

  test('汇总文章的专业未知，明确的其他专业和方向不能当作汇总', () {
    TrainingPlan article(String title) => TrainingPlan(
      title: title,
      url: Uri.parse('https://jwc.usst.edu.cn/2026/page.htm'),
    );
    for (final title in ['2024级本科培养方案', '2024级各专业培养方案汇总', '培养计划（2024级）']) {
      expect(article(title).isSummary, isTrue, reason: title);
      expect(article(title).matchesMajor('计算机科学与技术'), isFalse);
    }
    for (final title in ['2024级机械工程培养方案', '2024级计算机科学与技术（中外合作）培养方案']) {
      expect(article(title).isSummary, isFalse, reason: title);
      expect(article(title).matchesMajor('计算机科学与技术'), isFalse);
    }
    expect(article('培养方案').matchesMajor('培养计划'), isFalse);
    expect(
      TrainingPlan(
        title: '2024级培养方案',
        url: Uri.parse('https://jwc.usst.edu.cn/a.pdf'),
      ).isSummary,
      isFalse,
    );
  });

  test('校内限制与无法识别的目录不能覆盖缓存', () async {
    final adapter = _Adapter()
      ..bodies['/pyjh/list.htm'] = utf8.encode(catalog)
      ..bodies['/pyjh/list2.htm'] = utf8.encode(
        '<ul class="wp_article_list"><a href="/_upload/m.pdf">机械培养计划</a></ul>',
      );
    final repository = TrainingPlanRepository(
      client: Dio()..httpClientAdapter = adapter,
      directory: directory,
    );
    expect(await repository.fetchCatalog(), hasLength(3));
    expect(adapter.calls, ['/pyjh/list.htm', '/pyjh/list2.htm']);
    adapter.bodies['/pyjh/list.htm'] = utf8.encode(
      '<p>当前ip并非校内地址，该信息仅允许校内地址访问</p>',
    );
    await expectLater(
      repository.fetchCatalog(),
      throwsA(isA<TrainingPlanException>()),
    );
    expect(await repository.loadCached(), hasLength(3));
    adapter.bodies['/pyjh/list.htm'] = utf8.encode('<html>临时维护</html>');
    await expectLater(
      repository.fetchCatalog(),
      throwsA(isA<TrainingPlanException>()),
    );
    expect(await repository.loadCached(), hasLength(3));
  });

  test('文章提取多个 PDF 与内嵌 PDF，按 URL 去重', () {
    final result = TrainingPlanRepository.parseLinks(
      '''
      <h1>2024级培养方案</h1><div class="wp_articlecontent">
      <a href="/_upload/a.pdf">计算机.pdf</a><a href="/_upload/b.pdf">机械.pdf</a>
      </div><iframe src="/viewer.html?file=%2F_upload%2Fa.pdf"></iframe>
    ''',
      Uri.parse('https://jwc.usst.edu.cn/2026/page.htm'),
      catalog: false,
    );
    expect(result.plans.map((item) => item.url.path), [
      '/_upload/a.pdf',
      '/_upload/b.pdf',
    ]);
  });

  test('PDF 流式落盘、同名链接不覆盖、离线复用，HTML 错误页不留下伪 PDF', () async {
    final adapter = _Adapter()
      ..bodies['/a/plan.pdf'] = utf8.encode('%PDF-1.7\nfixture-a')
      ..bodies['/b/plan.pdf'] = utf8.encode('%PDF-1.7\nfixture-b')
      ..bodies['/error.pdf'] = utf8.encode('<html>仅允许校内访问</html>');
    final repository = TrainingPlanRepository(
      client: Dio()..httpClientAdapter = adapter,
      directory: directory,
    );
    TrainingPlan plan(String path) => TrainingPlan(
      title: '培养计划.pdf',
      url: Uri.parse('https://jwc.usst.edu.cn$path'),
    );
    final first = await repository.download(plan('/a/plan.pdf'));
    final second = await repository.download(plan('/b/plan.pdf'));
    expect(first, isNot(second));
    expect(await File(first).readAsString(), contains('fixture-a'));
    adapter.bodies.clear();
    expect(await repository.download(plan('/a/plan.pdf')), first);
    expect(adapter.calls.where((path) => path == '/a/plan.pdf'), hasLength(1));
    adapter.bodies['/error.pdf'] = utf8.encode('<html>错误页</html>');
    await expectLater(
      repository.download(plan('/error.pdf')),
      throwsA(isA<TrainingPlanException>()),
    );
    final files = await Directory('${directory.path}/training-plans')
        .list()
        .toList();
    expect(files, hasLength(2));
    expect(files.any((file) => file.path.endsWith('.part')), isFalse);
  });
}
