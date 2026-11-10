import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../app_theme.dart';
import '../data/map_calibration.dart';
import '../data/map_trace.dart';

/// 定位诊断页：同时显示「纯 GPS」与「系统融合定位」两路结果，
/// 采样 30 秒后给出各自的均值、散布和两者中心距，用于判断漂移来自哪一路。
///
/// 入口：地图页长按右下角定位按钮。
class MapDiagnosticsPage extends StatefulWidget {
  const MapDiagnosticsPage({super.key});

  @override
  State<MapDiagnosticsPage> createState() => _MapDiagnosticsPageState();
}

class _MapDiagnosticsPageState extends State<MapDiagnosticsPage> {
  static const Distance _distance = Distance();
  static const Duration _sampleDuration = Duration(seconds: 30);

  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<Position>? _fusedSub;

  Position? _gps;
  Position? _fused;

  bool _sampling = false;
  int _remaining = 0;
  Timer? _ticker;

  final List<Position> _gpsSamples = <Position>[];
  final List<Position> _fusedSamples = <Position>[];

  String? _error;
  String _report = '';

  @override
  void initState() {
    super.initState();
    _subscribe();
    MapCalibration.load().then((_) {
      if (mounted) setState(() {});
    });
    MapTraces.load().then(
      (_) {
        if (mounted) setState(() {});
      },
      onError: (Object _) {
        if (mounted) setState(() => _error = '路线历史读取失败，请检查本地存储后重试');
      },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _gpsSub?.cancel();
    _fusedSub?.cancel();
    super.dispose();
  }

  Future<void> _subscribe() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _error = '没有定位权限');
        return;
      }

      _gpsSub =
          Geolocator.getPositionStream(
            locationSettings: AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
              intervalDuration: const Duration(seconds: 1),
              forceLocationManager: true,
            ),
          ).listen(
            (p) {
              if (!mounted) return;
              setState(() => _gps = p);
              if (_sampling) _gpsSamples.add(p);
            },
            onError: (Object _) {
              if (mounted) setState(() => _error = 'GPS 定位中断，请检查系统定位服务');
            },
            cancelOnError: false,
          );

      _fusedSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
            ),
          ).listen(
            (p) {
              if (!mounted) return;
              setState(() => _fused = p);
              if (_sampling) _fusedSamples.add(p);
            },
            onError: (Object _) {
              if (mounted) setState(() => _error = '融合定位中断，请检查系统定位服务');
            },
            cancelOnError: false,
          );
    } catch (e) {
      if (mounted) setState(() => _error = '订阅定位失败：$e');
    }
  }

  void _startSampling() {
    if (_sampling) return;
    _gpsSamples.clear();
    _fusedSamples.clear();
    setState(() {
      _sampling = true;
      _remaining = _sampleDuration.inSeconds;
      _report = '';
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        timer.cancel();
        _finishSampling();
      }
    });
  }

  void _finishSampling() {
    setState(() {
      _sampling = false;
      _report = _buildReport();
    });
  }

  ({int count, double lat, double lng, double spread, double accuracy}) _stats(
    List<Position> samples,
  ) {
    if (samples.isEmpty) {
      return (count: 0, lat: 0, lng: 0, spread: 0, accuracy: 0);
    }
    var lat = 0.0;
    var lng = 0.0;
    for (final p in samples) {
      lat += p.latitude;
      lng += p.longitude;
    }
    lat /= samples.length;
    lng /= samples.length;

    final center = LatLng(lat, lng);
    var worst = 0.0;
    var sum = 0.0;
    for (final p in samples) {
      final d = _distance.as(
        LengthUnit.Meter,
        center,
        LatLng(p.latitude, p.longitude),
      );
      sum += d;
      if (d > worst) worst = d;
    }
    final accuracy = samples.map((p) => p.accuracy).reduce(math.min);
    return (
      count: samples.length,
      lat: lat,
      lng: lng,
      spread: sum / samples.length,
      accuracy: accuracy,
    );
  }

  String _buildReport() {
    final gps = _stats(_gpsSamples);
    final fused = _stats(_fusedSamples);
    final lines = <String>[
      '【定位诊断】',
      'GPS直连: n=${gps.count}, 平均偏离中心 ${gps.spread.toStringAsFixed(1)} m, '
          '最优精度 ${gps.accuracy.toStringAsFixed(1)} m',
      if (gps.count > 0)
        '  均值 ${gps.lat.toStringAsFixed(6)}, ${gps.lng.toStringAsFixed(6)}',
      '融合定位: n=${fused.count}, 平均偏离中心 ${fused.spread.toStringAsFixed(1)} m, '
          '最优精度 ${fused.accuracy.toStringAsFixed(1)} m',
      if (fused.count > 0)
        '  均值 ${fused.lat.toStringAsFixed(6)}, ${fused.lng.toStringAsFixed(6)}',
    ];
    if (gps.count > 0 && fused.count > 0) {
      final d = _distance.as(
        LengthUnit.Meter,
        LatLng(gps.lat, gps.lng),
        LatLng(fused.lat, fused.lng),
      );
      lines.add('两路中心相距: ${d.toStringAsFixed(1)} m');
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('定位诊断'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            '站在一个固定的位置别动，点“开始采样”，30 秒后把报告发出来。\n'
            '两路中心差得多，说明系统融合定位把点带偏了；两路都偏同一个方向，'
            '才说明是地图本身的问题。',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          _card('纯 GPS（forceLocationManager）', _gps, const Color(0xFF2E7D32)),
          const SizedBox(height: 12),
          _card('系统融合定位（GPS+Wi-Fi+基站）', _fused, const Color(0xFF1565C0)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _sampling ? null : _startSampling,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              _sampling ? '采样中… 还剩 $_remaining 秒' : '开始采样（30 秒）',
              style: const TextStyle(fontSize: 15),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '定位校准',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  MapCalibration.describe(),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '在地图页长按你所在的真实位置即可校准（需室外、精度 ≤25 m）。',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                if (MapCalibration.active) ...<Widget>[
                  const SizedBox(height: 8),
                  for (var i = 0; i < MapCalibration.samples.length; i++)
                    _calibrationRow(i, MapCalibration.samples[i]),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await Clipboard.setData(
                            ClipboardData(
                              text: MapCalibration.exportForSurvey(),
                            ),
                          );
                          if (!mounted) return;
                          messenger.showSnackBar(
                            const SnackBar(content: Text('标定点已复制，可直接粘贴发送')),
                          );
                        },
                        icon: const Icon(Icons.ios_share, size: 16),
                        label: const Text('导出标定点'),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            await MapCalibration.clear();
                          } catch (_) {
                            if (mounted) {
                              setState(() => _error = '标定点清除失败，请检查存储后重试');
                            }
                            return;
                          }
                          if (!mounted) return;
                          setState(() {});
                        },
                        child: const Text('清除全部'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '路线采集',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  MapTraces.count == 0
                      ? '还没有记录。在地图页点「录制」按钮开始走，走完再点一次停止。'
                      : '已记录 ${MapTraces.count} 条路线，可导出后发给开发方用于优化推荐。',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (MapTraces.count > 0)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await Clipboard.setData(
                            ClipboardData(text: await MapTraces.exportText()),
                          );
                        } catch (_) {
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('路线导出失败，请检查本地存储后重试'),
                              ),
                            );
                          }
                          return;
                        }
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(content: Text('路线记录已复制，可直接粘贴发送')),
                        );
                      },
                      icon: const Icon(Icons.ios_share, size: 16),
                      label: const Text('导出路线记录'),
                    ),
                  ),
              ],
            ),
          ),
          if (_report.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                _report,
                style: const TextStyle(fontSize: 12, height: 1.7),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _report));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('报告已复制')));
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('复制报告'),
            ),
          ],
        ],
      ),
    );
  }

  /// 单个标定点：显示时间、精度、偏移，并允许单独删除。
  Widget _calibrationRow(int index, MapCalibrationSample sample) {
    final (east, north) = MapCalibration.offsetOf(sample);
    final time =
        '${sample.savedAt.hour.toString().padLeft(2, '0')}:'
        '${sample.savedAt.minute.toString().padLeft(2, '0')}';
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '第 ${index + 1} 个 · $time · 精度 ${sample.accuracy.toStringAsFixed(0)} m · '
            '偏移 东${east.toStringAsFixed(0)} 北${north.toStringAsFixed(0)} m',
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: '删除这个标定点',
          onPressed: () async {
            try {
              await MapCalibration.removeAt(index);
            } catch (_) {
              if (mounted) setState(() => _error = '标定点删除失败，请检查存储后重试');
              return;
            }
            if (!mounted) return;
            setState(() {});
          },
        ),
      ],
    );
  }

  Widget _card(String title, Position? p, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (p == null)
            const Text(
              '等待定位…',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            )
          else ...<Widget>[
            Text(
              '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '精度 ±${p.accuracy.toStringAsFixed(1)} m · '
              '${DateTime.now().difference(p.timestamp).inSeconds} 秒前',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
