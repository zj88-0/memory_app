import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../models/safezone_model.dart';
import '../../services/auth_provider.dart';
import '../../services/data_service.dart';
import '../../services/safezone_service.dart';
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
                // Profile card
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryLight],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 6))],
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.white.withOpacity(0.25),
                      child: Text(
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(user.name,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(user.email,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(
                            user.role == UserRole.elderly ? l10n.roleElderly : l10n.roleCaregiver,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 28),

                // Language
                _SectionHeader(title: l10n.language),
                const SizedBox(height: 10),
                _LanguageSelector(user: user, auth: auth, l10n: l10n),
                const SizedBox(height: 28),

                // Activity Recommendations
                _SectionHeader(title: l10n.activityRecommendations),
                const SizedBox(height: 10),
                _SettingsTile(
                  icon: Icons.interests_rounded,
                  label: l10n.editMyInterests,
                  color: const Color(0xFF7B61FF),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const InterestSelectionScreen(isEditing: true),
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

                // Account
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
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
                          ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
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
                          MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
                    }
                  },
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  void _editName(BuildContext context, UserModel user, AuthProvider auth, AppLocalizations l10n) {
    final ctrl = TextEditingController(text: user.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.editName),
        content: TextField(
            controller: ctrl, autofocus: true,
            style: const TextStyle(fontSize: 17),
            decoration: InputDecoration(labelText: l10n.name, prefixIcon: const Icon(Icons.person_rounded))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              await auth.updateUserName(ctrl.text.trim());
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _changePassword(BuildContext context, UserModel user, AuthProvider auth, AppLocalizations l10n) {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.changePassword),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: oldCtrl, obscureText: true,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                  labelText: l10n.currentPassword,
                  prefixIcon: const Icon(Icons.lock_rounded))),
          const SizedBox(height: 12),
          TextField(
              controller: newCtrl, obscureText: true,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                  labelText: l10n.password,
                  prefixIcon: const Icon(Icons.lock_open_rounded))),
          const SizedBox(height: 12),
          TextField(
              controller: confirmCtrl, obscureText: true,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                  labelText: l10n.confirmPassword,
                  prefixIcon: const Icon(Icons.lock_outline_rounded))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          ElevatedButton(
            onPressed: () async {
              if (auth.hashForCompare(oldCtrl.text) != user.password) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.invalidCredentials), backgroundColor: AppTheme.error));
                return;
              }
              if (newCtrl.text != confirmCtrl.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.passwordMismatch), backgroundColor: AppTheme.error));
                return;
              }
              Navigator.pop(ctx);
              await auth.updatePassword(newCtrl.text);
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}

// ── Set Home tile — visible ONLY to elderly ──────────────────────────────────
class _SetHomeTile extends StatefulWidget {
  final UserModel user;
  final AppLocalizations l10n;
  const _SetHomeTile({required this.user, required this.l10n});

  @override
  State<_SetHomeTile> createState() => _SetHomeTileState();
}

class _SetHomeTileState extends State<_SetHomeTile> {
  bool _loading = false;
  SafeZoneSettings? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await DataService().getSafeZone(widget.user.id);
    if (mounted) setState(() => _settings = s);
  }

  Future<void> _setHome() async {
    setState(() => _loading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _snack(widget.l10n.locationServiceDisabled);
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          _snack(widget.l10n.locationPermissionDenied);
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        _snack(widget.l10n.locationPermissionDenied);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      final existing = await DataService().getSafeZone(widget.user.id);
      final updated = (existing ?? SafeZoneSettings(elderlyId: widget.user.id))
          .copyWith(homeLat: pos.latitude, homeLng: pos.longitude);
      await DataService().saveSafeZone(updated);
      if (mounted) {
        setState(() => _settings = updated);
        _snack(widget.l10n.homeLocationSaved);
      }
    } catch (e) {
      _snack(widget.l10n.locationError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final hasHome = _settings?.hasHome ?? false;

    return GestureDetector(
      onTap: _loading ? null : _setHome,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E0E0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          _loading
              ? const SizedBox(width: 26, height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.location_on_rounded,
                  color: hasHome ? AppTheme.success : AppTheme.textPrimary, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.setHomeLocation,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600,
                      color: hasHome ? AppTheme.success : AppTheme.textPrimary)),
              if (hasHome)
                Text(
                  '${_settings!.homeLat!.toStringAsFixed(5)}, '
                  '${_settings!.homeLng!.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                )
              else
                Text(l10n.setHomeLocationDesc,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ]),
          ),
          Icon(Icons.arrow_forward_ios_rounded,
              color: AppTheme.textPrimary.withOpacity(0.4), size: 16),
        ]),
      ),
    );
  }
}

// ── Test alarm tile — simulates a 500 m breach to trigger the full alert flow ─
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
    final l10n = widget.l10n;

    // Confirm before firing so the elderly doesn't tap it by accident.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 28),
          const SizedBox(width: 10),
          Text(l10n.testAlarmTitle,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        ]),
        content: Text(l10n.testAlarmDesc,
            style: const TextStyle(fontSize: 15, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.testAlarmConfirm,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _triggering = true);

    // Load current settings.
    final existing = await DataService().getSafeZone(widget.user.id);
    if (existing == null || !existing.hasHome) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.safeZoneNoHomeYet)),
        );
        setState(() => _triggering = false);
      }
      return;
    }

    // Temporarily set radius to 0 so current position is always "outside"
    // and force isAbnormalTime by saving a sleep window that covers NOW,
    // then restore everything after the check fires.
    final now = DateTime.now();
    final testStart = (now.hour - 1 + 24) % 24;
    final testEnd = (now.hour + 2) % 24;

    final testSettings = existing.copyWith(
      enabled: true,
      radiusMeters: 0,           // any distance triggers the alarm
      sleepStartHour: testStart, // window covers the current hour
      sleepEndHour: testEnd,
      awaitingConfirmation: false,
    );
    await DataService().saveSafeZone(testSettings);

    // Force an immediate check — the service will detect a breach and fire.
    await SafeZoneService().triggerTestCheck(widget.user.id);

    // Restore original settings after a short delay so the real monitoring
    // is not permanently affected.
    await Future.delayed(const Duration(seconds: 3));
    await DataService().saveSafeZone(existing.copyWith(awaitingConfirmation: false));

    if (mounted) {
      setState(() => _triggering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.testAlarmTriggered)),
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
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.03), blurRadius: 6,
              offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          _triggering
              ? const SizedBox(width: 26, height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: AppTheme.warning))
              : const Icon(Icons.notifications_active_rounded,
                  color: AppTheme.warning, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(l10n.testAlarmButton,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600,
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
  const _LanguageSelector({required this.user, required this.auth, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final langs = [
      {'code': 'en', 'label': 'English', 'flag': '🇬🇧'},
      {'code': 'zh', 'label': '中文', 'flag': '🇨🇳'},
      {'code': 'ms', 'label': 'Bahasa Melayu', 'flag': '🇲🇾'},
      {'code': 'ta', 'label': 'தமிழ்', 'flag': '🇮🇳'},
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: Text(lang['flag']!, style: const TextStyle(fontSize: 28)),
              title: Text(lang['label']!,
                  style: TextStyle(fontSize: 17, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
              trailing: selected
                  ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 26)
                  : const Icon(Icons.circle_outlined, color: Color(0xFFCFD8DC), size: 26),
              onTap: () => auth.updateLanguage(lang['code']!),
            ),
            if (idx < langs.length - 1) const Divider(height: 1, indent: 20, endIndent: 20),
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
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary, letterSpacing: 0.5));
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _SettingsTile({required this.icon, required this.label, required this.onTap, this.color});

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
          border: Border.all(color: color != null ? color!.withOpacity(0.3) : const Color(0xFFE0E0E0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Icon(icon, color: c, size: 26),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c))),
          Icon(Icons.arrow_forward_ios_rounded, color: c.withOpacity(0.5), size: 16),
        ]),
      ),
    );
  }
}
