import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:project_usst/main.dart' as application;

/// Bounded two-second samples for the separate device acceptance entrypoint.
class RuntimeFrameWindow {
  RuntimeFrameWindow({this.capacity = 600}) : assert(capacity > 0);

  final int capacity;
  final List<int> _build = [];
  final List<int> _raster = [];
  int _observed = 0;

  void record(int buildMicros, int rasterMicros) {
    _observed++;
    if (_build.length >= capacity) return;
    _build.add(buildMicros);
    _raster.add(rasterMicros);
  }

  Map<String, int> take({int budgetMicros = 16667}) {
    int percentile(List<int> values, double quantile) =>
        values.isEmpty ? 0 : values[(values.length * quantile).ceil() - 1];
    _build.sort();
    _raster.sort();
    final result = {
      'observedFrames': _observed,
      'sampledFrames': _build.length,
      'frameBudgetUs': budgetMicros,
      'buildP50Us': percentile(_build, 0.5),
      'buildP95Us': percentile(_build, 0.95),
      'rasterP50Us': percentile(_raster, 0.5),
      'rasterP95Us': percentile(_raster, 0.95),
      'buildOverBudget': _build.where((v) => v > budgetMicros).length,
      'rasterOverBudget': _raster.where((v) => v > budgetMicros).length,
    };
    _build.clear();
    _raster.clear();
    _observed = 0;
    return result;
  }
}

/// Production builds continue to use lib/main.dart without this instrumentation.
void main() {
  final startup = Stopwatch()..start();
  final binding = WidgetsFlutterBinding.ensureInitialized();
  binding.waitUntilFirstFrameRasterized.then((_) {
    debugPrint(
      'LITANG_RUNTIME_FIRST_FRAME ${jsonEncode({'rasterizedCallbackElapsedUs': startup.elapsedMicroseconds})}',
    );
  });
  final window = RuntimeFrameWindow();
  binding.addTimingsCallback((List<FrameTiming> timings) {
    for (final timing in timings) {
      window.record(
        timing.buildDuration.inMicroseconds,
        timing.rasterDuration.inMicroseconds,
      );
    }
  });
  Timer.periodic(const Duration(seconds: 2), (_) {
    final views = binding.platformDispatcher.views;
    final hz = views.isEmpty ? 60.0 : views.first.display.refreshRate;
    final cache = PaintingBinding.instance.imageCache;
    final metrics = {
      'at': DateTime.now().toUtc().toIso8601String(),
      'mode': kProfileMode ? 'profile' : (kReleaseMode ? 'release' : 'debug'),
      ...window.take(budgetMicros: hz > 0 ? (1000000 / hz).round() : 16667),
      'imageCacheBytes': cache.currentSizeBytes,
      'liveImages': cache.liveImageCount,
    };
    debugPrint('LITANG_RUNTIME_METRICS ${jsonEncode(metrics)}');
  });
  application.main();
}
