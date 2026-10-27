import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/cache_store.dart';
import 'package:project_usst/data/models.dart';
import 'package:project_usst/data/notice_prefs.dart';
import 'package:project_usst/data/notice_rank.dart';
import 'package:project_usst/data/notice_source.dart';

void main() {
  group('RemoteNoticeSource.parseFeed', () {
    test('解析 v2 数据（kind / scope / date）', () {
      final raw = jsonEncode({
        'schemaVersion': 2,
        'updatedAt': '2026-10-25T12:41:14.063Z',
        'total': 2,
        'notices': [
          {
            'dept': '基础学部',
            'kind': '竞赛',
            'scope': 'college',
            'title': '【统计建模】2026年（第十二届）全国大学生统计建模大赛校赛获奖名单公告',
            'url': 'https://jcxb.usst.edu.cn/2026/0914/c18415a370397/page.htm',
            'date': '2026-09-14',
          },
          {
            'dept': '教务处',
            'kind': '教学',
            'scope': 'school',
            'title': '关于2026年国庆节放假期间教学安排的通知',
            'url': 'https://jwc.usst.edu.cn/2026/0914/c10239a370432/page.htm',
            'date': '2026-09-14',
          },
        ],
      });

      final feed = RemoteNoticeSource.parseFeed(raw)!;
      expect(feed.notices.length, 2);
      expect(feed.fetchedAt, DateTime.parse('2026-10-25T12:41:14.063Z'));

      final first = feed.notices.first;
      expect(first.kind, '竞赛');
      expect(first.scope, 'college');
      expect(first.dept, '基础学部');
      expect(first.publishedAt, DateTime(2026, 9, 14));
      expect(first.dateText, '2026-09-14');
    });

    test('兼容 v1 旧格式（只有 category、没有 kind）', () {
      final raw = jsonEncode({
        'schemaVersion': 1,
        'notices': [
          {
            'id': 'jwc:https://x/1',
            'dept': '教务处',
            'category': '通知公告',
            'scope': 'school',
            'title': '关于调整上下课铃声的通知',
            'url': 'https://x/1',
            'date': '2026-10-20',
          },
        ],
      });
      final feed = RemoteNoticeSource.parseFeed(raw)!;
      expect(feed.notices.single.kind, '通知公告');
      expect(feed.notices.single.publishedAt, DateTime(2026, 10, 20));
    });

    test('脏数据返回 null，不抛异常', () {
      expect(RemoteNoticeSource.parseFeed('not json'), isNull);
      expect(RemoteNoticeSource.parseFeed('{}'), isNull);
      expect(RemoteNoticeSource.parseFeed('[]'), isNull);
    });

    test('缺 title 或 dept 的条目被跳过', () {
      final raw = jsonEncode({
        'notices': [
          {'dept': '教务处', 'title': '', 'url': 'https://x/1'},
          {'title': '有标题没部门', 'url': 'https://x/2'},
          {'dept': '教务处', 'title': '正常的一条通知', 'url': 'https://x/3'},
        ],
      });
      final feed = RemoteNoticeSource.parseFeed(raw)!;
      expect(feed.notices.length, 1);
      expect(feed.notices.single.title, '正常的一条通知');
    });
  });

  group('Notice', () {
    test('timeLabel 用相对时间，超过一周用日期', () {
      final now = DateTime.now();
      expect(Notice(dept: 'd', title: 't', publishedAt: now).timeLabel, '今天');
      expect(
        Notice(
          dept: 'd',
          title: 't',
          publishedAt: now.subtract(const Duration(days: 1)),
        ).timeLabel,
        '昨天',
      );
      expect(
        Notice(
          dept: 'd',
          title: 't',
          publishedAt: now.subtract(const Duration(days: 3)),
        ).timeLabel,
        '3 天前',
      );
      expect(Notice(dept: 'd', title: 't').timeLabel, '');
    });
  });

  group('NoticeRanker', () {
    final now = DateTime(2026, 10, 25);

    Notice n(
      String title,
      String kind,
      int daysAgo, {
      String dept = '教务处',
      String scope = 'school',
    }) {
      return Notice(
        dept: dept,
        title: title,
        kind: kind,
        scope: scope,
        publishedAt: now.subtract(Duration(days: daysAgo)),
      );
    }

    test('同一天里竞赛 > 通知 > 新闻', () {
      final list = [n('新闻一条', '新闻', 0), n('通知一条', '通知', 0), n('竞赛一条', '竞赛', 0)];
      final ranked = NoticeRanker.rank(list, now: now);
      expect(ranked.map((e) => e.kind).toList(), ['竞赛', '通知']);
    });

    test('新鲜的通知压过一周前的竞赛', () {
      final list = [n('七天前的竞赛', '竞赛', 7), n('今天的通知', '通知', 0)];
      final ranked = NoticeRanker.rank(list, now: now);
      expect(ranked.first.title, '今天的通知');
    });

    test('本院加成分只有在设置学院后才生效', () {
      final list = [
        n('本院通知', '通知', 0, dept: '光电信息与计算机工程学院', scope: 'college'),
        n('外院通知', '通知', 0, dept: '外语学院', scope: 'college'),
      ];
      // 同为学院级通知、同一天，没设学院时按分数+标题兜底排序，本院不会自动靠前
      final without = NoticeRanker.rank(list, now: now);
      expect(without.length, 2);

      final withCollege = NoticeRanker.rank(
        list,
        college: '光电信息与计算机工程学院',
        now: now,
      );
      expect(withCollege.first.title, '本院通知');
    });

    test('filterCollege 只留指定学院', () {
      final list = [
        n('本院通知', '通知', 0, dept: '管理学院'),
        n('外院通知', '通知', 0, dept: '外语学院'),
      ];
      final ranked = NoticeRanker.rank(list, filterCollege: '管理学院', now: now);
      expect(ranked.map((e) => e.dept).toSet(), {'管理学院'});
    });

    test('按分类筛选', () {
      final list = [n('竞赛', '竞赛', 0), n('讲座', '讲座', 0), n('通知', '通知', 0)];
      expect(NoticeRanker.rank(list, kind: '讲座', now: now).single.kind, '讲座');
      // 「新闻」筛选项把党群也算进来
      expect(
        NoticeRanker.rank(
          [n('新闻', '新闻', 0), n('党建', '党群', 0)],
          kind: '新闻',
          now: now,
        ).length,
        2,
      );
    });

    test('没有日期的排后面', () {
      final list = [
        Notice(dept: '教务处', title: '没有日期', kind: '通知'),
        n('一个月前', '通知', 30),
      ];
      final ranked = NoticeRanker.rank(list, now: now);
      expect(ranked.first.title, '一个月前');
    });

    test('kindsIn 按权重顺序返回数据里出现过的分类', () {
      final kinds = NoticeRanker.kindsIn([
        n('a', '新闻', 0),
        n('b', '竞赛', 0),
        n('c', '通知', 0),
      ]);
      expect(kinds, ['竞赛', '通知', '新闻']);
    });
  });

  group('镜像新鲜度', () {
    NoticeFeed feed(DateTime? at) => NoticeFeed(
      notices: [
        Notice(dept: '教务处', title: '通知', publishedAt: DateTime(2026, 10, 25)),
      ],
      fetchedAt: at,
    );
    final now = DateTime(2026, 10, 25, 12);

    test('三天内算新，超过三天算停滞（继续试下一个镜像）', () {
      expect(
        RemoteNoticeSource.isFreshEnough(
          feed(now.subtract(const Duration(hours: 2))),
          now,
        ),
        isTrue,
      );
      expect(
        RemoteNoticeSource.isFreshEnough(
          feed(now.subtract(const Duration(days: 4))),
          now,
        ),
        isFalse,
      );
    });

    test('没有 updatedAt 时当作可用，不至于整条链路失败', () {
      expect(RemoteNoticeSource.isFreshEnough(feed(null), now), isTrue);
    });
  });

  group('本院识别', () {
    const depts = <String>['基础学部', '出版学院', '健康科学与工程学院', '光电信息与计算机工程学院', '外语学院'];

    test('教务写的就是站点名时直接对上', () {
      expect(NoticePrefs.matchCollege('健康科学与工程学院', depts), '健康科学与工程学院');
      expect(NoticePrefs.matchCollege(' 外语学院 ', depts), '外语学院');
    });

    test('教务用的旧名靠开头两个字兜底（出版印刷与艺术设计学院 → 出版学院）', () {
      expect(NoticePrefs.matchCollege('出版印刷与艺术设计学院', depts), '出版学院');
    });

    test('对不上或撞车时返回 null，不乱认', () {
      expect(NoticePrefs.matchCollege('机械工程学院', depts), isNull);
      expect(NoticePrefs.matchCollege('', depts), isNull);
      // 「学院」两个字开头太泛，多个候选并列时应放弃
      expect(NoticePrefs.matchCollege('学院路校区', const ['学院甲', '学院乙']), isNull);
    });
  });

  group('真实产物', () {
    // 直接拿 tools/notice-sync/out/notices.json 跑一遍：
    // 解析器 + 排序在 7000+ 条真实数据上不炸，而且结果看得懂。
    final file = File('tools/notice-sync/out/notices.json');
    if (!file.existsSync()) {
      test(
        '跳过：本地没有 notices.json',
        () {},
        skip: '先跑 node tools/notice-sync/fetch.mjs',
      );
      return;
    }

    test('线上产物能解析、能排序', () {
      final feed = RemoteNoticeSource.parseFeed(file.readAsStringSync())!;
      expect(feed.notices.length, greaterThan(1000));

      final ranked = NoticeRanker.rank(feed.notices);
      expect(ranked.length, greaterThan(100));
      // 默认列表里不该出现新闻/党群
      expect(
        ranked.any((n) => NoticeRanker.offFeedKinds.contains(n.kind)),
        isFalse,
      );
      // 排在最前面的必须是最近一周内的
      final recent = DateTime.now().subtract(const Duration(days: 8));
      expect(ranked.first.publishedAt!.isAfter(recent), isTrue);
      // 竞赛类必须存在（这次补漏的核心）
      expect(ranked.where((n) => n.kind == '竞赛').length, greaterThan(20));
      expect(ranked.firstWhere((n) => n.title.contains('统计建模')).kind, '竞赛');
    });
  });

  group('离线刷新', () {
    test('force 刷新失败时保留缓存，不退化成演示数据', () async {
      final dir = await Directory.systemTemp.createTemp('litang_notice_');
      final oldDirOverride = CacheStore.directoryOverride;
      final oldHttpOverrides = HttpOverrides.current;
      CacheStore.directoryOverride = () async => dir;
      CacheStore.clearMemory();
      addTearDown(() async {
        HttpOverrides.global = oldHttpOverrides;
        CacheStore.directoryOverride = oldDirOverride;
        CacheStore.clearMemory();
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      await CacheStore.write('notices_feed_v2', <String, dynamic>{
        'fetchedAt': '2026-10-25T23:44:38.470Z',
        'notices': <Map<String, dynamic>>[
          <String, dynamic>{
            'dept': '教务处',
            'kind': '通知',
            'scope': 'school',
            'title': '缓存里的通知',
            'url': 'https://jwc.usst.edu.cn/cached.htm',
            'date': '2026-10-25',
          },
        ],
      });

      // 模拟完全离线：任何 HTTP 请求都直接失败。
      HttpOverrides.global = _OfflineHttpOverrides();
      final feed = await RemoteNoticeSource().fetch(force: true);

      expect(feed.origin, NoticeOrigin.cache);
      expect(feed.notices.single.title, '缓存里的通知');
    });
  });
}

class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw const SocketException('offline');
  }
}
