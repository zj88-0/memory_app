/// Stores the per-user alarm-screen preferences.
///
/// Fields:
///   [useAlarmScreen]   – true  → full-screen alarm overlay (default: true)
///                        false → plain OS notification only
///   [ringtoneUri]      – content:// URI of the chosen ringtone from the
///                        Android ringtone picker.  null → system default.
///   [snoozeMinutes]    – how long a snooze delays the alarm (default: 5).
class AlarmPrefs {
  final bool useAlarmScreen;
  final String? ringtoneUri;
  final int snoozeMinutes;

  const AlarmPrefs({
    this.useAlarmScreen = true,
    this.ringtoneUri,
    this.snoozeMinutes = 5,
  });

  AlarmPrefs copyWith({
    bool? useAlarmScreen,
    String? ringtoneUri,
    int? snoozeMinutes,
    bool clearRingtone = false,
  }) =>
      AlarmPrefs(
        useAlarmScreen: useAlarmScreen ?? this.useAlarmScreen,
        ringtoneUri: clearRingtone ? null : (ringtoneUri ?? this.ringtoneUri),
        snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      );

  Map<String, dynamic> toJson() => {
        'useAlarmScreen': useAlarmScreen,
        'ringtoneUri': ringtoneUri,
        'snoozeMinutes': snoozeMinutes,
      };

  factory AlarmPrefs.fromJson(Map<String, dynamic> json) => AlarmPrefs(
        useAlarmScreen: json['useAlarmScreen'] as bool? ?? true,
        ringtoneUri: json['ringtoneUri'] as String?,
        snoozeMinutes: json['snoozeMinutes'] as int? ?? 5,
      );
}
