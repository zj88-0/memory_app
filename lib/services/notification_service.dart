import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/schedule_model.dart';

/// NotificationService — three channels:
/// • eldercare_reminders  → schedule alerts shown to ELDERLY (local device)
/// • eldercare_caregiver  → quick-action alerts shown to CAREGIVERS (local device)
/// • eldercare_safezone   → "Are you OK?" check shown to ELDERLY when safe-zone breach
///
/// In a real multi-device setup these would be push notifications (FCM).
/// Role filtering is done by the caller before calling these methods.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // ── callback: called when the elderly taps the notification BODY (opens app)
  // to show the in-app dialog.  Register via setShowSafeZoneDialogCallback.
  void Function()? _showSafeZoneDialogCallback;
  void setShowSafeZoneDialogCallback(void Function()? cb) =>
      _showSafeZoneDialogCallback = cb;

  // ── callback: called when the elderly taps the "I'm OK" ACTION BUTTON
  // directly in the notification shade (app stays in background).
  // Register via [setElderlyOkCallback] from main.dart or auth_provider.
  void Function()? _elderlyOkCallback;
  void setElderlyOkCallback(void Function() cb) => _elderlyOkCallback = cb;

  Future<void> init() async {
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        if (details.actionId == 'safezone_ok') {
          // Elderly tapped the "I'm OK" action button directly in the
          // notification shade — confirm without opening the app.
          _elderlyOkCallback?.call();
        } else if (details.payload == 'safezone_ok') {
          // Elderly tapped the notification body to open the app —
          // show the in-app dialog so they can confirm visually.
          _showSafeZoneDialogCallback?.call();
        }
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Returns true when the app was cold-started by tapping a safe-zone
  /// notification (body tap, not the action button).  Call this once after
  /// the overlay widget is mounted so it can display the dialog.
  Future<bool> wasLaunchedFromSafeZoneNotification() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return false;
    final payload = details.notificationResponse?.payload;
    final action = details.notificationResponse?.actionId;
    // Body tap has payload but no actionId; action button has actionId.
    return payload == 'safezone_ok' && (action == null || action.isEmpty);
  }

  // ── Schedule reminder (elderly only) ──────────────────────────────────────
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

  // ── Caregiver instant alert ────────────────────────────────────────────────
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

  // ── Safe-zone "Are you OK?" prompt shown to the ELDERLY ───────────────────
  /// Displays a high-priority notification with an "I'm OK" action button.
  /// The elderly tapping the button fires [_elderlyOkCallback].
  Future<void> showElderlyCheckNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'eldercare_safezone', 'Safe Zone Alerts',
      channelDescription: 'Safety check when leaving home at unusual hours',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
      // Action button so the elderly can respond without opening the app.
      actions: [
        AndroidNotificationAction(
          'safezone_ok',
          "I'm OK",
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      999999, // fixed ID so we can cancel it
      '🏠 Are you OK?',
      'You appear to have left home. Tap "I\'m OK" if you are safe.',
      details,
      payload: 'safezone_ok',
    );
  }

  Future<void> cancelElderlyCheck() async {
    await _plugin.cancel(999999);
  }
}
