import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/lms/course_info_cache.dart';
import 'package:project_usst/data/lms/todo_api.dart';

void main() {
  late Directory dir;

  setUp(() async {
    CacheStore.clearMemory();
    dir = await Directory.systemTemp.createTemp('course_info_cache_test');
    CacheStore.directoryOverride = () async => dir;
  });

  tearDown(() async {
    CacheStore.directoryOverride = null;
    CacheStore.clearMemory();
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Windows 上异步写入可能还没释放文件句柄，删不掉就算了
    }
  });

  test('课程缓存按学号隔离', () async {
    const a = LmsCourseInfo(
      id: '1',
      name: 'A 的课程',
      teacher: '张老师',
      termCode: '2026-2027-1',
    );
    const b = LmsCourseInfo(
      id: '2',
      name: 'B 的课程',
      teacher: '李老师',
      termCode: '2026-2027-1',
    );

    await CourseInfoCache.save('2026-2027-1', 'tronclass', <LmsCourseInfo>[
      a,
    ], username: 'A');
    await CourseInfoCache.save('2026-2027-1', 'tronclass', <LmsCourseInfo>[
      b,
    ], username: 'B');

    final loadedA = await CourseInfoCache.load(
      '2026-2027-1',
      'tronclass',
      username: 'A',
    );
    final loadedB = await CourseInfoCache.load(
      '2026-2027-1',
      'tronclass',
      username: 'B',
    );
    expect(loadedA!.single.name, 'A 的课程');
    expect(loadedB!.single.name, 'B 的课程');
    expect(
      await CourseInfoCache.load('2026-2027-1', 'tronclass', username: 'C'),
      isNull,
    );
  });
}
