import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// 签到监控用的本地通知通道（和作业提醒分开，方便单独关）。
class RollcallNotifications {
  RollcallNotifications._();

  static final RollcallNotifications instance = RollcallNotifications._();

  static const String _channelId = 'litang_rollcall';
  static const String _channelName = '签到提醒';
  static const String _channelDesc = '有新的课堂签到时提醒';

  /// 固定 id：新签到覆盖旧通知，不在通知栏堆一排。
  static const int _notificationId = 0x5A17;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _unavailable = false;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<bool> _ensureReady() async {
    if (_initialized) return true;
    if (_unavailable || !_supported) return false;
    try {
      tz_data.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      try {
        await android?.requestNotificationsPermission();
      } catch (_) {
        // 用户拒绝通知权限时监控照样跑，只是没有提醒
      }
      _initialized = true;
      return true;
    } catch (_) {
      _unavailable = true;
      return false;
    }
  }

  /// 弹一条签到提醒。同一时间只留最新一条。
  Future<void> show({required String title, required String body}) async {
    if (!await _ensureReady()) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        onlyAlertOnce: true,
        styleInformation: BigTextStyleInformation(''),
      ),
      iOS: DarwinNotificationDetails(),
    );
    try {
      await _plugin.show(
        id: _notificationId,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (_) {
      // 弹不出来不影响监控主流程
    }
  }

  Future<void> cancelAll() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: _notificationId);
    } catch (_) {
      // 忽略
    }
  }
}
