import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/lms/course_visit_history.dart';
import 'package:project_usst/data/lms/todo_api.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('course_visits_');
    CacheStore.clearMemory();
    CacheStore.directoryOverride = () async => directory;
  });

  tearDown(() async {
    CacheStore.directoryOverride = null;
    CacheStore.clearMemory();
    await directory.delete(recursive: true);
  });

  test('连续点击按最后访问顺序保存，重启读取仍保留', () async {
    await Future.wait(<Future<void>>[
      CourseVisitHistory.record('student-a', 'tronclass', '2'),
      CourseVisitHistory.record('student-a', 'tronclass', '1'),
      CourseVisitHistory.record('student-a', 'tronclass', '2'),
    ]);
    CacheStore.clearMemory();
    expect(await CourseVisitHistory.load('student-a', 'tronclass'), ['2', '1']);
  });

  test('账号和课程来源相互独立', () async {
    await CourseVisitHistory.record('a', 'tronclass', '1');
    await CourseVisitHistory.record('a', 'chaoxing', '2');
    await CourseVisitHistory.record('b', 'tronclass', '3');
    expect(await CourseVisitHistory.load('a', 'tronclass'), ['1']);
    expect(await CourseVisitHistory.load('a', 'chaoxing'), ['2']);
    expect(await CourseVisitHistory.load('b', 'tronclass'), ['3']);
    expect(await CourseVisitHistory.load('b', 'chaoxing'), isEmpty);
  });

  test('排序保留未访问课程的服务器顺序，不插入已删除课程', () {
    const courses = <LmsCourseInfo>[
      LmsCourseInfo(id: 'a', name: 'A', teacher: '', termCode: ''),
      LmsCourseInfo(id: 'b', name: 'B', teacher: '', termCode: ''),
      LmsCourseInfo(id: 'c', name: 'C', teacher: '', termCode: ''),
    ];
    final sorted = CourseVisitHistory.sort(courses, ['deleted', 'b']);
    expect(sorted.map((course) => course.id), ['b', 'a', 'c']);
    expect(courses.map((course) => course.id), ['a', 'b', 'c']);
  });

  test('历史有上限，重复访问不产生重复条目', () {
    final recent = List.generate(110, (i) => '$i');
    final promoted = CourseVisitHistory.promote(recent, '50');
    expect(promoted.length, CourseVisitHistory.limit);
    expect(promoted.first, '50');
    expect(promoted.where((id) => id == '50'), hasLength(1));
  });

  test('未登录点击不写入公共历史', () async {
    await CourseVisitHistory.record('', 'tronclass', '1');
    expect(await CourseVisitHistory.load('', 'tronclass'), isEmpty);
  });
}
