import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../models/safezone_model.dart';
import '../../services/data_service.dart';
import '../../services/safezone_service.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Opened when an admin caregiver taps the elderly member card in the group screen.
/// Allows the caregiver to:
///   1. Set / update the elderly's interests (delegates to InterestSelectionScreen).
///   2. Enable / disable the Safe Zone feature.
///   3. Adjust the sleep-time window used to detect "abnormal hours".
class ElderlyManagementPage extends StatefulWidget {
  final UserModel elderly;
  const ElderlyManagementPage({super.key, required this.elderly});

  @override
  State<ElderlyManagementPage> createState() => _ElderlyManagementPageState();
}

class _ElderlyManagementPageState extends State<ElderlyManagementPage> {
  SafeZoneSettings? _settings;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await DataService().getSafeZone(widget.elderly.id);
    setState(() {
      _settings = s ??
          SafeZoneSettings(
            elderlyId: widget.elderly.id,
            // 10 m for testing — change to 500 for production
            radiusMeters: 10,
            sleepStartHour: 22,
            sleepEndHour: 7,
          );
    });
  }

  Future<void> _save(SafeZoneSettings updated) async {
    setState(() { _saving = true; _settings = updated; });
    await DataService().saveSafeZone(updated);
    // Restart monitoring with updated settings if it's running.
    SafeZoneService().stop();
    if (updated.enabled && updated.hasHome) {
      SafeZoneService().start(widget.elderly.id);
    }
    setState(() => _saving = false);
  }

  Future<void> _pickTime({required bool isSleepStart}) async {
    final l10n = AppLocalizations.of(context)!;
    final current = isSleepStart
        ? _settings!.sleepStartHour
        : _settings!.sleepEndHour;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current, minute: 0),
      helpText: isSleepStart ? l10n.sleepStart : l10n.sleepEnd,
    );
    if (picked != null) {
      final updated = _settings!.copyWith(
        sleepStartHour: isSleepStart ? picked.hour : null,
        sleepEndHour: isSleepStart ? null : picked.hour,
      );
      await _save(updated);
    }
  }

  String _hourLabel(int h) {
    final period = h < 12 ? 'AM' : 'PM';
    final display = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$display:00 $period';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final s = _settings;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l10n.manageElderly)),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ── Elderly info card ───────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppTheme.accent, Color(0xFFFF8A65)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(
                        color: AppTheme.accent.withOpacity(0.3),
                        blurRadius: 14, offset: const Offset(0, 6))],
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      child: Text(
                        widget.elderly.name.isNotEmpty
                            ? widget.elderly.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800,
                            color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.elderly.name,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 20,
                                  fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis),
                          Text(widget.elderly.email,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13),
                              overflow: TextOverflow.ellipsis),
                        ])),
                  ]),
                ),

                const SizedBox(height: 28),

                // ── Interests ───────────────────────────────────────────────
                _SectionHeader(title: l10n.activityRecommendations),
                const SizedBox(height: 10),
                _ManageTile(
                  icon: Icons.interests_rounded,
                  label: l10n.editElderlyInterests,
                  color: const Color(0xFF7B61FF),
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/interests',
                    arguments: widget.elderly.id,
                  ),
                ),
                const SizedBox(height: 28),

                // ── Safe Zone ───────────────────────────────────────────────
                _SectionHeader(title: l10n.safeZone),
                const SizedBox(height: 10),

                // Enable / disable toggle
                _ToggleTile(
                  icon: Icons.shield_rounded,
                  label: l10n.enableSafeZone,
                  subtitle: s.hasHome
                      ? l10n.safeZoneActiveDesc
                      : l10n.safeZoneNoHomeDesc,
                  value: s.enabled,
                  onChanged: (v) async {
                    if (v && !s.hasHome) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.safeZoneNoHomeYet)));
                      return;
                    }
                    await _save(s.copyWith(enabled: v));
                  },
                ),
                const SizedBox(height: 10),

                // Home location status (read-only for caregiver — set by elderly)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Row(children: [
                    Icon(
                      s.hasHome ? Icons.location_on_rounded : Icons.home_outlined,
                      color: s.hasHome ? AppTheme.success : AppTheme.textSecondary,
                      size: 26,
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.homeLocation,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                          Text(
                            s.hasHome
                                ? '${s.homeLat!.toStringAsFixed(5)}, '
                                  '${s.homeLng!.toStringAsFixed(5)}'
                                : l10n.homeNotSetYet,
                            style: TextStyle(
                                fontSize: 13,
                                color: s.hasHome
                                    ? AppTheme.success
                                    : AppTheme.textSecondary),
                          ),
                        ])),
                  ]),
                ),

                const SizedBox(height: 28),

                // ── Sleep / Abnormal-time window ─────────────────────────────
                _SectionHeader(title: l10n.sleepTimeWindow),
                const SizedBox(height: 6),
                Text(l10n.sleepTimeDesc,
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary, height: 1.4)),
                const SizedBox(height: 12),

                Row(children: [
                  Expanded(
                    child: _TimePickerCard(
                      label: l10n.sleepStart,
                      timeLabel: _hourLabel(s.sleepStartHour),
                      icon: Icons.bedtime_rounded,
                      color: const Color(0xFF5C6BC0),
                      onTap: () => _pickTime(isSleepStart: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimePickerCard(
                      label: l10n.sleepEnd,
                      timeLabel: _hourLabel(s.sleepEndHour),
                      icon: Icons.wb_sunny_rounded,
                      color: const Color(0xFFFF8A65),
                      onTap: () => _pickTime(isSleepStart: false),
                    ),
                  ),
                ]),

                const SizedBox(height: 12),

                // Current status indicator
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: s.isAbnormalTime
                        ? AppTheme.warning.withOpacity(0.12)
                        : AppTheme.success.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: s.isAbnormalTime
                          ? AppTheme.warning.withOpacity(0.4)
                          : AppTheme.success.withOpacity(0.4),
                    ),
                  ),
                  child: Row(children: [
                    Icon(
                      s.isAbnormalTime
                          ? Icons.nightlight_round
                          : Icons.wb_sunny_outlined,
                      color: s.isAbnormalTime ? AppTheme.warning : AppTheme.success,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.isAbnormalTime
                            ? l10n.currentlyAbnormalTime
                            : l10n.currentlyNormalTime,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: s.isAbnormalTime
                              ? AppTheme.warning
                              : AppTheme.success,
                        ),
                      ),
                    ),
                  ]),
                ),

                if (_saving) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],

                const SizedBox(height: 40),
              ],
            ),
    );
  }
}

// ── sub-widgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary, letterSpacing: 0.5));
}

class _ManageTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ManageTile({required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.03), blurRadius: 6,
              offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 14),
          Expanded(child: Text(label,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: color))),
          Icon(Icons.arrow_forward_ios_rounded,
              color: color.withOpacity(0.5), size: 16),
        ]),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final void Function(bool) onChanged;
  const _ToggleTile({
    required this.icon, required this.label, required this.subtitle,
    required this.value, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = value ? AppTheme.success : AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: value
                ? AppTheme.success.withOpacity(0.4)
                : const Color(0xFFE0E0E0)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.03), blurRadius: 6,
            offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Icon(icon, color: c, size: 26),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: c)),
              Text(subtitle, style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
            ])),
        Switch(value: value, onChanged: onChanged,
            activeColor: AppTheme.success),
      ]),
    );
  }
}

class _TimePickerCard extends StatelessWidget {
  final String label;
  final String timeLabel;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _TimePickerCard({
    required this.label, required this.timeLabel, required this.icon,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.03), blurRadius: 6,
              offset: const Offset(0, 2))],
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(fontSize: 12, color: color,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(timeLabel,
              style: TextStyle(fontSize: 18, color: color,
                  fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}
