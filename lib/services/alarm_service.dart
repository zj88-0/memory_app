import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alarm/alarm.dart';

import '../models/alarm_prefs.dart';
import '../models/schedule_model.dart';
import '../screens/schedule/schedule_alarm_screen.dart';
import 'notification_service.dart';
import 'data_service.dart';

/// AlarmService – schedules exact alarms for ScheduleItems.
///
/// TWO complementary layers:
///   1. `alarm` Flutter package  → reliable scheduling, Doze-exempt,
///      fires Alarm.ringStream in the main isolate when app is OPEN.
///   2. Native AlarmManager.setAlarmClock()  → fires AlarmReceiver →
///      AlarmForegroundService even when the app is FULLY KILLED; also
///      starts MainActivity so the Flutter alarm screen appears over the
///      lock screen (exactly like the device clock alarm).
///
/// Cross-isolate handover:
///   When Alarm.ringStream fires in a background isolate (app was killed or
///   backgrounded) `navigatorKey` is null there.  We persist the pending
///   ScheduleItem to SharedPreferences under [_pendingShowKey] so the
///   foreground UI isolate can read and display it once auth completes.
class AlarmService {
  static final AlarmService _instance = AlarmService._internal();
  factory AlarmService() => _instance;
  AlarmService._internal();

  static GlobalKey<NavigatorState>? navigatorKey;

  /// Set to true when an elderly user is logged in; false for caregivers /
  /// logged-out state.  All alarm operations are guarded behind this flag so
  /// the alarm feature never fires on a caregiver device.
  static bool isElderlyMode = false;

  AlarmPrefs _cachedPrefs = const AlarmPrefs();
  StreamSubscription<AlarmSettings>? _ringSubscription;

  // SharedPreferences key used to hand off across isolates.
  static const String _pendingShowKey = 'alarm_pending_show';

  // Native MethodChannel (same channel used by MainActivity).
  static const MethodChannel _channel = MethodChannel('eldercare/ringtone');

  // Track if we were launched specifically to show an alarm from a cold state.
  bool wasLaunchedFromColdAlarm = false;

  // ── In-memory dedup guards ────────────────────────────────────────────────
  // Prevents multiple alarm screens being pushed in the same app session.
  bool _isAlarmScreenShowing = false;
  // Prevents showPendingOrMissedAlarm from re-triggering after the alarm was
  // already handled (dismissed/snoozed) in the current session.
  bool _pendingAlarmHandledThisSession = false;
  // Timestamp of the last stopAlarm() call. Used to suppress the
  // didChangeAppLifecycleState.resumed re-trigger that fires immediately
  // after the alarm screen is dismissed (the system briefly pauses then
  // resumes the activity, which would cause a second alarm screen to appear).
  DateTime? _lastStopAlarmTime;
  // Prevents double-push of ScheduleScreen when both the native onOpenSchedule
  // channel call AND flutter_local_notifications tap callback fire for the
  // same "View Schedule" notification tap.
  bool _openScheduleInFlight = false;

  // ── Init ─────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await Alarm.init();

    // Listen for alarms ringing in the MAIN (UI) isolate.
    _ringSubscription = Alarm.ringStream.stream.listen(_onAlarmRinging);

    // Listen for the native "onAlarmPayload" method call that
    // MainActivity sends when a new alarm intent arrives via onNewIntent
    // (handles the case where app was already running in the background).
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAlarmPayload') {
        final payload = call.arguments as String?;
        if (payload != null && payload.isNotEmpty) {
          await handleAlarmPayload(payload);
        }
      } else if (call.method == 'onOpenSchedule') {
        // The native "View Schedule" notification was tapped while the app
        // was already running (warm-start via onNewIntent in MainActivity).
        // Guard against double-push: flutter_local_notifications may ALSO
        // fire _onLocalNotificationTapped for the same notification.
        if (!_openScheduleInFlight) {
          _openScheduleInFlight = true;
          markAlarmHandledForSession();
          NotificationService().triggerOpenSchedule();
          // Reset the flag after a short delay so future taps work.
          Future.delayed(const Duration(milliseconds: 500), () {
            _openScheduleInFlight = false;
          });
        }
      }
    });

    // ── Cold-start: check native alarm payload ────────────────────────────
    // When the app is fully killed and an alarm fires, AlarmForegroundService
    // (Layer 2) starts MainActivity with an "alarm_payload" intent extra.
    // MainActivity stores it as initialAlarmPayload; we read it here so it
    // is available via showPendingOrMissedAlarm() once auth completes.
    try {
      final nativePayload =
          await _channel.invokeMethod<String>('getInitialAlarmPayload');
      if (nativePayload != null && nativePayload.isNotEmpty) {
        wasLaunchedFromColdAlarm = true; // Set flag to block Home Screen
        // NOTE: isElderlyMode is not yet set at this point (auth resolves later).
        // We call _storeColdAlarmPayload() directly instead of handleAlarmPayload()
        // so the guard in handleAlarmPayload() does not prematurely discard the
        // payload.  Only elderly devices receive alarm_payload intents.
        await _storeColdAlarmPayload(nativePayload);
      }
    } catch (e) {
      debugPrint('AlarmService: getInitialAlarmPayload error: $e');
    }

    // ── Cold-start: check alarm package for past-due alarms ───────────────
    // If Alarm.ringStream fired in a background isolate before the UI was
    // ready, or if the alarm package did not fire the event at all (e.g. it
    // already removed the entry), scan Alarm.getAlarms() for anything whose
    // dateTime has passed and store it so showPendingOrMissedAlarm() can
    // display it.
    await _storeMissedAlarmIfAny();
  }

  void dispose() {
    _ringSubscription?.cancel();
    _ringSubscription = null;
  }

  // ── Ring handler (may be called from background isolate) ──────────────────

  void _onAlarmRinging(AlarmSettings alarmSettings) async {
    // Alarms are only for elderly users.  Guard here in case the ring-stream
    // fires on a caregiver device (should not happen, but belt-and-suspenders).
    if (!isElderlyMode) {
      debugPrint('AlarmService: isElderlyMode=false — ignoring ring event.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final itemJson = prefs.getString('alarm_json_${alarmSettings.id}');
    if (itemJson == null) return;

    // Mark as rang so checkMissedAlarms() doesn't re-trigger.
    await prefs.setBool('alarm_rang_${alarmSettings.id}', true);

    final nav = navigatorKey?.currentState;
    if (nav != null) {
      // Navigator is live – push directly.
      final item = ScheduleItem.fromJson(
          jsonDecode(itemJson) as Map<String, dynamic>);
      _pushAlarmScreen(item);
    } else {
      // Background isolate or navigator not yet mounted.
      // Only store if nothing is already pending (don't overwrite).
      if (!prefs.containsKey(_pendingShowKey)) {
        await prefs.setString(_pendingShowKey, itemJson);
      }
    }
  }

  // ── Scan for alarms whose time has passed (cold-start helper) ─────────────

  Future<void> _storeMissedAlarmIfAny() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    // Already something pending – don't overwrite.
    if (prefs.containsKey(_pendingShowKey)) return;

    for (final alarm in Alarm.getAlarms()) {
      if (alarm.dateTime.isAfter(now)) continue; // Not yet due.

      final alreadyRang = prefs.getBool('alarm_rang_${alarm.id}') ?? false;
      if (alreadyRang) continue; // Already handled, skip.

      final itemJson = prefs.getString('alarm_json_${alarm.id}');
      if (itemJson != null) {
        // Mark as rang immediately to prevent re-processing on next cold-start.
        await prefs.setBool('alarm_rang_${alarm.id}', true);
        await prefs.setString(_pendingShowKey, itemJson);
        break; // Store the first unhandled alarm; show one at a time.
      }
    }
  }

  // ── Called by _AppRootState after auth completes + nav is ready ───────────
  //
  // Shows the alarm screen for any alarm that fired while the app was
  // killed or backgrounded.  Call this:
  //   • once after a successful login (first userId seen)
  //   • whenever the app returns to the foreground (AppLifecycleState.resumed)

  Future<void> showPendingOrMissedAlarm() async {
    // If we already showed (and user dismissed/snoozed) an alarm this session,
    // don't re-show it when the app resumes or the schedule page opens.
    if (_pendingAlarmHandledThisSession) return;

    // Cooldown: ignore resumed events that fire within 3 seconds of stopAlarm().
    // Android briefly pauses and then resumes the activity as the alarm screen
    // is dismissed, which would otherwise trigger a second alarm screen.
    final stopTime = _lastStopAlarmTime;
    if (stopTime != null &&
        DateTime.now().difference(stopTime).inSeconds < 3) {
      debugPrint('AlarmService: showPendingOrMissedAlarm suppressed (within stop cooldown).');
      return;
    }

    final nav = navigatorKey?.currentState;
    if (nav == null) return;

    final prefs = await SharedPreferences.getInstance();

    // Check cross-isolate pending item (set by handleAlarmPayload / _storeMissedAlarmIfAny).
    final pendingJson = prefs.getString(_pendingShowKey);
    if (pendingJson != null) {
      await prefs.remove(_pendingShowKey);
      try {
        final item = ScheduleItem.fromJson(
            jsonDecode(pendingJson) as Map<String, dynamic>);
        _pushAlarmScreen(item);
      } catch (e) {
        debugPrint('AlarmService: Error showing pending alarm: $e');
      }
    }
    
    // Fallback scanner (checkMissedAlarms) was intentionally removed as it 
    // caused recursive popups. We rely on the native alarm execution exclusively.
  }

  /// Stores the cold-start alarm payload to SharedPreferences so that
  /// showPendingOrMissedAlarm() can pick it up once auth completes and the
  /// navigator is ready.
  ///
  /// This is intentionally separate from handleAlarmPayload() so it can be
  /// called during init() BEFORE isElderlyMode is known (the alarm_payload
  /// intent itself is proof enough this is an elderly device).
  Future<void> _storeColdAlarmPayload(String payload) async {
    try {
      final parts = payload.split('||');
      if (parts.length >= 3) {
        final itemJson = parts.sublist(2).join('||');
        final item = ScheduleItem.fromJson(
            jsonDecode(itemJson) as Map<String, dynamic>);
        final alarmId = item.id.hashCode.abs() % 0x7FFFFFFF;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('alarm_rang_$alarmId', true);
        // Store for showPendingOrMissedAlarm() once nav is ready.
        await prefs.setString(_pendingShowKey, itemJson);
      }
    } catch (e) {
      debugPrint('AlarmService: _storeColdAlarmPayload error: $e');
    }
  }

  // ── Handle payload from notification tap (warm / cold start) ─────────────

  Future<void> handleAlarmPayload(String payload) async {
    // Only handle alarm payloads for elderly users.
    if (!isElderlyMode) {
      debugPrint('AlarmService: isElderlyMode=false — ignoring alarm payload.');
      return;
    }
    try {
      final parts = payload.split('||');
      if (parts.length >= 3) {
        final itemJson = parts.sublist(2).join('||');
        final item = ScheduleItem.fromJson(
            jsonDecode(itemJson) as Map<String, dynamic>);

        // Mark as rang immediately so checkMissedAlarms() on the schedule
        // screen NEVER re-triggers this alarm after we have handled it.
        final alarmId = item.id.hashCode.abs() % 0x7FFFFFFF;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('alarm_rang_$alarmId', true);

        final nav = navigatorKey?.currentState;
        if (nav != null) {
          _pushAlarmScreen(item);
        } else {
          // Navigator not ready — store for showPendingOrMissedAlarm().
          await prefs.setString(_pendingShowKey, itemJson);
        }
      }
    } catch (e) {
      debugPrint('AlarmService: Error parsing alarm payload: $e');
    }
  }

  // ── Schedule ──────────────────────────────────────────────────────────────

  Future<void> scheduleAlarm(ScheduleItem item,
      {required String userId}) async {
    final alarmId = item.id.hashCode.abs() % 0x7FFFFFFF;
    final alarmTime =
        item.scheduledTime.subtract(Duration(minutes: item.notifyMinutesBefore));

    if (alarmTime.isBefore(DateTime.now())) return;

    // Persist item data so any isolate can look it up by alarm ID.
    final prefs = await SharedPreferences.getInstance();
    final itemJson = jsonEncode(item.toJson());
    final payload = 'alarm_fire||$userId||$itemJson';
    final body = item.description.isNotEmpty
        ? item.description
        : 'Time for your task!';
    await prefs.setString('alarm_title_$alarmId', item.title);
    await prefs.setString('alarm_userId_$alarmId', userId);
    await prefs.setString('alarm_itemId_$alarmId', item.id);
    await prefs.setString('alarm_json_$alarmId', itemJson);
    await prefs.setString('alarm_body_$alarmId', body);
    await prefs.setString('alarm_payload_$alarmId', payload);
    // Store trigger timestamp for BootReceiver rescheduling.
    await prefs.setInt('alarm_trigger_ms_$alarmId',
        alarmTime.millisecondsSinceEpoch);
    await prefs.setBool('alarm_useAlarmScreen_$alarmId', _cachedPrefs.useAlarmScreen);
    await prefs.setBool('alarm_rang_$alarmId', false);
    // Track active alarm ID so BootReceiver can reschedule after reboot.
    await _addToActiveAlarms(alarmId);

    if (_cachedPrefs.useAlarmScreen) {
      // The native layer provides robust lock-screen overlay and process-wakeup.
      try {
        await _channel.invokeMethod('scheduleNativeAlarm', {
          'id': alarmId,
          'triggerAtMs': alarmTime.millisecondsSinceEpoch,
          'title': item.title,
          'body': body,
          'payload': payload,
          'useAlarmScreen': true,
          'skipAudio': false, // Ensure native audio rings
        });
      } catch (e) {
        debugPrint('AlarmService: scheduleNativeAlarm failed (non-fatal): $e');
      }
      return; // DO NOT schedule via the flutter alarm package to avoid overlapping alarms/audio events.
    } else {
      // Notification-only mode.
      await NotificationService().scheduleReminderNotification(
          item, userId: userId, useAlarmScreen: false);
    }

    debugPrint('AlarmService: Scheduled alarm #$alarmId'
        ' for "${item.title}" at $alarmTime');
  }

  // ── Cancel ────────────────────────────────────────────────────────────────

  Future<void> cancelAlarm(String itemId) async {
    final alarmId = itemId.hashCode.abs() % 0x7FFFFFFF;

    await Alarm.stop(alarmId);

    // Also cancel the native AlarmManager alarm.
    try {
      await _channel.invokeMethod('cancelNativeAlarm', {'id': alarmId});
    } catch (e) {
      debugPrint('AlarmService: cancelNativeAlarm failed (non-fatal): $e');
    }

    await NotificationService().cancelNotification(itemId);

    // Clean up all persisted data for this alarm.
    final prefs = await SharedPreferences.getInstance();
    for (final suffix in [
      'json', 'rang', 'title', 'userId', 'itemId',
      'body', 'payload', 'trigger_ms', 'useAlarmScreen',
    ]) {
      await prefs.remove('alarm_${suffix}_$alarmId');
    }
    await _removeFromActiveAlarms(alarmId);
  }

  // ── Stop ringing alarm(s) ─────────────────────────────────────────────────

  Future<void> stopAlarm() async {
    // Mark as handled synchronously BEFORE any awaits so that if
    // didChangeAppLifecycleState.resumed fires while we are still in this
    // async method, it cannot sneak in a second alarm screen.
    _pendingAlarmHandledThisSession = true;
    _isAlarmScreenShowing = false;
    _lastStopAlarmTime = DateTime.now();

    final prefs = await SharedPreferences.getInstance();

    // Mark all flutter-package alarms that have already passed as rang.
    final now = DateTime.now();
    for (final alarm in Alarm.getAlarms()) {
      if (!alarm.dateTime.isAfter(now)) {
        await prefs.setBool('alarm_rang_${alarm.id}', true);
        await Alarm.stop(alarm.id);
      }
    }

    // ALSO mark native-only alarms as rang (they are tracked via the active
    // alarm IDs list and never appear in Alarm.getAlarms()).
    // This prevents checkMissedAlarms() from firing a second banner after
    // the user dismisses via the Flutter alarm screen.
    final raw = prefs.getString(_activeAlarmsKey);
    if (raw != null) {
      final ids = (jsonDecode(raw) as List).map<int>((e) => e as int);
      for (final id in ids) {
        final triggerMs = prefs.getInt('alarm_trigger_ms_$id');
        if (triggerMs != null && triggerMs <= now.millisecondsSinceEpoch) {
          await prefs.setBool('alarm_rang_$id', true);
        }
      }
    }

    // Clear any stored pending alarm so it won't re-show on next resume.
    await prefs.remove(_pendingShowKey);

    // Also stop the native foreground service.
    try {
      await _channel.invokeMethod('stopNativeAlarm');
    } catch (_) {}

    if (wasLaunchedFromColdAlarm) {
      // Tells the native side to drop lockscreen privileges and finish the activity.
      try {
        await _channel.invokeMethod('closeAlarmWindow');
      } catch (_) {}

      // Reset the flag in case the Flutter engine persists in memory after finish()
      wasLaunchedFromColdAlarm = false;
    }
  }

  // ── Snooze ────────────────────────────────────────────────────────────────

  Future<void> snoozeAlarm(ScheduleItem item,
      {String? userId, int snoozeMinutes = 5}) async {
    await stopAlarm();

    // Fetch userId from prefs if not provided.
    String resolvedUserId = userId ?? '';
    if (resolvedUserId.isEmpty) {
      resolvedUserId = DataService().getCurrentUserId() ?? '';
    }

    final snoozedItem = item.copyWith(
      scheduledTime: DateTime.now().add(Duration(minutes: snoozeMinutes)),
      notifyMinutesBefore: 0,
    );
    if (resolvedUserId.isNotEmpty) {
      await scheduleAlarm(snoozedItem, userId: resolvedUserId);
    }
  }

  // ── Missed-alarm window check (called from schedule screen) ───────────────

  /// Checks for alarms that should have fired but didn't (e.g. app was restarted
  /// within the alarm window). Instead of showing the full-screen alarm screen
  /// (which caused triple popups), this now only shows a notification banner.
  /// The user can tap the notification to open the alarm screen.
  Future<void> checkMissedAlarms(List<ScheduleItem> items,
      String userId) async {
    // If an alarm was already handled (shown + dismissed) this session,
    // do NOT fire a second notification — that is the double-trigger bug.
    if (_pendingAlarmHandledThisSession) return;

    // Also suppress if we are still within the stop-alarm cooldown window
    // (e.g. ScheduleScreen opens immediately after alarm dismissal because
    //  the user tapped the "View Schedule" notification).
    final stopTime = _lastStopAlarmTime;
    if (stopTime != null &&
        DateTime.now().difference(stopTime).inSeconds < 5) {
      debugPrint('AlarmService: checkMissedAlarms suppressed (within stop cooldown).');
      return;
    }

    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    for (final item in items) {
      if (item.isCompleted) continue;

      final alarmId = item.id.hashCode.abs() % 0x7FFFFFFF;
      final alarmTime =
          item.scheduledTime.subtract(Duration(minutes: item.notifyMinutesBefore));

      // Only alert within the notify window.
      final inWindow = !now.isBefore(alarmTime) &&
          now.isBefore(item.scheduledTime);
      if (!inWindow) continue;

      final alreadyRang = prefs.getBool('alarm_rang_$alarmId') ?? false;
      if (alreadyRang) continue;

      // Mark as rang immediately to prevent re-triggering.
      await prefs.setBool('alarm_rang_$alarmId', true);

      // Show an IMMEDIATE notification — do NOT push the alarm screen directly
      // here (avoids triple popups when the schedule stream emits multiple times).
      // scheduleReminderNotification won't work because the time has already
      // passed; use showInstantAlert instead so the user sees a banner now.
      // Tapping the notification will open the alarm screen via the tap callback.
      final useAlarmScreen = prefs.getBool('alarm_useAlarmScreen_$alarmId') ?? true;
      final payload = useAlarmScreen
          ? 'alarm_fire||$userId||${jsonEncode(item.toJson())}'
          : '';
      await NotificationService().showInstantAlert(
        title: '\u23f0 ${item.title}',
        body: item.description.isNotEmpty ? item.description : 'Time for your task!',
        channel: 'eldercare_alarms',
        payload: payload,
        fullScreenIntent: false, // notification-bar only; no automatic screen takeover
      );
    }
  }

  // ── Reschedule all ────────────────────────────────────────────────────────

  Future<void> rescheduleAll(String userId, List<ScheduleItem> items) async {
    for (final item in items) {
      if (!item.isCompleted) {
        await cancelAlarm(item.id);
        await scheduleAlarm(item, userId: userId);
      }
    }
  }

  // ── Prefs ─────────────────────────────────────────────────────────────────

  void updateAlarmPrefs(AlarmPrefs prefs) {
    _cachedPrefs = prefs;
  }

  /// Resets the session-level "alarm was already handled" flag.
  /// Call this on each new login so the user's alarms work correctly for
  /// the new session (e.g. after dismissing yesterday's alarm and logging out).
  void resetSessionAlarmFlag() {
    _pendingAlarmHandledThisSession = false;
  }

  /// Clears the "already rang" flag for [itemId] in SharedPreferences.
  /// Call this when a user redeployes a past/missed task with new timing
  /// so the new alarm is not silently skipped by checkMissedAlarms().
  Future<void> resetAlarmRangFlag(String itemId) async {
    final alarmId = itemId.hashCode.abs() % 0x7FFFFFFF;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alarm_rang_$alarmId', false);
    debugPrint('AlarmService: alarm_rang_$alarmId cleared (redeployed).');
  }

  /// Marks the current session as having already handled an alarm.
  /// Use this on a cold-start that was triggered by a post-dismiss
  /// "View Schedule" notification so that checkMissedAlarms() running
  /// on the subsequently opened ScheduleScreen does not fire a new
  /// alarm notification and create an infinite loop.
  void markAlarmHandledForSession() {
    _pendingAlarmHandledThisSession = true;
    _lastStopAlarmTime = DateTime.now();
    debugPrint('AlarmService: session manually marked as alarm-handled.');
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  void _pushAlarmScreen(ScheduleItem item) {
    // Dedup guard: only one alarm screen at a time.
    if (_isAlarmScreenShowing) {
      debugPrint('AlarmService: Alarm screen already showing, skipping duplicate push.');
      return;
    }
    final nav = navigatorKey?.currentState;
    if (nav == null) return;
    _isAlarmScreenShowing = true;
    nav.push(PageRouteBuilder(
      // opaque: true ensures the HomeScreen (and any other background route)
      // is NEVER rendered while the alarm screen is active.  With opaque: false
      // the previous route bled through during the fade-in — visible over the
      // lock screen because FLAG_SHOW_WHEN_LOCKED was still set on the window.
      opaque: true,
      barrierDismissible: false,
      pageBuilder: (_, __, ___) => ScheduleAlarmScreen(item: item),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    )).then((_) {
      // Screen was popped (dismissed/snoozed) — clear the flag.
      _isAlarmScreenShowing = false;
    });
  }

  static Future<void> showAlarmScreen(ScheduleItem item) async {
    final inst = AlarmService();
    if (inst._isAlarmScreenShowing) {
      debugPrint('AlarmService: Alarm screen already showing, skipping duplicate push.');
      return;
    }
    final nav = navigatorKey?.currentState;
    if (nav == null) return;
    inst._isAlarmScreenShowing = true;
    nav.push(PageRouteBuilder(
      // Same opaque: true fix as _pushAlarmScreen — prevents the background
      // route from rendering through the alarm screen over the lock screen.
      opaque: true,
      barrierDismissible: false,
      pageBuilder: (_, __, ___) => ScheduleAlarmScreen(item: item),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    )).then((_) {
      inst._isAlarmScreenShowing = false;
    });
  }

  // ── Active-alarm-ID tracking (for BootReceiver after reboot) ─────────────
  //
  // Flutter SharedPreferences stores keys prefixed with "flutter." on Android,
  // so BootReceiver.kt reads them with "flutter.alarm_active_ids" etc.

  static const String _activeAlarmsKey = 'alarm_active_ids';

  Future<void> _addToActiveAlarms(int alarmId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeAlarmsKey);
    final ids = raw != null
        ? (jsonDecode(raw) as List).map<int>((e) => e as int).toSet()
        : <int>{};
    ids.add(alarmId);
    await prefs.setString(_activeAlarmsKey, jsonEncode(ids.toList()));
  }

  Future<void> _removeFromActiveAlarms(int alarmId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeAlarmsKey);
    if (raw == null) return;
    final ids = (jsonDecode(raw) as List).map<int>((e) => e as int).toSet();
    ids.remove(alarmId);
    await prefs.setString(_activeAlarmsKey, jsonEncode(ids.toList()));
  }
}
