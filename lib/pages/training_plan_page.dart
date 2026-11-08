import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../data/jwc/training_plan_repository.dart';
import '../widgets/async_state.dart';
import 'pdf_preview_page.dart';
import 'simple_web_page.dart';

class TrainingPlanPage extends StatefulWidget {
  const TrainingPlanPage({super.key, this.major = '', this.repository});
  final String major;
  final TrainingPlanRepository? repository;
  @override
  State<TrainingPlanPage> createState() => _TrainingPlanPageState();
}

class _TrainingPlanPageState extends State<TrainingPlanPage> {
  late final TrainingPlanRepository _repository =
      widget.repository ?? TrainingPlanRepository();
  final _search = TextEditingController();
  List<TrainingPlan> _plans = [];
  bool _loading = true;
  late bool _onlyMajor = widget.major.trim().isNotEmpty;
  int? _cohort;
  String? _error;
  String? _opening;
  double? _downloadProgress;
  CancelToken? _catalogCancel;
  CancelToken? _documentCancel;
  Uri _webUrl = TrainingPlanRepository.catalogUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _catalogCancel?.cancel();
    final cancel = CancelToken();
    _catalogCancel = cancel;
    setState(() {
      _loading = true;
      _error = null;
    });
    final cached = await _repository.loadCached();
    if (!mounted || cancel.isCancelled) return;
    if (cached.isNotEmpty) setState(() => _plans = cached);
    try {
      final plans = await _repository.fetchCatalog(cancelToken: cancel);
      if (!mounted || cancel.isCancelled) return;
      setState(() {
        _plans = plans;
        if (!_plans.any((plan) => plan.cohort == _cohort)) _cohort = null;
      });
    } catch (e) {
      if (!mounted || cancel.isCancelled) return;
      setState(
        () => _error = e is TrainingPlanException
            ? e.message
            : '培养计划目录加载失败，请检查网络后重试',
      );
    } finally {
      if (mounted && !cancel.isCancelled) setState(() => _loading = false);
    }
  }

  void _openWeb() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SimpleWebPage(title: '学校培养计划', url: _webUrl.toString()),
    ),
  );

  Future<void> _open(TrainingPlan plan) async {
    if (_opening != null) return;
    final cancel = CancelToken();
    _documentCancel = cancel;
    setState(() {
      _opening = plan.url.toString();
      _webUrl = plan.url;
      _downloadProgress = null;
      _error = null;
    });
    try {
      final documents = await _repository.documents(plan, cancelToken: cancel);
      if (!mounted || cancel.isCancelled) return;
      final ordered = [
        ...documents.where((item) => item.matchesMajor(widget.major)),
        ...documents.where((item) => !item.matchesMajor(widget.major)),
      ];
      final document = documents.length == 1 && !plan.isSummary
          ? documents.single
          : await showDialog<TrainingPlan>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: const Text('选择培养计划 PDF'),
                children: ordered
                    .map(
                      (item) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, item),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title),
                            Text(
                              item.matchesMajor(widget.major)
                                  ? '专业名称匹配，仍请核对年级与方向'
                                  : '适用专业待核对，请以 PDF 原文为准',
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
      if (document == null || !mounted || cancel.isCancelled) return;
      final path = await _repository.download(
        document,
        cancelToken: cancel,
        onProgress: (received, total) {
          if (!mounted || cancel.isCancelled) return;
          final progress = total > 0 ? received / total : null;
          if (progress == null ||
              _downloadProgress == null ||
              (progress - _downloadProgress!).abs() >= 0.01 ||
              received == total) {
            setState(() => _downloadProgress = progress);
          }
        },
      );
      if (!mounted || cancel.isCancelled) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PdfPreviewPage(title: document.title, path: path),
        ),
      );
    } catch (e) {
      if (!mounted || cancel.isCancelled) return;
      setState(
        () => _error = e is TrainingPlanException
            ? e.message
            : 'PDF 获取失败，请检查网络后重试',
      );
    } finally {
      if (mounted) {
        setState(() {
          _opening = null;
          _downloadProgress = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _catalogCancel?.cancel();
    _documentCancel?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _plans
        .where(
          (plan) =>
              (!_onlyMajor ||
                  plan.matchesMajor(widget.major) ||
                  plan.isSummary) &&
              (_cohort == null || plan.cohort == _cohort) &&
              (query.isEmpty || plan.title.toLowerCase().contains(query)),
        )
        .toList();
    final years =
        _plans.map((plan) => plan.cohort).whereType<int>().toSet().toList()
          ..sort((a, b) => b.compareTo(a));
    return Scaffold(
      appBar: AppBar(
        title: const Text('培养计划'),
        actions: [
          IconButton(
            tooltip: '刷新目录',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '学校网页',
            onPressed: _openWeb,
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    children: [
                      Text(
                        widget.major.isEmpty
                            ? '未获取到专业，可搜索专业名称或浏览全部计划。'
                            : '当前专业：${widget.major}。请核对计划中的入学年级与专业方向。',
                      ),
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: '搜索专业或计划名称',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                      if (widget.major.isNotEmpty)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('本专业及待核对汇总'),
                          value: _onlyMajor,
                          onChanged: (value) =>
                              setState(() => _onlyMajor = value),
                        ),
                      DropdownButton<int>(
                        isExpanded: true,
                        value: _cohort,
                        hint: const Text('全部年级'),
                        items: [
                          const DropdownMenuItem<int>(
                            value: null,
                            child: Text('全部年级'),
                          ),
                          for (final year in years)
                            DropdownMenuItem(
                              value: year,
                              child: Text('$year 级'),
                            ),
                        ],
                        onChanged: (value) => setState(() => _cohort = value),
                      ),
                    ],
                  ),
                ),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Text(_plans.isEmpty ? _error! : '$_error\n当前显示已缓存目录。'),
                        Wrap(
                          spacing: 12,
                          children: [
                            TextButton(
                              onPressed: _load,
                              child: const Text('重试'),
                            ),
                            TextButton(
                              onPressed: _openWeb,
                              child: const Text('学校网页'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AsyncStateView(
                loading: _loading && _plans.isEmpty,
                emptyText: _plans.isEmpty
                    ? '尚无可用的培养计划目录'
                    : '没有匹配的计划，请调整专业、年级或搜索条件',
              ),
            )
          else
            SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (_, index) {
                final plan = visible[index];
                return ListTile(
                  leading: Icon(
                    plan.isPdf
                        ? Icons.picture_as_pdf_outlined
                        : Icons.description_outlined,
                  ),
                  title: Text(plan.title),
                  subtitle: Text(
                    [
                      plan.cohort == null ? '适用年级请以原文为准' : '${plan.cohort} 级',
                      if (plan.isSummary) '专业待核对，展开查看 PDF',
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _opening == null ? () => _open(plan) : null,
                );
              },
            ),
        ],
      ),
      bottomNavigationBar: _opening == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(value: _downloadProgress),
                    ),
                    TextButton(
                      onPressed: () => _documentCancel?.cancel(),
                      child: const Text('取消'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
