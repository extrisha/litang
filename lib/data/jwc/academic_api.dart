import 'dart:convert';

import 'package:dio/dio.dart';

import '../app_exception.dart';
import '../auth/cas_client.dart';

/// 培养方案树上的一个节点（大类 / 子类）。
class CreditCategory {
  const CreditCategory({
    this.id = '',
    this.parentId = '',
    required this.name,
    required this.earned,
    required this.required,
    required this.passed,
    this.children = const <CreditCategory>[],
  });

  /// 培养方案节点 id（拉课程明细用）。
  final String id;
  final String parentId;
  final String name;
  final double earned;
  final double required;
  final bool passed;

  /// 子分类（「通识课程」下面挂「通识-思政类01」这种）。
  final List<CreditCategory> children;

  bool get isLeaf => children.isEmpty;

  double get missing {
    final value = required - earned;
    return value > 0 ? value : 0;
  }

  double get progress => required <= 0 ? 1 : (earned / required).clamp(0, 1);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'parentId': parentId,
    'name': name,
    'earned': earned,
    'required': required,
    'passed': passed,
    'children': children.map((c) => c.toJson()).toList(),
  };

  static CreditCategory fromJson(Map<String, dynamic> json) => CreditCategory(
    id: json['id'] as String? ?? '',
    parentId: json['parentId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    earned: (json['earned'] as num?)?.toDouble() ?? 0,
    required: (json['required'] as num?)?.toDouble() ?? 0,
    passed: json['passed'] as bool? ?? false,
    children: (json['children'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => CreditCategory.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 学业情况快照（按培养方案树组织）。
class AcademicProgress {
  const AcademicProgress({
    required this.majorName,
    required this.earned,
    required this.required,
    required this.categories,
    required this.updatedAt,
  });

  final String majorName;
  final double earned;
  final double required;

  /// 顶层大类（通识课程 / 学科基础课程 / 专业课程 / 任选课程）。
  final List<CreditCategory> categories;
  final DateTime updatedAt;

  double get missing => required - earned > 0 ? required - earned : 0;

  double get progress => required <= 0 ? 0 : (earned / required).clamp(0, 1);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'majorName': majorName,
    'earned': earned,
    'required': required,
    'updatedAt': updatedAt.toIso8601String(),
    'categories': categories.map((c) => c.toJson()).toList(),
  };

  static AcademicProgress fromJson(Map<String, dynamic> json) =>
      AcademicProgress(
        majorName: json['majorName'] as String? ?? '',
        earned: (json['earned'] as num?)?.toDouble() ?? 0,
        required: (json['required'] as num?)?.toDouble() ?? 0,
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        categories: (json['categories'] as List<dynamic>? ?? <dynamic>[])
            .map((e) => CreditCategory.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 培养方案节点下的一门课。
class AcademicCourse {
  const AcademicCourse({
    required this.name,
    required this.code,
    required this.credits,
    required this.term,
    required this.score,
    required this.status,
  });

  final String name;
  final String code;
  final double credits;
  final String term;
  final String score;

  /// passed / inProgress / failed / notStarted / other
  final String status;

  bool get passed => status == 'passed';
  bool get inProgress => status == 'inProgress';
  bool get failed => status == 'failed';
  bool get notStarted => status == 'notStarted';

  String get statusLabel => switch (status) {
    'passed' => '已修',
    'inProgress' => '在修',
    'failed' => '未过',
    'notStarted' => '未修',
    _ => '其他',
  };

  /// 正方 XDZT：1=在修，2=未过，3=未修，4/21=已修。
  static String statusOf(String xdzt) => switch (xdzt) {
    '1' => 'inProgress',
    '2' => 'failed',
    '3' => 'notStarted',
    '4' || '21' => 'passed',
    _ => 'other',
  };

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'code': code,
    'credits': credits,
    'term': term,
    'score': score,
    'status': status,
  };

  static AcademicCourse fromJson(Map<String, dynamic> json) => AcademicCourse(
    name: json['name'] as String? ?? '',
    code: json['code'] as String? ?? '',
    credits: (json['credits'] as num?)?.toDouble() ?? 0,
    term: json['term'] as String? ?? '',
    score: json['score'] as String? ?? '',
    status: json['status'] as String? ?? 'other',
  );
}

/// 正方「学业情况」接口（培养方案树 + 课程明细）。
class AcademicApi {
  AcademicApi(this.client);

  final CasClient client;

  static const String _url =
      'https://jwgl.usst.edu.cn/jwglxt/xsxy/xsxyqk_cxXsxyqkIndex.html?gnmkdm=N105515&layout=default';

  Future<AcademicProgress> fetch() async {
    final resp = await client.getJson(Uri.parse(_url));
    return parse(resp.data ?? '');
  }

  /// 某个叶子节点下的课程明细（点击子分类时按需拉取）。
  Future<List<AcademicCourse>> fetchCourses(
    String categoryId,
    String xhId,
  ) async {
    // 正方有两套课程明细接口：库内节点用 Kcxx，方案外/其他节点用 FKcxx。
    // 不知道节点属于哪种，先试 Kcxx，空结果再试 FKcxx。
    final primary = await _fetchCourseList(
      '/jwglxt/xsxy/xsxyqk_cxJxzxjhxfyqKcxx.html',
      categoryId,
      xhId,
    );
    if (primary.isNotEmpty) {
      return primary;
    }
    return _fetchCourseList(
      '/jwglxt/xsxy/xsxyqk_cxJxzxjhxfyqFKcxx.html',
      categoryId,
      xhId,
    );
  }

  Future<List<AcademicCourse>> _fetchCourseList(
    String path,
    String categoryId,
    String xhId,
  ) async {
    final Response<dynamic> resp;
    try {
      resp = await client.postApi(
        Uri.parse('https://jwgl.usst.edu.cn$path'),
        <String, String>{
          'fromXh_id': '',
          'xfyqjd_id': categoryId,
          'xh_id': xhId,
        },
        referer: 'https://jwgl.usst.edu.cn/jwglxt/xsxy/xsxyqk_cxXsxyqkIndex.html?gnmkdm=N105515&layout=default',
      );
    } catch (e) {
      throw AppException(AppFailure.network, '课程明细拉取失败，请检查网络', e);
    }
    final raw = resp.data ?? '';
    final trimmed = raw.trim();
    // 解析器对非 JSON 一律返回空列表，但「拿到登录页」不能被当成「没有课程」：
    // 两个接口都试完之后会得到空列表，页面就显示「暂无课程」了。
    if (trimmed.isNotEmpty &&
        !trimmed.startsWith('[') &&
        !trimmed.startsWith('{')) {
      throw const AppException(AppFailure.auth, '教务登录已失效，请在「我的」重新登录后重试');
    }
    return parseCourses(raw);
  }

  /// 页面把培养方案树内联在 JS 字符串里：
  /// `<li fxfyqjd_id='父'>` … `<p class='title1' id='p<ID>' yxxf='已修' yqzdxf='要求' sftg='达标'>名称`
  static AcademicProgress parse(String html) {
    final pattern = RegExp(
      "<p class='title1' id='p([0-9A-Za-z_-]+)' yxxf='([0-9.]*)' yqzdxf='([0-9.]*)' sftg='(\\d*)'>\"\\s*\\+\\s*\"([^\"&]+)&nbsp;",
    );

    final nodes = <String, CreditCategory>{};
    for (final match in pattern.allMatches(html)) {
      final id = match.group(1)!;
      final name = (match.group(5) ?? '').trim();
      if (name.isEmpty || nodes.containsKey(id)) {
        continue;
      }
      nodes[id] = CreditCategory(
        id: id,
        parentId: _parentOf(html, match.start),
        name: name,
        earned: double.tryParse(match.group(2)!) ?? 0,
        required: double.tryParse(match.group(3)!) ?? 0,
        passed: match.group(4) == '1',
      );
    }

    if (nodes.isEmpty) {
      return AcademicProgress(
        majorName: '',
        earned: 0,
        required: 0,
        categories: const <CreditCategory>[],
        updatedAt: DateTime.now(),
      );
    }

    final ordered = nodes.values.toList();
    // 根节点 = 要求学分最多的那个（培养方案总学分）
    final root = ordered.reduce((a, b) => b.required > a.required ? b : a);

    // 建树：父节点不存在的挂到根上，避免丢数据
    final childMap = <String, List<CreditCategory>>{};
    for (final node in ordered) {
      if (identical(node, root)) {
        continue;
      }
      final parentId = nodes.containsKey(node.parentId)
          ? node.parentId
          : root.id;
      childMap.putIfAbsent(parentId, () => <CreditCategory>[]).add(node);
    }

    CreditCategory attach(CreditCategory node) => CreditCategory(
      id: node.id,
      parentId: node.parentId,
      name: node.name,
      earned: node.earned,
      required: node.required,
      passed: node.passed,
      children: (childMap[node.id] ?? const <CreditCategory>[])
          .map(attach)
          .toList(),
    );

    final rootNode = attach(root);
    return AcademicProgress(
      majorName: root.name,
      earned: root.earned,
      required: root.required,
      categories: rootNode.children,
      updatedAt: DateTime.now(),
    );
  }

  /// 从节点前面的 `<li ... fxfyqjd_id='父'>` 里取父节点 id。
  static String _parentOf(String html, int nodeStart) {
    final start = nodeStart > 3000 ? nodeStart - 3000 : 0;
    final window = html.substring(start, nodeStart);
    final matches = RegExp("fxfyqjd_id='([0-9A-Za-z_-]*)'").allMatches(window);
    if (matches.isEmpty) {
      return '';
    }
    return matches.last.group(1) ?? '';
  }

  /// 解析课程明细 JSON（字段来自正方：KCZT/XDZT/KCMC/KCH/XF/CJ/XNMC/XQMMC）。
  static List<AcademicCourse> parseCourses(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('[')) {
      return const <AcademicCourse>[];
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is! List) {
      return const <AcademicCourse>[];
    }
    final out = <AcademicCourse>[];
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }
      final map = item.cast<String, dynamic>();
      final name = (map['KCMC'] ?? '').toString().trim();
      if (name.isEmpty) {
        continue;
      }
      final xnm = (map['XNMC'] ?? '').toString().trim();
      final xqm = (map['XQMMC'] ?? '').toString().trim();
      out.add(
        AcademicCourse(
          name: name,
          code: (map['KCH'] ?? '').toString().trim(),
          credits: double.tryParse((map['XF'] ?? '').toString()) ?? 0,
          term: '$xnm $xqm'.trim(),
          score: (map['CJ'] ?? map['MAXCJ'] ?? '').toString().trim(),
          status: AcademicCourse.statusOf((map['XDZT'] ?? '').toString()),
        ),
      );
    }
    return out;
  }
}
