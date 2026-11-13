import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app_theme.dart';
import '../../data/cache_store.dart';
import '../../data/lms/qr_diagnosis.dart';

/// 二维码「诊断模式」：只解剖，不发请求。
///
/// 设计约束（重要）：
///   - **全程零网络**。不调用 `answer_qr_rollcall`、不读花名册、不探会话。
///   - 目的是在一次真实签到**之前**把二维码载荷拆开看：格式、时间戳、
///     渠道 id、以及和设备时钟的偏差。
///   - 为什么必须先于签到：一旦自己已经 `on_call_fine`，再用同一枚 token
///     去提交，服务端会先回「已签」一类的结果，哈希校验的结果就被盖住了，
///     所以「签完再测」拿不到有效信息。诊断必须发生在提交之前、且不产生提交。
class QrDiagnosticPage extends StatefulWidget {
  const QrDiagnosticPage({super.key});

  @override
  State<QrDiagnosticPage> createState() => _QrDiagnosticPageState();
}

class _QrDiagnosticPageState extends State<QrDiagnosticPage> {
  static const String _storeKey = 'usst_qr_diag_v1';
  static const int _keep = 60;

  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  final List<QrSample> _samples = <QrSample>[];
  QrSample? _current;
  String? _lastRaw;
  bool _torch = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final entry = await CacheStore.read(_storeKey, secure: true);
      final data = entry?.data;
      if (data is List) {
        final restored = data
            .whereType<Map>()
            .map((row) => QrSample.fromJson(row.cast<String, dynamic>()))
            .whereType<QrSample>()
            .toList();
        if (!mounted) return;
        setState(() {
          _samples
            ..clear()
            ..addAll(restored);
          _current = restored.isEmpty ? null : restored.first;
          _loaded = true;
        });
        return;
      }
    } catch (_) {
      // 读不出来就当没历史
    }
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  Future<void> _persist() async {
    try {
      await CacheStore.write(
        _storeKey,
        _samples.map((sample) => sample.toJson()).toList(),
        secure: true,
      );
    } catch (_) {
      // 落盘失败只影响下次打开，不影响本次诊断
    }
  }

  void _absorb(String raw) {
    if (raw == _lastRaw) return;
    _lastRaw = raw;
    final sample = QrSample.analyze(raw, DateTime.now());
    setState(() {
      _samples.insert(0, sample);
      if (_samples.length > _keep) {
        _samples.removeRange(_keep, _samples.length);
      }
      _current = sample;
    });
    HapticFeedback.selectionClick();
    unawaited(_persist());
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      _absorb(raw);
      return;
    }
  }

  Future<void> _pasteRaw() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('粘贴二维码内容', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            hintText: '/j?p=0~...!3~<校验串>!4~...',
            hintStyle: TextStyle(fontSize: 11),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('诊断'),
          ),
        ],
      ),
    );
    if (raw == null || raw.isEmpty) return;
    _absorb(raw);
  }

  Future<void> _export() async {
    if (_samples.isEmpty) {
      _toast('还没有样本');
      return;
    }
    final text = const JsonEncoder.withIndent('  ').convert(
      <String, dynamic>{
        'exported_at': DateTime.now().toIso8601String(),
        'count': _samples.length,
        'samples': _samples.map((sample) => sample.toJson()).toList(),
      },
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toast('已复制 ${_samples.length} 枚样本的 JSON');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('二维码诊断'),
        actions: <Widget>[
          IconButton(
            tooltip: '粘贴内容',
            onPressed: _pasteRaw,
            icon: const Icon(Icons.content_paste),
          ),
          IconButton(
            tooltip: '导出样本',
            onPressed: _export,
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: '手电筒',
            onPressed: () async {
              await _controller.toggleTorch();
              setState(() => _torch = !_torch);
            },
            icon: Icon(_torch ? Icons.flashlight_on : Icons.flashlight_off),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '相机不可用：${error.errorCode.name}\n'
                  '${error.errorDetails?.message ?? ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white54, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 340),
              color: Colors.black.withValues(alpha: 0.78),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.visibility_off,
                          size: 14,
                          color: AppColors.successText,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '只读诊断：本页不发送任何请求',
                            style: TextStyle(
                              color: AppColors.successText,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${_samples.length} 枚',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (!_loaded)
                      const Text(
                        '正在读取历史…',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      )
                    else if (current == null)
                      const Text(
                        '对准签到二维码，或点右上角粘贴。\n'
                        '建议在真正提交之前先扫一枚，签完之后再扫同一枚『已签』会盖住校验结果。',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      )
                    else
                      _DiagnosisCard(sample: current, previous: _previousOf(current)),
                    if (_samples.length > 1) ...<Widget>[
                      const SizedBox(height: 12),
                      const Text(
                        '最近样本',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      for (final sample in _samples.take(4))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            sample.summaryLine,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 10.5,
                              fontFeatures: <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  QrSample? _previousOf(QrSample sample) {
    final index = _samples.indexOf(sample);
    if (index < 0 || index + 1 >= _samples.length) return null;
    return _samples[index + 1];
  }
}

class _DiagnosisCard extends StatelessWidget {
  const _DiagnosisCard({required this.sample, this.previous});

  final QrSample sample;
  final QrSample? previous;

  @override
  Widget build(BuildContext context) {
    final rows = sample.rows(previous: previous);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 72,
                  child: Text(
                    row.$1,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10.5,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: TextStyle(
                      color: row.$3 ? AppColors.danger : Colors.white,
                      fontSize: 11.5,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
