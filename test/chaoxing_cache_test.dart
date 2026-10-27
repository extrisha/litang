import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/chaoxing/chaoxing_cache.dart';
import 'package:project_usst/data/chaoxing/chaoxing_client.dart';

void main() {
  late Directory dir;

  setUp(() async {
    CacheStore.clearMemory();
    dir = await Directory.systemTemp.createTemp('chaoxing_cache_test');
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

  test('课程 / 作业 / 活动缓存往返', () async {
    await ChaoxingCache.writeCourses('A', const <ChaoxingCourse>[
      ChaoxingCourse(
        courseId: '1',
        classId: '2',
        cpi: '3',
        name: '大学物理实验',
        teacher: '张老师',
      ),
    ]);
    await ChaoxingCache.writeWorks('A', const <ChaoxingWork>[
      ChaoxingWork(
        workId: 'w1',
        title: '实验报告',
        courseName: '大学物理实验',
        statusText: '未交',
        deadline: '2026-11-01',
        expired: false,
        taskUrl: 'https://example.com/work',
      ),
    ]);
    await ChaoxingCache.writeActivities('A', const <ChaoxingActivity>[
      ChaoxingActivity(
        id: 'a1',
        name: '签到',
        activeType: '2',
        status: 1,
        signCode: '1234',
        courseName: '大学物理实验',
        courseId: '1',
        classId: '2',
      ),
    ]);

    final data = await ChaoxingCache.read('A');
    expect(data, isNotNull);
    expect(data!.courses.single.name, '大学物理实验');
    expect(data.works.single.workId, 'w1');
    expect(data.activities.single.signCode, '1234');
  });

  test('缓存按学号隔离', () async {
    await ChaoxingCache.writeCourses('A', const <ChaoxingCourse>[
      ChaoxingCourse(courseId: '1', classId: '2', cpi: '3', name: 'A 的课程'),
    ]);

    expect(await ChaoxingCache.read('B'), isNull);
    expect((await ChaoxingCache.read('A'))!.courses.single.name, 'A 的课程');
  });
}
