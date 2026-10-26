library;

/// 地图地点搜索：支持简称、中文/阿拉伯数字混用、以及不连续的缩写。
///
/// 目标是把「怎么顺口怎么打」都认下来：
///   教超   → 上海教育超市        （字不连续，靠子序列匹配）
///   二公   → 第二学生公寓一/二/三号楼（简称展开）
///   二公三 → 第二学生公寓三号楼    （简称 + 数字）
///   2公三  → 同上                 （阿拉伯数字和中文数字等价）
///   一教   → 第一教学楼
///   图档   → 图书馆·档案馆

import 'campus_places.dart';

/// 编号类简称的规则：`<数字><类>` → `<第N…>`。
/// 只覆盖校园里高频的几类，别的继续往 kBuildingAliases 里加就行。
final List<({RegExp pattern, String Function(String number, String tail) build})>
_shortRules = <({RegExp pattern, String Function(String number, String tail) build})>[
  (
    pattern: RegExp(r'^([0-9]{1,2}|[一二三四五六七八九十]{1,3})公(.*)$'),
    build: (number, tail) => '第${_digits(number)}学生公寓$tail',
  ),
  (
    pattern: RegExp(r'^([0-9]{1,2}|[一二三四五六七八九十]{1,3})食(?:堂)?(.*)$'),
    build: (number, tail) => '第${_digits(number)}食堂$tail',
  ),
  (
    pattern: RegExp(r'^([0-9]{1,2}|[一二三四五六七八九十]{1,3})教(?:学楼)?(.*)$'),
    build: (number, tail) => '第${_digits(number)}教学楼$tail',
  ),
  (
    pattern: RegExp(r'^([0-9]{1,2}|[一二三四五六七八九十]{1,3})宿(?:舍)?(.*)$'),
    build: (number, tail) => '第${_digits(number)}学生宿舍$tail',
  ),
];

const Map<String, String> _cnDigits = <String, String>{
  '一': '1',
  '二': '2',
  '三': '3',
  '四': '4',
  '五': '5',
  '六': '6',
  '七': '7',
  '八': '8',
  '九': '9',
  '十': '10',
};

/// 把「十一 / 二十三 / 三」这类数字统一成阿拉伯数字，方便和地点名对齐。
String _digits(String raw) {
  if (RegExp(r'^[0-9]+$').hasMatch(raw)) return raw;
  final single = _cnDigits[raw];
  if (single != null) return single;
  final match = RegExp(r'^([一二三四五六七八九]?)十([一二三四五六七八九]?)$').firstMatch(raw);
  if (match == null) return raw;
  final tens = match.group(1)!.isEmpty ? '1' : _cnDigits[match.group(1)!]!;
  final ones = match.group(2)!.isEmpty ? '0' : _cnDigits[match.group(2)!]!;
  return '${int.parse(tens) * 10 + int.parse(ones)}';
}

/// 归一化：去空白/标点、中文数字转阿拉伯、英文小写。
/// 地点名和查询都过一遍，后面才好比较。
String normalizePlaceText(String raw, {bool stripParens = true}) {
  var text = raw
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll('·', '')
      .replaceAll('　', '')
      .replaceAll(RegExp(r'\s+'), '')
      .toLowerCase();

  // 数字序列逐个转换：第十一学生宿舍 → 第11学生宿舍
  text = text.replaceAllMapped(
    RegExp(r'[一二三四五六七八九十]{1,3}'),
    (m) => _digits(m.group(0)!),
  );

  // 去掉括号里的补充说明：(BCD区) / (逸兴楼)，这些不该影响搜索；
  // 但「小礼堂（沪江大学体育馆）」这种括号里带着别名，得留一份带括号的
  if (stripParens) {
    text = text.replaceAll(RegExp(r'\([^)]*\)'), '');
  }
  return text;
}

/// 一次查询可能对应多个「目标串」：原文、别名、规则展开。
List<String> expandPlaceQuery(String query) {
  final raw = query.trim();
  if (raw.isEmpty) return const <String>[];

  final out = <String>[];
  void add(String value) {
    final n = normalizePlaceText(value);
    if (n.isNotEmpty && !out.contains(n)) out.add(n);
  }

  add(raw);

  // 1) 别名表：精确命中，或「查询是别名前缀」（二公 → 二公一/二公二/二公三）
  for (final entry in kBuildingAliases.entries) {
    final key = normalizePlaceText(entry.key);
    if (key == normalizePlaceText(raw) || key.startsWith(normalizePlaceText(raw))) {
      add(entry.value);
    }
  }

  // 2) 编号规则：二公三 → 第二学生公寓三号楼
  final normalizedRaw = normalizePlaceText(raw);
  for (final rule in _shortRules) {
    final m = rule.pattern.firstMatch(raw);
    if (m == null) continue;
    add(rule.build(m.group(1)!, m.group(2) ?? ''));
    break;
  }
  // 规则没命中时，退一步用归一化后的串再试一次（2公三 / 二公三 都能走）
  for (final rule in _shortRules) {
    final m = rule.pattern.firstMatch(normalizedRaw);
    if (m == null) continue;
    add(rule.build(m.group(1)!, m.group(2) ?? ''));
    break;
  }

  return out;
}

/// 子序列匹配打分：查询的每个字都按顺序出现就算命中，越紧凑分越高。
/// 「教超」能命中「上海教育超市」（教…超），但不会命中「超市教育」这种乱序。
int? _subsequenceScore(String name, String needle) {
  var i = 0;
  var first = -1;
  var last = -1;
  for (var j = 0; j < name.length && i < needle.length; j++) {
    if (name[j] == needle[i]) {
      if (first < 0) first = j;
      last = j;
      i++;
    }
  }
  if (i < needle.length) return null; // 没排完
  final span = last - first + 1;
  final gaps = span - needle.length;
  // 命中的跨度太长说明只是碰巧凑齐，压分
  return (300 - gaps * 25 - first * 2).clamp(1, 300);
}

/// 地点名的几种归一化形态：去掉括号补充说明的、保留括号的。
/// 「小礼堂（沪江大学体育馆）」要能用「体育馆」搜到，也得能用「小礼堂」搜到。
List<String> placeNameVariants(String name) {
  final out = <String>[];
  for (final strip in <bool>[true, false]) {
    final v = normalizePlaceText(name, stripParens: strip);
    if (v.isNotEmpty && !out.contains(v)) out.add(v);
  }
  return out;
}

/// 单个目标串对一个地点名的打分；不匹配返回 null。
int? scorePlaceName(String name, String needle) {
  if (needle.isEmpty) return null;
  int? best;
  for (final variant in placeNameVariants(name)) {
    final s = _scoreVariant(variant, needle);
    if (s != null && (best == null || s > best)) best = s;
  }
  return best;
}

int? _scoreVariant(String n, String needle) {
  if (n.isEmpty) return null;

  if (n == needle) return 1000;
  if (n.startsWith(needle)) return 800 - (n.length - needle.length).clamp(0, 200);
  final idx = n.indexOf(needle);
  if (idx >= 0) return 600 - idx * 3 - (n.length - needle.length).clamp(0, 200);

  // 短查询（1 个字）不做子序列，否则「一」能把全图都搜出来
  if (needle.length < 2) return null;
  return _subsequenceScore(n, needle);
}


/// 比较两个名字里的数字序列，用来给同分结果定序。
int _compareNumbers(String a, String b) {
  final na = RegExp(r'\d+').allMatches(normalizePlaceText(a)).map((m) => int.parse(m.group(0)!)).toList();
  final nb = RegExp(r'\d+').allMatches(normalizePlaceText(b)).map((m) => int.parse(m.group(0)!)).toList();
  final len = na.length < nb.length ? na.length : nb.length;
  for (var i = 0; i < len; i++) {
    if (na[i] != nb[i]) return na[i].compareTo(nb[i]);
  }
  if (na.length != nb.length) return na.length.compareTo(nb.length);
  return 0;
}

/// 搜索地点，按相关度排序。
List<CampusPlace> searchCampusPlaces(
  String query, {
  List<CampusPlace> places = kCampusPlaces,
  int limit = 12,
}) {
  final needles = expandPlaceQuery(query);
  if (needles.isEmpty) return const <CampusPlace>[];

  final scored = <({CampusPlace place, int score})>[];
  final best = <String, int>{};

  for (final place in places) {
    int? top;
    for (final needle in needles) {
      final s = scorePlaceName(place.name, needle);
      if (s != null && (top == null || s > top)) top = s;
    }
    if (top == null) continue;

    // 同名地点（数据里有重复条目）只留分最高的那条
    final prev = best[place.name];
    if (prev != null) {
      if (top <= prev) continue;
      scored.removeWhere((e) => e.place.name == place.name);
    }
    best[place.name] = top;
    scored.add((place: place, score: top));
  }

  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    // 同分按名字里的数字排：第二学生公寓一号楼 → 二号楼 → 三号楼
    final byNumber = _compareNumbers(a.place.name, b.place.name);
    if (byNumber != 0) return byNumber;
    // 同分时短名字靠前（「第二食堂」比「第二食堂二楼」更像用户要找的）
    final byLen = a.place.name.length.compareTo(b.place.name.length);
    if (byLen != 0) return byLen;
    return a.place.name.compareTo(b.place.name);
  });

  return <CampusPlace>[for (final e in scored.take(limit)) e.place];
}
