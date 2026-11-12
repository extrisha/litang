import 'dart:async';

import 'package:flutter/foundation.dart';
import '../data/app_exception.dart';
import '../data/geo/radar_location.dart';
import '../data/auth/cas_client.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/internal/internal_settings.dart';
import '../data/internal/rollcall_watch_store.dart';
import '../data/lms/radar_target.dart';
import '../data/lms/rollcall_api.dart';
import '../data/lms/tronclass_auth.dart';
import 'rollcall_notifications.dart';
import 'rollcall_signer.dart';

/// 监控引擎的运行状态，给内部模式页展示。
@immutable
class RollcallMonitorState {
  const RollcallMonitorState({
    this.running = false,
    this.checking = false,
    this.lastCheckAt,
    this.lastMessage,
    this.lastError,
  });

  final bool running;
  final bool checking;
  final DateTime? lastCheckAt;

  /// 上一次检查的结果摘要，例如「发现 2 个签到，处理 1 个」。
  final String? lastMessage;

  /// 上一次检查的失败原因。
  final String? lastError;

  RollcallMonitorState copyWith({
    bool? running,
    bool? checking,
    DateTime? lastCheckAt,
    String? lastMessage,
    Object? lastError = _unset,
  }) {
    return RollcallMonitorState(
      running: running ?? this.running,
      checking: checking ?? this.checking,
      lastCheckAt: lastCheckAt ?? this.lastCheckAt,
      lastMessage: lastMessage ?? this.lastMessage,
      lastError: identical(lastError, _unset)
          ? this.lastError
          : lastError as String?,
    );
  }
}

const Object _unset = Object();

/// 签到监控（仅前台）。
///
/// 只要 App 在前台且内部模式开着监控，就按配置的间隔拉一次
/// `/api/radar/rollcalls`：
///   - 发现没处理过的签到 → 本地通知；
///   - 开了「自动雷达签到」且不是演练 → 按选定基准点直接提交；
///   - 每条点名只处理一次（[RollcallWatchStore] 持久化），提交失败也不重试。
///
/// 后台常驻不在这里做：Flutter 侧没有前台服务，锁屏后定时器会被系统挂起。
class RollcallMonitor {
  RollcallMonitor._();

  static final RollcallMonitor instance = RollcallMonitor._();

  final ValueNotifier<RollcallMonitorState> state =
      ValueNotifier<RollcallMonitorState>(const RollcallMonitorState());

  /// 最近的日志行（新的在前），给内部模式页看。
  final ValueNotifier<List<String>> log = ValueNotifier<List<String>>(
    const <String>[],
  );

  Timer? _timer;
  Duration? _interval;
  bool _busy = false;
  bool _paused = false;
  bool _listening = false;

  late final RollcallSigner _signer = RollcallSigner(
    log: _append,
    notify: _notify,
    deviceLocation: _deviceLocation,
    studentId: () => JwglAuth.instance.studentId,
  );

  bool get running => _timer != null;

  void _ensureListening() {
    if (_listening) return;
    _listening = true;
    InternalMode.instance.settings.addListener(() {
      unawaited(syncWithSettings());
    });
  }

  /// 按当前配置启动或停止（配置改变、App 启动时调用）。
  Future<void> syncWithSettings() async {
    _ensureListening();
    await InternalMode.instance.ensureLoaded();
    final settings = InternalMode.instance.settings.value;
    if (!settings.enabled || !settings.monitor || _paused) {
      await stop();
      return;
    }
    final interval = Duration(seconds: settings.intervalSeconds);
    if (_timer != null && _timer!.isActive && _interval == interval) {
      // 间隔没变（只是改了别的开关）就别重排计时，也别立刻再查一次
      state.value = state.value.copyWith(running: true);
      return;
    }
    _timer?.cancel();
    _interval = interval;
    _timer = Timer.periodic(interval, (_) => unawaited(checkNow()));
    state.value = state.value.copyWith(running: true);
    _append('监控已启动，每 ${settings.intervalSeconds} 秒检查一次');
    unawaited(checkNow());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _interval = null;
    if (state.value.running) {
      _append('监控已停止');
    }
    state.value = state.value.copyWith(running: false);
  }

  void onAppPaused() {
    _paused = true;
    unawaited(stop());
  }

  void onAppResumed() {
    _paused = false;
    unawaited(syncWithSettings());
  }

  /// 立刻检查一次（内部模式页的「立即检查」按钮也用它）。
  Future<void> checkNow() async {
    if (_busy) return;
    final settings = InternalMode.instance.settings.value;
    if (!settings.enabled || !settings.monitor) return;
    _busy = true;
    state.value = state.value.copyWith(checking: true);
    try {
      final client = await _client();
      final list = await RollcallApi(client).fetchOngoing();
      final store = RollcallWatchStore.instance;
      await store.prune(list.map((rollcall) => rollcall.id).toSet());

      final pending = list.where((rollcall) => rollcall.isSignable).toList();
      var acted = 0;
      for (final rollcall in pending) {
        if (await store.isHandled(rollcall.id)) continue;
        acted++;
        if (rollcall.isSelfRollcall && settings.submitsInsteadOfNotify) {
          await _signer.submitSelfRegistration(client, rollcall, settings);
        } else if (rollcall.isNumberRollcall &&
            settings.submitsNumberInsteadOfNotify) {
          await _signer.submitNumber(client, rollcall, settings);
        } else if (rollcall.isRadarRollcall &&
            settings.submitsInsteadOfNotify) {
          await _signer.submitRadar(client, rollcall, settings);
        } else {
          await store.record(rollcall.id, RollcallWatchState.notified);
          await _notify(
            settings,
            '${rollcall.courseName} 正在${rollcall.typeLabel}',
            '${rollcall.timeText} · 打开理堂去签到',
          );
          _append('通知：${rollcall.courseName} ${rollcall.typeLabel}');
        }
      }
      state.value = state.value.copyWith(
        checking: false,
        lastCheckAt: DateTime.now(),
        lastMessage: pending.isEmpty
            ? '没有进行中的签到'
            : '发现 ${pending.length} 个签到，新处理 $acted 个',
        lastError: null,
      );
    } catch (error) {
      final message = error is AppException ? error.message : '签到检查失败：$error';
      state.value = state.value.copyWith(
        checking: false,
        lastCheckAt: DateTime.now(),
        lastError: message,
      );
      _append('检查失败：$message');
    } finally {
      _busy = false;
    }
  }

  Future<void> _notify(
    InternalSettings settings,
    String title,
    String body,
  ) async {
    if (!settings.notify) return;
    await RollcallNotifications.instance.show(title: title, body: body);
  }

  Future<CasClient> _client() async {
    final auth = JwglAuth.instance;
    if (!auth.isLoggedIn) {
      await auth.restore().catchError((Object error) {
        debugPrint('[rollcall-monitor] 恢复登录失败：$error');
      });
    }
    if (auth.client == null) {
      throw const AppException(AppFailure.auth, '未登录教务系统，无法监控签到');
    }
    await TronclassAuth.instance.ensureLoggedIn();
    final client = auth.client;
    if (client == null) {
      throw const AppException(AppFailure.auth, '一网畅学登录失效，请重新登录');
    }
    return client;
  }

  /// 取一次设备定位；没权限 / 超时都返回 null，由调用方决定是否降级。
  ///
  /// 具体权限、系统开关、精度判断都在 [RadarLocationService] 里，
  /// 这里传 `prompt: false`：监控是后台行为，不弹窗。
  Future<DeviceLocation?> _deviceLocation() async {
    final result = await RadarLocationService.instance.locate(prompt: false);
    return result.location;
  }
  void _append(String line) {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    final next = <String>['$stamp $line', ...log.value];
    log.value = next.length > 60 ? next.sublist(0, 60) : next;
    debugPrint('[rollcall-monitor] $line');
  }

  @visibleForTesting
  void debugReset() {
    _timer?.cancel();
    _timer = null;
    _interval = null;
    _busy = false;
    _paused = false;
    _listening = false;
    _signer.reset();
    log.value = const <String>[];
    state.value = const RollcallMonitorState();
  }
}
