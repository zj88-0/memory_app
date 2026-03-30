import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/schedule_model.dart';

/// NotificationService — two channels:
/// • eldercare_reminders  → schedule alerts shown only to ELDERLY (local device)
/// • eldercare_caregiver  → quick-action alerts shown only to CAREGIVERS (local device)
///
/// In a real multi-device setup these would be push notifications (FCM).
/// For now, role filtering is done by the caller before calling these methods.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings,
        onDidReceiveNotificationResponse: (details) {});
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Schedule a reminder — call this ONLY on the elderly's device.
  Future<void> scheduleReminderNotification(ScheduleItem item) async {
    final notifyAt = item.scheduledTime
        .subtract(Duration(minutes: item.notifyMinutesBefore));
    if (notifyAt.isBefore(DateTime.now())) return;

    final tzNotifyAt = tz.TZDateTime.from(notifyAt, tz.local);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'eldercare_reminders', 'Schedule Reminders',
        channelDescription: 'Your daily schedule reminders',
        importance: Importance.max, priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true, enableVibration: true,
      ),
    );
    final id = item.id.hashCode.abs() % 100000;
    await _plugin.zonedSchedule(
      id, '⏰ ${item.title}',
      'In ${item.notifyMinutesBefore} min — ${item.description}',
      tzNotifyAt, details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelNotification(String itemId) async {
    await _plugin.cancel(itemId.hashCode.abs() % 100000);
  }

  /// Show an instant alert — call this ONLY on the caregiver's device.
  /// In a single-device dev environment this fires on the same phone;
  /// the role check in the caller prevents elderly from triggering this
  /// on their own device. With FCM you'd target only caregiver tokens.
  Future<void> showCaregiverAlert({
    required String title,
    required String body,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'eldercare_caregiver', 'Caregiver Alerts',
        channelDescription: 'Alerts when elderly need help',
        importance: Importance.max, priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true, enableVibration: true,
      ),
    );
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title, body, details,
    );
  }
}
