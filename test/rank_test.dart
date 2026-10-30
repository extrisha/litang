import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/jwc/pdf_text_extractor.dart';
import 'package:project_usst/data/jwc/rank_api.dart';

/// 造一个最小 PDF 结构：一个 ToUnicode CMap 流 + 一个内容流（不压缩）。
Uint8List _miniPdf({required List<int> contentBytes}) {
  final builder = BytesBuilder();
  void addStream(List<int> bytes) {
    builder.add(latin1.encode('stream\n'));
    builder.add(bytes);
    builder.add(latin1.encode('\nendstream\n'));
  }

  addStream(
    latin1.encode(
      '/CIDInit /ProcSet findresource begin\n'
      'begincmap\n'
      '1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n'
      '2 beginbfchar\n<0001> <4E13>\n<0002> <751F>\nendbfchar\n'
      'endcmap\n',
    ),
  );
  addStream(contentBytes);
  return builder.toBytes();
}

List<int> _content(List<int> payload) {
  final builder = BytesBuilder();
  builder.add(latin1.encode('BT /F1 12 Tf ('));
  builder.add(payload);
  builder.add(latin1.encode(') Tj ET'));
  return builder.toBytes();
}

void main() {
  group('PdfTextExtractor', () {
    test('从 CID 字符串 + ToUnicode 还原中文', () {
      final pdf = _miniPdf(
        contentBytes: _content(<int>[0x00, 0x01, 0x00, 0x02]),
      );
      expect(PdfTextExtractor.extract(pdf), contains('专生'));
    });

    test('十六进制字符串同样能还原', () {
      final pdf = _miniPdf(
        contentBytes: latin1.encode('BT /F1 12 Tf <00010002> Tj ET'),
      );
      expect(PdfTextExtractor.extract(pdf), contains('专生'));
    });

    test('没有 CMap 时返回空串（不抛异常）', () {
      final pdf = _miniPdf(contentBytes: _content(<int>[0x00, 0x01]));
      expect(PdfTextExtractor.extract(pdf), contains('专'));
    });
  });

  group('RankApi.resolvePdfUrl', () {
    test('不会重复拼接 /jwglxt', () {
      expect(
        RankApi.resolvePdfUrl('/jwglxt/templete/scorePrint//a.pdf'),
        'https://jwgl.usst.edu.cn/jwglxt/templete/scorePrint//a.pdf',
      );
      expect(
        RankApi.resolvePdfUrl('jwglxt/x.pdf'),
        'https://jwgl.usst.edu.cn/jwglxt/x.pdf',
      );
    });

    test('HTTP 协议自动升级为 HTTPS，保持教务域名', () {
      expect(
        RankApi.resolvePdfUrl('http://jwgl.usst.edu.cn/jwglxt/x.pdf'),
        'https://jwgl.usst.edu.cn/jwglxt/x.pdf',
      );
    });

    test('拦截外部未知域名并回落到官方教务地址', () {
      expect(
        RankApi.resolvePdfUrl('https://evil.example.com/scorePrint/x.pdf'),
        'https://jwgl.usst.edu.cn/scorePrint/x.pdf',
      );
      expect(
        RankApi.resolvePdfUrl('http://attacker.com/jwglxt/templete/a.pdf'),
        'https://jwgl.usst.edu.cn/jwglxt/templete/a.pdf',
      );
    });
  });

  group('RankApi.parseRank', () {
    test('解析中文排名句子', () {
      final result = RankApi.parseRank('该生在该专业现排名为第6名，该专业共有学生59名。');
      expect(result, isNotNull);
      expect(result!.rank, 6);
      expect(result.total, 59);
    });

    test('容忍空格与英文逗号', () {
      final result = RankApi.parseRank('该生在该专业现排名为第 12 名, 该专业共有学生 120 名');
      expect(result, isNotNull);
      expect(result!.rank, 12);
      expect(result.total, 120);
    });

    test('解析不到返回 null', () {
      expect(RankApi.parseRank('专业排名证明'), isNull);
      expect(RankApi.parseRank(''), isNull);
    });
  });
}
