import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/lms/todo_api.dart';

void main() {
  group('LmsApi.parseTodos', () {
    test('解析作业待办', () {
      const raw =
          '{"todo_list":[{'
          '"id": 2046131, "course_id": 151598, "title": "第二章计算作业2", "type": "homework",'
          '"course_name": "工程力学C", "end_time": "2026-10-25T13:59:00Z"}]}';
      final list = LmsApi.parseTodos(raw);
      expect(list.length, 1);
      expect(list.first.title, '第二章计算作业2');
      expect(list.first.courseName, '工程力学C');
      expect(list.first.isHomework, isTrue);
      expect(list.first.typeLabel, '作业');
      expect(list.first.deadline, isNotNull);
    });

    test('解析考试/测验选择题待办', () {
      const raw =
          '{"todo_list":[{'
          '"id": 198887, "course_id": 151502, "title": "科学与工程伦理选择题测验", "type": "exam",'
          '"course_name": "科学与工程伦理", "end_time": "2026-11-05T15:59:00Z"}]}';
      final list = LmsApi.parseTodos(raw);
      expect(list.length, 1);
      expect(list.first.id, 198887);
      expect(list.first.courseId, 151502);
      expect(list.first.title, '科学与工程伦理选择题测验');
      expect(list.first.courseName, '科学与工程伦理');
      expect(list.first.isHomework, isFalse);
      expect(list.first.type, 'exam');
      expect(list.first.typeLabel, '考试');
    });

    test('解析嵌套 course 对象与 activity_type 兼容结构', () {
      const raw =
          '{"todo_list":[{'
          '"id": 198888, "course": {"id": 151502, "name": "科学与工程伦理"}, "title": "第二章测验",'
          '"activity_type": "quiz", "deadline": "2026-11-06T12:00:00Z"}]}';
      final list = LmsApi.parseTodos(raw);
      expect(list.length, 1);
      expect(list.first.id, 198888);
      expect(list.first.courseId, 151502);
      expect(list.first.courseName, '科学与工程伦理');
      expect(list.first.type, 'quiz');
    });

    test('空/异常数据返回空列表', () {
      expect(LmsApi.parseTodos(''), isEmpty);
      expect(LmsApi.parseTodos('<html>'), isEmpty);
      expect(LmsApi.parseTodos('{"todo_list":[]}'), isEmpty);
    });
  });

  group('LmsApi.parseExams', () {
    test('解析考试安排', () {
      const raw =
          '{"items":[{'
          '"kcmc":"思想道德与法治","ksmc":"2025-2026-2学期期末考试",'
          '"xnmc":"2025-2026","xqmmc":"2","kssj":"未放开不可查",'
          '"jxdd":"申图205;申图205","jsxx":"09053/王素雷"}]}';
      final list = LmsApi.parseExams(raw);
      expect(list.length, 1);
      expect(list.first.courseName, '思想道德与法治');
      expect(list.first.termLabel, '2025-2026 第2学期');
      expect(list.first.location, '申图205');
      expect(list.first.timePending, isTrue);
    });

    test('时间已公布时 timePending 为 false', () {
      const raw = '{"items":[{"kcmc":"高数","kssj":"2026-01-10 09:00~11:00"}]}';
      final list = LmsApi.parseExams(raw);
      expect(list.first.timePending, isFalse);
    });

    test('空/异常数据返回空列表', () {
      expect(LmsApi.parseExams(''), isEmpty);
      expect(LmsApi.parseExams('{"items":[]}'), isEmpty);
    });
  });
}
