import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'services/auth_provider.dart';
import 'services/notification_service.dart';
import 'services/tts_service.dart';
import 'services/data_service.dart';
import 'services/safezone_service.dart';
import 'services/alarm_service.dart';          // ← NEW
import 'models/user_model.dart';
import 'utils/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/home/safezone_check_overlay.dart';
import 'screens/schedule/schedule_screen.dart'; // ← NEW

// ── Must be registered BEFORE Firebase is used in background isolate ─────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) =>
    firebaseMessagingBackgroundHandler(message);

// ── Global navigator key — lets AlarmService push the alarm screen ────────────
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

// ── Security overlay flag — true whenever the app is not in the foreground ────
// Flipped by _AppRootState's WidgetsBindingObserver. The MaterialApp builder
// listens to it and places a solid black Scaffold over all routes so no app
// content leaks through the app-switcher thumbnail or screen-wake preview.
final ValueNotifier<bool> _appObscured = ValueNotifier(false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await DataService().init();
  await NotificationService().init();
  await TtsService().init();
  await AlarmService().init();                 // ← NEW

  // Give AlarmService the navigator key so it can push alarm screen.
  AlarmService.navigatorKey = _navigatorKey;  // ← NEW

  // Wire the notification "I'm OK" action → SafeZoneService.confirmSafe()
  NotificationService().setElderlyOkCallback(() {
    SafeZoneService().confirmSafe();
  });

  // Wire alarm notification tap (warm-start: app already running) →
  // AlarmService so the full-screen alarm overlay is shown immediately.
  // Guard: only elderly users have alarms; silently ignore on caregiver devices.
  NotificationService().setAlarmTapCallback((payload) async {
    if (!AlarmService.isElderlyMode) return;
    await AlarmService().handleAlarmPayload(payload);
  });

  // Wire the post-dismiss "View Schedule" notification tap (warm-start).
  // The cold-start case is handled by _AppRootState after login.
  // Guard: only elderly users have schedule alarms; ignore for caregivers.
  NotificationService().setOpenScheduleCallback(() {
    if (!AlarmService.isElderlyMode) return;
    // Ensure checkMissedAlarms() on the opened ScheduleScreen does not
    // re-fire the alarm notification (the alarm was already dismissed).
    AlarmService().markAlarmHandledForSession();
    final nav = _navigatorKey.currentState;
    if (nav != null) {
      nav.push(MaterialPageRoute(builder: (_) => const ScheduleScreen()));
    }
  });

  // Request battery optimization exclusion so exact alarms fire reliably
  // even when the screen is off or the device is in Doze mode.
  // This shows a one-time system dialog; Android remembers the user's choice.
  await NotificationService().requestBatteryOptimizationExclusion();

  runApp(ElderCareApp(navigatorKey: _navigatorKey));
}

class ElderCareApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;  // ← NEW param
  const ElderCareApp({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider()..init(),
      child: Consumer<AuthProvider>(
        builder: (ctx, auth, _) {
          final locale = _localeFor(auth.currentUser?.preferredLanguage ?? 'en');
          _syncSafeZone(auth);

          return MaterialApp(
            navigatorKey: navigatorKey,         // ← NEW — wire the key
            title: 'ElderCare',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.theme,
            locale: locale,
            supportedLocales: const [
              Locale('en'),
              Locale('zh'),
              Locale('ms'),
              Locale('ta'),
            ],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: _AppRoot(auth: auth),
            // ── Security overlay ──────────────────────────────────────────────
            // Sits above every route (including pushed alarm / schedule screens).
            // Shows a plain black screen whenever the app is not in the
            // foreground so no content leaks through the OS app switcher or
            // the brief moment before the lock screen fully covers the window.
            builder: (context, child) {
              return ValueListenableBuilder<bool>(
                valueListenable: _appObscured,
                builder: (ctx, isObscured, _) {
                  return Stack(
                    children: [
                      child!,
                      if (isObscured)
                        const Scaffold(backgroundColor: Colors.black),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _syncSafeZone(AuthProvider auth) {
    final user = auth.currentUser;
    if (user == null || !auth.isLoggedIn) {
      SafeZoneService().stop();
      return;
    }
    if (user.role == UserRole.elderly) {
      SafeZoneService().start(user.id);
    } else {
      SafeZoneService().stop();
    }
  }

  Locale _localeFor(String code) {
    switch (code) {
      case 'zh': return const Locale('zh');
      case 'ms': return const Locale('ms');
      case 'ta': return const Locale('ta');
      default:   return const Locale('en');
    }
  }
}

class _AppRoot extends StatefulWidget {
  final AuthProvider auth;
  const _AppRoot({required this.auth});

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  StreamSubscription<void>? _notifSub;
  String? _lastUserId;
  // Whether we have already attempted to show a cold-start alarm this session.
  // This prevents the alarm re-appearing when _AppRoot rebuilds after auth.
  bool _coldAlarmAttempted = false;
  // Whether we have already handled the cold-start "View Schedule" tap.
  bool _coldScheduleTapHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // If the app was woken by an alarm while the phone was locked,
    // show the alarm screen as soon as the navigator frame is built.
    // We do this BEFORE auth so there is no black-screen delay.
    if (AlarmService().wasLaunchedFromColdAlarm && !_coldAlarmAttempted) {
      _coldAlarmAttempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AlarmService().showPendingOrMissedAlarm();
      });
    }
    _syncNotifStream();
    _uploadFcmToken();
  }

  @override
  void didUpdateWidget(_AppRoot old) {
    super.didUpdateWidget(old);
    _syncNotifStream();
  }

  /// Called every time the app lifecycle changes.
  /// When the app comes back to the foreground (e.g. user taps the alarm
  /// notification or the full-screen intent brings the app forward),
  /// we check for any pending alarm that fired while we were in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ── Security overlay ────────────────────────────────────────────────────
    // Show a solid black cover the instant the app loses focus so no content
    // is visible in the OS app-switcher snapshot or while the lock screen
    // animation is running. Remove it the moment the app is fully resumed.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _appObscured.value = true;
    } else if (state == AppLifecycleState.resumed) {
      _appObscured.value = false;

      // Only check for pending alarms when an elderly user is logged in.
      // Caregivers do not have alarms and this call must never trigger for them.
      if (widget.auth.isLoggedIn && widget.auth.isElderly) {
        // Small delay so the navigator is fully settled after resume.
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) AlarmService().showPendingOrMissedAlarm();
        });
      }
    }
  }

  void _syncNotifStream() {
    final userId = widget.auth.currentUser?.id;
    if (userId == _lastUserId) return;

    // Detect first-login (null → userId) to trigger missed-alarm check.
    final wasLoggedOut = _lastUserId == null && userId != null;
    _lastUserId = userId;

    _notifSub?.cancel();
    _notifSub = null;

    if (userId != null && userId.isNotEmpty) {
      _notifSub = DataService()
          .streamIncomingNotifications(userId)
          .listen((_) {});

      // ── Update the elderly-mode flag in AlarmService ──────────────────────
      // This is the single source of truth: all alarm callbacks check this
      // flag before doing anything, ensuring caregivers are completely excluded.
      AlarmService.isElderlyMode = widget.auth.isElderly;

      // Load alarm preferences ONLY for elderly users.
      if (widget.auth.isElderly) {
        DataService().getAlarmPrefs(userId).then((prefs) {
          AlarmService().updateAlarmPrefs(prefs);
        });
      }

      if (wasLoggedOut) {
        // Reset the session-handled flag so this login session's alarms work.
        // (The flag is set when user dismisses an alarm; each login is a new session.)
        AlarmService().resetSessionAlarmFlag();

        // After first successful login, show any alarm that fired while the
        // app was killed or in the background (cold-start case).
        // Guard: only relevant for elderly users.
        if (widget.auth.isElderly) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) AlarmService().showPendingOrMissedAlarm();
          });
        }

        // Cold-start: app was launched by tapping the post-dismiss
        // "View Schedule" notification (payload == 'open_schedule').
        // Navigate to ScheduleScreen once the navigator is ready.
        // Guard: only relevant for elderly users (caregivers never dismiss alarms).
        if (widget.auth.isElderly && !_coldScheduleTapHandled) {
          _coldScheduleTapHandled = true;
          NotificationService().wasLaunchedFromScheduleNotification().then((wasIt) {
            if (wasIt && mounted) {
              // The app was cold-started by tapping the post-dismiss
              // "View Schedule" notification. Mark the session as
              // alarm-handled BEFORE opening ScheduleScreen so that
              // checkMissedAlarms() on the stream does not re-fire the
              // alarm notification and create an infinite repeat loop.
              AlarmService().markAlarmHandledForSession();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final nav = _navigatorKey.currentState;
                if (nav != null && mounted) {
                  nav.push(MaterialPageRoute(
                    builder: (_) => const ScheduleScreen(),
                  ));
                }
              });
            }
          });
        }
      }
    } else {
      // User logged out — clear the elderly-mode flag so no alarm events
      // are processed until an elderly user logs in again.
      AlarmService.isElderlyMode = false;
    }
  }

  Future<void> _uploadFcmToken() async {
    final userId = widget.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final token = await NotificationService().getFcmToken();
      if (token != null) {
        await DataService().saveFcmToken(userId, token);
      }
      NotificationService().onTokenRefresh.listen((newToken) {
        DataService().saveFcmToken(userId, newToken);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AlarmService().wasLaunchedFromColdAlarm) {
      // The app was cold-started solely to show the alarm screen.
      // We return a loading screen here so that the app doesn't briefly flash 
      // the LoginScreen or HomeScreen before the alarm overlay is pushed.
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 16),
            ],
          ),
        ),
      );
    }
    
    if (!widget.auth.isLoggedIn) return const LoginScreen();
    return const SafeZoneCheckOverlay(child: HomeScreen());
  }
}
