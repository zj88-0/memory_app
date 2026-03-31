import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'services/auth_provider.dart';
import 'services/notification_service.dart';
import 'services/tts_service.dart';
import 'services/data_service.dart';
import 'services/safezone_service.dart';
import 'models/user_model.dart';
import 'utils/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/home/safezone_check_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DataService().init();
  await NotificationService().init();
  await TtsService().init();

  // Wire the notification "I'm OK" action → SafeZoneService.confirmSafe()
  NotificationService().setElderlyOkCallback(() {
    SafeZoneService().confirmSafe();
  });

  runApp(const ElderCareApp());
}

class ElderCareApp extends StatelessWidget {
  const ElderCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider()..init(),
      child: Consumer<AuthProvider>(
        builder: (ctx, auth, _) {
          final locale = _localeFor(auth.currentUser?.preferredLanguage ?? 'en');

          // Start / stop SafeZone monitoring whenever the logged-in user changes.
          _syncSafeZone(auth);

          return MaterialApp(
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
      // SafeZoneService checks its own enabled flag before alerting.
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
      default: return const Locale('en');
    }
  }
}

class _AppRoot extends StatelessWidget {
  final AuthProvider auth;
  const _AppRoot({required this.auth});

  @override
  Widget build(BuildContext context) {
    if (!auth.isLoggedIn) return const LoginScreen();
    // Wrap the home screen with the safe-zone in-app overlay.
    // The overlay is transparent when no alert is active.
    return const SafeZoneCheckOverlay(child: HomeScreen());
  }
}
