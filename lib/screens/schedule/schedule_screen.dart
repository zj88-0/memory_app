import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../models/schedule_model.dart';
import '../../services/auth_provider.dart';
import '../../services/data_service.dart';
import '../../services/notification_service.dart';
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
  final time = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final groupId = auth.currentGroup?.id;
    if (groupId == null) { setState(() => _loading = false); return; }
    final items = await DataService().getSchedulesByGroup(groupId);
    if (mounted) setState(() { _items = items; _loading = false; });
  }

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

    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (auth.currentGroup == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.schedule)),
        body: Center(child: Text(l10n.joinOrCreate,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 18))),
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
                const Icon(Icons.calendar_today_rounded, size: 80, color: AppTheme.textSecondary),
                const SizedBox(height: 16),
                Text(l10n.noUpcomingTasks,
                    style: const TextStyle(fontSize: 20, color: AppTheme.textSecondary)),
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
                    Text(l10n.allTasks, style: Theme.of(context).textTheme.titleLarge),
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

  Future<void> _markComplete(ScheduleItem item) async {
    await DataService().updateSchedule(item.copyWith(isCompleted: true));
    _load();
  }

  Future<void> _delete(ScheduleItem item) async {
    await NotificationService().cancelNotification(item.id);
    await DataService().deleteSchedule(item.id);
    _load();
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
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.event_rounded, color: AppTheme.primary, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(item.title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
                  text: '${l10n.notifyBefore}: ${item.notifyMinutesBefore} ${l10n.minutes}'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => tts.speak('${item.title}. ${item.description}', langCode: lang),
                  icon: const Icon(Icons.volume_up_rounded, size: 28),
                  label: Text(l10n.tapToSpeak, style: const TextStyle(fontSize: 17)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    minimumSize: const Size(double.infinity, 56),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel, style: const TextStyle(fontSize: 16)),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: () { Navigator.pop(context); _markComplete(item); },
                  child: Text(l10n.markDone, style: const TextStyle(fontSize: 16)),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _showScheduleDialog(BuildContext context, {ScheduleItem? item}) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.read<AuthProvider>();
    final isEdit = item != null;

    final titleCtrl = TextEditingController(text: item?.title ?? '');
    final descCtrl = TextEditingController(text: item?.description ?? '');
    DateTime selectedTime = item?.scheduledTime ?? DateTime.now().add(const Duration(hours: 1));
    int notifyMins = item?.notifyMinutesBefore ?? 5;
    RepeatType repeat = item?.repeatType ?? RepeatType.none;
    final lang = auth.currentUser?.preferredLanguage ?? 'en';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 16),
              Text(isEdit ? l10n.editSchedule : l10n.addSchedule,
                  style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 24),
              TextField(
                controller: titleCtrl,
                style: const TextStyle(fontSize: 17),
                decoration: InputDecoration(
                  labelText: l10n.taskTitle,
                  prefixIcon: const Icon(Icons.title_rounded, color: AppTheme.primary)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: descCtrl,
                style: const TextStyle(fontSize: 16), maxLines: 2,
                decoration: InputDecoration(
                  labelText: l10n.taskDescription,
                  prefixIcon: const Icon(Icons.notes_rounded, color: AppTheme.primary)),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    initialDate: selectedTime,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date == null) return;
                  if (!ctx.mounted) return;
                  final time = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.fromDateTime(selectedTime),
                  );
                  if (time == null) return;
                  setModal(() {
                    selectedTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFDDE2E8)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.access_time_rounded, color: AppTheme.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(
                      _formatDateTime(selectedTime, lang),
                      style: const TextStyle(fontSize: 16),
                    )),
                    const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                value: notifyMins,
                decoration: InputDecoration(
                  labelText: '${l10n.notifyBefore} (${l10n.minutes})',
                  prefixIcon: const Icon(Icons.notifications_rounded, color: AppTheme.primary),
                ),
                items: [2, 5, 10, 15, 30, 60].map((m) =>
                    DropdownMenuItem(value: m, child: Text('$m ${l10n.minutes}',
                        style: const TextStyle(fontSize: 16)))).toList(),
                onChanged: (v) => setModal(() => notifyMins = v ?? 5),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<RepeatType>(
                value: repeat,
                decoration: const InputDecoration(
                  labelText: 'Repeat',
                  prefixIcon: Icon(Icons.repeat_rounded, color: AppTheme.primary),
                ),
                items: [
                  DropdownMenuItem(value: RepeatType.none, child: Text(l10n.repeatNone, style: const TextStyle(fontSize: 16))),
                  DropdownMenuItem(value: RepeatType.daily, child: Text(l10n.repeatDaily, style: const TextStyle(fontSize: 16))),
                  DropdownMenuItem(value: RepeatType.weekly, child: Text(l10n.repeatWeekly, style: const TextStyle(fontSize: 16))),
                  DropdownMenuItem(value: RepeatType.monthly, child: Text(l10n.repeatMonthly, style: const TextStyle(fontSize: 16))),
                ],
                onChanged: (v) => setModal(() => repeat = v ?? RepeatType.none),
              ),
              const SizedBox(height: 28),
              Row(children: [
                if (isEdit) ...[
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () { Navigator.pop(ctx); _delete(item); },
                    icon: const Icon(Icons.delete_rounded, color: AppTheme.error),
                    label: Text(l10n.delete,
                        style: const TextStyle(color: AppTheme.error, fontSize: 16)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.error),
                      minimumSize: const Size(0, 56),
                    ),
                  )),
                  const SizedBox(width: 12),
                ],
                Expanded(flex: 2, child: ElevatedButton(
                  onPressed: () async {
                    if (titleCtrl.text.isEmpty) return;
                    final groupId = auth.currentGroup?.id ?? '';
                    final newItem = isEdit
                        ? item.copyWith(
                            title: titleCtrl.text.trim(),
                            description: descCtrl.text.trim(),
                            scheduledTime: selectedTime,
                            notifyMinutesBefore: notifyMins,
                            repeatType: repeat,
                          )
                        : ScheduleItem(
                            id: const Uuid().v4(),
                            title: titleCtrl.text.trim(),
                            description: descCtrl.text.trim(),
                            scheduledTime: selectedTime,
                            notifyMinutesBefore: notifyMins,
                            repeatType: repeat,
                            groupId: groupId,
                            createdBy: auth.currentUser?.id ?? '',
                            createdAt: DateTime.now(),
                          );
                    if (isEdit) {
                      await DataService().updateSchedule(newItem);
                    } else {
                      await DataService().createSchedule(newItem);
                    }
                    // Fix #4: schedule reminders are for elderly only
                    if (auth.isElderly) {
                      await NotificationService().scheduleReminderNotification(newItem);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 56)),
                  child: Text(l10n.save, style: const TextStyle(fontSize: 18)),
                )),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Next Task Card (pinned) ──────────────────────────────────────────────────
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
          // Fix #2: date/time row on TOP
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
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            // Fix #2: use l10n for "Soon!" text
            if (soon) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(l10n.soonLabel,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          Text(item.title,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 15)),
          ],
          const SizedBox(height: 16),
          // Fix #2: Edit and Mark Done as big full-width buttons in a row below
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
                  Text(l10n.edit,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
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
                  // Fix #2: prevent overflow - use Flexible for text
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
                item.isCompleted ? Icons.check_circle_rounded : Icons.event_rounded,
                color: item.isCompleted ? AppTheme.success : AppTheme.primary, size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700,
                decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                color: item.isCompleted ? AppTheme.textSecondary : AppTheme.textPrimary,
              )),
              const SizedBox(height: 4),
              Text(_formatTime(item.scheduledTime, lang),
                  style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
            ])),
            PopupMenuButton(
              icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary),
              itemBuilder: (_) => [
                PopupMenuItem(onTap: onEdit, child: Row(children: [
                  const Icon(Icons.edit_rounded, size: 20),
                  const SizedBox(width: 8), Text(l10n.edit)])),
                if (!item.isCompleted)
                  PopupMenuItem(onTap: onComplete, child: Row(children: [
                    const Icon(Icons.check_rounded, size: 20, color: AppTheme.success),
                    const SizedBox(width: 8), Text(l10n.markDone)])),
                PopupMenuItem(onTap: onDelete, child: Row(children: [
                  const Icon(Icons.delete_rounded, size: 20, color: AppTheme.error),
                  const SizedBox(width: 8),
                  Text(l10n.delete, style: const TextStyle(color: AppTheme.error))])),
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
    Expanded(child: Text(text, style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary))),
  ]);
}
