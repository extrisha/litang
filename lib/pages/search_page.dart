import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/models.dart';
import '../data/notice_search.dart';
import '../data/notice_source.dart';
import 'simple_web.dart';

/// 通知搜索页。
///
/// 只搜“已经抓下来的通知”，不做功能页跳转：
/// 用户输入关键词，下面直接给匹配的通知列表。
class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.source,
    this.initialNotices,
    this.initialFetchedAt,
    this.detectedCollege,
  });

  /// 首页已经拉过数据时直接传进来，没传就自己拉一次（会命中缓存）。
  final NoticeSource source;
  final List<Notice>? initialNotices;

  /// 这份数据是什么时候生成的（来自 notices.json 的 updatedAt）。
  final DateTime? initialFetchedAt;
  final String? detectedCollege;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const List<String> _hotSearches = <String>[
    '寒假',
    '选课',
    '四六级',
    '奖学金',
    '补考',
    '校历',
    '转专业',
    '推免',
    '期末考试',
    '讲座',
  ];

  static final List<String> _recentSearches = <String>[];

  static const List<String> _kindOrder = <String>[
    '竞赛',
    '教学',
    '通知',
    '讲座',
    '学工',
    '就业',
    '科研',
    '招生',
    '新闻',
  ];

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  NoticeSearchIndex? _index;
  List<Notice> _notices = const <Notice>[];
  List<SearchHit> _hits = const <SearchHit>[];
  String _query = '';
  String _kind = '全部';
  bool _loading = true;
  String? _error;
  DateTime? _fetchedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final initial = widget.initialNotices;
    if (initial != null && initial.isNotEmpty) {
      // 先让搜索页把骨架画出来，再建索引，避免首帧卡一下。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _buildIndex(initial, widget.initialFetchedAt);
        }
      });
      return;
    }
    try {
      final feed = await widget.source.fetch();
      if (!mounted) {
        return;
      }
      _buildIndex(feed.notices, feed.fetchedAt);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _buildIndex(List<Notice> notices, DateTime? fetchedAt) {
    final index = NoticeSearchIndex.build(notices);
    if (!mounted) {
      return;
    }
    setState(() {
      _notices = notices;
      _index = index;
      _fetchedAt = fetchedAt;
      _loading = false;
      _error = null;
    });
    if (_query.trim().isNotEmpty) {
      _runSearch(_query);
    }
  }

  void _onChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) {
        return;
      }
      _runSearch(value);
    });
  }

  void _submit(String value) {
    _debounce?.cancel();
    _runSearch(value, remember: true);
  }

  void _runSearch(String value, {bool remember = false}) {
    final index = _index;
    final query = value.trim();
    if (index == null) {
      return;
    }
    if (query.isEmpty) {
      setState(() {
        _hits = const <SearchHit>[];
      });
      return;
    }
    final hits = index.search(
      query,
      filter: SearchFilter(kind: _kind == '全部' ? null : _kind),
      college: widget.detectedCollege,
      limit: 60,
    );
    if (remember) {
      _remember(query);
    }
    setState(() {
      _hits = hits;
      _query = value;
    });
  }

  void _searchFor(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _debounce?.cancel();
    _runSearch(query, remember: true);
  }

  void _remember(String query) {
    if (query.isEmpty) {
      return;
    }
    _recentSearches.remove(query);
    _recentSearches.insert(0, query);
    if (_recentSearches.length > 8) {
      _recentSearches.removeLast();
    }
  }

  String _urlFor(Notice notice) {
    final raw = notice.url;
    if (raw == null || raw.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) {
      return raw;
    }
    return 'https://jwc.usst.edu.cn${raw.startsWith('/') ? '' : '/'}$raw';
  }

  Future<void> _openNotice(Notice notice) async {
    final url = _urlFor(notice);
    if (url.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('这条通知没有原文链接')));
      return;
    }
    _remember(_query);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimpleWebPage(title: notice.title, url: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _searchBar(),
            if (!_loading && _error == null && _index != null) _filterBar(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: '返回',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, size: 22),
          ),
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.search,
                    size: 19,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: _onChanged,
                      onSubmitted: _submit,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: '搜通知、公告，比如“寒假安排”',
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _controller.clear();
                        _onChanged('');
                      },
                      child: const Icon(
                        Icons.cancel,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    final present = <String>{for (final notice in _notices) notice.kind};
    final kinds = <String>[
      for (final kind in _kindOrder)
        if (present.contains(kind)) kind,
      for (final kind in present)
        if (!_kindOrder.contains(kind)) kind,
    ];
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: <Widget>[
          _kindChip('全部'),
          for (final kind in kinds) ...<Widget>[
            const SizedBox(width: 6),
            _kindChip(kind),
          ],
        ],
      ),
    );
  }

  Widget _kindChip(String label) {
    final selected = _kind == label;
    return GestureDetector(
      onTap: () {
        if (_kind == label) {
          return;
        }
        setState(() => _kind = label);
        _runSearch(_query);
      },
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: selected ? AppColors.usstRed : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? AppColors.usstRed : const Color(0xFFE5E5E5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              '通知还没加载出来',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _load();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_query.trim().isEmpty) {
      return _discover();
    }
    if (_hits.isEmpty) {
      return _emptyResult();
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _hits.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
            child: Text(
              '找到 ${_hits.length} 条通知',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          );
        }
        return _hitTile(_hits[index - 1]);
      },
    );
  }

  Widget _discover() {
    final at = _fetchedAt;
    final dataLabel = at == null ? '' : '（数据 ${at.month}-${at.day}）';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        _sectionTitle('热门搜索'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[for (final word in _hotSearches) _wordChip(word)],
        ),
        if (_recentSearches.isNotEmpty) ...<Widget>[
          const SizedBox(height: 24),
          _sectionTitle('最近搜索'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final word in _recentSearches) _wordChip(word),
            ],
          ),
        ],
        const SizedBox(height: 28),
        Text(
          '共 ${_notices.length} 条通知$dataLabel，支持搜标题、部门和分类。',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _emptyResult() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
      children: <Widget>[
        const Icon(Icons.search_off, size: 48, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        const Text(
          '没有找到相关通知',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          '换个关键词试试',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final word in _hotSearches.take(6)) _wordChip(word),
          ],
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    );
  }

  Widget _wordChip(String text) {
    return GestureDetector(
      onTap: () => _searchFor(text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E5E5)),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _hitTile(SearchHit hit) {
    final notice = hit.notice;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openNotice(notice),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _highlightedTitle(hit),
              const SizedBox(height: 7),
              Row(
                children: <Widget>[
                  _kindBadge(notice.kind),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${notice.dept} · ${notice.timeLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _highlightedTitle(SearchHit hit) {
    final title = hit.notice.title;
    final terms = hit.terms.where((term) => term.length >= 2).toList();
    if (terms.isEmpty) {
      return Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      );
    }

    final pattern = RegExp(
      terms.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in pattern.allMatches(title)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: title.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: title.substring(match.start, match.end),
          style: const TextStyle(
            color: AppColors.usstRed,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < title.length) {
      spans.add(TextSpan(text: title.substring(cursor)));
    }
    if (spans.isEmpty) {
      return Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      );
    }

    return Text.rich(
      TextSpan(
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: AppColors.textPrimary,
        ),
        children: spans,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _kindBadge(String kind) {
    const colors = <String, Color>{
      '竞赛': Color(0xFFE53935),
      '教学': Color(0xFF1E88E5),
      '通知': Color(0xFFF29D38),
      '讲座': Color(0xFF7E57C2),
      '学工': Color(0xFF26A69A),
      '就业': Color(0xFF43A047),
      '科研': Color(0xFF3949AB),
      '招生': Color(0xFF00ACC1),
      '新闻': Color(0xFF8D8D8D),
    };
    final color = colors[kind] ?? const Color(0xFF8D8D8D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(kind, style: TextStyle(fontSize: 10.5, color: color)),
    );
  }
}
