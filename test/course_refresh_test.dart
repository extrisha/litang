import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/auth/session_store.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/jwc/course_api.dart';
import 'package:project_usst/data/jwc/course_repository.dart';
import 'package:project_usst/data/models.dart';

class _Client extends CasClient {
  _Client(this.body) {
    studentId = 'A';
  }
  String body;
  int timetableCalls = 0;
  Completer<void>? gate;
  bool offline = false;
  @override
  Future<Response<String>> getJson(Uri uri, {Map<String, String>? data}) async {
    if (offline) {
      throw DioException(
        requestOptions: RequestOptions(path: uri.toString()),
        type: DioExceptionType.connectionError,
        error: 'campus network unavailable',
      );
    }
    final isTimetable = uri.path.contains('xskbcx');
    if (isTimetable) {
      timetableCalls++;
      await gate?.future;
    }
    return Response(
      requestOptions: RequestOptions(path: uri.toString()),
      statusCode: 200,
      data: isTimetable ? body : '<html></html>',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    CacheStore.clearMemory();
    await CourseRepository.clear();
  });

  test('当前学期合法空课表立即返回，不查询历史学期', () async {
    final client = _Client('{"xsxx":{"XNM":"2026","XQM":"3"},"kbList":[]}');
    expect((await CourseApi(client).fetchCurrent()).courses, isEmpty);
    expect(client.timetableCalls, 1);
  });

  test('错误 JSON 结构不能被缓存为空课表', () async {
    final client = _Client('{"message":"服务不可用"}');
    await expectLater(CourseApi(client).fetchCurrent(), throwsException);
    expect(client.timetableCalls, 2);
  });

  test('并发请求合并且正常空课表覆盖旧缓存', () async {
    await CacheStore.write('usst_course_snapshot_v2', {
      'termLabel': '旧学期',
      'courses': [],
    }, secure: true);
    final client = _Client(
      '{"xsxx":{"XNMC":"2026-2027","XQMMC":"1"},"kbList":[]}',
    )..gate = Completer<void>();
    final a = CourseRepository.refresh(client);
    final b = CourseRepository.refresh(client);
    expect(identical(a, b), isTrue);
    client.gate!.complete();
    await Future.wait([a, b]);
    expect(client.timetableCalls, 1);
    expect(
      (await CourseRepository.loadCache(username: 'A'))!.termLabel,
      '2026-2027 第1学期',
    );
  });

  test('清理账号缓存后，旧请求不能把旧快照写回来', () async {
    final client = _Client('{"kbList":[]}')..gate = Completer<void>();
    final pending = CourseRepository.refresh(client);
    await CourseRepository.clear();
    client.gate!.complete();
    await pending;
    expect(await CourseRepository.loadCache(username: 'A'), isNull);
  });

  final oldSchedule = CourseSnapshot(
    termLabel: '已下载学期',
    xnm: '2026',
    xqm: '3',
    updatedAt: DateTime(2026, 1),
    courses: const [
      Course(
        name: '离线高等数学',
        day: 1,
        start: 1,
        span: 2,
        room: '一教101',
        weeks: [1, 2, 3],
        weeksText: '1-3周',
      ),
    ],
  );

  test('升级后离线迁移旧课表，重启仍可读且不冒充刚更新', () async {
    await SessionStore().save(CasClient(), username: 'A');
    await CacheStore.write(
      'usst_course_snapshot_v2',
      oldSchedule.toJson(),
      secure: true,
    );
    CacheStore.clearMemory();
    final migrated = await CourseRepository.loadCache(username: 'A');
    expect(migrated!.courses.single.name, '离线高等数学');
    expect(
      await CacheStore.read('usst_course_snapshot_v2', secure: true),
      isNull,
    );
    CacheStore.clearMemory();
    expect(
      (await CourseRepository.loadCache(username: 'A'))!.courses.single.room,
      '一教101',
    );
    expect(await CourseRepository.isFresh(username: 'A'), isFalse);
  });

  test('旧全局课表只能归入本地保存账号，不能被另一账号认领', () async {
    await SessionStore().save(CasClient(), username: 'A');
    await CacheStore.write(
      'usst_course_snapshot_v2',
      oldSchedule.toJson(),
      secure: true,
    );
    expect(await CourseRepository.loadCache(username: 'B'), isNull);
    expect(
      await CacheStore.read('usst_course_snapshot_v2', secure: true),
      isNotNull,
    );
    expect(await CourseRepository.loadCache(username: 'A'), isNotNull);
    await SessionStore().save(CasClient(), username: 'B');
    expect(await CourseRepository.loadCache(), isNull);
  });

  test('没有本地账号记录时不猜测旧课表归属', () async {
    await CacheStore.write(
      'usst_course_snapshot_v2',
      oldSchedule.toJson(),
      secure: true,
    );
    expect(await CourseRepository.loadCache(username: 'A'), isNull);
    expect(
      await CacheStore.read('usst_course_snapshot_v2', secure: true),
      isNotNull,
    );
  });

  test('旧课表还没迁移时切换登录账号，不能将其认作新账号课表', () async {
    await SessionStore().save(CasClient(), username: 'A');
    await CacheStore.write(
      'usst_course_snapshot_v2',
      oldSchedule.toJson(),
      secure: true,
    );
    await SessionStore().save(CasClient(), username: 'B');
    expect(await CourseRepository.loadCache(username: 'B'), isNull);
    expect(
      await CacheStore.read('usst_course_snapshot_v2', secure: true),
      isNull,
    );
  });

  test('新格式合法空课表不从旧缓存复活课程', () async {
    await SessionStore().save(CasClient(), username: 'A');
    await CacheStore.write(
      'usst_course_snapshot_v2',
      oldSchedule.toJson(),
      secure: true,
    );
    await CourseRepository.save(
      CourseSnapshot(
        termLabel: '新学期无课',
        xnm: '2027',
        xqm: '12',
        courses: [],
        updatedAt: DateTime.now(),
      ),
      username: 'A',
    );
    expect((await CourseRepository.loadCache(username: 'A'))!.courses, isEmpty);
  });

  test('离开校园网刷新失败不覆盖已保存课表', () async {
    await CourseRepository.save(oldSchedule, username: 'A');
    await expectLater(
      CourseRepository.refresh(_Client('')..offline = true),
      throwsA(isA<DioException>()),
    );
    CacheStore.clearMemory();
    expect(
      (await CourseRepository.loadCache(username: 'A'))!.courses.single.name,
      '离线高等数学',
    );
  });

  test('缓存已有结构化周次时，缺少原始周次文字也能离线显示', () async {
    final raw = oldSchedule.toJson();
    ((raw['courses'] as List).single as Map)['weeksText'] = '';
    await CourseRepository.save(CourseSnapshot.fromJson(raw), username: 'A');
    expect(
      (await CourseRepository.loadCache(username: 'A'))!.courses.single.weeks,
      [1, 2, 3],
    );
  });
}
