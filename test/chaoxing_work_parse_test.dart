import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/chaoxing/chaoxing_client.dart';

/// 作业列表 HTML 解析。
/// 结构取自 2026-10-28 真实页面（人体解剖学，14 条作业）。
void main() {
  const course = ChaoxingCourse(
    courseId: '267465995',
    classId: '155660588',
    cpi: '497874758',
    name: '人体解剖学',
    teacher: '王艳',
  );

  // 真实条目：aria-label 里是「作业名 ; 状态」
  const modern = '''
<ul class="bottomList">
  <li onclick="goTask(this);" data="https://mooc1.chaoxing.com/mooc-ans/mooc2/work/task?courseId=267465995&amp;classId=155660588&amp;cpi=497874758&amp;workId=57616202&amp;answerId=0&amp;enc=8747a1f3" onkeydown="if(event.keyCode == 13){goTask(this);}" tabindex="0" aria-label="消化系统 ; 未交" role="link">
    <div class="tag work-icon icon-zy"></div>
    <div class="right-content">
      <p class="overHidden2 fl">消化系统</p>
      <p class="status fl">未交</p>
    </div>
    <div class="time notOver" tabindex="0">截止：2026-11-01 23:59</div>
  </li>
</ul>''';

  // 老格式：没有 aria-label，只能靠 class 匹配
  const legacy = '''
<li onclick="goTask(this);" data="https://mooc1.chaoxing.com/mooc-ans/mooc2/work/task?courseId=1&classId=2&workId=999&answerId=0&enc=abc">
  <p class="overHidden2 fl">心血管系统</p>
  <p class="status fl">已交</p>
  <div class="time icon-zy-g">已截止</div>
</li>''';

  test('优先用 aria-label 解析标题和状态', () {
    final works = ChaoxingClient.parseWorkListHtml(modern, course);
    expect(works.length, 1);
    final w = works.single;
    expect(w.workId, '57616202');
    expect(w.title, '消化系统');
    expect(w.statusText, '未交');
    expect(w.courseName, '人体解剖学');
    // &amp; 必须还原，否则 taskUrl 请求会带上实体
    expect(w.taskUrl, contains('&classId=155660588'));
    expect(w.taskUrl, isNot(contains('&amp;')));
  });

  test('没有 aria-label 时退回 class 匹配（老页面）', () {
    final works = ChaoxingClient.parseWorkListHtml(legacy, course);
    expect(works.length, 1);
    final w = works.single;
    expect(w.title, '心血管系统');
    expect(w.statusText, '已交');
    expect(w.expired, isTrue); // body 里有 icon-zy-g
  });

  test('两种结构混在一起时都能解析', () {
    final works = ChaoxingClient.parseWorkListHtml(
      '$modern\n$legacy',
      course,
    );
    expect(works.length, 2);
    expect(works.map((w) => w.title), containsAll(<String>['消化系统', '心血管系统']));
  });

  test('没有 workId 的条目跳过，不抛异常', () {
    const broken = '<li onclick="goTask(this);" data="https://x/task?courseId=1"></li>';
    expect(ChaoxingClient.parseWorkListHtml(broken, course), isEmpty);
    expect(ChaoxingClient.parseWorkListHtml('', course), isEmpty);
    expect(ChaoxingClient.parseWorkListHtml('<html></html>', course), isEmpty);
  });
}
