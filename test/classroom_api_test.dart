import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/jwc/classroom_api.dart';
import 'package:project_usst/data/jwc/classroom_data.dart';

class _FakeCasClient extends CasClient {
  _FakeCasClient(this.responses);

  final Map<String, String> responses;

  @override
  Future<Response<String>> getApi(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final key = uri.path;
    final data = responses[key] ?? '{}';
    return Response<String>(
      requestOptions: RequestOptions(path: uri.path),
      statusCode: 200,
      data: data,
    );
  }
}

void main() {
  group('ClassroomData & Normalize', () {
    test('教学楼清单齐全且包含已知教室', () {
      expect(allKnownBuildings, contains('第一教学楼'));
      expect(allKnownBuildings, contains('卓越楼'));
      expect(allKnownBuildings, contains('综合楼'));
      expect(knownClassroomsByBuilding['第一教学楼'], isNotEmpty);
      expect(knownClassroomsByBuilding['第一教学楼']!, contains('一教201'));
      expect(knownClassroomsByBuilding['卓越楼']!, contains('卓越楼117'));
    });

    test('normalizeClassroomName 别名替换正确', () {
      expect(normalizeClassroomName('第一教学楼101'), '一教101');
      expect(normalizeClassroomName('第三教学楼201'), '三教201');
      expect(normalizeClassroomName('第四教学楼303'), '四教303');
      expect(normalizeClassroomName('卓越工程大楼118'), '卓越楼118');
      expect(normalizeClassroomName('综合A101'), '综合楼A区101');
      expect(normalizeClassroomName('综合B201'), '综合楼B区201');
    });
  });

  group('LappScheduleItem 周次与节次匹配', () {
    const item = LappScheduleItem(
      id: '1001',
      courseName: '高等数学',
      teacherName: '张三',
      dayOfWeek: 1,
      startPeriod: 1,
      periodLength: 2,
      classroom: '一教201',
      startWeek: 1,
      endWeek: 16,
      weeksText: '1,2,3,4,5,6',
      startTime: '08:00',
      endTime: '09:25',
    );

    test('weeksText 优先判断活跃周', () {
      expect(item.isActiveInWeek(4), isTrue);
      expect(item.isActiveInWeek(6), isTrue);
      expect(item.isActiveInWeek(7), isFalse);
    });

    test('节次区间重叠判断', () {
      // 课程是 1-2 节 (start=1, len=2 -> 1..2)
      expect(item.matchesSection(1, 2), isTrue);
      expect(item.matchesSection(2, 3), isTrue);
      expect(item.matchesSection(3, 5), isFalse);
    });
  });

  group('ClassroomApi.queryClassrooms 计算空教室与占用', () {
    test('正确识别占用课程、授课教师与空闲教室', () async {
      const mockSchedule = '''
      {
        "resultCode": 0,
        "result": {
          "total": 1,
          "data": [
            {
              "id": "c1",
              "kcmc": "大学物理",
              "lsmc": "李四",
              "zj": 1,
              "jc": 1,
              "jccd": 2,
              "jsdd": "一教201",
              "qsz": 1,
              "jsz": 16,
              "zc": "1-16",
              "classTimeBegin": "08:00",
              "classTimeEnd": "09:25"
            }
          ]
        }
      }
      ''';

      final client = _FakeCasClient(<String, String>{
        '/_web/_customizes/usst/schoolTimetable/mobile/permit/pc/pub/index.html':
            '<html>ok</html>',
        '/_web/_lightapp/schedule/mobile/school/queryClassSchedule.rst':
            mockSchedule,
      });

      final api = ClassroomApi(client);
      final rooms = await api.queryClassrooms(
        building: '第一教学楼',
        week: 1,
        dayOfWeek: 1,
        sectionRange: (1, 2),
      );

      expect(rooms, isNotEmpty);
      final room201 = rooms.firstWhere((r) => r.name == '一教201');
      expect(room201.isFree, isFalse);
      expect(room201.occupiedCourse, '大学物理');
      expect(room201.occupiedTeacher, '李四');

      final room205 = rooms.firstWhere((r) => r.name == '一教205');
      expect(room205.isFree, isTrue);
      expect(room205.occupiedCourse, isEmpty);
    });
  });

  group('ClassroomApi 全校课表与课程聚合', () {
    test('queryCourses 能正确聚合教学班多个上课时段并识别本研属性', () async {
      const mockCourseSchedule = '''
      {
        "resultCode": 0,
        "result": {
          "total": 2,
          "data": [
            {
              "id": "s1",
              "kcdm": "22000210",
              "kcmc": "数据结构",
              "bjdm": "B22000210-01",
              "bjmc": "(2026-2027-1)-22000210-01",
              "lsmc": "王五",
              "lszc": "教授",
              "xy": "光电信息与计算机工程学院",
              "xf": "3.5",
              "xs": "56",
              "kclx": "专业必修",
              "zj": 1,
              "jc": 1,
              "jccd": 2,
              "jsdd": "卓越楼201",
              "qsz": 1,
              "jsz": 16,
              "zc": "1-16",
              "classTimeBegin": "08:00",
              "classTimeEnd": "09:25"
            },
            {
              "id": "s2",
              "kcdm": "22000210",
              "kcmc": "数据结构",
              "bjdm": "B22000210-01",
              "bjmc": "(2026-2027-1)-22000210-01",
              "lsmc": "王五",
              "lszc": "教授",
              "xy": "光电信息与计算机工程学院",
              "xf": "3.5",
              "xs": "56",
              "kclx": "专业必修",
              "zj": 4,
              "jc": 3,
              "jccd": 2,
              "jsdd": "卓越楼201",
              "qsz": 1,
              "jsz": 16,
              "zc": "1-16",
              "classTimeBegin": "09:45",
              "classTimeEnd": "11:10"
            }
          ]
        }
      }
      ''';

      final client = _FakeCasClient(<String, String>{
        '/_web/_customizes/usst/schoolTimetable/mobile/permit/pc/pub/index.html':
            '<html>ok</html>',
        '/_web/_lightapp/schedule/mobile/school/queryClassSchedule.rst':
            mockCourseSchedule,
      });

      final api = ClassroomApi(client);
      final courses = await api.queryCourses(keyword: '数据结构');

      expect(courses.length, 1);
      final course = courses.first;
      expect(course.courseName, '数据结构');
      expect(course.courseCode, '22000210');
      expect(course.isUndergraduate, isTrue);
      expect(course.isGraduate, isFalse);
      expect(course.teacherDisplay, '王五 (教授)');
      expect(course.creditHoursDisplay, '3.5 学分 · 56 学时');
      expect(course.slots.length, 2);
      expect(course.slots[0].dayOfWeekName, '周一');
      expect(course.slots[0].sectionDesc, '第1-2节');
      expect(course.slots[1].dayOfWeekName, '周四');
      expect(course.slots[1].sectionDesc, '第3-4节');
    });

    test('fetchColleges 解析学院列表', () async {
      const mockColleges = '''
      {
        "resultCode": 0,
        "result": {
          "data": [
            {"xy": "光电信息与计算机工程学院"},
            {"xy": "机械工程学院"}
          ]
        }
      }
      ''';

      final client = _FakeCasClient(<String, String>{
        '/_web/_customizes/usst/schoolTimetable/mobile/permit/pc/pub/index.html':
            '<html>ok</html>',
        '/_web/_lightapp/schedule/mobile/school/queryClassXy.rst':
            mockColleges,
      });

      final api = ClassroomApi(client);
      final colleges = await api.fetchColleges();
      expect(colleges, contains('光电信息与计算机工程学院'));
      expect(colleges, contains('机械工程学院'));
    });
  });
}
