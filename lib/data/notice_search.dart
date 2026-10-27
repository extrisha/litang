import 'dart:math' as math;

import 'models.dart';

/// 搜索过滤条件。null 表示不限制。
class SearchFilter {
  const SearchFilter({this.kind, this.dept, this.since});

  final String? kind;
  final String? dept;
  final DateTime? since;

  bool matches(Notice notice) {
    if (kind != null && kind!.isNotEmpty && notice.kind != kind) {
      return false;
    }
    if (dept != null && dept!.isNotEmpty && notice.dept != dept) {
      return false;
    }
    final since = this.since;
    if (since != null) {
      final at = notice.publishedAt;
      if (at == null || at.isBefore(since)) {
        return false;
      }
    }
    return true;
  }
}

/// 一条搜索结果。
class SearchHit {
  const SearchHit({
    required this.notice,
    required this.score,
    required this.terms,
  });

  final Notice notice;
  final double score;

  /// 用来在标题里做高亮的原始查询词（越长越靠前）。
  final List<String> terms;
}

/// 通知搜索：倒排索引 + BM25 + 校园同义词 + 覆盖率门槛。
///
/// 不依赖服务端，也不“训练模型”。7k 多条标题在手机上建一次索引就够了。
class NoticeSearchIndex {
  NoticeSearchIndex._({
    required this._notices,
    required this._termFreqs,
    required this._docLengths,
    required this._avgdl,
    required this._docFreq,
    required this._normalizedTitles,
    required this._looseTitles,
  });

  final List<Notice> _notices;
  final List<Map<String, int>> _termFreqs;
  final List<int> _docLengths;
  final double _avgdl;
  final Map<String, int> _docFreq;
  final List<String> _normalizedTitles;
  final List<String> _looseTitles;

  static const double _k1 = 1.2;
  static const double _b = 0.75;

  /// 同义词只在查询侧生效：原词权重 1.0，同义词 0.35。
  static const Map<String, List<String>> _synonyms = <String, List<String>>{
    '放假': <String>['寒假', '暑假', '校历'],
    '寒假': <String>['放假', '校历'],
    '暑假': <String>['放假', '校历'],
    '四六级': <String>['四级', '六级', 'cet'],
    '四级': <String>['四六级'],
    '六级': <String>['四六级'],
    '补考': <String>['缓考'],
    '缓考': <String>['补考'],
    '奖学金': <String>['助学金', '评奖', '公示'],
    '助学金': <String>['奖学金', '资助'],
    '转专业': <String>['转专业考核'],
    '选课': <String>['退改选', '补选'],
    '推免': <String>['保研', '免试'],
    '保研': <String>['推免'],
    '考试': <String>['考务', '监考', '巡考'],
    '期末': <String>['期末考试'],
    '培养计划': <String>['教学计划'],
    '校历': <String>['教学日历'],
    '医保': <String>['医疗保险'],
    '体测': <String>['体质测试'],
    '军训': <String>['军事训练'],
    '校园卡': <String>['一卡通'],
    '空教室': <String>['空闲教室'],
    '电费': <String>['水电', '缴费'],
    '成绩': <String>['绩点', '成绩单'],
    '成绩单': <String>['学业证明', '在读证明'],
    '在读证明': <String>['学业证明'],
    '食堂': <String>['餐饮', '餐厅'],
    '校车': <String>['班车', '通勤'],
    '学生证': <String>['补办学生证'],
  };

  /// 问句里的填充词，查询侧去掉；标题里保留也没关系。
  static const List<String> _stopPhrases = <String>[
    '什么时候',
    '什么时间',
    '几点钟',
    '几点',
    '哪天',
    '怎么样',
    '怎么',
    '如何',
    '怎样',
    '哪些',
    '哪个',
    '多少',
    '请问',
    '想问',
    '想知道',
    '告诉我',
    '一下',
    '可以',
    '需要',
    '是否',
    '开始',
    '结束',
    '时间',
    '日期',
    '多久',
    '现在',
    '今年',
    '明年',
    '这学期',
    '本学期',
    '关于',
    '麻烦',
    '帮忙',
    '帮我',
    '吗',
    '呢',
    '啊',
    '呀',
    '吧',
  ];

  static const Map<String, double> _kindBoost = <String, double>{
    '竞赛': 0.6,
    '教学': 0.5,
    '通知': 0.45,
    '讲座': 0.3,
    '学工': 0.25,
    '就业': 0.25,
    '科研': 0.1,
    '招生': 0.1,
    '新闻': -0.4,
    '党群': -0.6,
  };

  /// 标题里的“文体词”。用户搜“暑假放假安排”时，
  /// 带“安排”的通知应该比只带“暑假”的短讯更相关。
  static const List<String> _typeWords = <String>[
    '安排',
    '方案',
    '通知',
    '公示',
    '名单',
    '办法',
    '指南',
    '规定',
    '细则',
    '计划',
    '报名',
    '结果',
    '公告',
    '要求',
  ];

  /// 查询分词用的校园词典。
  ///
  /// 只用于“把一句话切成几个概念”，不参与建索引；索引那边仍然是
  /// bigram，所以词典没收录的新词也能靠 bigram 搜到。
  static final Set<String> _dictionary = <String>{
    ..._synonyms.keys,
    for (final values in _synonyms.values) ...values,
    '通知',
    '公告',
    '公示',
    '名单',
    '安排',
    '方案',
    '办法',
    '指南',
    '规定',
    '细则',
    '考试',
    '报名',
    '成绩',
    '选课',
    '退改选',
    '补选',
    '重修',
    '缓考',
    '补考',
    '监考',
    '巡考',
    '期末',
    '期中',
    '期末考试',
    '寒假',
    '暑假',
    '放假',
    '校历',
    '教学日历',
    '转专业',
    '推免',
    '保研',
    '免试',
    '奖学金',
    '助学金',
    '评奖',
    '资助',
    '培养计划',
    '教学计划',
    '学分',
    '绩点',
    '排名',
    '学籍',
    '毕业',
    '学位',
    '论文',
    '答辩',
    '实习',
    '就业',
    '招聘',
    '宣讲',
    '竞赛',
    '大创',
    '创新创业',
    '讲座',
    '报告',
    '论坛',
    '食堂',
    '宿舍',
    '公寓',
    '校园卡',
    '一卡通',
    '水电',
    '电费',
    '缴费',
    '医保',
    '医疗',
    '体测',
    '体质',
    '军训',
    '军事训练',
    '校车',
    '班车',
    '通勤',
    '图书馆',
    '档案馆',
    '成绩单',
    '在读证明',
    '学业证明',
    '学生证',
    '补办学生证',
    '补办',
    '教室',
    '空教室',
    '智慧教室',
    '录取',
    '招生',
    '研究生',
    '本科',
    '硕士',
    '博士',
    '国际交流',
    '留学',
    '签证',
    '户籍',
    '户口',
    '档案',
    '社团',
    '志愿',
    '献血',
    '体检',
    '疫苗',
    '消防',
    '安全',
    '实验室',
    '采购',
    '招标',
    '比价',
    '询价',
    '项目',
    '申报',
    '科研',
    '基金',
    '成果',
    '会议',
    '培训',
    '教学',
    '教务',
    '学工',
    '团委',
    '党委',
    '宣传',
    '统战',
    '工会',
    '校友',
    '基金会',
    '信息公开',
    '规章制度',
    '上海理工大学',
    '上理',
    '全校',
    '车辆',
  };

  static final RegExp _runs = RegExp(r'[a-z0-9]+|[\u4e00-\u9fff]+');
  static final RegExp _brackets = RegExp(r'[（(【\[][^）)】\]]*[）)】\]]');

  /// 把标题/查询归一化成只含中文 + 小写英文 + 数字的串。
  ///
  /// 这样“四、六级”和“四六级”能对上；“关于2026年寒假安排的通知”
  /// 去标点后也更容易做整句匹配。
  static String normalize(String input, {bool dropBrackets = false}) {
    var text = input;
    if (dropBrackets) {
      text = text.replaceAll(_brackets, '');
    }
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      var code = rune;
      // 全角 ASCII -> 半角
      if (code >= 0xFF01 && code <= 0xFF5E) {
        code -= 0xFEE0;
      }
      if (code == 0x3000) {
        code = 0x20;
      }
      // 大写 -> 小写
      if (code >= 0x41 && code <= 0x5A) {
        code += 0x20;
      }
      final isDigit = code >= 0x30 && code <= 0x39;
      final isLower = code >= 0x61 && code <= 0x7A;
      final isChinese = code >= 0x4E00 && code <= 0x9FFF;
      if (isDigit || isLower || isChinese) {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  /// 中文没有空格：这里用 bigram 切（“奖学金” -> 奖学 / 学金），
  /// 再补上整段短词。这样不需要 jieba，也能匹配大部分校园词。
  static List<String> tokenize(String normalized) {
    final out = <String>[];
    for (final match in _runs.allMatches(normalized)) {
      final run = match[0]!;
      if (_isAscii(run)) {
        out.add(run);
        continue;
      }
      if (run.length <= 8) {
        out.add(run);
      }
      if (run.length == 1) {
        out.add(run);
        continue;
      }
      for (var i = 0; i + 1 < run.length; i++) {
        out.add(run.substring(i, i + 2));
      }
    }
    return out;
  }

  static bool _isAscii(String text) {
    for (final code in text.codeUnits) {
      if (code > 0x7F) {
        return false;
      }
    }
    return true;
  }

  static String _cleanQuery(String normalized) {
    var core = normalized;
    for (final phrase in _stopPhrases) {
      core = core.replaceAll(phrase, '');
    }
    return core.isEmpty ? normalized : core;
  }

  /// 用校园词典把查询切成“概念”。
  ///
  /// 这一步只用于判断“这句 query 的核心词是什么”，
  /// 比如“暑假放假安排”切成 暑假 / 放假 / 安排，
  /// 后面挑最稀有的“暑假”当锚点，避免被“放假安排”带偏。
  static List<String> _segment(String text) {
    final out = <String>[];
    var i = 0;
    while (i < text.length) {
      String? found;
      final maxLen = math.min(8, text.length - i);
      for (var len = maxLen; len >= 2; len--) {
        final sub = text.substring(i, i + len);
        if (_dictionary.contains(sub)) {
          found = sub;
          break;
        }
      }
      if (found != null) {
        out.add(found);
        i += found.length;
        continue;
      }
      final code = text.codeUnitAt(i);
      if (code < 0x80) {
        var j = i;
        while (j < text.length && text.codeUnitAt(j) < 0x80) {
          j++;
        }
        out.add(text.substring(i, j));
        i = j;
      } else {
        // 词典没收录的字直接跳过，不硬切。
        i++;
      }
    }
    return out;
  }

  static NoticeSearchIndex build(List<Notice> notices) {
    final termFreqs = <Map<String, int>>[];
    final docLengths = <int>[];
    final docFreq = <String, int>{};
    final normalizedTitles = <String>[];
    final looseTitles = <String>[];
    var totalLength = 0;

    for (final notice in notices) {
      final full = normalize(notice.title);
      final loose = normalize(notice.title, dropBrackets: true);
      normalizedTitles.add(full);
      looseTitles.add(loose);

      // 同一篇标题的完整版和“去括号版”合并成一份词频，
      // 避免同一篇文档被算两遍长度。
      final tokens = <String>{...tokenize(full), ...tokenize(loose)};
      final tf = <String, int>{};
      for (final token in tokens) {
        tf[token] = 1;
      }
      termFreqs.add(tf);
      docLengths.add(tokens.length);
      totalLength += tokens.length;
      for (final token in tokens) {
        docFreq[token] = (docFreq[token] ?? 0) + 1;
      }
    }

    final avgdl = notices.isEmpty ? 0.0 : totalLength / notices.length;
    return NoticeSearchIndex._(
      notices: notices,
      termFreqs: termFreqs,
      docLengths: docLengths,
      avgdl: avgdl,
      docFreq: docFreq,
      normalizedTitles: normalizedTitles,
      looseTitles: looseTitles,
    );
  }

  List<SearchHit> search(
    String raw, {
    SearchFilter? filter,
    String? college,
    int limit = 40,
  }) {
    final query = _buildQuery(raw);
    if (query.terms.isEmpty || _notices.isEmpty) {
      return const <SearchHit>[];
    }

    final now = DateTime.now();
    final scored = <SearchHit>[];
    final n = _notices.length.toDouble();
    final avgdl = _avgdl <= 0 ? 1.0 : _avgdl;

    // 词典切出来的概念里，挑“最稀有且真的出现过”的一个当锚点。
    // 如果所有概念都没出现过，就留一个当兜底（通常会返回空，
    // 比如“空教室”“学生证”这种库里没有的词）。
    String? anchor;
    String? missingAnchor;
    var anchorDf = 1 << 30;
    for (final segment in query.segments) {
      final df = _docFreq[segment] ?? 0;
      if (df > 0 && df < anchorDf) {
        anchorDf = df;
        anchor = segment;
      } else if (df == 0 && missingAnchor == null) {
        missingAnchor = segment;
      }
    }
    anchor ??= missingAnchor;

    for (var i = 0; i < _notices.length; i++) {
      final notice = _notices[i];
      if (filter != null && !filter.matches(notice)) {
        continue;
      }
      final titleFull = _normalizedTitles[i];
      final titleLoose = _looseTitles[i];

      var anchorOk = anchor == null;
      if (anchor != null) {
        final anchorValue = anchor;
        final hasAnchorText =
            titleFull.contains(anchorValue) || titleLoose.contains(anchorValue);
        if (hasAnchorText) {
          if (anchorDf <= 200) {
            // 稀有词可能是更长词的一部分（“校车” vs “全校车辆”），
            // 只在候选很少时才做一次词典切分，避免建索引时切 7000 条。
            final titleSegments = <String>{
              ..._segment(titleFull),
              ..._segment(titleLoose),
            };
            anchorOk = titleSegments.any(
              (segment) =>
                  segment == anchorValue ||
                  segment.startsWith(anchorValue) ||
                  segment.endsWith(anchorValue),
            );
          } else {
            anchorOk = true;
          }
        }
        // 只有一个概念时允许走同义词，比如“放假” -> 寒假/暑假/校历。
        if (!anchorOk && query.segments.length == 1) {
          for (final synonym in _synonyms[anchorValue] ?? const <String>[]) {
            final normalizedSynonym = normalize(synonym);
            if (titleFull.contains(normalizedSynonym) ||
                titleLoose.contains(normalizedSynonym)) {
              anchorOk = true;
              break;
            }
          }
        }
      }
      if (!anchorOk) {
        continue;
      }

      var matchedSegments = 0;
      for (final segment in query.segments) {
        if (titleFull.contains(segment) || titleLoose.contains(segment)) {
          matchedSegments++;
        }
      }
      final segmentCoverage = query.segments.isEmpty
          ? 0.0
          : matchedSegments / query.segments.length;

      final tf = _termFreqs[i];
      var score = 0.0;
      var synonymMatched = false;

      for (final entry in query.terms.entries) {
        final freq = tf[entry.key];
        if (freq == null) {
          continue;
        }
        if (entry.value < 1.0) {
          synonymMatched = true;
        }
        final df = _docFreq[entry.key] ?? 1;
        final idf = math.log(1 + (n - df + 0.5) / (df + 0.5));
        final dl = _docLengths[i].toDouble();
        score +=
            entry.value *
            idf *
            freq *
            (_k1 + 1) /
            (freq + _k1 * (1 - _b + _b * dl / avgdl));
      }

      if (score <= 0) {
        continue;
      }

      final exact =
          (query.core.isNotEmpty && titleFull.contains(query.core)) ||
          (query.core.isNotEmpty && titleLoose.contains(query.core));

      var covered = 0;
      for (final term in query.originalTerms) {
        if (tf.containsKey(term)) {
          covered++;
        }
      }
      final coverage = query.originalTerms.isEmpty
          ? 0.0
          : covered / query.originalTerms.length;

      // 没有词典锚点的 query（生词、缩写）才用覆盖率兜底。
      if (anchor == null && !exact && coverage < 0.5) {
        if (!(coverage == 0 && synonymMatched)) {
          continue;
        }
      }

      if (exact) {
        score *= 1.8;
      } else if (coverage >= 0.99) {
        score *= 1.25;
      }
      score *= 0.8 + 0.4 * coverage;
      // 命中的“概念”越多越相关：搜“暑假放假安排”时，
      // “暑假+安排”应该排在只有“暑假”的短讯前面。
      score *= 1 + 0.6 * segmentCoverage;

      // 查询里带了“安排/公示/报名”这类文体词，标题里也有，
      // 说明文档类型对得上。
      for (final typeWord in _typeWords) {
        if (query.core.contains(typeWord) &&
            (titleFull.contains(typeWord) || titleLoose.contains(typeWord))) {
          score += 6;
          break;
        }
      }

      final boost = _kindBoost[notice.kind];
      if (boost != null) {
        score += boost;
      }
      if (college != null && college.isNotEmpty && notice.dept == college) {
        score += 1.2;
      }
      final date = notice.publishedAt;
      if (date != null) {
        final days = now.difference(date).inHours / 24.0;
        if (days >= 0) {
          score += 0.8 * math.exp(-days / 365);
        }
      }

      scored.add(
        SearchHit(notice: notice, score: score, terms: query.highlightTerms),
      );
    }

    if (scored.isEmpty) {
      return const <SearchHit>[];
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }
      final ad = a.notice.publishedAt;
      final bd = b.notice.publishedAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    final top = scored.first.score;
    final minScore = math.max(0.8, top * 0.12);
    final out = <SearchHit>[];
    for (final hit in scored) {
      if (hit.score < minScore) {
        continue;
      }
      out.add(hit);
      if (out.length >= limit) {
        break;
      }
    }
    return out;
  }

  static _Query _buildQuery(String raw) {
    final normalized = normalize(raw);
    final core = _cleanQuery(normalized);
    final terms = <String, double>{};

    void add(String token, double weight) {
      final old = terms[token];
      if (old == null || weight > old) {
        terms[token] = weight;
      }
    }

    final fullTokens = tokenize(core);
    final looseTokens = tokenize(normalize(core, dropBrackets: true));
    for (final token in fullTokens) {
      add(token, 1.0);
    }
    for (final token in looseTokens) {
      add(token, 1.0);
    }

    for (final entry in _synonyms.entries) {
      if (!core.contains(entry.key)) {
        continue;
      }
      for (final synonym in entry.value) {
        for (final token in tokenize(normalize(synonym))) {
          add(token, 0.35);
        }
      }
    }

    final originalTerms = <String>{...fullTokens, ...looseTokens};
    final segments = _segment(core);
    final highlight = <String>[
      if (core.length >= 2) core,
      ...segments,
      ...originalTerms.where((t) => t.length >= 2),
    ];
    // 去重，长的放前面；高亮不需要太多碎片。
    final seen = <String>{};
    final highlightTerms = <String>[];
    for (final term
        in highlight..sort((a, b) => b.length.compareTo(a.length))) {
      if (seen.add(term)) {
        highlightTerms.add(term);
      }
      if (highlightTerms.length >= 8) {
        break;
      }
    }

    return _Query(
      core: core,
      terms: terms,
      originalTerms: originalTerms,
      segments: segments,
      highlightTerms: highlightTerms,
    );
  }
}

class _Query {
  const _Query({
    required this.core,
    required this.terms,
    required this.originalTerms,
    required this.segments,
    required this.highlightTerms,
  });

  final String core;
  final Map<String, double> terms;
  final Set<String> originalTerms;
  final List<String> segments;
  final List<String> highlightTerms;
}
