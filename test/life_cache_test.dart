import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/life_cache.dart';
import 'package:project_usst/data/lms/rollcall_api.dart';
import 'package:project_usst/data/lms/todo_api.dart';

/// 验证「冷启动先显示旧数据」的缓存层：
/// 序列化往返不能丢字段，坏数据不能把页面搞崩。
void main() {
  late Directory dir;

  setUp(() async {
    CacheStore.clearMemory();
    dir = await Directory.systemTemp.createTemp('life_cache_test');
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

  test('待办缓存往返', () async {
    final items = <LmsTodo>[
      LmsTodo(
        id: 1,
        courseId: 2,
        title: '第三次作业',
        courseName: '高等数学',
        type: 'homework',
        deadline: DateTime(2026, 11, 1, 23, 59),
      ),
      LmsTodo(
        id: 3,
        courseId: 4,
        title: '单元测验',
        courseName: '大学物理',
        type: 'exam',
        deadline: null,
      ),
    ];
    await LifeCache.writeTodos(items);

    final back = await LifeCache.readTodos();
    expect(back, isNotNull);
    expect(back!.length, 2);
    expect(back[0].title, '第三次作业');
    expect(back[0].courseName, '高等数学');
    expect(back[0].isHomework, isTrue);
    expect(back[0].deadline, DateTime(2026, 11, 1, 23, 59));
    expect(back[1].deadline, isNull);
    expect(back[1].typeLabel, '考试');
  });

  test('考试缓存往返', () async {
    await LifeCache.writeExams(<LmsExam>[
      const LmsExam(
        courseName: '线性代数',
        examName: '期末考试',
        termLabel: '2026-2027 第1学期',
        timeText: '2027-01-10 09:00',
        location: '一教 305',
        teacher: '张老师',
      ),
    ]);

    final back = await LifeCache.readExams();
    expect(back, isNotNull);
    final exam = back!.single;
    expect(exam.courseName, '线性代数');
    expect(exam.location, '一教 305');
    expect(exam.timePending, isFalse);
  });

  test('签到缓存往返', () async {
    await LifeCache.writeRollcalls(<Rollcall>[
      const Rollcall(
        id: 'r1',
        courseName: '大学英语',
        type: 'qr_rollcall',
        timeText: '2 分钟前',
        isExpired: true,
        status: 'absent',
      ),
    ]);

    final back = await LifeCache.readRollcalls();
    expect(back, isNotNull);
    final item = back!.single;
    expect(item.id, 'r1');
    expect(item.isQrRollcall, isTrue);
    expect(item.isExpired, isTrue);
    expect(item.status, 'absent');
  });

  test('缓存内容不是列表时返回 null，不抛异常', () async {
    await CacheStore.write('life_todos_v1', 'oops');
    expect(await LifeCache.readTodos(), isNull);
  });

  test('缓存里的脏条目会被跳过', () async {
    await CacheStore.write('life_todos_v1', <Object?>[
      <String, dynamic>{'id': 1, 'title': '正常条目'},
      <String, dynamic>{'id': 2}, // 没有 title，应被丢弃
      'not a map',
    ]);

    final back = await LifeCache.readTodos();
    expect(back, isNotNull);
    expect(back!.length, 1);
    expect(back.single.title, '正常条目');
  });

  test('按学号隔离缓存，不串账号', () async {
    await LifeCache.writeTodos(<LmsTodo>[
      const LmsTodo(
        id: 1,
        courseId: 2,
        title: 'A 的作业',
        courseName: '高数',
        type: 'homework',
        deadline: null,
      ),
    ], username: 'A');
    await LifeCache.writeTodos(<LmsTodo>[
      const LmsTodo(
        id: 2,
        courseId: 3,
        title: 'B 的作业',
        courseName: '大物',
        type: 'homework',
        deadline: null,
      ),
    ], username: 'B');

    final a = await LifeCache.readTodos(username: 'A');
    final b = await LifeCache.readTodos(username: 'B');
    expect(a!.single.title, 'A 的作业');
    expect(b!.single.title, 'B 的作业');
    expect(await LifeCache.readTodos(username: 'C'), isNull);
  });
}
