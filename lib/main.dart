import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'services/auth_provider.dart';
import 'services/notification_service.dart';
import 'services/tts_service.dart';
import 'services/data_service.dart';
import 'utils/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DataService().init();
  await NotificationService().init();
  await TtsService().init();
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
    return const HomeScreen();
  }
}
