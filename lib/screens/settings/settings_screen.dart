import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:geolocator/geolocator.dart';
import 'package:open_settings_plus/open_settings_plus.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../models/safezone_model.dart';
import '../../models/alarm_prefs.dart';
import '../../services/auth_provider.dart';
import '../../services/data_service.dart';
import '../../services/safezone_service.dart';
import '../../services/alarm_service.dart';
import '../../utils/app_theme.dart';
import '../auth/login_screen.dart';
import '../interests/interest_selection_screen.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final l10n = AppLocalizations.of(context)!;
    final user = auth.currentUser;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l10n.settings)),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ── Profile card ─────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.primary.withOpacity(0.3),
                          blurRadius: 14,
                          offset: const Offset(0, 6))
                    ],
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.white.withOpacity(0.25),
                      child: Text(
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text(user.email,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 14),
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                user.role == UserRole.elderly
                                    ? l10n.roleElderly
                                    : l10n.roleCaregiver,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 28),

                // ── Language ─────────────────────────────────────────────────
                _SectionHeader(title: l10n.language),
                const SizedBox(height: 10),
                _LanguageSelector(user: user, auth: auth, l10n: l10n),
                const SizedBox(height: 28),

                // ── Schedule Alarms (NEW) ─────────────────────────────────────
                _SectionHeader(title: l10n.scheduleAlarms),
                const SizedBox(height: 10),
                _AlarmPrefsSection(user: user, l10n: l10n),
                const SizedBox(height: 28),

                // ── Activity Recommendations ──────────────────────────────────
                _SectionHeader(title: l10n.activityRecommendations),
                const SizedBox(height: 10),
                _SettingsTile(
                  icon: Icons.interests_rounded,
                  label: l10n.editMyInterests,
                  color: const Color(0xFF7B61FF),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const InterestSelectionScreen(isEditing: true),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Safe Zone (elderly only) ──────────────────────────────────
                if (user.role == UserRole.elderly) ...[
                  _SectionHeader(title: l10n.safeZone),
                  const SizedBox(height: 10),
                  _SetHomeTile(user: user, l10n: l10n),
                  const SizedBox(height: 10),
                  _TestAlarmTile(user: user, l10n: l10n),
                  const SizedBox(height: 28),
                ],

                // ── Account ───────────────────────────────────────────────────
                _SectionHeader(title: l10n.account),
                const SizedBox(height: 10),
                _SettingsTile(
                  icon: Icons.person_rounded,
                  label: l10n.editName,
                  onTap: () => _editName(context, user, auth, l10n),
                ),
                const SizedBox(height: 10),
                _SettingsTile(
                  icon: Icons.lock_rounded,
                  label: l10n.changePassword,
                  onTap: () => _changePassword(context, user, auth, l10n),
                ),
                const SizedBox(height: 28),

                _SectionHeader(title: l10n.session),
                const SizedBox(height: 10),
                _SettingsTile(
                  icon: Icons.logout_rounded,
                  label: l10n.logout,
                  color: AppTheme.error,
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(l10n.logout),
                        content: Text('${l10n.logout}?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(l10n.cancel)),
                          ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.error),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(l10n.yes)),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      SafeZoneService().stop();
                      await auth.logout();
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen()),
                          (_) => false);
                    }
                  },
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  void _editName(BuildContext context, UserModel user, AuthProvider auth,
      AppLocalizations l10n) {
    final ctrl = TextEditingController(text: user.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.editName),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(fontSize: 17),
            decoration: InputDecoration(
                labelText: l10n.name,
                prefixIcon: const Icon(Icons.person_rounded))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          ElevatedButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(ctx);
              final updated = user.copyWith(name: newName);
              await DataService().updateUser(updated);
              await auth.updateUserName(newName);
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _changePassword(BuildContext context, UserModel user, AuthProvider auth,
      AppLocalizations l10n) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.changePassword),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            obscureText: true,
            style: const TextStyle(fontSize: 17),
            decoration: InputDecoration(
                labelText: l10n.newPassword,
                prefixIcon: const Icon(Icons.lock_rounded))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          ElevatedButton(
            onPressed: () async {
              final pw = ctrl.text.trim();
              if (pw.length < 6) return;
              Navigator.pop(ctx);
              try {
                await FirebaseAuth.instance.currentUser
                    ?.updatePassword(pw);
                final updated = user.copyWith(password: pw);
                await DataService().updateUser(updated);
              } catch (_) {}
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}

// ─── Alarm Prefs Section (NEW) ────────────────────────────────────────────────
/// Lets the user toggle between full-screen alarm overlay vs plain notification,
/// and pick a ringtone from the system ringtone picker.
class _AlarmPrefsSection extends StatefulWidget {
  final UserModel user;
  final AppLocalizations l10n;
  const _AlarmPrefsSection({required this.user, required this.l10n});

  @override
  State<_AlarmPrefsSection> createState() => _AlarmPrefsSectionState();
}

class _AlarmPrefsSectionState extends State<_AlarmPrefsSection> {
  AlarmPrefs _prefs = const AlarmPrefs();
  bool _loading = true;
  String? _ringtoneName;

  // MethodChannel to call Android's RingtoneManager from Dart.
  static const _ringtoneChannel = MethodChannel('eldercare/ringtone');

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await DataService().getAlarmPrefs(widget.user.id);
    String? name;
    if (p.ringtoneUri != null) {
      name = await _getRingtoneName(p.ringtoneUri!);
    }
    if (mounted) setState(() { _prefs = p; _ringtoneName = name; _loading = false; });
  }

  Future<void> _savePrefs(AlarmPrefs updated) async {
    final oldUseAlarmScreen = _prefs.useAlarmScreen;
    setState(() => _prefs = updated);
    
    await DataService().saveAlarmPrefs(widget.user.id, updated);
    AlarmService().updateAlarmPrefs(updated); // KEEP ALARM SERVICE IN SYNC

    // If they toggled the "Alarm Screen" setting, we MUST reschedule existing
    // alarms, otherwise the native background intents will still hold the old
    // 'useAlarmScreen' extra from when they were originally scheduled.
    if (updated.useAlarmScreen != oldUseAlarmScreen) {
      final group = await DataService().getGroupForUser(widget.user.id);
      if (group != null) {
        final items = await DataService().getSchedulesByGroup(group.id);
        await AlarmService().rescheduleAll(widget.user.id, items);
      }
    }
  }

  Future<String?> _getRingtoneName(String uri) async {
    try {
      return await _ringtoneChannel.invokeMethod<String>(
          'getRingtoneName', {'uri': uri});
    } catch (_) { return null; }
  }

  /// Opens the native Android ringtone picker and waits for the result.
  Future<void> _pickRingtone() async {
    try {
      final result = await _ringtoneChannel.invokeMethod<Map>(
        'pickRingtone',
        {'currentUri': _prefs.ringtoneUri},
      );
      if (result != null) {
        final uri  = result['uri']  as String?;
        final name = result['name'] as String?;
        final updated = _prefs.copyWith(ringtoneUri: uri);
        await _savePrefs(updated);
        setState(() => _ringtoneName = name);
      }
    } on PlatformException catch (e) {
      debugPrint('pickRingtone error: $e');
    }
  }

  /// Opens the device Sound & Vibration settings page directly using
  /// open_settings_plus so the user can change the overall ringtone volume.
  void _openSoundSettings() {
    if (OpenSettingsPlus.shared is OpenSettingsPlusAndroid) {
      (OpenSettingsPlus.shared as OpenSettingsPlusAndroid).sound();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // ── Toggle: Alarm Screen vs Notification ──────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.alarm_rounded,
                    color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.l10n.alarmFullScreen,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(
                    _prefs.useAlarmScreen
                        ? widget.l10n.alarmFullScreenOn
                        : widget.l10n.alarmFullScreenOff,
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary),
                  ),
                ],
              )),
              Switch(
                value: _prefs.useAlarmScreen,
                activeColor: AppTheme.primary,
                onChanged: (val) =>
                    _savePrefs(_prefs.copyWith(useAlarmScreen: val)),
              ),
            ]),
          ),

          const Divider(height: 1, indent: 20, endIndent: 20),

          // ── Ringtone picker ───────────────────────────────────────────────
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF7B61FF).withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.music_note_rounded,
                  color: Color(0xFF7B61FF), size: 22),
            ),
            title: Text(widget.l10n.alarmRingtone,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            subtitle: Text(
              _ringtoneName ?? (_prefs.ringtoneUri == null
                  ? widget.l10n.alarmRingtoneDefault
                  : widget.l10n.alarmRingtoneCustom),
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: AppTheme.textSecondary),
            onTap: _pickRingtone,
          ),

          const Divider(height: 1, indent: 20, endIndent: 20),

          // ── Reset to default ──────────────────────────────────────────────
          if (_prefs.ringtoneUri != null)
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.restore_rounded,
                    color: AppTheme.error, size: 22),
              ),
              title: Text(widget.l10n.alarmResetRingtone,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.error)),
              onTap: () async {
                await _savePrefs(
                    _prefs.copyWith(clearRingtone: true));
                setState(() => _ringtoneName = null);
              },
            ),

          if (_prefs.ringtoneUri != null)
            const Divider(height: 1, indent: 20, endIndent: 20),

          // ── Open device Sound settings ────────────────────────────────────
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.volume_up_rounded,
                  color: AppTheme.warning, size: 22),
            ),
            title: Text(widget.l10n.alarmAdjustVolume,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            subtitle: Text(widget.l10n.alarmAdjustVolumeDesc,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
            trailing: const Icon(Icons.open_in_new_rounded,
                size: 16, color: AppTheme.textSecondary),
            onTap: _openSoundSettings,
          ),
        ],
      ),
    );
  }
}

// ─── Safe Zone tiles (unchanged from original) ────────────────────────────────
class _SetHomeTile extends StatefulWidget {
  final UserModel user;
  final AppLocalizations l10n;
  const _SetHomeTile({required this.user, required this.l10n});
  @override
  State<_SetHomeTile> createState() => _SetHomeTileState();
}

class _SetHomeTileState extends State<_SetHomeTile> {
  bool _saving = false;

  Future<void> _setHome() async {
    setState(() => _saving = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final existing = await DataService().getSafeZone(widget.user.id);
      final settings = (existing ?? SafeZoneSettings(elderlyId: widget.user.id))
          .copyWith(
            homeLat: pos.latitude,
            homeLng: pos.longitude,
            enabled: true,
          );
      await DataService().saveSafeZone(settings);
      SafeZoneService().start(widget.user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.l10n.homeLocationSaved)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.l10n.locationError)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _saving ? null : _setHome,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          _saving
              ? const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primary))
              : const Icon(Icons.home_rounded,
                  color: AppTheme.primary, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(widget.l10n.setHomeLocation,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary)),
              Text(widget.l10n.setHomeSubtitle,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ]),
          ),
          Icon(Icons.arrow_forward_ios_rounded,
              color: AppTheme.primary.withOpacity(0.5), size: 16),
        ]),
      ),
    );
  }
}

class _TestAlarmTile extends StatefulWidget {
  final UserModel user;
  final AppLocalizations l10n;
  const _TestAlarmTile({required this.user, required this.l10n});
  @override
  State<_TestAlarmTile> createState() => _TestAlarmTileState();
}

class _TestAlarmTileState extends State<_TestAlarmTile> {
  bool _triggering = false;

  Future<void> _triggerTest() async {
    setState(() => _triggering = true);
    final existing = await DataService().getSafeZone(widget.user.id);
    if (existing == null || !existing.hasHome) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.l10n.safeZoneNoHomeYet)),
        );
        setState(() => _triggering = false);
      }
      return;
    }
    final now = DateTime.now();
    final testStart = (now.hour - 1 + 24) % 24;
    final testEnd = (now.hour + 2) % 24;
    final testSettings = existing.copyWith(
      enabled: true,
      radiusMeters: 0,
      sleepStartHour: testStart,
      sleepEndHour: testEnd,
      awaitingConfirmation: false,
    );
    await DataService().saveSafeZone(testSettings);
    await SafeZoneService().triggerTestCheck(widget.user.id);
    await Future.delayed(const Duration(seconds: 3));
    final currentAfterTest = await DataService().getSafeZone(widget.user.id);
    final isAwaiting = currentAfterTest?.awaitingConfirmation ?? false;
    await DataService()
        .saveSafeZone(existing.copyWith(awaitingConfirmation: isAwaiting));
    if (mounted) {
      setState(() => _triggering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.l10n.testAlarmTriggered)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return GestureDetector(
      onTap: _triggering ? null : _triggerTest,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          _triggering
              ? const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.warning))
              : const Icon(Icons.notifications_active_rounded,
                  color: AppTheme.warning, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.testAlarmButton,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warning)),
              Text(l10n.testAlarmSubtitle,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ]),
          ),
          Icon(Icons.arrow_forward_ios_rounded,
              color: AppTheme.warning.withOpacity(0.5), size: 16),
        ]),
      ),
    );
  }
}

// ─── Reused sub-widgets ───────────────────────────────────────────────────────

class _LanguageSelector extends StatelessWidget {
  final UserModel user;
  final AuthProvider auth;
  final AppLocalizations l10n;
  const _LanguageSelector(
      {required this.user, required this.auth, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final langs = [
      {'code': 'en', 'label': 'English',        'flag': '🇬🇧'},
      {'code': 'zh', 'label': '中文',             'flag': '🇨🇳'},
      {'code': 'ms', 'label': 'Bahasa Melayu',  'flag': '🇲🇾'},
      {'code': 'ta', 'label': 'தமிழ்',           'flag': '🇮🇳'},
    ];
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE0E0E0))),
      child: Column(
        children: langs.asMap().entries.map((e) {
          final idx = e.key;
          final lang = e.value;
          final selected = user.preferredLanguage == lang['code'];
          return Column(children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading:
                  Text(lang['flag']!, style: const TextStyle(fontSize: 28)),
              title: Text(lang['label']!,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500)),
              trailing: selected
                  ? const Icon(Icons.check_circle_rounded,
                      color: AppTheme.primary, size: 26)
                  : const Icon(Icons.circle_outlined,
                      color: Color(0xFFCFD8DC), size: 26),
              onTap: () => auth.updateLanguage(lang['code']!),
            ),
            if (idx < langs.length - 1)
              const Divider(height: 1, indent: 20, endIndent: 20),
          ]);
        }).toList(),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary,
          letterSpacing: 0.5));
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _SettingsTile(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textPrimary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: color != null
                  ? color!.withOpacity(0.3)
                  : const Color(0xFFE0E0E0)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          Icon(icon, color: c, size: 26),
          const SizedBox(width: 14),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600, color: c))),
          Icon(Icons.arrow_forward_ios_rounded,
              color: c.withOpacity(0.5), size: 16),
        ]),
      ),
    );
  }
}
