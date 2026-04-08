import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/schedule_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TOP-LEVEL FCM background handler — MUST be a top-level function (not inside
// a class) so it can run in a separate Dart isolate when the app is terminated.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // We only need to show a local notification here; the payload was already
  // crafted on the Firestore side (or by another device via DataService).
  await NotificationService()._showFcmNotification(message);
}

/// NotificationService — three local channels + FCM (push) integration.
///
/// Channels:
///   • eldercare_high_priority  → FCM data-only messages (requests, messages)
///   • eldercare_reminders      → scheduled local alarms shown to ELDERLY
///   • eldercare_caregiver      → quick-action / request alerts to CAREGIVERS
///   • eldercare_safezone       → "Are you OK?" prompt to ELDERLY
///
/// FCM is used so other-device events (elderly presses quick-action button →
/// caregiver gets notified; caregiver creates schedule → elderly gets reminded)
/// work even when the app is in the background or fully killed.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  // ── Callbacks ─────────────────────────────────────────────────────────────
  void Function()? _showSafeZoneDialogCallback;
  void setShowSafeZoneDialogCallback(void Function()? cb) =>
      _showSafeZoneDialogCallback = cb;

  void Function()? _elderlyOkCallback;
  void setElderlyOkCallback(void Function() cb) => _elderlyOkCallback = cb;

  void Function(String payload)? _alarmTapCallback;
  void setAlarmTapCallback(void Function(String payload)? cb) =>
      _alarmTapCallback = cb;

  /// Called when user taps the post-dismiss "View Schedule" notification.
  void Function()? _openScheduleCallback;
  void setOpenScheduleCallback(void Function()? cb) =>
      _openScheduleCallback = cb;

  /// Programmatically fire the "open schedule" callback (e.g. from AlarmService
  /// when the native onOpenSchedule method call arrives on a warm start).
  void triggerOpenSchedule() => _openScheduleCallback?.call();

  // ── Initialise ────────────────────────────────────────────────────────────
  Future<void> init() async {
    tz_data.initializeTimeZones();

    // Detect device timezone from Android so zonedSchedule fires at the
    // correct local time (without this tz.local defaults to UTC).
    try {
      const platform = MethodChannel('eldercare/ringtone');
      final tzName = await platform.invokeMethod<String>('getTimezone');
      if (tzName != null && tzName.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(tzName));
      }
    } catch (e) {
      debugPrint('NotificationService: Could not set timezone: $e');
    }

    // ── 1. flutter_local_notifications setup ─────────────────────────────
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: _onLocalNotificationBackgroundTapped,
    );

    // Request POST_NOTIFICATIONS permission (Android 13+).
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();

    // ── 2. Create notification channels (Android 8+) ──────────────────────
    await _createChannels();

    // ── 3. FCM permissions ( iOS + Android 13+ ) ──────────────────────────
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // ── 4. Register the top-level background handler ──────────────────────
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // ── 5. Foreground FCM messages (app is open) ──────────────────────────
    FirebaseMessaging.onMessage.listen(_showFcmNotification);

    // ── 6. FCM message tap while app was in background (not killed) ────────
    FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmTap);

    // ── 7. FCM message that launched the app from terminated state ─────────
    final initialMsg = await _fcm.getInitialMessage();
    if (initialMsg != null) {
      _handleFcmTap(initialMsg);
    }
  }

  // ── Create notification channels ──────────────────────────────────────────
  Future<void> _createChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    await android.createNotificationChannel(const AndroidNotificationChannel(
      'eldercare_high_priority',
      'ElderCare Alerts',
      description: 'Important real-time alerts (requests, messages)',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));

    await android.createNotificationChannel(const AndroidNotificationChannel(
      'eldercare_reminders',
      'Schedule Reminders',
      description: 'Your daily schedule reminders',
      importance: Importance.max,   // max required for fullScreenIntent
      playSound: true,
      enableVibration: true,
    ));

    // Dedicated high-priority alarm channel for full-screen task alarms.
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'eldercare_alarms',
      'Schedule Alarms',
      description: 'Full-screen alarm when task time is near',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));

    await android.createNotificationChannel(const AndroidNotificationChannel(
      'eldercare_caregiver',
      'Caregiver Alerts',
      description: 'Alerts when elderly need help',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));

    await android.createNotificationChannel(const AndroidNotificationChannel(
      'eldercare_safezone',
      'Safe Zone Alerts',
      description: 'Safety check when leaving home at unusual hours',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));
  }

  // ── FCM helpers ───────────────────────────────────────────────────────────

  /// Returns the FCM token for this device. Save to Firestore on each login
  /// so other devices can send notifications via Cloud Messaging.
  Future<String?> getFcmToken() => _fcm.getToken();

  /// Listen for token refreshes. Call this after login and save updated token.
  Stream<String> get onTokenRefresh => _fcm.onTokenRefresh;

  // ── Show a local notification from a FCM RemoteMessage ───────────────────
  /// Called both in foreground [FirebaseMessaging.onMessage] and in the
  /// background top-level handler [firebaseMessagingBackgroundHandler].
  Future<void> _showFcmNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;

    final title = notification?.title ?? data['title'] ?? 'ElderCare';
    final body  = notification?.body  ?? data['body']  ?? '';
    final channel = data['channel'] ?? 'eldercare_high_priority';
    final payload = data['payload'];

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channel,
        _channelName(channel),
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true,
        enableVibration: true,
      ),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  String _channelName(String id) {
    switch (id) {
      case 'eldercare_reminders': return 'Schedule Reminders';
      case 'eldercare_caregiver': return 'Caregiver Alerts';
      case 'eldercare_safezone':  return 'Safe Zone Alerts';
      default:                   return 'ElderCare Alerts';
    }
  }

  void _handleFcmTap(RemoteMessage message) {
    final payload = message.data['payload'];
    if (payload == 'safezone_ok') {
      _showSafeZoneDialogCallback?.call();
    }
    // Extend here for other deep-link payloads (e.g. 'open_requests').
  }

  // ── Local notification tap handler ────────────────────────────────────────
  static void _onLocalNotificationTapped(NotificationResponse details) async {
    final payload = details.payload ?? '';

    if (details.actionId == 'safezone_ok') {
      NotificationService()._elderlyOkCallback?.call();
    } else if (payload == 'safezone_ok') {
      NotificationService()._showSafeZoneDialogCallback?.call();
    } else if (payload.startsWith('alarm_fire||')) {
      // Alarm notification tapped — AlarmService.init() handles this via
      // getNotificationAppLaunchDetails() on the next cold-start check.
      // For warm-start (app already running), signal directly.
      NotificationService()._alarmTapCallback?.call(payload);
    } else if (payload == 'open_schedule') {
      // Post-dismiss "View Schedule" notification tapped while app is running.
      NotificationService()._openScheduleCallback?.call();
    }
  }

  @pragma('vm:entry-point')
  static void _onLocalNotificationBackgroundTapped(NotificationResponse details) {
    // Runs in a separate isolate; keep minimal.
    if (details.actionId == 'safezone_ok') {
      NotificationService()._elderlyOkCallback?.call();
    }
  }

  // ── Cold-launch detection ─────────────────────────────────────────────────
  /// Returns true when the app was cold-started by tapping a safe-zone
  /// notification body.  Call once after overlay is mounted.
  Future<bool> wasLaunchedFromSafeZoneNotification() async {
    // Check FCM initial message first (app was killed).
    final fcmInit = await _fcm.getInitialMessage();
    if (fcmInit != null && fcmInit.data['payload'] == 'safezone_ok') return true;

    // Fallback: local notification tap.
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return false;
    final payload = details.notificationResponse?.payload;
    final action  = details.notificationResponse?.actionId;
    return payload == 'safezone_ok' && (action == null || action.isEmpty);
  }

  /// Returns true when the app was cold-started by tapping the post-dismiss
  /// "View Schedule" notification (i.e. after alarm was turned off while app
  /// was closed or in background).
  ///
  /// Checks both:
  ///   1. flutter_local_notifications launch details (payload == 'open_schedule')
  ///   2. Native MainActivity flag (notif_payload == 'open_schedule' via intent extra)
  Future<bool> wasLaunchedFromScheduleNotification() async {
    // First check flutter_local_notifications (Flutter-issued notification tap).
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details != null && details.didNotificationLaunchApp) {
      final payload = details.notificationResponse?.payload;
      if (payload == 'open_schedule') return true;
    }
    // Also check the native pending flag (set by MainActivity when started via
    // the AlarmForegroundService-issued "View Schedule" notification).
    try {
      const platform = MethodChannel('eldercare/ringtone');
      final pending = await platform.invokeMethod<bool>('getPendingOpenSchedule');
      if (pending == true) return true;
    } catch (_) {}
    return false;
  }

  /// Exposes the initial notification payload if the app was launched by tapping one,
  /// or if it was launched via a fullScreenIntent (which acts like a tap).
  Future<String?> getAppLaunchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details != null && details.didNotificationLaunchApp) {
      return details.notificationResponse?.payload;
    }
    return null;
  }

  // ── Schedule reminder (elderly only — local alarm) ────────────────────────
  /// Schedules a flutter_local_notifications alarm so the ELDERLY device is
  /// reminded at the right time even without an internet connection.
  /// Uses exactAllowWhileIdle + fullScreenIntent so it wakes the device.
  ///
  /// [userId] is embedded in the payload so the alarm screen can be shown
  /// correctly when the app is cold-started by tapping the notification.
  Future<void> scheduleReminderNotification(ScheduleItem item,
      {String userId = '', bool useAlarmScreen = true}) async {
    final notifyAt = item.scheduledTime
        .subtract(Duration(minutes: item.notifyMinutesBefore));
    if (notifyAt.isBefore(DateTime.now())) return;

    final tzNotifyAt = tz.TZDateTime.from(notifyAt, tz.local);
    // IMPORTANT: payload must use jsonEncode (not toString) so handleAlarmPayload
    // can correctly decode it on cold/warm start from a tapped notification.
    // When useAlarmScreen is false, use an empty payload so tapping the
    // notification does NOT trigger the alarm screen.
    final payload = useAlarmScreen
        ? 'alarm_fire||$userId||${jsonEncode(item.toJson())}'
        : '';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'eldercare_alarms',
        'Schedule Alarms',
        channelDescription: 'Full-screen alarm when task time is near',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true,
        enableVibration: true,
        fullScreenIntent: useAlarmScreen,   // ← only take over screen in alarm mode
        autoCancel: !useAlarmScreen,
      ),
    );
    final id = item.id.hashCode.abs() % 100000;
    await _plugin.zonedSchedule(
      id,
      '\u23f0 ${item.title}',
      item.notifyMinutesBefore > 0
          ? 'Starting in ${item.notifyMinutesBefore} min'
          : item.description,
      tzNotifyAt,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
    debugPrint('NotificationService: zonedSchedule set for "${item.title}" at $tzNotifyAt '
        '(useAlarmScreen=$useAlarmScreen)');
  }

  // ── Battery optimization exclusion ────────────────────────────────────────
  /// Asks Android to exclude this app from battery optimization so that
  /// exact alarms fire reliably even when the screen is off / Doze mode.
  /// On Chinese-brand ROMs (MIUI, ColorOS, etc.) this is required.
  Future<void> requestBatteryOptimizationExclusion() async {
    try {
      const platform = MethodChannel('eldercare/ringtone');
      await platform.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      debugPrint('NotificationService: battery opt request failed: $e');
    }
  }

  Future<void> cancelNotification(String itemId) async {
    await _plugin.cancel(itemId.hashCode.abs() % 100000);
  }

  // ── Caregiver instant alert (local — shown on THIS device) ───────────────
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

  // ── Safe-zone "Are you OK?" prompt (ELDERLY device, local) ───────────────
  Future<void> showElderlyCheckNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'eldercare_safezone', 'Safe Zone Alerts',
      channelDescription: 'Safety check when leaving home at unusual hours',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
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
      999999,
      '🏠 Are you OK?',
      'You appear to have left home. Tap "I\'m OK" if you are safe.',
      details,
      payload: 'safezone_ok',
    );
  }

  Future<void> cancelElderlyCheck() async {
    await _plugin.cancel(999999);
  }

  // ── Generic push-style local notification (called by DataService) ─────────
  /// Shows an immediate local notification. Use this when a Firestore stream
  /// (running in the foreground) detects a new request/schedule and wants to
  /// alert THIS device right away.
  Future<void> showInstantAlert({
    required String title,
    required String body,
    String channel = 'eldercare_high_priority',
    String? payload,
    bool fullScreenIntent = false,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channel,
        _channelName(channel),
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true,
        enableVibration: true,
        fullScreenIntent: fullScreenIntent,
      ),
    );
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  // ── Post-dismiss "View Schedule" notification ─────────────────────────────
  /// Shows a persistent notification after the user dismisses an alarm.
  /// Tapping it navigates to the Schedule page. Works whether the app is
  /// open (warm) or closed (cold) at the moment of dismissal.
  Future<void> showViewScheduleNotification({String taskTitle = ''}) async {
    final title = taskTitle.isNotEmpty
        ? '✅ Done: $taskTitle'
        : '✅ Alarm dismissed';
    const body = 'Tap to view your schedule';
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'eldercare_schedule_reminders',
        'Schedule Reminders',
        channelDescription: 'Your daily schedule reminders',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: false,
        enableVibration: false,
        autoCancel: true,
      ),
    );
    // Use a fixed ID so repeated dismissals replace the previous notification.
    await _plugin.show(88888, title, body, details, payload: 'open_schedule');
  }
}
