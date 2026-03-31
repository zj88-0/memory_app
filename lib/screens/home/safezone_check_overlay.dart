import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/safezone_service.dart';
import '../../services/notification_service.dart';
import '../../services/data_service.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Overlay dialog shown to the elderly user inside the app when a safe-zone
/// breach is detected during abnormal hours.
///
/// Usage — wrap your top-level scaffold or MaterialApp child with this widget:
///
///   SafeZoneCheckOverlay(child: HomeScreen())
///
/// The overlay listens to [SafeZoneService.onCheckRequired] and shows itself
/// automatically.
class SafeZoneCheckOverlay extends StatefulWidget {
  final Widget child;
  const SafeZoneCheckOverlay({super.key, required this.child});

  @override
  State<SafeZoneCheckOverlay> createState() => _SafeZoneCheckOverlayState();
}

class _SafeZoneCheckOverlayState extends State<SafeZoneCheckOverlay> {
  bool _visible = false;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    // Register this widget as the in-app callback for SafeZoneService
    // (breach detected while app is already open).
    SafeZoneService().setInAppCheckCallback(_show);
    // Register for notification-body taps (app opened from notification).
    NotificationService().setShowSafeZoneDialogCallback(_show);
    // After the first frame, check cold-launch and persisted pending flag.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOnStart());
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    SafeZoneService().setInAppCheckCallback(null);
    NotificationService().setShowSafeZoneDialogCallback(null);
    super.dispose();
  }

  /// Called once after first frame to handle:
  ///  1. App cold-started by tapping the safe-zone notification body.
  ///  2. App re-opened normally while awaitingConfirmation flag is still set
  ///     in SharedPreferences (e.g. the app was killed mid-check).
  Future<void> _checkOnStart() async {
    // 1 — Cold launch from notification?
    final launchedFromNotif =
        await NotificationService().wasLaunchedFromSafeZoneNotification();
    if (launchedFromNotif) {
      _show();
      return;
    }

    // 2 — Persisted awaitingConfirmation?
    final elderlyId = SafeZoneService().currentElderlyId;
    if (elderlyId == null) return;
    final settings = await DataService().getSafeZone(elderlyId);
    if (settings != null && settings.awaitingConfirmation) {
      _show();
    }
  }

  void _show() {
    if (!mounted) return;
    setState(() => _visible = true);
    // Auto-close after 2 minutes (matching the service's confirm timeout).
    _autoCloseTimer?.cancel();
    _autoCloseTimer = Timer(const Duration(minutes: 2), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  Future<void> _confirm() async {
    _autoCloseTimer?.cancel();
    await SafeZoneService().confirmSafe();
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_visible) _buildDialog(context),
      ],
    );
  }

  Widget _buildDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 10))
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Pulsing icon
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_off_rounded,
                  color: AppTheme.warning, size: 40),
            ),
            const SizedBox(height: 20),
            Text(l10n.safeZoneCheckTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Text(l10n.safeZoneCheckBody,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, color: AppTheme.textSecondary, height: 1.5)),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.check_circle_rounded, size: 26),
                label: Text(l10n.imOk,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
