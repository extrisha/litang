import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'cache_store.dart';
import 'models.dart';

/// 通知数据源抽象。UI 面向这个接口，来源可插拔。
abstract class NoticeSource {
  /// [force] 为 true 时忽略本地缓存（下拉刷新用）。
  Future<NoticeFeed> fetch({bool force = false});
}

/// 一次抓取的结果（比裸 List 多带一点元信息，UI 可以显示"数据时间/离线"）。
class NoticeFeed {
  const NoticeFeed({
    required this.notices,
    this.fetchedAt,
    this.origin = NoticeOrigin.remote,
  });

  final List<Notice> notices;

  /// 服务端生成这份数据的时间（不是本地拉到的时间）。
  final DateTime? fetchedAt;

  final NoticeOrigin origin;

  bool get isOffline =>
      origin == NoticeOrigin.cache || origin == NoticeOrigin.demo;

  static const NoticeFeed empty = NoticeFeed(notices: <Notice>[]);
}

enum NoticeOrigin {
  /// 从远端镜像拉到的
  remote,

  /// 本地缓存（网络失败时的兜底）
  cache,

  /// 现抓官网（远端全挂了才走这条）
  live,

  /// 演示数据
  demo,
}

/// 演示数据源：答辩 / 离线 / 抓取失败时的兜底。
class DemoNoticeSource implements NoticeSource {
  const DemoNoticeSource();

  @override
  Future<NoticeFeed> fetch({bool force = false}) async => NoticeFeed(
    origin: NoticeOrigin.demo,
    notices: <Notice>[
      Notice(
        dept: '教务处',
        kind: '通知',
        title: '关于调整校园上下课铃声的通知',
        publishedAt: DateTime.now().subtract(const Duration(hours: 3)),
      ),
      Notice(
        dept: '基础学部',
        kind: '竞赛',
        title: '【统计建模】2026年（第十二届）全国大学生统计建模大赛校赛获奖名单公告',
        publishedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      Notice(
        dept: '教务处',
        kind: '教学',
        title: '关于 2026 上海市高等学校信息技术水平考试模拟考试的通知',
        publishedAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
    ],
  );
}

/// 远端数据源：读 CI 每天生成好的 `notices.json`。
///
/// 顺序：本地缓存（6 小时内直接用）→ Gitee → GitHub → gh-proxy 镜像 →
/// 过期缓存 → 现抓教务处列表页 → 演示数据。
///
/// 这样既不用每台设备去爬学校站点，也不会因为某一个源挂了就白屏。
class RemoteNoticeSource implements NoticeSource {
  RemoteNoticeSource({
    NoticeSource? fallback,
    this.cacheTtl = const Duration(hours: 6),
  }) : _fallback = fallback ?? const DemoNoticeSource();

  final NoticeSource _fallback;
  final Duration cacheTtl;

  static const String _cacheKey = 'notices_feed_v2';

  /// 三个镜像，任意一个能用就行。Gitee 在国内最快，GitHub 兜底。
  static const List<String> mirrors = <String>[
    'https://gitee.com/extrisha/lit-Calendar/raw/main/notices.json',
    'https://raw.githubusercontent.com/extrisha/litang/main/tools/notice-sync/out/notices.json',
    'https://gh-proxy.com/https://raw.githubusercontent.com/extrisha/litang/main/tools/notice-sync/out/notices.json',
  ];

  @override
  Future<NoticeFeed> fetch({bool force = false}) async {
    // force 只表示「跳过新鲜度检查，优先去拉新数据」，
    // 不能把缓存丢掉：离线时如果连缓存都没了，首页会退化成演示数据，
    // 再叠上学院/分类筛选就看起来像“没有任何通知”。
    final cached = await _readCache();
    if (!force && cached != null && cached.age < cacheTtl) {
      return cached.feed;
    }

    // 镜像可能各自停滞（GitHub 有新数据、Gitee 还停在几天前），
    // 所以「能解析」还不够，得是「够新」的才算数；都不新就用最新的那个。
    NoticeFeed? stale;
    final now = DateTime.now();
    for (final url in mirrors) {
      final feed = await _download(url);
      if (feed == null || feed.notices.isEmpty) continue;
      if (isFreshEnough(feed, now)) {
        await _writeCache(feed);
        return feed;
      }
      if (stale == null || _newer(feed, stale)) stale = feed;
    }
    if (stale != null) {
      await _writeCache(stale);
      return stale;
    }

    // 网络失败：过期缓存也比没有强
    if (cached != null) {
      return NoticeFeed(
        notices: cached.feed.notices,
        fetchedAt: cached.feed.fetchedAt,
        origin: NoticeOrigin.cache,
      );
    }

    // 再退一步：现抓教务处（列表页很小，几 KB）
    final live = await _liveFallback();
    if (live != null && live.notices.isNotEmpty) return live;

    return _fallback.fetch();
  }

  /// 云端数据超过这个天数就算「镜像停滞」，继续试下一个镜像。
  static const Duration maxStaleness = Duration(days: 3);

  /// 云端给的 `updatedAt` 够不够新；没有 `updatedAt` 就当作可用。
  static bool isFreshEnough(NoticeFeed feed, DateTime now) {
    final at = feed.fetchedAt;
    if (at == null) return true;
    return now.difference(at) <= maxStaleness;
  }

  static bool _newer(NoticeFeed a, NoticeFeed b) {
    final x = a.fetchedAt;
    final y = b.fetchedAt;
    if (x == null) return false;
    if (y == null) return true;
    return x.isAfter(y);
  }

  Future<NoticeFeed?> _download(String url) async {
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      // 云端 feed 有 1.2 MB / 7000+ 条，jsonDecode + 建模放主线会卡掉首帧，
      // 扔到后台 isolate 做（Web 上 compute 会退化成同步执行）。
      return await compute(parseFeed, utf8.decode(res.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  Future<NoticeFeed?> _liveFallback() async {
    try {
      return await JwcNoticeSource().fetch();
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- 解析

  /// 解析 `notices.json`。兼容 v1（带 `id`/`category` 的旧格式）。
  static NoticeFeed? parseFeed(String raw) {
    try {
      final decoded = jsonDecode(raw);
      final Map<String, dynamic> map;
      if (decoded is List) {
        map = <String, dynamic>{'notices': decoded};
      } else if (decoded is Map<String, dynamic>) {
        map = decoded;
      } else {
        return null;
      }
      final list = map['notices'];
      if (list is! List) return null;

      final notices = <Notice>[];
      for (final item in list) {
        if (item is! Map) continue;
        final title = (item['title'] as String?)?.trim() ?? '';
        final dept = (item['dept'] as String?)?.trim() ?? '';
        if (title.isEmpty || dept.isEmpty) continue;
        notices.add(
          Notice(
            dept: dept,
            title: title,
            kind:
                (item['kind'] as String?) ??
                (item['category'] as String?) ??
                '通知',
            scope: (item['scope'] as String?) ?? 'school',
            publishedAt: Notice.parseDate(item['date']),
            url: (item['url'] as String?)?.trim(),
          ),
        );
      }
      if (notices.isEmpty) return null;
      return NoticeFeed(
        notices: notices,
        fetchedAt: DateTime.tryParse((map['updatedAt'] as String?) ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- 缓存

  Future<_CachedFeed?> _readCache() async {
    // 缓存可能是几 MB 的 JSON，解析同样放到后台 isolate。
    final raw = await CacheStore.readRaw(_cacheKey);
    if (raw == null) return null;
    final (feed, savedAt) = await compute(_parseCachedFeed, raw);
    if (feed == null || savedAt == null) return null;
    return _CachedFeed(feed, DateTime.now().difference(savedAt));
  }

  Future<void> _writeCache(NoticeFeed feed) async {
    await CacheStore.write(_cacheKey, <String, dynamic>{
      'fetchedAt': feed.fetchedAt?.toIso8601String(),
      'notices': <Map<String, dynamic>>[
        for (final n in feed.notices)
          <String, dynamic>{
            'dept': n.dept,
            'kind': n.kind,
            'scope': n.scope,
            'title': n.title,
            'url': n.url,
            'date': n.publishedAt?.toIso8601String().substring(0, 10),
          },
      ],
    });
  }

  static NoticeFeed? _feedFromCache(Object? data) {
    if (data is! Map) return null;
    final list = data['notices'];
    if (list is! List) return null;
    final notices = <Notice>[];
    for (final item in list) {
      if (item is! Map) continue;
      final title = item['title'] as String?;
      final dept = item['dept'] as String?;
      if (title == null || dept == null) continue;
      notices.add(
        Notice(
          dept: dept,
          title: title,
          kind: item['kind'] as String? ?? '通知',
          scope: item['scope'] as String? ?? 'school',
          publishedAt: Notice.parseDate(item['date']),
          url: item['url'] as String?,
        ),
      );
    }
    if (notices.isEmpty) return null;
    return NoticeFeed(
      notices: notices,
      fetchedAt: DateTime.tryParse(data['fetchedAt'] as String? ?? ''),
      origin: NoticeOrigin.cache,
    );
  }
}

/// 顶级函数：供 `compute()` 在后台 isolate 里解析缓存，
/// 因此不能是实例方法（跨 isolate 不能带着 this）。
(NoticeFeed?, DateTime?) _parseCachedFeed(String raw) {
  final entry = CacheStore.decode(raw);
  if (entry == null) return (null, null);
  return (RemoteNoticeSource._feedFromCache(entry.data), entry.savedAt);
}

/// 缓存 + 它的年龄（用来判断要不要联网刷新）。
class _CachedFeed {
  const _CachedFeed(this.feed, this.age);

  final NoticeFeed feed;
  final Duration age;
}

/// 官网现抓数据源：远端全部失败时兜底抓教务处公开列表页（无需登录）。
class JwcNoticeSource implements NoticeSource {
  JwcNoticeSource([this._fallback = const DemoNoticeSource()]);

  final NoticeSource _fallback;

  static const Map<String, String> _listUrls = <String, String>{
    '教务处': 'https://jwc.usst.edu.cn/10239/list.htm',
    '通知公告': 'https://jwc.usst.edu.cn/zygg/list.htm',
  };

  @override
  Future<NoticeFeed> fetch({bool force = false}) async {
    final result = <Notice>[];
    for (final entry in _listUrls.entries) {
      try {
        final res = await http
            .get(Uri.parse(entry.value))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final parsed = _parse(
            utf8.decode(res.bodyBytes),
            entry.key,
            entry.value,
          );
          result.addAll(parsed.take(8));
        }
      } catch (_) {
        // 忽略单条失败，继续下一个源
      }
    }
    if (result.isEmpty) return _fallback.fetch();
    return NoticeFeed(
      notices: result.take(30).toList(),
      origin: NoticeOrigin.live,
    );
  }

  /// 解析 wisedu(webplus) 列表页：
  /// <li class="news n1 clearfix">
  ///   <span class="news_title"><a href='...' title='标题'>标题</a></span>
  ///   <span class="news_meta">2026-10-22</span>
  /// </li>
  List<Notice> _parse(String html, String dept, String baseUrl) {
    final items = <Notice>[];
    final liRe = RegExp(r'<li class="news[^"]*">([\s\S]*?)</li>');
    final titleRe = RegExp(
      r'''title=['"]([^'"]+)['"]|<div class="news_title">([^<]+)</div>|<span class="news_title">([^<]+)</span>''',
    );
    final dateRe = RegExp(
      r'<span class="news_meta">([^<]*)</span>|(\d{4}-\d{2}-\d{2})',
    );
    final hrefRe = RegExp(r'''href=['"]([^'"]+)['"]''');
    final base = Uri.parse(baseUrl);

    for (final m in liRe.allMatches(html)) {
      final block = m.group(1) ?? '';
      final tm = titleRe.firstMatch(block);
      final title = (tm?.group(1) ?? tm?.group(2) ?? tm?.group(3) ?? '').trim();
      if (title.isEmpty) continue;
      final date =
          (dateRe.firstMatch(block)?.group(1) ??
                  dateRe.firstMatch(block)?.group(2) ??
                  '')
              .trim();
      final href = hrefRe.firstMatch(block)?.group(1);
      String? url;
      if (href != null && href.isNotEmpty) {
        url = base.resolve(href).toString();
      }
      items.add(
        Notice(
          dept: dept,
          title: title,
          publishedAt: Notice.parseDate(date),
          url: url,
        ),
      );
    }
    return items;
  }
}
