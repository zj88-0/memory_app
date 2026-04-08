import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../models/schedule_model.dart';
import '../../services/alarm_service.dart';
import '../../services/notification_service.dart';
import '../../utils/app_theme.dart';

/// ScheduleAlarmScreen — shown as a full-screen route when a scheduled task
/// fires and the user has chosen "alarm screen" mode (instead of a plain
/// notification).  Design mirrors a phone clock alarm: big pulsing button,
/// task name, time, and a dismiss action.
///
/// Push this route with [AlarmService.showAlarmScreen] — it handles the
/// WakeLock, ringtone playback, and navigation automatically.
class ScheduleAlarmScreen extends StatefulWidget {
  final ScheduleItem item;
  const ScheduleAlarmScreen({super.key, required this.item});

  @override
  State<ScheduleAlarmScreen> createState() => _ScheduleAlarmScreenState();
}

class _ScheduleAlarmScreenState extends State<ScheduleAlarmScreen>
    with TickerProviderStateMixin {
  // ── Pulse animation for the big "Done" button ─────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // ── Ripple animation around the button ────────────────────────────────────
  late AnimationController _rippleCtrl;
  late Animation<double> _rippleAnim;

  // ── Live clock ────────────────────────────────────────────────────────────
  late Timer _clockTimer;
  late String _currentTime;
  late String _currentDate;

  @override
  void initState() {
    super.initState();

    // Lock orientation to portrait for the alarm screen.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Keep screen bright — AlarmService already acquired WakeLock.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _currentTime = _formattedTime();
    _currentDate = _formattedDate();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = _formattedTime();
          _currentDate = _formattedDate();
        });
      }
    });

    // Pulse: scale 1.0 → 1.08 → 1.0 every 1.2 s
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Ripple: opacity 0.6 → 0, scale 1.0 → 1.8 every 1.8 s
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _rippleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _pulseCtrl.dispose();
    _rippleCtrl.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _formattedTime() => DateFormat('HH:mm').format(DateTime.now());

  String _formattedDate() {
    // Use locale-aware long date format.
    final locale = Intl.defaultLocale ?? 'en';
    try {
      return DateFormat('EEEE, d MMMM', locale).format(DateTime.now());
    } catch (_) {
      return DateFormat('EEEE, d MMMM').format(DateTime.now());
    }
  }

  Future<void> _dismiss() async {
    await AlarmService().stopAlarm();
    // Show a 'View Schedule' notification so the user has a clear path to
    // their schedule after turning off the alarm — works for both warm
    // (app already open) and cold (app was killed) launch scenarios.
    await NotificationService().showViewScheduleNotification(
      taskTitle: widget.item.title,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _snooze() async {
    await AlarmService().snoozeAlarm(widget.item);
    // Show a 'View Schedule' notification as confirmation that the alarm
    // was snoozed and the user can check their upcoming tasks.
    await NotificationService().showViewScheduleNotification(
      taskTitle: widget.item.title,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final size = MediaQuery.of(context).size;
    const snoozeMin = 5; // minutes — matches AlarmService default

    return PopScope(
      // Prevent back-button dismissal — user must tap the big button.
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // ── Gradient background ──────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D1B2A), Color(0xFF1A3A5C), Color(0xFF0D1B2A)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),

            // ── Subtle star-like dots ────────────────────────────────────────
            ..._buildDots(size),

            // ── Main content ─────────────────────────────────────────────────
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 40),

                  // Live clock
                  Text(
                    _currentTime,
                    style: const TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.w200,
                      color: Colors.white,
                      letterSpacing: -2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _currentDate,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white60,
                      letterSpacing: 0.5,
                    ),
                  ),

                  const Spacer(),

                  // Task name & description
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        // Alarm bell icon
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.primary.withOpacity(0.5),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.alarm_rounded,
                            color: AppTheme.primary,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          l10n.alarmTimeFor,
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white.withOpacity(0.6),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.item.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.15,
                          ),
                        ),
                        if (widget.item.description.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            widget.item.description,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              color: Colors.white.withOpacity(0.65),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const Spacer(),

                  // ── Big pulsing DONE button ──────────────────────────────
                  _BigDoneButton(
                    pulseAnim: _pulseAnim,
                    rippleAnim: _rippleAnim,
                    label: l10n.alarmDone,
                    onTap: _dismiss,
                  ),
                  const SizedBox(height: 28),

                  // ── Snooze (smaller, text-style) ─────────────────────────
                  TextButton.icon(
                    onPressed: _snooze,
                    icon: const Icon(Icons.snooze_rounded, color: Colors.white54, size: 20),
                    label: Text(
                      l10n.alarmSnooze(snoozeMin),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Generate subtle scattered dots for visual depth.
  List<Widget> _buildDots(Size size) {
    const positions = [
      [0.1, 0.05], [0.85, 0.08], [0.25, 0.15], [0.7, 0.12],
      [0.05, 0.35], [0.92, 0.3],  [0.4, 0.22], [0.6, 0.28],
      [0.15, 0.6],  [0.8, 0.55],  [0.5, 0.42],
    ];
    return positions.map((p) => Positioned(
      left: size.width * p[0],
      top: size.height * p[1],
      child: Container(
        width: 3, height: 3,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.25),
          shape: BoxShape.circle,
        ),
      ),
    )).toList();
  }
}

// ─── Big pulsing Done button ──────────────────────────────────────────────────
class _BigDoneButton extends StatelessWidget {
  final Animation<double> pulseAnim;
  final Animation<double> rippleAnim;
  final String label;
  final VoidCallback onTap;

  const _BigDoneButton({
    required this.pulseAnim,
    required this.rippleAnim,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([pulseAnim, rippleAnim]),
      builder: (_, __) {
        final rippleScale = 1.0 + rippleAnim.value * 0.8;
        final rippleOpacity = (0.6 * (1 - rippleAnim.value)).clamp(0.0, 1.0);
        return SizedBox(
          width: 210,
          height: 210,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer ripple ring
              Transform.scale(
                scale: rippleScale,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primary.withOpacity(rippleOpacity),
                      width: 2,
                    ),
                  ),
                ),
              ),
              // Middle glow ring
              Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primary.withOpacity(0.12),
                ),
              ),
              // Pulsing main button
              Transform.scale(
                scale: pulseAnim.value,
                child: GestureDetector(
                  onTap: onTap,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.55),
                          blurRadius: 30,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_rounded, color: Colors.white, size: 52),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
