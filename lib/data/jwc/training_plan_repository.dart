import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import 'package:path_provider/path_provider.dart';

import '../app_exception.dart';
import '../cache_store.dart';
import '../http/api_client.dart';

/// 培养计划数据获取失败。
///
/// 继承 [AppException]，页面可以直接用 `e.message`，
/// 与项目其它业务异常保持同一套处理方式。
class TrainingPlanException extends AppException {
  const TrainingPlanException(String message)
    : super(AppFailure.server, message);
}

class TrainingPlan {
  const TrainingPlan({required this.title, required this.url});
  final String title;
  final Uri url;
  bool get isPdf => url.path.toLowerCase().endsWith('.pdf');

  /// 只识别明确写出的入学年级；发布年份、版本年份不能当成入学年级。
  int? get cohort =>
      int.tryParse(RegExp(r'(20\d{2})\s*级').firstMatch(title)?.group(1) ?? '');

  /// 汇总文章没有指定专业；不能按其他专业排除，也不能认作本专业计划。
  bool get isSummary =>
      !isPdf &&
      normalizedMajor(title)
          .replaceAll(RegExp(r'各|全部|所有|全校|汇总|汇编|合集|[()]'), '')
          .isEmpty;

  bool matchesMajor(String major) {
    if (major.trim().isEmpty) return false;
    final name = normalizedMajor(title);
    return name.isNotEmpty && name == normalizedMajor(major);
  }

  static String normalizedMajor(String value) => value
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll(RegExp(r'20\d{2}\s*(级|年|版)?'), '')
      .replaceAll(RegExp(r'本科|人才培养方案|人才培养计划|培养方案|培养计划|专业|\s|[《》【】_\-]'), '')
      .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '')
      .trim();

  Map<String, String> toJson() => {'title': title, 'url': url.toString()};
  static TrainingPlan fromJson(Map<String, dynamic> json) => TrainingPlan(
    title: json['title'] as String,
    url: Uri.parse(json['url'] as String),
  );
}

class TrainingPlanLinks {
  const TrainingPlanLinks(this.plans, this.nextPage);
  final List<TrainingPlan> plans;
  final Uri? nextPage;
}

/// 教务目录与文章附件解析。学校限制访问或结构变化时保留错误，不能写成空目录。
class TrainingPlanRepository {
  TrainingPlanRepository({Dio? client, this.directory})
    : _client = client ?? ApiClient.longRunning;

  static final catalogUrl = Uri.parse('https://jwc.usst.edu.cn/pyjh/list.htm');
  static const _catalogKey = 'jwc_training_plans_v1';
  final Dio _client;
  final Directory? directory;

  static void checkAccess(String source) {
    final text = html.parse(source).body?.text ?? source;
    if (text.contains('仅允许校内') ||
        text.contains('并非校内地址') ||
        text.contains('只允许校内') ||
        text.contains('校内IP访问')) {
      throw const TrainingPlanException(
        '培养计划目录仅限校内访问。请连接校园网或学校授权 VPN 后重试，也可在学校网页中查看。',
      );
    }
  }

  static TrainingPlanLinks parseLinks(
    String source,
    Uri base, {
    bool catalog = true,
  }) {
    checkAccess(source);
    final document = html.parse(source);
    final containers = document.querySelectorAll(
      catalog
          ? '.wp_article_list, .news_list, .news-list, .article-list'
          : '.wp_articlecontent, .article-content, .Article_Content',
    );
    final scoped = containers.isNotEmpty;
    final anchors = scoped
        ? containers.expand((element) => element.querySelectorAll('a[href]'))
        : document.querySelectorAll('a[href]');
    final plans = <String, TrainingPlan>{};
    for (final anchor in anchors) {
      final href = anchor.attributes['href']?.trim() ?? '';
      if (href.isEmpty || href.startsWith('#')) continue;
      final url = base.resolve(href);
      if (!['http', 'https'].contains(url.scheme) ||
          url.host != catalogUrl.host ||
          url == base) {
        continue;
      }
      final title = (anchor.attributes['title'] ?? anchor.text)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (title.isEmpty) continue;
      final pdf = url.path.toLowerCase().endsWith('.pdf');
      final planTitle = title.contains('培养计划') || title.contains('培养方案');
      final article = RegExp(r'/[^/]+/page\.(htm|psp)$').hasMatch(url.path);
      if (!pdf && !(catalog && (planTitle || (scoped && article)))) continue;
      // 排除返回目录/栏目导航；分页单独处理。
      if (RegExp(r'/list\d*\.(htm|psp)$').hasMatch(url.path)) continue;
      plans[url.toString()] = TrainingPlan(title: title, url: url);
    }
    if (!catalog) {
      for (final element in document.querySelectorAll(
        'iframe[src], embed[src], object[data]',
      )) {
        final raw =
            element.attributes['src'] ?? element.attributes['data'] ?? '';
        final embedded = base.resolve(raw);
        final file = embedded.queryParameters['file'];
        final url = file == null ? embedded : base.resolve(file);
        if (url.host == catalogUrl.host &&
            url.path.toLowerCase().endsWith('.pdf')) {
          plans.putIfAbsent(
            url.toString(),
            () => TrainingPlan(
              title:
                  document.querySelector('h1, .arti_title')?.text.trim() ??
                  url.pathSegments.last,
              url: url,
            ),
          );
        }
      }
    }
    Uri? next;
    for (final anchor in document.querySelectorAll('a[href]')) {
      final label = anchor.text.replaceAll(RegExp(r'\s'), '');
      if (label != '下一页' && anchor.attributes['rel'] != 'next') continue;
      final href = anchor.attributes['href'] ?? '';
      if (href.isEmpty || href.startsWith('#')) continue;
      final candidate = base.resolve(href);
      if (candidate.host == catalogUrl.host &&
          candidate.path.startsWith('/pyjh/') &&
          candidate != base) {
        next = candidate;
        break;
      }
    }
    return TrainingPlanLinks(plans.values.toList(), next);
  }

  static List<TrainingPlan> _decodePlans(Object? value) {
    if (value is! List) return [];
    try {
      return value
          .map(
            (item) =>
                TrainingPlan.fromJson((item as Map).cast<String, dynamic>()),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<TrainingPlan>> loadCached() async =>
      _decodePlans((await CacheStore.read(_catalogKey))?.data);

  Future<String> _getHtml(Uri url, CancelToken? cancelToken) async {
    final response = await _client.get<String>(
      url.toString(),
      options: Options(responseType: ResponseType.plain),
      cancelToken: cancelToken,
    );
    if (response.statusCode != 200 || response.data == null) {
      throw TrainingPlanException('教务网站返回 HTTP ${response.statusCode}，请稍后重试');
    }
    return response.data!;
  }

  Future<List<TrainingPlan>> fetchCatalog({CancelToken? cancelToken}) async {
    final seen = <Uri>{};
    final result = <String, TrainingPlan>{};
    Uri? url = catalogUrl;
    while (url != null && seen.add(url)) {
      if (seen.length > 30) {
        throw const TrainingPlanException('目录分页较多，请在学校网页查看完整目录');
      }
      final links = parseLinks(await _getHtml(url, cancelToken), url);
      for (final item in links.plans) {
        result[item.url.toString()] = item;
      }
      url = links.nextPage;
    }
    if (result.isEmpty) {
      throw const TrainingPlanException('未能识别培养计划目录，请在学校网页查看或稍后重试');
    }
    final plans = result.values.toList();
    await CacheStore.write(
      _catalogKey,
      plans.map((item) => item.toJson()).toList(),
    );
    return plans;
  }

  String _id(Uri url) => sha256.convert(utf8.encode(url.toString())).toString();

  Future<List<TrainingPlan>> documents(
    TrainingPlan plan, {
    CancelToken? cancelToken,
  }) async {
    if (plan.isPdf) return [plan];
    final key = 'jwc_plan_documents_${_id(plan.url)}';
    final cached = _decodePlans((await CacheStore.read(key))?.data);
    if (cached.isNotEmpty) return cached;
    final links = parseLinks(
      await _getHtml(plan.url, cancelToken),
      plan.url,
      catalog: false,
    );
    if (links.plans.isEmpty) {
      throw const TrainingPlanException('该页面暂未识别到 PDF 附件，请使用“学校网页”查看原文');
    }
    await CacheStore.write(
      key,
      links.plans.map((item) => item.toJson()).toList(),
    );
    return links.plans;
  }

  Future<bool> _validPdf(File file) async {
    if (!await file.exists() || await file.length() < 5) return false;
    final handle = await file.open();
    try {
      return ascii.decode(await handle.read(5), allowInvalid: true) == '%PDF-';
    } finally {
      await handle.close();
    }
  }

  Future<String> download(
    TrainingPlan plan, {
    CancelToken? cancelToken,
    ProgressCallback? onProgress,
  }) async {
    final base = directory ?? await getApplicationDocumentsDirectory();
    final folder = Directory('${base.path}/training-plans');
    await folder.create(recursive: true);
    final file = File('${folder.path}/${_id(plan.url)}.pdf');
    if (await _validPdf(file)) return file.path;
    final partial = File('${file.path}.part');
    try {
      final response = await _client.download(
        plan.url.toString(),
        partial.path,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
        deleteOnError: true,
      );
      if (response.statusCode != 200 || !await _validPdf(partial)) {
        throw const TrainingPlanException('下载结果不是 PDF，可能需要校园网访问；请在学校网页核对');
      }
      if (await file.exists()) await file.delete();
      await partial.rename(file.path);
      return file.path;
    } finally {
      if (await partial.exists()) await partial.delete();
    }
  }
}
