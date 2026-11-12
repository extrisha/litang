import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/chaoxing/chaoxing_client.dart';
import 'package:project_usst/data/chaoxing/chaoxing_html.dart';

void main() {
  group('ChaoxingHtml.hiddenFields', () {
    test('按 name / id 取隐藏域，属性顺序不影响', () {
      const html =
          '<form>'
          '<input value="abc123" type="hidden" id="workEnc">'
          '<input type="hidden" name="examEnc" value="def456"/>'
          "<input type='hidden' name='enc' value='789'>"
          '</form>';
      final fields = ChaoxingHtml.hiddenFields(html);
      expect(fields['workEnc'], 'abc123');
      expect(fields['examEnc'], 'def456');
      expect(fields['enc'], '789');
    });

    test('非 hidden 的 input 不取', () {
      const html =
          '<input type="text" name="workEnc" value="nope">'
          '<input type="hidden" name="workEnc" value="yes">';
      expect(ChaoxingHtml.hiddenFields(html)['workEnc'], 'yes');
    });

    test('空页面返回空表，不抛异常', () {
      expect(ChaoxingHtml.hiddenFields(''), isEmpty);
      expect(ChaoxingHtml.hiddenFields('<html>'), isEmpty);
    });
  });

  group('ChaoxingHtml.workRows', () {
    test('锚点是 li[data]，不要求 onclick 里有 goTask', () {
      const html =
          '<ul>'
          '<li data="http://mooc1.chaoxing.com/mooc-ans/mooc2/work/task'
          '?courseId=1&amp;classId=2&amp;workId=57616202&amp;answerId=0&amp;enc=e"'
          ' aria-label="消化系统 ; 未交">'
          '<p class="overHidden2 fl">消化系统</p>'
          '<p class="status fl">未交</p>'
          '<div class="time notOver">截止：2026-11-20 23:59</div>'
          '</li>'
          '</ul>';
      final rows = ChaoxingHtml.workRows(html);
      expect(rows, hasLength(1));
      expect(rows.single.url, contains('workId=57616202'));
      expect(rows.single.url, contains('&classId=2'));
      expect(rows.single.title, '消化系统');
      expect(rows.single.status, '未交');
      expect(rows.single.timeText, contains('2026-11-20'));
      expect(rows.single.expired, isFalse);
    });

    test('aria-label 缺失时退回 class 文本', () {
      const html =
          '<li data="/work/task?workId=9">'
          '<p class="overHidden2">实验报告</p>'
          '<p class="status">待批阅</p>'
          '</li>';
      final row = ChaoxingHtml.workRows(html).single;
      expect(row.title, '实验报告');
      expect(row.status, '待批阅');
    });

    test('过期图标标记为 expired', () {
      const html =
          '<li data="/work/task?workId=9" aria-label="过期作业 ; 已完成">'
          '<i class="icon-zy-g"></i>'
          '</li>';
      expect(ChaoxingHtml.workRows(html).single.expired, isTrue);
    });

    test('没有 li[data] 时返回空', () {
      expect(ChaoxingHtml.workRows('<ul><li>暂无作业</li></ul>'), isEmpty);
    });
  });

  group('ChaoxingHtml.courseRows', () {
    test('同一门课的两个入口只留一条', () {
      const html =
          '<ul>'
          '<li courseId="267465996" clazzId="155660593" personId="497874758">'
          '<span class="course-name">人体解剖学实验</span>'
          '<p class="line2" title="王艳"></p></li>'
          '<li courseId="267465996" clazzId="155660593" personId="497874758">'
          '<span class="course-name">人体解剖学实验</span>'
          '<p class="line2" title="王艳"></p></li>'
          '</ul>';
      final rows = ChaoxingHtml.courseRows(html);
      expect(rows, hasLength(1));
      expect(rows.single.courseId, '267465996');
      expect(rows.single.classId, '155660593');
      expect(rows.single.cpi, '497874758');
      expect(rows.single.name, '人体解剖学实验');
      expect(rows.single.teacher, '王艳');
    });

    test('兼容 stucoursemiddle 链接形态', () {
      const html =
          '<a href="http://mooc1.chaoxing.com/visit/stucoursemiddle'
          '?courseid=111&amp;clazzid=222&amp;cpi=333" title="大学物理"></a>';
      final row = ChaoxingHtml.courseRows(html).single;
      expect(row.courseId, '111');
      expect(row.classId, '222');
      expect(row.cpi, '333');
      expect(row.name, '大学物理');
    });

    test('实体与空白折叠', () {
      const html =
          '<li courseId="1" clazzId="2" personId="3">'
          '<span class="course-name">  数据&amp;结构  </span>'
          '</li>';
      expect(ChaoxingHtml.courseRows(html).single.name, '数据&结构');
    });
  });

  group('ChaoxingClient.parseWorkListHtml 走 DOM', () {
    const course = ChaoxingCourse(
      courseId: '1',
      classId: '2',
      cpi: '3',
      name: '人体解剖学实验',
    );

    test('移动端模板（无 goTask）也能解析', () {
      const html =
          '<li data="http://mooc1.chaoxing.com/mooc-ans/mooc2/work/task'
          '?courseId=1&amp;classId=2&amp;workId=57616202&amp;answerId=0&amp;enc=e"'
          ' aria-label="消化系统 ; 未交">'
          '<div class="time notOver">截止：2026-11-20 23:59</div>'
          '</li>';
      final works = ChaoxingClient.parseWorkListHtml(html, course);
      expect(works, hasLength(1));
      expect(works.single.workId, '57616202');
      expect(works.single.title, '消化系统');
      expect(works.single.statusText, '未交');
      expect(works.single.taskUrl, isNot(contains('&amp;')));
      expect(works.single.deadlineAt, isNotNull);
    });

    test('老模板（goTask）仍走正则兜底', () {
      const html =
          '<li onclick="goTask(this);" data="/work/task?workId=42" '
          'aria-label="老作业 ; 未交">'
          '<p class="overHidden2 fl">老作业</p>'
          '<p class="status fl">未交</p>'
          '</li>';
      final works = ChaoxingClient.parseWorkListHtml(html, course);
      expect(works.single.workId, '42');
      expect(works.single.title, '老作业');
    });
  });
}
