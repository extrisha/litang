import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/chaoxing/chaoxing_client.dart';

/// 课程列表的 JSON 解析。
/// 结构来自 2026-10-28 用真实账号抓的 `backclazzdata` 响应。
void main() {
  String payload() => jsonEncode(<String, dynamic>{
    'result': 1,
    'msg': '',
    'channelList': <dynamic>[
      // 1) 文件夹型 channel：没有 course，应被忽略
      <String, dynamic>{
        'catalogId': 9146613,
        'key': 9146613,
        'content': <String, dynamic>{
          'folderName': '大一上',
          'cpi': 497874758,
        },
      },
      // 2) 正常课程
      <String, dynamic>{
        'key': 155660593, // classId
        'cpi': 497874758, // personId
        'content': <String, dynamic>{
          'name': '(2026-2027-1)-19101230-02',
          'course': <String, dynamic>{
            'data': <dynamic>[
              <String, dynamic>{
                'id': 267465996, // courseId
                'name': '人体解剖学实验',
                'teacherfactor': '王艳',
              },
              <String, dynamic>{
                'id': 267465995,
                'name': '大学物理',
                'teacherfactor': '李老师',
              },
            ],
          },
        },
      },
      // 3) 缺字段的脏数据
      <String, dynamic>{
        'key': 1,
        'content': <String, dynamic>{
          'course': <String, dynamic>{
            'data': <dynamic>[
              <String, dynamic>{'id': 0},
              <String, dynamic>{'name': ''},
            ],
          },
        },
      },
    ],
  });

  test('能解析出 courseId / classId / cpi / 课程名 / 教师', () {
    final courses = ChaoxingClient.parseCourseListJson(payload());
    expect(courses, isNotNull);
    expect(courses!.length, 2);

    final first = courses.first;
    expect(first.courseId, '267465996');
    expect(first.classId, '155660593');
    expect(first.cpi, '497874758');
    expect(first.name, '人体解剖学实验');
    expect(first.teacher, '王艳');
  });

  test('未登录（result=0）返回 null，让调用方回退 HTML', () {
    final raw = jsonEncode(<String, dynamic>{
      'result': 0,
      'msg': '请重新登录',
    });
    expect(ChaoxingClient.parseCourseListJson(raw), isNull);
  });

  test('结构不认识时返回 null，不抛异常', () {
    expect(ChaoxingClient.parseCourseListJson(''), isNull);
    expect(ChaoxingClient.parseCourseListJson('<html></html>'), isNull);
    expect(ChaoxingClient.parseCourseListJson('{"result":1}'), isNull);
    expect(
      ChaoxingClient.parseCourseListJson('{"result":1,"channelList":"oops"}'),
      isNull,
    );
  });
}
