/// SafeZone settings stored per elderly user, persisted via DataService.
class SafeZoneSettings {
  final String elderlyId;
  final bool enabled;
  final double? homeLat;
  final double? homeLng;

  /// Radius in metres. Use 10 for testing, 500 for production.
  final double radiusMeters;

  /// Sleeping window — alerts outside these hours are "abnormal-time" events.
  final int sleepStartHour; // 0-23, e.g. 22 = 10 PM
  final int sleepEndHour;   // 0-23, e.g. 7  =  7 AM

  /// Whether we are currently waiting for the elderly's "I'm OK" response.
  final bool awaitingConfirmation;

  const SafeZoneSettings({
    required this.elderlyId,
    this.enabled = false,
    this.homeLat,
    this.homeLng,
    this.radiusMeters = 10, // 10 m for testing (change to 500 for production)
    this.sleepStartHour = 22,
    this.sleepEndHour = 7,
    this.awaitingConfirmation = false,
  });

  bool get hasHome => homeLat != null && homeLng != null;

  /// Returns true when the current wall-clock hour falls in the sleeping window.
  bool get isAbnormalTime {
    final h = DateTime.now().hour;
    if (sleepStartHour > sleepEndHour) {
      // e.g. 22 → 7: crosses midnight
      return h >= sleepStartHour || h < sleepEndHour;
    }
    return h >= sleepStartHour && h < sleepEndHour;
  }

  Map<String, dynamic> toJson() => {
        'elderlyId': elderlyId,
        'enabled': enabled,
        'homeLat': homeLat,
        'homeLng': homeLng,
        'radiusMeters': radiusMeters,
        'sleepStartHour': sleepStartHour,
        'sleepEndHour': sleepEndHour,
        'awaitingConfirmation': awaitingConfirmation,
      };

  factory SafeZoneSettings.fromJson(Map<String, dynamic> json) =>
      SafeZoneSettings(
        elderlyId: json['elderlyId'] as String,
        enabled: json['enabled'] as bool? ?? false,
        homeLat: (json['homeLat'] as num?)?.toDouble(),
        homeLng: (json['homeLng'] as num?)?.toDouble(),
        radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 10,
        sleepStartHour: json['sleepStartHour'] as int? ?? 22,
        sleepEndHour: json['sleepEndHour'] as int? ?? 7,
        awaitingConfirmation: json['awaitingConfirmation'] as bool? ?? false,
      );

  SafeZoneSettings copyWith({
    bool? enabled,
    double? homeLat,
    double? homeLng,
    double? radiusMeters,
    int? sleepStartHour,
    int? sleepEndHour,
    bool? awaitingConfirmation,
  }) =>
      SafeZoneSettings(
        elderlyId: elderlyId,
        enabled: enabled ?? this.enabled,
        homeLat: homeLat ?? this.homeLat,
        homeLng: homeLng ?? this.homeLng,
        radiusMeters: radiusMeters ?? this.radiusMeters,
        sleepStartHour: sleepStartHour ?? this.sleepStartHour,
        sleepEndHour: sleepEndHour ?? this.sleepEndHour,
        awaitingConfirmation: awaitingConfirmation ?? this.awaitingConfirmation,
      );
}
