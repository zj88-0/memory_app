import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../models/schedule_model.dart';
import '../../services/auth_provider.dart';
import '../../services/data_service.dart';
import '../../services/alarm_service.dart';         // ← NEW
import '../../services/tts_service.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// ── Locale-aware date helpers ─────────────────────────────────────────────────
String _formatDateTime(DateTime dt, String langCode) {
  if (langCode == 'zh') {
    return '${dt.year}年${dt.month.toString().padLeft(2,'0')}月'
        '${dt.day.toString().padLeft(2,'0')}日  '
        '${dt.hour.toString().padLeft(2,'0')}:'
        '${dt.minute.toString().padLeft(2,'0')}';
  }
  return DateFormat('EEE, dd MMM yyyy  HH:mm').format(dt);
}

String _formatTime(DateTime dt, String langCode) {
  final time =
      '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  if (langCode == 'zh') {
    return '$time  •  ${dt.year}年${dt.month}月${dt.day}日';
  }
  return DateFormat('HH:mm  •  EEE dd MMM').format(dt);
}

// ─────────────────────────────────────────────────────────────────────────────
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  List<ScheduleItem> _items = [];
  bool _loading = true;
  StreamSubscription<List<ScheduleItem>>? _sub;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _listen() {
    final auth = context.read<AuthProvider>();
    final groupId = auth.currentGroup?.id;
    if (groupId == null) { setState(() => _loading = false); return; }
    _sub?.cancel();
    _sub = DataService().streamSchedulesByGroup(groupId).listen((items) {
      if (mounted) {
        setState(() { _items = items; _loading = false; });
        // ── Missed-alarm catch-up ─────────────────────────────────────────
        // If an alarm should have fired (phone was off / app was killed) but
        // wasn't marked as rang, fire it now — as long as the task hasn't
        // started yet.  Window: alarmTime ≤ now < scheduledTime.
        final userId = auth.currentUser?.id ?? '';
        if (userId.isNotEmpty) {
          AlarmService().checkMissedAlarms(items, userId);
        }
      }
    });
  }

  Future<void> _load() async => _listen();

  ScheduleItem? get _nextTask {
    final upcoming = _items
        .where((i) => !i.isCompleted && i.scheduledTime.isAfter(DateTime.now()))
        .toList();
    if (upcoming.isEmpty) return null;
    upcoming.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    return upcoming.first;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthProvider>();
    final lang = auth.currentUser?.preferredLanguage ?? 'en';

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (auth.currentGroup == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.schedule)),
        body: Center(child: Text(l10n.joinOrCreate,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18))),
      );
    }

    final next = _nextTask;
    final others = _items.where((i) => i != next).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l10n.schedule)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showScheduleDialog(context),
        icon: const Icon(Icons.add_rounded, size: 28),
        label: Text(l10n.addSchedule,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: _items.isEmpty
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 80, color: AppTheme.textSecondary),
                const SizedBox(height: 16),
                Text(l10n.noUpcomingTasks,
                    style: const TextStyle(
                        fontSize: 20, color: AppTheme.textSecondary)),
              ],
            ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (next != null) ...[
                    _NextTaskCard(
                      item: next, l10n: l10n, lang: lang,
                      onTap: () => _showDetailDialog(context, next),
                      onEdit: () => _showScheduleDialog(context, item: next),
                      onComplete: () => _markComplete(next),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (others.isNotEmpty) ...[
                    Text(l10n.allTasks,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    ...others.map((item) => _ScheduleCard(
                      item: item, l10n: l10n,
                      lang: auth.currentUser?.preferredLanguage ?? 'en',
                      onTap: () => _showDetailDialog(context, item),
                      onEdit: () => _showScheduleDialog(context, item: item),
                      onDelete: () => _delete(item),
                      onComplete: () => _markComplete(item),
                    )),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  // ── CRUD with AlarmService ─────────────────────────────────────────────────

  Future<void> _markComplete(ScheduleItem item) async {
    // Cancel the alarm when done.
    await AlarmService().cancelAlarm(item.id);
    await DataService().updateSchedule(item.copyWith(isCompleted: true));
  }

  Future<void> _delete(ScheduleItem item) async {
    await AlarmService().cancelAlarm(item.id);
    await DataService().deleteSchedule(item.id);
  }

  /// Cancels the old alarm, resets the rang flag so the alarm fires fresh,
  /// marks the task as not-completed (active), saves to Firestore, then
  /// schedules the new alarm.
  Future<void> _redeployAlarm(ScheduleItem saved, String userId) async {
    await AlarmService().cancelAlarm(saved.id);
    // Clear the alarm_rang flag so the alarm is not treated as already handled.
    await AlarmService().resetAlarmRangFlag(saved.id);
    // Reset the session-level guard so the new alarm can be shown this session.
    AlarmService().resetSessionAlarmFlag();
    // Mark the task as active so it shows up in the upcoming-tasks list.
    final reactivated = saved.copyWith(isCompleted: false);
    await DataService().updateSchedule(reactivated);
    if (userId.isNotEmpty) {
      await AlarmService().scheduleAlarm(reactivated, userId: userId);
    }
  }

  /// Shows add/edit dialog.
  /// When editing, a choice sheet asks whether to just update details or
  /// fully redeploy the alarm (cancel old → reset rang flag → reschedule).
  void _showScheduleDialog(BuildContext context, {ScheduleItem? item}) {
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?.id ?? '';
    final groupId = auth.currentGroup?.id ?? '';
    final lang = auth.currentUser?.preferredLanguage ?? 'en';
    final l10n = AppLocalizations.of(context)!;

    if (item != null) {
      // ── Existing task: ask the user what kind of edit they want ────────
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _EditChoiceSheet(
          l10n: l10n,
          onDetailsOnly: () {
            // Update Firestore only, keep the existing alarm unchanged.
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (__) => _ScheduleFormSheet(
                existing: item,
                allItems: _items,
                groupId: groupId,
                createdBy: userId,
                lang: lang,
                l10n: l10n,
                onSave: (saved) async {
                  await DataService().updateSchedule(saved);
                },
              ),
            );
          },
          onRedeploy: () {
            // Edit form + full alarm reschedule + rang-flag reset.
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (__) => _ScheduleFormSheet(
                existing: item,
                allItems: _items,
                groupId: groupId,
                createdBy: userId,
                lang: lang,
                l10n: l10n,
                onSave: (saved) => _redeployAlarm(saved, userId),
              ),
            );
          },
        ),
      );
      return;
    }

    // ── New task ─────────────────────────────────────────────────────────
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScheduleFormSheet(
        existing: null,
        allItems: _items,
        groupId: groupId,
        createdBy: userId,
        lang: lang,
        l10n: l10n,
        onSave: (saved) async {
          await DataService().createSchedule(saved);
          if (userId.isNotEmpty) {
            await AlarmService().scheduleAlarm(saved, userId: userId);
          }
        },
      ),
    );
  }

  void _showDetailDialog(BuildContext context, ScheduleItem item) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.read<AuthProvider>();
    final lang = auth.currentUser?.preferredLanguage ?? 'en';
    final tts = TtsService();

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.event_rounded,
                    color: AppTheme.primary, size: 32),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(item.title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 20),
            _DetailRow(icon: Icons.access_time_rounded,
                text: _formatDateTime(item.scheduledTime, lang)),
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              _DetailRow(icon: Icons.notes_rounded, text: item.description),
            ],
            const SizedBox(height: 10),
            _DetailRow(icon: Icons.notifications_active_rounded,
                text:
                    '${l10n.notifyBefore}: ${item.notifyMinutesBefore} ${l10n.minutes}'),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.repeat_rounded,
              text: _repeatLabel(item.repeatType, l10n),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  tts.speak(
                      '${item.title}. ${item.description}. '
                      '${_formatDateTime(item.scheduledTime, lang)}');
                },
                icon: const Icon(Icons.volume_up_rounded),
                label: Text(l10n.readAloud),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.close),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  String _repeatLabel(RepeatType t, AppLocalizations l10n) {
    switch (t) {
      case RepeatType.daily:   return l10n.daily;
      case RepeatType.weekly:  return l10n.weekly;
      case RepeatType.monthly: return l10n.monthly;
      default:                 return l10n.noRepeat;
    }
  }
}

// ─── Schedule Form Bottom Sheet ───────────────────────────────────────────────
class _ScheduleFormSheet extends StatefulWidget {
  final ScheduleItem? existing;
  final List<ScheduleItem> allItems;
  final String groupId;
  final String createdBy;
  final String lang;
  final AppLocalizations l10n;
  final Future<void> Function(ScheduleItem) onSave;

  const _ScheduleFormSheet({
    required this.existing,
    required this.allItems,
    required this.groupId,
    required this.createdBy,
    required this.lang,
    required this.l10n,
    required this.onSave,
  });

  @override
  State<_ScheduleFormSheet> createState() => _ScheduleFormSheetState();
}

class _ScheduleFormSheetState extends State<_ScheduleFormSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();

  late DateTime _scheduledTime;
  int _notifyBefore = 5;
  RepeatType _repeat = RepeatType.none;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl.text   = e?.title ?? '';
    _descCtrl.text    = e?.description ?? '';
    _scheduledTime    = e?.scheduledTime ??
        DateTime.now().add(const Duration(hours: 1));
    _notifyBefore     = e?.notifyMinutesBefore ?? 5;
    _repeat           = e?.repeatType ?? RepeatType.none;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledTime),
    );
    if (time == null) return;
    setState(() {
      _scheduledTime = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;

    // Check for exact duplicate timing
    final duplicate = widget.allItems.any((i) =>
        i.id != widget.existing?.id &&
        !i.isCompleted &&
        i.scheduledTime.year == _scheduledTime.year &&
        i.scheduledTime.month == _scheduledTime.month &&
        i.scheduledTime.day == _scheduledTime.day &&
        i.scheduledTime.hour == _scheduledTime.hour &&
        i.scheduledTime.minute == _scheduledTime.minute);

    if (duplicate) {
      final msg = widget.lang == 'zh' 
          ? '相同的计划时间已存在'
          : 'A schedule with this exact time already exists';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      return;
    }

    setState(() => _saving = true);
    
    // Immediately close the dialog to prevent multiple taps, running the network calls in the background.
    Navigator.pop(context);

    final item = ScheduleItem(
      id: widget.existing?.id ?? const Uuid().v4(),
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      scheduledTime: _scheduledTime,
      notifyMinutesBefore: _notifyBefore,
      repeatType: _repeat,
      isCompleted: widget.existing?.isCompleted ?? false,
      groupId: widget.groupId,
      createdBy: widget.createdBy,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
    
    try {
      await widget.onSave(item);
    } catch (e) {
      debugPrint('Error saving schedule item: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final isEdit = widget.existing != null;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        top: 24, left: 24, right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Handle bar
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          )),
          const SizedBox(height: 20),
          Text(
            isEdit ? l10n.editSchedule : l10n.addSchedule,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),

          // Title
          TextField(
            controller: _titleCtrl,
            style: const TextStyle(fontSize: 17),
            decoration: InputDecoration(
              labelText: l10n.taskTitle,
              prefixIcon: const Icon(Icons.title_rounded),
            ),
          ),
          const SizedBox(height: 14),

          // Description
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              labelText: l10n.description,
              prefixIcon: const Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 14),

          // Date & time
          GestureDetector(
            onTap: _pickDateTime,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFBDBDBD)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_month_rounded,
                    color: AppTheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(
                  _formatDateTime(_scheduledTime, widget.lang),
                  style: const TextStyle(fontSize: 16),
                )),
                const Icon(Icons.edit_rounded, color: AppTheme.textSecondary, size: 18),
              ]),
            ),
          ),
          const SizedBox(height: 14),

          // Notify before
          Row(children: [
            const Icon(Icons.notifications_rounded,
                color: AppTheme.primary, size: 22),
            const SizedBox(width: 10),
            Text(l10n.notifyBefore,
                style: const TextStyle(fontSize: 15)),
            const Spacer(),
            DropdownButton<int>(
              value: _notifyBefore,
              items: [0, 5, 10, 15, 30, 60].map((m) => DropdownMenuItem(
                value: m,
                child: Text(
                  m == 0 ? l10n.notifyAtExactTime : '$m ${l10n.minutes}',
                ),
              )).toList(),
              onChanged: (v) => setState(() => _notifyBefore = v!),
            ),
          ]),
          const SizedBox(height: 14),

          // Repeat
          Row(children: [
            const Icon(Icons.repeat_rounded, color: AppTheme.primary, size: 22),
            const SizedBox(width: 10),
            Text(l10n.repeat, style: const TextStyle(fontSize: 15)),
            const Spacer(),
            DropdownButton<RepeatType>(
              value: _repeat,
              items: RepeatType.values.map((t) => DropdownMenuItem(
                value: t,
                child: Text(_repeatLabel(t, l10n)),
              )).toList(),
              onChanged: (v) => setState(() => _repeat = v!),
            ),
          ]),
          const SizedBox(height: 24),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                      isEdit ? l10n.saveChanges : l10n.addSchedule,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  String _repeatLabel(RepeatType t, AppLocalizations l10n) {
    switch (t) {
      case RepeatType.daily:   return l10n.daily;
      case RepeatType.weekly:  return l10n.weekly;
      case RepeatType.monthly: return l10n.monthly;
      default:                 return l10n.noRepeat;
    }
  }
}

// ─── Next Task Card ───────────────────────────────────────────────────────────
class _NextTaskCard extends StatelessWidget {
  final ScheduleItem item;
  final AppLocalizations l10n;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onComplete;
  final String lang;
  const _NextTaskCard({
    required this.item, required this.l10n, required this.onTap,
    required this.onEdit, required this.onComplete, required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    final diff = item.scheduledTime.difference(DateTime.now());
    final soon = diff.inMinutes <= 30;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: soon
                ? [AppTheme.error, AppTheme.error.withOpacity(0.8)]
                : [AppTheme.primary, AppTheme.primaryLight],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(
              color: (soon ? AppTheme.error : AppTheme.primary).withOpacity(0.35),
              blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.access_time_rounded, color: Colors.white70, size: 16),
            const SizedBox(width: 4),
            Expanded(child: Text(
              _formatTime(item.scheduledTime, lang),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('📌 ${l10n.nextTask}',
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            if (soon) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(l10n.soonLabel,
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          Text(item.title,
              style: const TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 15)),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: onEdit,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 6),
                  Text(l10n.edit, style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                ]),
              ),
            )),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: GestureDetector(
              onTap: onComplete,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.4)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 6),
                  Flexible(child: Text(l10n.markDone,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
                ]),
              ),
            )),
          ]),
        ]),
      ),
    );
  }
}

// ─── Schedule List Card ───────────────────────────────────────────────────────
class _ScheduleCard extends StatelessWidget {
  final ScheduleItem item;
  final AppLocalizations l10n;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onComplete;
  final String lang;
  const _ScheduleCard({
    required this.item, required this.l10n, required this.onTap,
    required this.onEdit, required this.onDelete, required this.onComplete,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: item.isCompleted
                    ? AppTheme.success.withOpacity(0.1)
                    : AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                item.isCompleted
                    ? Icons.check_circle_rounded
                    : Icons.event_rounded,
                color: item.isCompleted ? AppTheme.success : AppTheme.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700,
                decoration:
                    item.isCompleted ? TextDecoration.lineThrough : null,
                color: item.isCompleted
                    ? AppTheme.textSecondary
                    : AppTheme.textPrimary,
              )),
              const SizedBox(height: 4),
              Text(_formatTime(item.scheduledTime, lang),
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary)),
            ])),
            PopupMenuButton(
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppTheme.textSecondary),
              itemBuilder: (_) => [
                PopupMenuItem(onTap: onEdit,
                    child: Row(children: [
                  const Icon(Icons.edit_rounded, size: 20),
                  const SizedBox(width: 8), Text(l10n.edit)])),
                if (!item.isCompleted)
                  PopupMenuItem(onTap: onComplete,
                      child: Row(children: [
                    const Icon(Icons.check_rounded,
                        size: 20, color: AppTheme.success),
                    const SizedBox(width: 8), Text(l10n.markDone)])),
                PopupMenuItem(onTap: onDelete,
                    child: Row(children: [
                  const Icon(Icons.delete_rounded,
                      size: 20, color: AppTheme.error),
                  const SizedBox(width: 8),
                  Text(l10n.delete,
                      style: const TextStyle(color: AppTheme.error))])),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DetailRow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 20, color: AppTheme.primary),
    const SizedBox(width: 10),
    Expanded(child: Text(text,
        style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary))),
  ]);
}

// ─── Edit Choice Sheet ────────────────────────────────────────────────────────
// Appears when the user taps "Edit" on an existing task.
// Lets them choose between updating details only (alarm unchanged) or fully
// redeploying the alarm (cancels old alarm, resets rang flag, reschedules).
class _EditChoiceSheet extends StatelessWidget {
  final AppLocalizations l10n;
  final VoidCallback onDetailsOnly;
  final VoidCallback onRedeploy;

  const _EditChoiceSheet({
    required this.l10n,
    required this.onDetailsOnly,
    required this.onRedeploy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.editSchedule,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.editChoiceDesc,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),

          // Details only
          _ChoiceButton(
            icon: Icons.edit_note_rounded,
            color: AppTheme.primary,
            title: l10n.editDetailsOnly,
            subtitle: l10n.editDetailsOnlyDesc,
            onTap: () {
              Navigator.pop(context);
              onDetailsOnly();
            },
          ),
          const SizedBox(height: 12),

          // Redeploy alarm
          _ChoiceButton(
            icon: Icons.alarm_add_rounded,
            color: const Color(0xFFE65100),
            title: l10n.editRedeploy,
            subtitle: l10n.editRedeployDesc,
            onTap: () {
              Navigator.pop(context);
              onRedeploy();
            },
          ),
          const SizedBox(height: 12),

          // Cancel
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel,
                  style: const TextStyle(
                      fontSize: 16, color: AppTheme.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ChoiceButton({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary)),
            ],
          )),
          Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.5)),
        ]),
      ),
    );
  }
}
