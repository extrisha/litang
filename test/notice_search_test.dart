import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/models.dart';
import 'package:project_usst/data/notice_search.dart';

void main() {
  final notices = <Notice>[
    Notice(
      dept: '教务处',
      kind: '通知',
      title: '关于2026年寒假安排的通知',
      publishedAt: DateTime(2026, 1, 5),
      url: 'https://jwc.usst.edu.cn/a.htm',
    ),
    Notice(
      dept: '后勤管理处',
      kind: '通知',
      title: '关于2026年寒假期间后勤服务开放安排的通知',
      publishedAt: DateTime(2026, 1, 20),
      url: 'https://hq.usst.edu.cn/b.htm',
    ),
    Notice(
      dept: '研究生院',
      kind: '教学',
      title: '2026-2027学年校历',
      publishedAt: DateTime(2026, 6, 10),
      url: 'https://yjs.usst.edu.cn/c.htm',
    ),
    Notice(
      dept: '研究生院',
      kind: '通知',
      title: '关于2026年下半年全国大学英语四、六级等级考试报名的通知',
      publishedAt: DateTime(2026, 9, 10),
      url: 'https://yjs.usst.edu.cn/d.htm',
    ),
    Notice(
      dept: '基础学部',
      kind: '教学',
      title: '【本科教学】2026-2027-1学期初补考（缓考）监考安排',
      publishedAt: DateTime(2026, 9, 15),
      url: 'https://jcxb.usst.edu.cn/e.htm',
    ),
    Notice(
      dept: '后勤管理处',
      kind: '通知',
      title: '关于2026年暑假后勤服务开放安排的通知',
      publishedAt: DateTime(2026, 7, 13),
      url: 'https://hq.usst.edu.cn/f.htm',
    ),
    Notice(
      dept: '保卫部（处）',
      kind: '通知',
      title: '暑假安全倡议书',
      publishedAt: DateTime(2025, 7, 30),
      url: 'https://bwc.usst.edu.cn/g.htm',
    ),
    Notice(
      dept: '体育教学部',
      kind: '通知',
      title: '体测设备比选结果公告',
      publishedAt: DateTime(2026, 9, 15),
      url: 'https://tyb.usst.edu.cn/h.htm',
    ),
    Notice(
      dept: '信息化办公室',
      kind: '新闻',
      title: '智慧教室使用培训',
      publishedAt: DateTime(2026, 3, 9),
      url: 'https://net.usst.edu.cn/i.htm',
    ),
  ];

  final index = NoticeSearchIndex.build(notices);

  group('normalize / tokenize', () {
    test('去标点、全角转半角', () {
      expect(NoticeSearchIndex.normalize('关于２０２６年“四、六级”考试'), '关于2026年四六级考试');
    });

    test('中文 bigram + 短词整段', () {
      final tokens = NoticeSearchIndex.tokenize(
        NoticeSearchIndex.normalize('四、六级'),
      );
      expect(tokens, contains('四六级'));
      expect(tokens, contains('四六'));
      expect(tokens, contains('六级'));
    });
  });

  group('search', () {
    test('四六级能排到最前', () {
      final hits = index.search('四六级报名');
      expect(hits, isNotEmpty);
      expect(hits.first.notice.title, contains('四、六级'));
    });

    test('补考能匹配去括号后的标题', () {
      final hits = index.search('补考');
      expect(hits, isNotEmpty);
      expect(hits.first.notice.title, contains('补考'));
    });

    test('问句去掉“什么时候”后能命中寒假安排', () {
      final hits = index.search('寒假什么时候开始');
      expect(hits, isNotEmpty);
      expect(hits.first.notice.title, contains('寒假'));
      expect(hits.first.notice.title, contains('安排'));
    });

    test('暑假放假安排优先带“安排”的通知', () {
      final hits = index.search('暑假放假安排');
      expect(hits, isNotEmpty);
      expect(hits.first.notice.title, contains('暑假'));
      expect(hits.first.notice.title, contains('安排'));
    });

    test('空教室没有数据时返回空，不硬凑教室', () {
      expect(index.search('空教室'), isEmpty);
    });

    test('学生证没有数据时返回空', () {
      expect(index.search('学生证'), isEmpty);
    });

    test('分类过滤', () {
      final hits = index.search('校历', filter: const SearchFilter(kind: '教学'));
      expect(hits, isNotEmpty);
      expect(hits.every((hit) => hit.notice.kind == '教学'), isTrue);
    });

    test('空查询返回空', () {
      expect(index.search('   '), isEmpty);
    });
  });
}
