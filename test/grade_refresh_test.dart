import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/jwc/grade_api.dart';
import 'package:project_usst/data/jwc/grade_repository.dart';

class _Client extends CasClient {
  _Client(this.respond);
  final Future<String> Function(Uri, Map<String, String>?) respond;

  @override
  Future<Response<String>> getJson(
    Uri uri, {
    Map<String, String>? data,
  }) async => Response(
    requestOptions: RequestOptions(path: uri.toString()),
    statusCode: 200,
    data: await respond(uri, data),
  );
}

Map<String, Object> _grade(int index) => {
  'kcmc': '课程$index',
  'kch': '$index',
  'kch_id': 'course$index',
  'jxb_id': 'class$index',
  'xnm': '2026',
  'xqm': '3',
  'xnmmc': '2026-2027',
  'xqmmc': '1',
  'cj': '90',
  'bfzcj': '90',
};

String _page(List<Map<String, Object>> grades, {int? total}) =>
    jsonEncode({'totalCount': total ?? grades.length, 'items': grades});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    CacheStore.clearMemory();
    await GradeRepository.clear();
  });

  test('总评请求不等待分项，分项失败不会清除总评', () async {
    var calls = 0;
    final client = _Client((uri, _) async {
      calls++;
      if (uri.path.contains('cxDgXscj')) return _page([_grade(1)]);
      throw StateError('details unavailable');
    });
    final snapshot = await GradeApi(client).fetchAll();
    expect(calls, 1);
    expect(snapshot.grades.single.scoreText, '90');
    final enriched = await GradeApi(client).enrich(snapshot);
    expect(enriched.grades.single.scoreText, '90');
    expect(enriched.updatedAt, snapshot.updatedAt);
  });

  test('分项逐课降级最多三路并发，单课失败仍返回其他课程', () async {
    var active = 0;
    var peak = 0;
    var detailCalls = 0;
    final client = _Client((uri, _) async {
      if (uri.path.contains('cxDgXscj')) {
        return _page(List.generate(8, _grade));
      }
      if (uri.path.contains('cxXsfxcjIndex')) return '{"items":[]}';
      active++;
      detailCalls++;
      if (active > peak) peak = active;
      try {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (uri.queryParameters['jxb_id'] == 'class2') {
          throw StateError('single course unavailable');
        }
        return '<tr><td>期末</td><td>60%</td><td>90</td></tr>';
      } finally {
        active--;
      }
    });
    final snapshot = await GradeApi(client).fetchAll();
    final enriched = await GradeApi(client).enrich(snapshot);
    expect(peak, 3);
    expect(detailCalls, 8);
    expect(enriched.grades.where((grade) => grade.hasDetail), hasLength(7));
    expect(enriched.grades.every((grade) => grade.scoreText == '90'), isTrue);
  });

  test('合法空成绩覆盖旧缓存，且不请求无用分项', () async {
    var calls = 0;
    final client = _Client((uri, _) async {
      calls++;
      return _page([]);
    });
    await GradeRepository.save(
      GradeSnapshot(
        grades: GradeApi.parsePage(_page([_grade(1)])).grades,
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    final snapshot = await GradeRepository.refresh(client);
    await GradeRepository.enrich(client, snapshot);
    expect((await GradeRepository.loadCache())!.grades, isEmpty);
    expect(calls, 1);
  });

  test('重复返回第一页不能伪装成完整成绩', () async {
    final client = _Client((_, _) async => _page([_grade(1)], total: 2));
    await expectLater(GradeApi(client).fetchAll(), throwsStateError);
  });

  test('旧接口 totalResult 也必须继续读取后页', () async {
    final client = _Client(
      (_, data) async => jsonEncode({
        'totalResult': 2,
        'items': [_grade(int.parse(data!['queryModel.currentPage']!))],
      }),
    );
    expect((await GradeApi(client).fetchAll()).grades, hasLength(2));
  });

  test('缓存清理后同一客户端重新刷新不能合并到已失效请求', () async {
    final firstGate = Completer<void>();
    var calls = 0;
    final client = _Client((_, _) async {
      final index = ++calls;
      if (index == 1) await firstGate.future;
      return _page([_grade(index)]);
    });
    final old = GradeRepository.refresh(client);
    expect(identical(old, GradeRepository.refresh(client)), isTrue);
    await GradeRepository.clear();
    final fresh = GradeRepository.refresh(client);
    expect(identical(old, fresh), isFalse);
    final newSnapshot = await fresh;
    firstGate.complete();
    await old;
    expect(calls, 2);
    expect((await GradeRepository.loadCache())!.toJson(), newSnapshot.toJson());
  });

  test('即使抓取时间相同，旧总评的迟到分项也不能覆盖新缓存', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    var listCalls = 0;
    final client = _Client((uri, _) async {
      if (uri.path.contains('cxDgXscj')) return _page([_grade(++listCalls)]);
      if (!started.isCompleted) started.complete();
      await gate.future;
      return '{"items":[{"jxb_id":"class1","qmcj":"85"}]}';
    });
    final old = await GradeRepository.refresh(client);
    final pendingDetails = GradeRepository.enrich(client, old);
    await started.future;
    final fetched = await GradeRepository.refresh(client);
    final fresh = GradeSnapshot(
      grades: fetched.grades,
      updatedAt: old.updatedAt,
    );
    await GradeRepository.save(fresh);
    gate.complete();
    await pendingDetails;
    expect((await GradeRepository.loadCache())!.toJson(), fresh.toJson());
  });
}
