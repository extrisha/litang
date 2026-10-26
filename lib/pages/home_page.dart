import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/models.dart';
import '../data/notice_prefs.dart';
import '../data/notice_rank.dart';
import '../data/notice_source.dart';
import 'simple_web.dart';

/// 首页：AI 搜索框（搜索中心）+ 通知聚合流。数据来自可注入的 [NoticeSource]。
///
/// 通知不再按部门分块（那样 50 多个学院就是 50 个嵌套滚动区），
/// 改成一条按"分类权重 + 新鲜度 + 本院"排好序的扁平列表，顶部用筛选条收窄。
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.source = const DemoNoticeSource()});

  /// 通知数据源：默认演示数据，正式运行时由底部导航注入远端数据源。
  final NoticeSource source;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  NoticeFeed? _feed;
  Object? _error;
  bool _loading = true;

  List<Notice> _ranked = const <Notice>[];
  List<String> _kinds = const <String>[];

  /// 用户选的筛选学院（null = 全部学院）
  String? _selectedCollege;

  /// 教务里识别到的学院：只用来排序加分、以及在选择框里置顶
  String? _detectedCollege;

  String _kind = '全部';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (!force) setState(() => _loading = true);
    try {
      final feed = await widget.source.fetch(force: force);
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _error = null;
        _kinds = NoticeRanker.kindsIn(feed.notices);
        _loading = false;
      });
      _recompute();

      // 学院偏好单独读：存储偶尔会慢（甚至没有实现），不该把首屏卡在白屏上
      final depts = <String>{for (final n in feed.notices) n.dept};
      final detected = await NoticePrefs.detected(depts);
      final selected = await NoticePrefs.selected();
      if (!mounted) return;
      if (detected == _detectedCollege && selected == _selectedCollege) return;
      setState(() {
        _detectedCollege = detected;
        _selectedCollege = selected;
      });
      _recompute();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _recompute() {
    final feed = _feed;
    if (feed == null) return;
    _ranked = NoticeRanker.rank(
      feed.notices,
      college: _detectedCollege,
      filterCollege: _selectedCollege,
      kind: _kind,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _searchBar(context),
            if (_feed?.isOffline ?? false) _offlineBanner(),
            // 筛选条只要拿到数据就一直显示：之前它跟着列表一起消失，
            // 筛出空结果就再也点不回来了
            if (_feed != null) _filterBar(context),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_feed == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '通知加载失败',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _load(force: true),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  '$_error',
                  maxLines: 3,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    if (_ranked.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selectedCollege != null
                  ? '$_selectedCollege 暂时没有「$_kind」'
                  : '暂时没有「$_kind」的通知',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _kind = '全部';
                  _selectedCollege = null;
                });
                _recompute();
              },
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('清除筛选'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.usstRed,
      onRefresh: () => _load(force: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: _ranked.length,
        itemBuilder: (context, i) => _noticeRow(_ranked[i]),
      ),
    );
  }

  // ---------------------------------------------------------------- 顶部

  Widget _searchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: GestureDetector(
        onTap: () => _openSearchCenter(context),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.usstRed, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '问点什么，比如“寒假哪天才开始”',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
              Icon(Icons.search, color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _offlineBanner() {
    final feed = _feed!;
    final at = feed.fetchedAt;
    final when = at == null
        ? ''
        : '（数据 ${at.month}-${at.day}）';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '当前是离线数据$when，下拉可重试',
        style: const TextStyle(fontSize: 11.5, color: Color(0xFF9A6A1F)),
      ),
    );
  }

  Widget _filterBar(BuildContext context) {
    final chips = <String>['全部', ..._kinds];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: <Widget>[
          _collegeChip(context),
          const SizedBox(width: 6),
          for (final k in chips)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _chip(
                label: k,
                selected: _kind == k,
                onTap: () {
                  setState(() => _kind = k);
                  _recompute();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.usstRed : Colors.white,
          borderRadius: BorderRadius.circular(16),
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

  /// 「学院」按钮：点开就是筛选框，选中的学院直接当筛选条件。
  Widget _collegeChip(BuildContext context) {
    final label = _selectedCollege ?? '学院';
    final active = _selectedCollege != null;
    return GestureDetector(
      onTap: _pickCollege,
      child: Container(
        alignment: Alignment.center,
        constraints: const BoxConstraints(maxWidth: 168),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.usstRed : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? AppColors.usstRed : const Color(0xFFE5E5E5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.school_outlined,
              size: 13,
              color: active ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more,
              size: 13,
              color: active ? Colors.white : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  /// 学院筛选框：教务识别到的放最上面，选「全部学院」就清掉筛选。
  Future<void> _pickCollege() async {
    final feed = _feed;
    if (feed == null) return;

    final depts = <String>{
      for (final n in feed.notices)
        if (n.kind != '新闻' && n.kind != '党群') n.dept,
    }.toList()..sort();
    final detected = _detectedCollege;
    final others = depts.where((d) => d != detected).toList();

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, controller) => ListView(
          controller: controller,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text(
                '按学院筛选',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                detected == null
                    ? '登录过教务后，会自动把你的学院放在最上面'
                    : '已从教务识别到你的学院，放在最上面了',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            _collegeTile(
              ctx: ctx,
              name: '全部学院',
              value: '',
              subtitle: '不筛选，本院的通知依然排在前面',
              selected: _selectedCollege == null,
            ),
            if (detected != null)
              _collegeTile(
                ctx: ctx,
                name: detected,
                value: detected,
                subtitle: '来自教务',
                selected: _selectedCollege == detected,
                leadingIcon: Icons.school,
              ),
            for (final d in others)
              _collegeTile(
                ctx: ctx,
                name: d,
                value: d,
                selected: _selectedCollege == d,
              ),
          ],
        ),
      ),
    );

    if (picked == null || !mounted) return;
    final value = picked.isEmpty ? null : picked;
    await NoticePrefs.setSelected(value);
    if (!mounted) return;
    setState(() => _selectedCollege = value);
    _recompute();
  }

  Widget _collegeTile({
    required BuildContext ctx,
    required String name,
    required String value,
    required bool selected,
    String? subtitle,
    IconData? leadingIcon,
  }) {
    return ListTile(
      dense: true,
      leading: leadingIcon == null ? null : Icon(leadingIcon, size: 20),
      title: Text(name, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 11)),
      trailing: selected
          ? const Icon(Icons.check, size: 18, color: AppColors.usstRed)
          : null,
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  void _openSearchCenter(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '搜索中心',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'AI 智能问答 · 功能直达 · 历史通知检索',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            SizedBox(height: 16),
            Text(
              '（占位）接入 RAG 校园知识库后，可语义检索历史通知 / 校历 / 规章制度 / 培养计划，\n并支持自然语言直接问答。',
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 列表项

  static const Map<String, Color> _kindColors = <String, Color>{
    '竞赛': Color(0xFFE53935),
    '教学': Color(0xFF1E88E5),
    '通知': Color(0xFFF29D38),
    '讲座': Color(0xFF7E57C2),
    '学工': Color(0xFF26A69A),
    '就业': Color(0xFF43A047),
    '科研': Color(0xFF3949AB),
    '招生': Color(0xFF00ACC1),
    '新闻': Color(0xFF8D8D8D),
    '党群': Color(0xFF9E9E9E),
  };

  Future<void> _openNotice(Notice notice) async {
    final raw = notice.url;
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    final url = (uri != null && uri.hasScheme)
        ? raw
        : 'https://jwc.usst.edu.cn${raw.startsWith('/') ? '' : '/'}$raw';
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimpleWebPage(title: notice.title, url: url),
      ),
    );
  }

  Widget _noticeRow(Notice n) {
    final color = _kindColors[n.kind] ?? const Color(0xFF9E9E9E);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openNotice(n),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                margin: const EdgeInsets.only(top: 2, right: 10),
                width: 3,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            n.kind,
                            style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            n.dept,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      n.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: <Widget>[
                  Text(
                    n.timeLabel,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
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
}
