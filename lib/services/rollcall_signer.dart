import '../data/auth/cas_client.dart';
import '../data/internal/internal_settings.dart';
import '../data/internal/rollcall_watch_store.dart';
import '../data/lms/radar_target.dart';
import '../data/lms/rollcall_api.dart';

/// 自动签到的「执行层」：按类型把一次点名签掉。
///
/// 这里只关心「怎么签」——人数闸门、取码、取坐标、提交、复核、落记录；
/// 什么时候该签（轮询、开关、去重）由 [RollcallMonitor] 决定。
///
/// 三个入口都遵守同一套约定：
///   - 前置条件不满足就**不提交也不落记录**，下一轮还能再试；
///   - 提交前先过「已签人数过半」的闸门（可关）；
///   - 提交后必须回查花名册，`on_call_fine` 才算成功；
///   - 提交成功但名单没更新记 `unknown`，失败也不用自动重试。
class RollcallSigner {
  RollcallSigner({
    required this.log,
    required this.notify,
    required this.deviceLocation,
    required this.studentId,
    RollcallWatchStore? store,
  }) : _store = store ?? RollcallWatchStore.instance;

  /// 写一行日志（内部模式页的日志区）。
  final void Function(String line) log;

  /// 发本地通知（内部模式里可以关掉）。
  final Future<void> Function(
    InternalSettings settings,
    String title,
    String body,
  )
  notify;

  /// 取设备定位（`prompt: false`，后台不弹窗）。
  final Future<DeviceLocation?> Function() deviceLocation;

  /// 当前教务学号，复核花名册用。
  final String? Function() studentId;

  final RollcallWatchStore _store;

  /// 已经提示过的点名，避免每轮都弹一次。
  final Set<String> _warned = <String>{};

  /// 每条点名上次记过的「已签/总数」，用来抑制重复日志。
  final Map<String, String> _gateLog = <String, String>{};

  void reset() {
    _warned.clear();
    _gateLog.clear();
  }
  /// 数字口令：先从花名册读码，读到就提交，再复核花名册。
  ///
  /// 读不到码不记「已处理」——等班里有人签上、口令出现在花名册里，
  /// 下一轮还能再试；只是通知只弹一次。
  Future<void> submitNumber(
    CasClient client,
    Rollcall rollcall,
    InternalSettings settings,
  ) async {
    final api = RollcallApi(client);
    final roster = await api.fetchRoster(rollcall);
    if (roster == null) {
      if (_warned.add('roster:${rollcall.id}')) {
        log('${rollcall.courseName}：读不到点名名单，暂不自动提交');
        await notify(
          settings,
          '${rollcall.courseName} 正在${rollcall.typeLabel}',
          '读不到点名名单，请手动签到',
        );
      }
      return;
    }
    if (settings.waitForMajority && !roster.isMajoritySigned) {
      _logWaiting(rollcall, roster);
      return;
    }
    final code = roster.numberCode;
    if (code == null) {
      if (_warned.add(rollcall.id)) {
        final reason = '花名册里没有数字口令，请手动输入';
        log('${rollcall.courseName}：$reason');
        await notify(
          settings,
          '${rollcall.courseName} 正在${rollcall.typeLabel}',
          reason,
        );
      }
      return;
    }

    final store = _store;
    log('${rollcall.courseName}：读到数字口令 $code，提交中');
    try {
      final result = await api.answerNumber(rollcall, code);
      await _recordSignOutcome(
        client,
        rollcall,
        settings,
        result: result,
        method: '数字口令',
        successDetail: '口令 $code · 花名册已确认',
      );
    } catch (error) {
      await store.record(rollcall.id, RollcallWatchState.unknown);
      log('数字签到异常，已停止重试：$error');
    }
  }

  /// 自主签到：空 `{}` 直接提交，再复核花名册。
  Future<void> submitSelfRegistration(
    CasClient client,
    Rollcall rollcall,
    InternalSettings settings,
  ) async {
    if (!await _majorityGate(client, rollcall, settings)) return;
    final store = _store;
    log('${rollcall.courseName}：自主签到提交中');
    try {
      final result = await RollcallApi(client).answerSelfRegistration(rollcall);
      await _recordSignOutcome(
        client,
        rollcall,
        settings,
        result: result,
        method: '自主签到',
        successDetail: '花名册已确认',
      );
    } catch (error) {
      await store.record(rollcall.id, RollcallWatchState.unknown);
      log('自主签到异常，已停止重试：$error');
    }
  }

  /// 「已签人数过半」闸门。返回 true 表示可以提交。
  ///
  /// 没开这个限制就直接放行；开了但读不到名单时**不放行**——
  /// 读不到就没法确认人数，宁可这一轮不签，下一轮再试。
  Future<bool> _majorityGate(
    CasClient client,
    Rollcall rollcall,
    InternalSettings settings,
  ) async {
    if (!settings.waitForMajority) return true;
    final roster = await RollcallApi(client).fetchRoster(rollcall);
    if (roster == null || roster.total <= 0) {
      if (_warned.add('roster:${rollcall.id}')) {
        log('${rollcall.courseName}：读不到点名名单，暂不自动提交');
      }
      return false;
    }
    if (!roster.isMajoritySigned) {
      _logWaiting(rollcall, roster);
      return false;
    }
    return true;
  }

  /// 记录「还在等人签」的进度，只在人数变化时写一行，避免每轮刷屏。
  void _logWaiting(Rollcall rollcall, RosterInfo roster) {
    final stamp = '${roster.signed}/${roster.total}';
    if (_gateLog[rollcall.id] == stamp) return;
    _gateLog[rollcall.id] = stamp;
    log('${rollcall.courseName}：已签 $stamp，还没过半，继续等');
  }

  /// 提交之后的公共收尾：复核花名册 → 落记录 → 通知。
  ///
  /// 200 不算数：只有花名册里 `on_call_fine` 才算签上。
  /// 提交被受理但名单还没更新时记 `unknown`：不重试、也不谎报成功。
  Future<void> _recordSignOutcome(
    CasClient client,
    Rollcall rollcall,
    InternalSettings settings, {
    required SignResult result,
    required String method,
    required String successDetail,
  }) async {
    final api = RollcallApi(client);
    final me = studentId() ?? '';
    final recheck = me.isEmpty ? null : await api.recheckAttendance(rollcall, me);
    final confirmed = recheck?.success ?? result.success;
    final state = confirmed
        ? RollcallWatchState.confirmed
        : result.success
        ? RollcallWatchState.unknown
        : RollcallWatchState.rejected;
    await _store.record(rollcall.id, state);
    final detail = recheck?.message ?? result.message;
    log(
      '$method ${rollcall.courseName}：'
      '${confirmed ? '成功' : (result.success ? '已提交待确认' : '失败')}'
      '${confirmed || detail == null ? '' : '（$detail）'}',
    );
    await notify(
      settings,
      confirmed
          ? '已自动签到：${rollcall.courseName}'
          : '$method结果未确认：${rollcall.courseName}',
      confirmed ? successDetail : (detail ?? '已提交，请到一网畅学核对'),
    );
  }

  Future<void> submitRadar(
    CasClient client,
    Rollcall rollcall,
    InternalSettings settings,
  ) async {
    if (!await _majorityGate(client, rollcall, settings)) return;
    DeviceLocation? device;
    if (settings.radarMode == RadarLocationMode.auto ||
        settings.radarMode == RadarLocationMode.device) {
      device = await deviceLocation();
    }
    final target = resolveRadarTarget(
      rollcall: rollcall,
      mode: settings.radarMode,
      preferredBuildingId: settings.buildingId,
      devicePosition: device,
    );
    if (target == null) {
      if (_warned.add(rollcall.id)) {
        log('${rollcall.courseName}：没能确定基准点，本条不提交');
        await notify(
          settings,
          '${rollcall.courseName} 正在${rollcall.typeLabel}',
          '没能确定基准点（${settings.radarMode.name}），请手动签到',
        );
      }
      return;
    }

    final store = _store;
    try {
      final result = await RollcallApi(client).reportRadarPosition(
        rollcall,
        target.latitude,
        target.longitude,
        accuracy: target.accuracy,
      );
      await store.record(
        rollcall.id,
        result.success
            ? RollcallWatchState.confirmed
            : RollcallWatchState.rejected,
      );
      log(
        '自动签到 ${rollcall.courseName}：${result.success ? '成功' : '失败'}'
        '（${target.label}）${result.success ? '' : ' ${result.message ?? ''}'}',
      );
      await notify(
        settings,
        result.success
            ? '已自动签到：${rollcall.courseName}'
            : '自动签到失败：${rollcall.courseName}',
        result.success
            ? '${target.label} · ${rollcall.timeText}'
            : (result.message ?? '请手动签到'),
      );
    } catch (error) {
      // 请求结果未知：记成 unknown，之后不再自动重试（和参考实现一致）
      await store.record(rollcall.id, RollcallWatchState.unknown);
      log('自动签到异常，已停止重试：$error');
    }
  }

}
