import 'dart:core';

import 'rollcall_qr.dart';

/// 一枚二维码的解码结果 + 本地诊断。**不含任何网络行为。**
class QrSample {
  const QrSample({
    required this.scannedAt,
    required this.raw,
    required this.kind,
    this.courseId,
    this.rollcallId,
    this.data,
    this.ts,
    this.notes = const <String>[],
  });

  final DateTime scannedAt;
  final String raw;
  final String kind;
  final int? courseId;
  final int? rollcallId;
  final String? data;

  /// `data` 前 10 位解出来的 unix 秒。
  final int? ts;
  final List<String> notes;

  static QrSample analyze(String raw, DateTime at) {
    final payload = QrPayload.parse(raw);
    final notes = <String>[];
    final data = payload?.data;
    int? ts;
    if (data != null && data.length >= 10) {
      final head = data.substring(0, 10);
      if (RegExp(r'^\d{10}$').hasMatch(head)) {
        ts = int.tryParse(head);
      } else {
        notes.add('前 10 位不是纯数字，不是已知的 unix 秒前缀');
      }
    }
    if (data != null && data.length != 42) {
      notes.add('data 长度 ${data.length}，与已观测的 42 不符');
    }
    if (data != null &&
        data.length > 10 &&
        !RegExp(r'^[0-9a-f]+$').hasMatch(data.substring(10).toLowerCase())) {
      notes.add('校验段含非 hex 字符');
    }
    for (final code in <String>['\u0010', '\u001a', '\u001e', '\u001f']) {
      if (raw.contains(code)) {
        notes.add('载荷含控制字符 U+${code.codeUnitAt(0).toRadixString(16)}（官方紧凑编码会这样）');
        break;
      }
    }
    if (payload == null) {
      notes.add('无法按已知格式解析');
    } else {
      if (payload.rollcallId == null) notes.add('载荷里没有 rollcallId');
      if (data == null || data.isEmpty) notes.add('载荷里没有 data');
    }
    return QrSample(
      scannedAt: at,
      raw: raw,
      kind: _kindOf(raw),
      courseId: payload?.courseId,
      rollcallId: payload?.rollcallId,
      data: data,
      ts: ts,
      notes: notes,
    );
  }

  static String _kindOf(String raw) {
    final text = raw.trim();
    if (text.startsWith('{')) return 'JSON';
    if (text.toLowerCase().startsWith('http') || text.contains('/j?p=')) {
      return 'URL';
    }
    if (text.contains('!') || text.contains('~') || text.contains('\u001f')) {
      return '紧凑载荷';
    }
    if (RegExp(r'^\d{10}[0-9a-fA-F]{32}$').hasMatch(text)) return '裸 token';
    return '未知';
  }

  int? get ageSeconds {
    final stamp = ts;
    if (stamp == null) return null;
    final generated = DateTime.fromMillisecondsSinceEpoch(stamp * 1000);
    return scannedAt.difference(generated).inSeconds;
  }

  String? get hash => (data != null && data!.length > 10)
      ? data!.substring(10).toLowerCase()
      : null;

  String get summaryLine {
    final age = ageSeconds;
    return '${_hms(scannedAt)}  ${kind.padRight(4)}  '
        'id=${rollcallId ?? '-'}  '
        'ts=${ts ?? '-'}  '
        '${age == null ? '' : '距今 ${age}s'}';
  }

  /// (字段名, 值, 是否异常) —— 给卡片直接渲染。
  List<(String, String, bool)> rows({QrSample? previous}) {
    final out = <(String, String, bool)>[];
    out.add(('格式', kind, false));
    out.add(('原始长度', '${raw.length}', false));
    out.add(('courseId', '${courseId ?? '-'}', false));
    out.add(('rollcallId', '${rollcallId ?? '-'}', roucallMissing));
    if (data == null) {
      out.add(('data', '缺失', true));
      return out;
    }
    out.add(('data', '${data!.length} 字符', data!.length != 42));
    final tail = hash;
    out.add((
      '校验段',
      tail == null
          ? '-'
          : (tail.length <= 12
                ? tail
                : '${tail.substring(0, 8)}…${tail.substring(tail.length - 4)}'),
      false,
    ));
    final stamp = ts;
    if (stamp == null) {
      out.add(('时间戳', '无法解析', true));
    } else {
      final generated = DateTime.fromMillisecondsSinceEpoch(stamp * 1000);
      out.add(('时间戳', '$stamp → ${_hms(generated)}', false));
      final age = ageSeconds!;
      out.add((
        '与设备时钟',
        age >= 0 ? '二维码比本机慢 ${age}s' : '二维码比本机快 ${-age}s',
        age.abs() > 120,
      ));
      out.add(('秒内偏移', 'ts % 10 = ${stamp % 10}', false));
    }
    final prev = previous;
    if (prev != null && prev.ts != null && ts != null) {
      final dTs = ts! - prev.ts!;
      final dWall = scannedAt.difference(prev.scannedAt).inMilliseconds / 1000;
      final sameSecond = dTs == 0;
      final sameHash = sameSecond && hash != null && hash == prev.hash;
      out.add((
        '与上一枚',
        'Δts=${dTs}s · Δ扫码=${dWall.toStringAsFixed(1)}s',
        false,
      ));
      if (sameSecond) {
        out.add((
          '同秒判定',
          sameHash
              ? '同秒且校验段相同 → 时间与密钥全决定，和课程/场次无关'
              : '同秒但校验段不同 → 掺了场次/随机量，不是纯 f(时间)',
          !sameHash,
        ));
      } else if (dTs > 0 && dTs == dWall.round() && dTs <= 3) {
        out.add(('轮换', 'Δts 跟上了真实时间 → 按秒生成', false));
      }
    }
    for (final note in notes) {
      out.add(('提示', note, true));
    }
    return out;
  }

  bool get roucallMissing => rollcallId == null;

  static String _hms(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'scanned_at': scannedAt.toIso8601String(),
    'raw': raw,
    'kind': kind,
    'course_id': courseId,
    'rollcall_id': rollcallId,
    'data': data,
    'ts': ts,
    'notes': notes,
  };

  static QrSample? fromJson(Map<String, dynamic> json) {
    final raw = '${json['raw'] ?? ''}';
    final at = DateTime.tryParse('${json['scanned_at'] ?? ''}');
    if (raw.isEmpty || at == null) return null;
    return QrSample(
      scannedAt: at,
      raw: raw,
      kind: '${json['kind'] ?? '未知'}',
      courseId: json['course_id'] is int ? json['course_id'] as int : null,
      rollcallId: json['rollcall_id'] is int
          ? json['rollcall_id'] as int
          : null,
      data: json['data'] as String?,
      ts: json['ts'] is int ? json['ts'] as int : null,
      notes: (json['notes'] as List?)?.map((note) => '$note').toList() ??
          const <String>[],
    );
  }
}
