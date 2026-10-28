import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 扫一扫：识别老师屏幕上的签到二维码，返回原始内容。
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const <BarcodeFormat>[
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
    // Android 上识别到远处二维码时自动拉近；手动滑杆仍然可用。
    autoZoom: true,
  );
  bool _handled = false;
  double _zoom = 0;
  double _scaleStart = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _handled = true;
        unawaited(HapticFeedback.mediumImpact());
        Navigator.of(context).pop(raw.trim());
        return;
      }
    }
  }

  void _setZoom(double value) {
    final next = value.clamp(0.0, 1.0);
    if ((next - _zoom).abs() < 0.005) return;
    setState(() => _zoom = next);
    unawaited(
      _controller.setZoomScale(next).catchError((Object _) {
        // 相机还没初始化时忽略，等下一帧用户再拖即可。
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫码签到'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: <Widget>[
          IconButton(
            tooltip: '手电筒',
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
          IconButton(
            tooltip: '切换摄像头',
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // 双指捏合缩放，覆盖在预览上，不影响识别。
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onScaleStart: (_) => _scaleStart = _zoom,
              onScaleUpdate: (details) {
                if (details.pointerCount < 2) return;
                _setZoom(_scaleStart + (details.scale - 1) * 0.6);
              },
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 18),
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text(
                    '将二维码放入取景框内，双指缩放或拖动滑杆放大',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.zoom_out,
                        size: 18,
                        color: Colors.white70,
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                            overlayColor: Colors.white12,
                            trackHeight: 2,
                          ),
                          child: Slider(
                            value: _zoom,
                            onChanged: _setZoom,
                            onChangeEnd: (_) => _controller.setZoomScale(_zoom),
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.zoom_in,
                        size: 18,
                        color: Colors.white70,
                      ),
                      SizedBox(
                        width: 42,
                        child: Text(
                          '${(_zoom * 100).round()}%',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '重置缩放',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _setZoom(0);
                          unawaited(_controller.resetZoomScale());
                        },
                        icon: const Icon(
                          Icons.restart_alt,
                          size: 18,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
