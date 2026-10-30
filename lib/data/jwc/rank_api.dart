import 'dart:convert';

import '../auth/cas_client.dart';
import 'pdf_text_extractor.dart';

class RankException implements Exception {
  RankException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 专业排名（从教务「专业排名证明」PDF 里解析出来）。
class RankInfo {
  const RankInfo({
    required this.rank,
    required this.total,
    required this.major,
    required this.rawText,
    required this.updatedAt,
  });

  final int rank;
  final int total;
  final String major;
  final String rawText;
  final DateTime updatedAt;

  double get percentile => total <= 0 ? 0 : (1 - rank / total) * 100;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'rank': rank,
    'total': total,
    'major': major,
    'rawText': rawText,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static RankInfo fromJson(Map<String, dynamic> json) => RankInfo(
    rank: (json['rank'] as num?)?.toInt() ?? 0,
    total: (json['total'] as num?)?.toInt() ?? 0,
    major: json['major'] as String? ?? '',
    rawText: json['rawText'] as String? ?? '',
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}

/// 生成「专业排名证明」PDF 并解析排名。
class RankApi {
  RankApi(this.client);

  final CasClient client;

  static const String _base = 'https://jwgl.usst.edu.cn/jwglxt';
  static const String _listUrl =
      'https://jwgl.usst.edu.cn/jwglxt/xszsdy/xszsdy_cxXszsdyIndex.html?doType=query&gnmkdm=N109835';
  static const String _rankTemplate = '10252-xsxxwh-zypmzm';

  static final RegExp _rankPattern = RegExp(
    r'该生在该专业现排名为第\s*(\d+)\s*名[，,]\s*该专业共有学生\s*(\d+)\s*名',
  );

  Future<RankInfo> fetch() async {
    final listResp = await client.getJson(
      Uri.parse(_listUrl),
      data: <String, String>{
        'page': '1',
        'rows': '20',
        'sidx': '',
        'sord': 'asc',
      },
    );
    final raw = listResp.data ?? '';
    if (!raw.trimLeft().startsWith('{')) {
      throw RankException('获取学生信息失败，请重新登录');
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final items = (map['items'] as List<dynamic>? ?? <dynamic>[]);
    if (items.isEmpty) {
      throw RankException('没有查到你的学籍信息');
    }
    final row = (items.first as Map).cast<String, dynamic>();
    final major = row['zymc']?.toString() ?? '';

    final params = <String, String>{
      'ids': row['xh_id']?.toString() ?? '',
      'gsdygx': _rankTemplate,
      'lx': 'xsxxwh',
      'jg_id': row['jg_id']?.toString() ?? '',
      'njdm_id': row['njdm_id']?.toString() ?? '',
      'zyh_id': row['zyh_id']?.toString() ?? '',
      'bh_id': row['bh_id']?.toString() ?? '',
      'xh': row['xh']?.toString() ?? '',
      'sfby_dm': row['sfby']?.toString() ?? '',
      'sfzx': row['sfzx']?.toString() ?? '',
      'sfgz': '0',
    };

    final count = await _post('/bysxxcx/xscjzbdy_cxXsCount.html', params);
    if (!count.contains('可打印')) {
      throw RankException(
        count.replaceAll('"', '').trim().isEmpty
            ? '教务暂时不允许打印排名证明'
            : count.replaceAll('"', '').trim(),
      );
    }
    final fileType = (await _post(
      '/bysxxcx/xscjzbdy_cxGswjlx.html',
      params,
    )).replaceAll('"', '').trim();
    if (fileType.isEmpty) {
      throw RankException('教务没有返回证明文件类型');
    }
    params['wjlx'] = fileType;
    final filePath = await _post('/bysxxcx/xscjzbdy_dyList.html', params);
    final path = _cleanPath(filePath);
    if (!path.contains('.pdf')) {
      throw RankException(path.isEmpty ? '生成排名证明失败' : path);
    }
    // dyList 返回的是 /jwglxt/... 的绝对路径，不能再拼 _base（会变成 /jwglxt/jwglxt/...）
    final url = resolvePdfUrl(path);
    final bytes = await client.downloadBytes(Uri.parse(url));
    final text = PdfTextExtractor.extract(bytes);
    final match = _rankPattern.firstMatch(text);
    if (match == null) {
      throw RankException('没有从证明里解析到排名信息');
    }
    return RankInfo(
      rank: int.parse(match.group(1)!),
      total: int.parse(match.group(2)!),
      major: major,
      rawText: text,
      updatedAt: DateTime.now(),
    );
  }

  Future<String> _post(String path, Map<String, String> data) async {
    final resp = await client.getJson(Uri.parse('$_base$path'), data: data);
    return resp.data ?? '';
  }

  /// 把 dyList 返回的路径拼成完整 URL（path 自带 /jwglxt 前缀）。
  /// 校验协议与主机，强制升级为 HTTPS 且限制为校内域名，防止向外部第三方泄露教务凭据。
  static String resolvePdfUrl(String path) {
    final trimmed = path.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null) {
        final host = uri.host.toLowerCase();
        if (host == 'jwgl.usst.edu.cn' || host.endsWith('.usst.edu.cn')) {
          return uri.replace(scheme: 'https').toString();
        }
        // 若第三方传入外部域名，强制去除外部主机，回落到官方教务地址
        final safePath = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
        return 'https://jwgl.usst.edu.cn$safePath';
      }
    }
    final normalized = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return 'https://jwgl.usst.edu.cn$normalized';
  }

  static String _cleanPath(String raw) {
    var text = raw.trim();
    if (text.startsWith('"') && text.endsWith('"')) {
      try {
        text = jsonDecode(text) as String;
      } catch (_) {
        // 保持原样
      }
    }
    text = text.replaceAll(r'\/', '/').replaceAll('"', '');
    return text.split('#').first.trim();
  }

  /// 从 PDF 文本里解析排名（单独暴露，方便测试）。
  static ({int rank, int total})? parseRank(String text) {
    final match = _rankPattern.firstMatch(text);
    if (match == null) {
      return null;
    }
    return (
      rank: int.parse(match.group(1)!),
      total: int.parse(match.group(2)!),
    );
  }
}
