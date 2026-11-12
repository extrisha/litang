import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// 学习通这几个接口返回的都是服务端渲染的 HTML（不是 JSON），字段散在属性和
/// class 里。这里用 DOM 解析代替正则：
///
/// - 属性顺序、单双引号、`&amp;` 转义、标签换行都不影响结果；
/// - 想取「第几个 li」「某个 class 下的文本」直接查，不用写 `[\s\S]*?`。
///
/// 调用方仍保留正则兜底：个别租户会换模板，DOM 查不到时回退。
class ChaoxingHtml {
  ChaoxingHtml._();

  /// 解析成 [Document]；拿不到就返回 null（调用方回退正则）。
  static Document? parse(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      return html_parser.parse(raw);
    } catch (_) {
      return null;
    }
  }

  /// 所有隐藏域（`input[type=hidden]`），`name` 或 `id` 作为 key。
  ///
  /// 课程主页里的 `enc` / `workEnc` / `examEnc` / `openc` / `cpi` 都从这里取，
  /// 以前要按 id 一个个正则匹配，遇到属性顺序变化就取不到。
  static Map<String, String> hiddenFields(String raw) {
    final doc = parse(raw);
    if (doc == null) return const <String, String>{};
    final out = <String, String>{};
    for (final input in doc.querySelectorAll('input')) {
      final type = (input.attributes['type'] ?? '').toLowerCase();
      if (type != 'hidden') continue;
      final value = input.attributes['value'] ?? '';
      final name = (input.attributes['name'] ?? '').trim();
      final id = (input.attributes['id'] ?? '').trim();
      if (name.isNotEmpty) out.putIfAbsent(name, () => value);
      if (id.isNotEmpty) out.putIfAbsent(id, () => value);
    }
    return out;
  }

  /// 作业列表里的一行。
  static List<ChaoxingWorkRow> workRows(String raw) {
    final doc = parse(raw);
    if (doc == null) return const <ChaoxingWorkRow>[];
    final rows = <ChaoxingWorkRow>[];
    // 真正的锚点是 `li[data]`：`data` 里是完整的作业详情 URL。
    // 不要求 onclick 里有 goTask(this)，移动端模板没有这个函数名。
    for (final li in doc.querySelectorAll('li[data]')) {
      final rawUrl = _attr(li, 'data');
      if (rawUrl.isEmpty) continue;
      final url = decodeEntities(rawUrl);
      final label = decodeEntities(_attr(li, 'aria-label'));
      final parts = label.split(';');
      var title = parts.first.trim();
      var status = parts.length > 1 ? parts.skip(1).join(';').trim() : '';

      final timeNode = li.querySelector('.time');
      final timeText = timeNode == null
          ? ''
          : collapseWhitespace(timeNode.text);

      if (title.isEmpty) {
        title = collapseWhitespace(li.querySelector('.overHidden2')?.text ?? '')
            .trim();
      }
      if (status.isEmpty) {
        status = collapseWhitespace(li.querySelector('.status')?.text ?? '')
            .trim();
      }
      if (title.isEmpty) title = '作业';

      rows.add(
        ChaoxingWorkRow(
          url: url,
          title: title,
          status: status,
          timeText: timeText,
          expired:
              li.querySelector('.icon-zy-g') != null ||
              li.outerHtml.contains('icon-zy-g'),
        ),
      );
    }
    return rows;
  }

  /// 课程列表里的一门课。
  static List<ChaoxingCourseRow> courseRows(String raw) {
    final doc = parse(raw);
    if (doc == null) return const <ChaoxingCourseRow>[];
    final rows = <ChaoxingCourseRow>[];

    // 形态一：`<li courseId clazzId personId>`（PC 版课程列表）
    for (final li in doc.querySelectorAll('li')) {
      final courseId = _attr(li, 'courseid');
      final classId = _attr(li, 'clazzid');
      if (courseId.isEmpty || classId.isEmpty) continue;
      final cpi = _attr(li, 'personid');
      final titleAttr = _attr(li, 'title');
      final title = titleAttr.isNotEmpty
          ? titleAttr
          : (li.querySelector('.course-name')?.text ?? '');
      final line2 = li.querySelector('.line2');
      final teacherAttr = line2 == null ? '' : _attr(line2, 'title');
      final teacher = teacherAttr.isNotEmpty
          ? teacherAttr
          : (line2?.text ?? '');
      final name = collapseWhitespace(decodeEntities(title)).trim();
      if (name.isEmpty) continue;
      rows.add(
        ChaoxingCourseRow(
          courseId: courseId,
          classId: classId,
          cpi: cpi,
          name: name,
          teacher: collapseWhitespace(decodeEntities(teacher)).trim(),
        ),
      );
    }
    if (rows.isNotEmpty) return dedupe(rows);

    // 形态二：`<a href="...stucoursemiddle?courseid=..&clazzid=..">`（mooc2 版）
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = decodeEntities(_attr(a, 'href'));
      final uri = Uri.tryParse(href);
      if (uri == null) continue;
      final courseId = uri.queryParameters['courseid'] ?? '';
      final classId = uri.queryParameters['clazzid'] ?? '';
      if (courseId.isEmpty || classId.isEmpty) continue;
      final titleAttr = _attr(a, 'title');
      final name = collapseWhitespace(
        decodeEntities(titleAttr.isNotEmpty ? titleAttr : a.text),
      ).trim();
      if (name.isEmpty) continue;
      rows.add(
        ChaoxingCourseRow(
          courseId: courseId,
          classId: classId,
          cpi: uri.queryParameters['cpi'] ?? '',
          name: name,
          teacher: '',
        ),
      );
    }
    return dedupe(rows);
  }

  /// 同一门课会在列表里出现两次（课程名入口 + 教师名入口），按
  /// `courseId + classId` 去重，保留第一个。
  static List<ChaoxingCourseRow> dedupe(List<ChaoxingCourseRow> rows) {
    final seen = <String>{};
    final out = <ChaoxingCourseRow>[];
    for (final row in rows) {
      if (seen.add('${row.courseId}:${row.classId}')) out.add(row);
    }
    return out;
  }

  /// 取属性值。
  ///
  /// `package:html` 会把属性名统一小写（`courseId` → `courseid`），所以两种
  /// 写法都要试；模板里大小写并不统一。
  static String _attr(Element element, String name) {
    final direct = element.attributes[name];
    if (direct != null) return direct.trim();
    final lower = name.toLowerCase();
    for (final entry in element.attributes.entries) {
      if ('${entry.key}'.toLowerCase() == lower) {
        return entry.value.trim();
      }
    }
    return '';
  }

  /// DOM 里已经被解析成实体的文本，需要的最小反转义。
  static String decodeEntities(String raw) {
    if (!raw.contains('&')) return raw;
    return raw
        .replaceAll('&amp;', '&')
        .replaceAll('&#38;', '&')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
  }

  /// 折叠连续的空白/换行（HTML 缩进很脏）。
  static String collapseWhitespace(String raw) {
    if (raw.isEmpty) return raw;
    return raw.replaceAll(RegExp(r'[\s\u00a0]+'), ' ').trim();
  }
}

/// 作业列表的一行（还没绑到具体课程上）。
class ChaoxingWorkRow {
  const ChaoxingWorkRow({
    required this.url,
    required this.title,
    required this.status,
    required this.timeText,
    required this.expired,
  });

  final String url;
  final String title;
  final String status;
  final String timeText;
  final bool expired;
}

/// 课程列表的一门课。
class ChaoxingCourseRow {
  const ChaoxingCourseRow({
    required this.courseId,
    required this.classId,
    required this.cpi,
    required this.name,
    required this.teacher,
  });

  final String courseId;
  final String classId;
  final String cpi;
  final String name;
  final String teacher;
}
