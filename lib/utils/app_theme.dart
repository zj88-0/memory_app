import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF2E7D9A);
  static const Color primaryLight = Color(0xFF4FB3D5);
  static const Color primaryDark = Color(0xFF1A5570);
  static const Color accent = Color(0xFFFF8C42);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFE53935);
  static const Color background = Color(0xFFF5F9FC);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF1A2C3A);
  static const Color textSecondary = Color(0xFF607D8B);

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: primary, brightness: Brightness.light).copyWith(
          primary: primary, secondary: accent, surface: surface, error: error,
        ),
        scaffoldBackgroundColor: background,
        appBarTheme: const AppBarTheme(
          backgroundColor: primary, foregroundColor: Colors.white, elevation: 0, centerTitle: true,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary, foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 58),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary, side: const BorderSide(color: primary, width: 2),
            minimumSize: const Size(double.infinity, 58),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFCFD8DC))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFCFD8DC))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: primary, width: 2)),
          labelStyle: const TextStyle(fontSize: 16, color: textSecondary),
        ),
        cardTheme: CardTheme(
          elevation: 3, shadowColor: primary.withOpacity(0.15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          color: Colors.white,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: textPrimary),
          headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: textPrimary),
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: textPrimary),
          titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textPrimary),
          bodyLarge: TextStyle(fontSize: 17, color: textPrimary),
          bodyMedium: TextStyle(fontSize: 15, color: textSecondary),
        ),
      );
}

class AppIcons {
  static const Map<String, IconData> iconMap = {
    'notifications': Icons.notifications_rounded,
    'medical': Icons.medical_services_rounded,
    'food': Icons.restaurant_rounded,
    'water': Icons.water_drop_rounded,
    'medicine': Icons.medication_rounded,
    'help': Icons.help_rounded,
    'phone': Icons.phone_rounded,
    'toilet': Icons.wc_rounded,
    'walk': Icons.directions_walk_rounded,
    'exercise': Icons.fitness_center_rounded,
    'sleep': Icons.bedtime_rounded,
    'bath': Icons.bathtub_rounded,
    'heart': Icons.favorite_rounded,
    'warning': Icons.warning_rounded,
    'emergency': Icons.emergency_rounded,
    'happy': Icons.sentiment_very_satisfied_rounded,
    'pain': Icons.sick_rounded,
  };

  static IconData getIcon(String name) => iconMap[name] ?? Icons.notifications_rounded;
}

class AppColors {
  static const List<Color> presetColors = [
    Color(0xFF2E7D9A), Color(0xFF4CAF50), Color(0xFFFF8C42), Color(0xFFE53935),
    Color(0xFF9C27B0), Color(0xFF3F51B5), Color(0xFF00BCD4), Color(0xFFFF5722),
    Color(0xFF607D8B), Color(0xFF795548), Color(0xFFF06292), Color(0xFF8BC34A),
  ];
}
