import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/notice_rank.dart';
import 'package:project_usst/data/notice_source.dart';

/// 云端 notices.json 实测是 1.2 MB / 7500+ 条，这里造一份同量级的数据，
/// 验证「放到后台 isolate 解析」的结果与直接解析一致，并打印耗时参考。
void main() {
  String buildFeed(int count) {
    final notices = <Map<String, dynamic>>[
      for (var i = 0; i < count; i++)
        <String, dynamic>{
          'dept': i.isEven ? '教务处' : '研究生院',
          'title': '关于开展 2026 年度第 $i 批教学检查工作的通知',
          'kind': i % 3 == 0 ? '通知' : '新闻',
          'scope': 'school',
          'date': '2026-10-${(i % 28 + 1).toString().padLeft(2, '0')}',
          'url': 'https://jwc.usst.edu.cn/2026/1027/c$i/page.htm',
        },
    ];
    return jsonEncode(<String, dynamic>{
      'schemaVersion': 2,
      'updatedAt': '2026-10-27T10:00:00Z',
      'total': count,
      'notices': notices,
    });
  }

  test('同量级 feed：直接解析与 isolate 解析结果一致', () async {
    final raw = buildFeed(7500);
    debugPrint('构造数据: ${(raw.length / 1024 / 1024).toStringAsFixed(2)} MB');

    final sw = Stopwatch()..start();
    final direct = RemoteNoticeSource.parseFeed(raw);
    sw.stop();

    final sw2 = Stopwatch()..start();
    final viaCompute = await compute(RemoteNoticeSource.parseFeed, raw);
    sw2.stop();

    expect(direct, isNotNull);
    expect(viaCompute, isNotNull);
    expect(viaCompute!.notices.length, direct!.notices.length);
    expect(viaCompute.notices.first.title, direct.notices.first.title);

    debugPrint(
      '主线程直接解析: ${sw.elapsedMilliseconds} ms '
      '(这 ${sw.elapsedMilliseconds} ms 里 UI 是卡住的)',
    );
    debugPrint(
      'compute 总耗时: ${sw2.elapsedMilliseconds} ms '
      '(其中主线程只等待，不做解析)',
    );

    // 解析完之后首页还要排序一次，看看这一步值不值得一起挪走。
    final sw3 = Stopwatch()..start();
    final ranked = NoticeRanker.rank(direct.notices);
    sw3.stop();
    debugPrint(
      '主线程排序 ${direct.notices.length} 条: ${sw3.elapsedMilliseconds} ms '
      '(排序后 ${ranked.length} 条)',
    );

    // 拿到新数据后要把整份 feed 写回缓存，这一步同样是 jsonEncode。
    final sw4 = Stopwatch()..start();
    final encoded = jsonEncode(<String, dynamic>{
      'fetchedAt': DateTime.now().toIso8601String(),
      'notices': <Map<String, dynamic>>[
        for (final n in direct.notices)
          <String, dynamic>{
            'dept': n.dept,
            'kind': n.kind,
            'scope': n.scope,
            'title': n.title,
            'url': n.url,
            'date': n.publishedAt?.toIso8601String(),
          },
      ],
    });
    sw4.stop();
    debugPrint(
      '主线程编码缓存: ${sw4.elapsedMilliseconds} ms '
      '(${(encoded.length / 1024 / 1024).toStringAsFixed(2)} MB)',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
