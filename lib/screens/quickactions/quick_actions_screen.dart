import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/quick_action_model.dart';
import '../../models/request_model.dart';
import '../../services/auth_provider.dart';
import '../../services/data_service.dart';
import '../../services/stt_service.dart';
import '../../services/tts_service.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class QuickActionsScreen extends StatefulWidget {
  const QuickActionsScreen({super.key});
  @override
  State<QuickActionsScreen> createState() => _QuickActionsScreenState();
}

class _QuickActionsScreenState extends State<QuickActionsScreen> {
  List<QuickActionButton> _buttons = [];
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
    final items = await DataService().getQuickActionsByGroup(groupId);
    if (mounted) setState(() { _buttons = items; _loading = false; });
  }

  // Step 1: confirm send dialog
  Future<void> _confirmAndSend(QuickActionButton btn) async {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.read<AuthProvider>();
    final lang = auth.currentUser?.preferredLanguage ?? 'en';
    // Fix #3/#4: elderly needs at least one caregiver in group first
    if (auth.isElderly && !auth.groupHasCaregivers) {
      final l10nCheck = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10nCheck.needCaregiverFirst),
        backgroundColor: AppTheme.error,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: l10nCheck.inviteCaregiver,
          textColor: Colors.white,
          onPressed: () {},
        ),
      ));
      return;
    }
    await TtsService().speak(btn.label, langCode: lang);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(AppIcons.getIcon(btn.iconName), color: Color(btn.colorValue), size: 32),
          const SizedBox(width: 12),
          Expanded(child: Text(btn.label,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (btn.description.isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 12),
              child: Text(btn.description,
                  style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary))),
          Text(l10n.confirmSend, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => TtsService().speak(btn.label, langCode: lang),
            icon: const Icon(Icons.volume_up_rounded),
            label: Text(l10n.playAudio),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          ),
        ]),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          SizedBox(width: 120, child: OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
            child: Text(l10n.no, style: const TextStyle(fontSize: 18)),
          )),
          SizedBox(width: 120, child: ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 50), backgroundColor: Color(btn.colorValue)),
            child: Text(l10n.yes, style: const TextStyle(fontSize: 18)),
          )),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Step 2: optional details dialog (new)
    final details = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DetailsDialog(lang: lang, l10n: l10n),
    );
    if (!mounted) return;

    // Step 3: create ActionRequest in DataService
    final user = auth.currentUser!;
    final req = ActionRequest(
      id: const Uuid().v4(),
      groupId: auth.currentGroup!.id,
      elderlyId: user.id,
      elderlyName: user.name,
      buttonLabel: btn.label,
      buttonIconName: btn.iconName,
      buttonColorValue: btn.colorValue,
      additionalDetails: details ?? '',
      createdAt: DateTime.now(),
    );
    await DataService().createRequest(req);

    // Notify all caregivers in the group — this works even when their app
    // is closed, as the notification document is picked up by their device's
    // Firestore stream listener (or FCM when fully killed).
    final group = auth.currentGroup!;
    final notifTitle = '🔔 ${user.name} ${l10n.requestFrom}';
    final notifBody  = details != null && details.isNotEmpty
        ? '${btn.label}: $details'
        : btn.label;
    for (final memberId in group.memberIds) {
      await DataService().sendNotificationDocument(
        targetUserId: memberId,
        title: notifTitle,
        body: notifBody,
        channel: 'eldercare_caregiver',
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.requestSent, style: const TextStyle(fontSize: 16)),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  void _openEditor({QuickActionButton? existing}) {
    final auth = context.read<AuthProvider>();
    final group = auth.currentGroup;
    if (group == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickActionEditor(
        existing: existing,
        groupId: group.id,
        createdBy: auth.currentUser!.id,
        onSaved: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthProvider>();
    final isCaregiver = auth.isCaregiver;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.quickActions),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_rounded, size: 30),
            onPressed: () => _openEditor(),
            tooltip: l10n.addQuickAction,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : auth.currentGroup == null
              ? _NoGroupPlaceholder(l10n: l10n)
              : _buttons.isEmpty
                  ? _EmptyPlaceholder(l10n: l10n, onAdd: () => _openEditor())
                  : Column(children: [
                      if (isCaregiver)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          color: AppTheme.primary.withOpacity(0.08),
                          child: Row(children: [
                            const Icon(Icons.info_outline_rounded, color: AppTheme.primary, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(l10n.caregiverViewOnly,
                                style: const TextStyle(fontSize: 13, color: AppTheme.primary))),
                          ]),
                        ),
                      Expanded(child: RefreshIndicator(
                        onRefresh: _load,
                        child: GridView.builder(
                          padding: const EdgeInsets.all(20),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2, crossAxisSpacing: 16,
                            mainAxisSpacing: 16, childAspectRatio: 0.85,
                          ),
                          itemCount: _buttons.length,
                          itemBuilder: (ctx, i) {
                            final btn = _buttons[i];
                            return _QuickActionCard(
                              button: btn,
                              canSend: !isCaregiver,
                              canEdit: true,
                              onTap: isCaregiver ? null : () => _confirmAndSend(btn),
                              onEdit: () => _openEditor(existing: btn),
                              onDelete: () async {
                                await DataService().deleteQuickAction(btn.id);
                                _load();
                              },
                            );
                          },
                        ),
                      )),
                    ]),
      floatingActionButton: (auth.currentGroup != null && _buttons.isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text(l10n.addQuickAction,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }
}

// ─── Details Dialog (STT + typing) ───────────────────────────────────────────
class _DetailsDialog extends StatefulWidget {
  final String lang;
  final AppLocalizations l10n;
  const _DetailsDialog({required this.lang, required this.l10n});
  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  final _ctrl = TextEditingController();
  final _recorder = FlutterSoundRecorder();
  bool _recorderReady = false;
  bool _isRecording = false;
  bool _processing = false;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    _initRecorder();
  }

  Future<void> _initRecorder() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) return;
    await _recorder.openRecorder();
    if (mounted) setState(() => _recorderReady = true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _recorder.closeRecorder();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _recorder.stopRecorder();
      if (!mounted) return;
      setState(() { _isRecording = false; _processing = true; });
      if (_recordingPath != null) {
        final bcp47 = SttService.toBcp47(widget.lang);
        final transcript = await SttService().transcribe(_recordingPath!, bcp47);
        if (mounted) {
          setState(() { _processing = false; });
          if (transcript != null && transcript.isNotEmpty) {
            _ctrl.text = (_ctrl.text.isEmpty ? '' : '${_ctrl.text} ') + transcript;
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(widget.l10n.sttError)));
          }
        }
      }
    } else {
      final dir = await getTemporaryDirectory();
      _recordingPath = '${dir.path}/stt_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.startRecorder(
        toFile: _recordingPath,
        codec: Codec.pcm16WAV,
        sampleRate: 16000,
      );
      setState(() => _isRecording = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l10n;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(l.addDetails,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        // Language indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.language_rounded, size: 16, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(SttService.toBcp47(widget.lang),
                style: const TextStyle(fontSize: 13, color: AppTheme.primary, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _ctrl,
          maxLines: 3,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: l.typeOrSpeak,
            hintStyle: const TextStyle(fontSize: 15),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 14),
        // STT record button
        if (_processing)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
            ]),
          )
        else if (_recorderReady)
          GestureDetector(
            onTap: _toggleRecording,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: _isRecording ? AppTheme.error : AppTheme.primary,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [BoxShadow(
                  color: (_isRecording ? AppTheme.error : AppTheme.primary).withOpacity(0.3),
                  blurRadius: 12, offset: const Offset(0, 4),
                )],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white, size: 24),
                const SizedBox(width: 8),
                Text(_isRecording ? l.stopRecording : l.startRecording,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
      ]),
      actionsAlignment: MainAxisAlignment.spaceEvenly,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(l.skipDetails, style: const TextStyle(fontSize: 16)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          style: ElevatedButton.styleFrom(minimumSize: const Size(100, 48)),
          child: Text(l.sendRequest, style: const TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}

// ─── Quick Action Card ────────────────────────────────────────────────────────
class _QuickActionCard extends StatelessWidget {
  final QuickActionButton button;
  final bool canSend;
  final bool canEdit;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _QuickActionCard({
    required this.button, required this.canSend, required this.canEdit,
    required this.onTap, required this.onEdit, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(button.colorValue);
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: canSend ? onTap : null,
      onLongPress: canEdit ? () {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded, size: 26),
              title: Text(l10n.edit, style: const TextStyle(fontSize: 18)),
              onTap: () { Navigator.pop(ctx); onEdit(); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: AppTheme.error, size: 26),
              title: Text(l10n.delete, style: const TextStyle(fontSize: 18, color: AppTheme.error)),
              onTap: () { Navigator.pop(ctx); onDelete(); },
            ),
          ])),
        );
      } : null,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withOpacity(canSend ? 0.7 : 0.5)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(
            color: color.withOpacity(canSend ? 0.35 : 0.15),
            blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(AppIcons.getIcon(button.iconName),
              color: Colors.white.withOpacity(canSend ? 1.0 : 0.7), size: 52),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(button.label, textAlign: TextAlign.center,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white.withOpacity(canSend ? 1.0 : 0.8),
                    fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          Text(l10n.holdToEdit,
              style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11)),
        ]),
      ),
    );
  }
}

// ─── Placeholders ─────────────────────────────────────────────────────────────
class _NoGroupPlaceholder extends StatelessWidget {
  final AppLocalizations l10n;
  const _NoGroupPlaceholder({required this.l10n});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.group_off_rounded, size: 80, color: AppTheme.textSecondary),
      const SizedBox(height: 16),
      Text(l10n.noGroup, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      Text(l10n.joinOrCreate, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
    ]),
  ));
}

class _EmptyPlaceholder extends StatelessWidget {
  final AppLocalizations l10n;
  final VoidCallback onAdd;
  const _EmptyPlaceholder({required this.l10n, required this.onAdd});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.touch_app_rounded, size: 80, color: AppTheme.textSecondary),
      const SizedBox(height: 16),
      Text(l10n.addQuickAction,
          style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded, size: 28),
        label: Text(l10n.addQuickAction),
      ),
    ]),
  ));
}

// ─── Editor Bottom Sheet ──────────────────────────────────────────────────────
class _QuickActionEditor extends StatefulWidget {
  final QuickActionButton? existing;
  final String groupId;
  final String createdBy;
  final VoidCallback onSaved;
  const _QuickActionEditor({this.existing, required this.groupId,
      required this.createdBy, required this.onSaved});
  @override
  State<_QuickActionEditor> createState() => _QuickActionEditorState();
}

class _QuickActionEditorState extends State<_QuickActionEditor> {
  final _labelCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _selectedIcon = 'notifications';
  Color _selectedColor = AppTheme.primary;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _labelCtrl.text = widget.existing!.label;
      _descCtrl.text = widget.existing!.description;
      _selectedIcon = widget.existing!.iconName;
      _selectedColor = Color(widget.existing!.colorValue);
    }
  }

  @override
  void dispose() { _labelCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    if (_labelCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.fillAllFields)));
      return;
    }
    setState(() => _saving = true);
    final ds = DataService();
    if (widget.existing != null) {
      await ds.updateQuickAction(widget.existing!.copyWith(
        label: _labelCtrl.text.trim(), description: _descCtrl.text.trim(),
        iconName: _selectedIcon, colorValue: _selectedColor.value,
      ));
    } else {
      await ds.createQuickAction(QuickActionButton(
        id: const Uuid().v4(),
        label: _labelCtrl.text.trim(), description: _descCtrl.text.trim(),
        iconName: _selectedIcon, colorValue: _selectedColor.value,
        groupId: widget.groupId, createdBy: widget.createdBy,
        createdAt: DateTime.now(),
      ));
    }
    if (mounted) Navigator.pop(context);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      initialChildSize: 0.92, maxChildSize: 0.97, minChildSize: 0.6,
      builder: (ctx, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          Container(width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Text(widget.existing == null ? l10n.addQuickAction : l10n.editQuickAction,
                style: Theme.of(context).textTheme.titleLarge),
          ),
          Expanded(child: ListView(controller: ctrl,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            children: [
              Center(child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 110, height: 110,
                decoration: BoxDecoration(color: _selectedColor, borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: _selectedColor.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))]),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(AppIcons.getIcon(_selectedIcon), color: Colors.white, size: 44),
                  const SizedBox(height: 6),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(_labelCtrl.text.isEmpty ? '...' : _labelCtrl.text,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))),
                ]),
              )),
              const SizedBox(height: 24),
              TextField(controller: _labelCtrl, onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 17),
                  decoration: InputDecoration(labelText: l10n.buttonLabel, prefixIcon: const Icon(Icons.label_rounded))),
              const SizedBox(height: 16),
              TextField(controller: _descCtrl, style: const TextStyle(fontSize: 17), maxLines: 2,
                  decoration: InputDecoration(labelText: l10n.buttonDescription, prefixIcon: const Icon(Icons.description_rounded))),
              const SizedBox(height: 24),
              Text(l10n.selectColor, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => _pickColor(context),
                child: Container(height: 56,
                  decoration: BoxDecoration(color: _selectedColor, borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: _selectedColor.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))]),
                  child: const Center(child: Icon(Icons.palette_rounded, color: Colors.white, size: 28))),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10,
                children: AppColors.presetColors.map((c) => GestureDetector(
                  onTap: () => setState(() => _selectedColor = c),
                  child: Container(width: 40, height: 40,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle,
                        border: Border.all(color: _selectedColor == c ? AppTheme.textPrimary : Colors.transparent, width: 3),
                        boxShadow: [BoxShadow(color: c.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))])),
                )).toList()),
              const SizedBox(height: 24),
              Text(l10n.selectIcon, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFCFD8DC))),
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 12, runSpacing: 12,
                  children: AppIcons.iconMap.entries.map((e) {
                    final selected = e.key == _selectedIcon;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedIcon = e.key),
                      child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                        width: 56, height: 56,
                        decoration: BoxDecoration(color: selected ? _selectedColor : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: selected ? _selectedColor : const Color(0xFFCFD8DC), width: 2),
                            boxShadow: selected ? [BoxShadow(color: _selectedColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : []),
                        child: Icon(e.value, size: 28, color: selected ? Colors.white : AppTheme.textSecondary)),
                    );
                  }).toList()),
              ),
              const SizedBox(height: 32),
              _saving ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(onPressed: _save, child: Text(l10n.save)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
              const SizedBox(height: 24),
            ],
          )),
        ]),
      ),
    );
  }

  void _pickColor(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        Color temp = _selectedColor;
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.selectColor),
          content: SingleChildScrollView(child: ColorPicker(
            pickerColor: temp, onColorChanged: (c) => temp = c,
            pickerAreaHeightPercent: 0.5, enableAlpha: false,
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            ElevatedButton(onPressed: () { setState(() => _selectedColor = temp); Navigator.pop(ctx); }, child: Text(l10n.confirm)),
          ],
        );
      },
    );
  }
}
