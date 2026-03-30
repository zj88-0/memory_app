import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/moment_model.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../services/data_service.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

class MomentsScreen extends StatefulWidget {
  const MomentsScreen({super.key});
  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  List<Moment> _moments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final gid = auth.currentGroup?.id;
    if (gid == null) { setState(() => _loading = false); return; }

    // Always show local first for speed
    final local = await DataService().getMomentsByGroup(gid);
    if (mounted) setState(() { _moments = local; _loading = false; });

    // Then try to merge from server in background
    _syncFromServer(gid);
  }

  Future<void> _syncFromServer(String gid) async {
    final serverData = await ApiService().fetchMoments(gid);
    if (serverData.isEmpty || !mounted) return;
    final serverMoments = serverData.map(Moment.fromJson).toList();
    // Update local state with server data (server is source of truth for imageUrl)
    if (mounted) setState(() => _moments = serverMoments);
  }

  void _showAddDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMomentSheet(onPosted: _load),
    );
  }

  // Fix #6: instant optimistic delete — remove from UI immediately,
  // then delete from local storage and server in background
  void _deleteOptimistic(Moment moment) {
    // Immediately remove from UI
    setState(() => _moments.removeWhere((m) => m.id == moment.id));
    // Background cleanup
    _deleteInBackground(moment);
  }

  Future<void> _deleteInBackground(Moment moment) async {
    await DataService().deleteMoment(moment.id);
    await ApiService().deleteMoment(moment.id); // fire-and-forget, errors ignored
  }

  Future<void> _confirmDelete(Moment moment) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteMoment),
        content: Text(l10n.deleteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirm == true) _deleteOptimistic(moment);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l10n.moments)),
      floatingActionButton: auth.currentGroup != null
          ? FloatingActionButton.extended(
              onPressed: _showAddDialog,
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white),
              label: Text(l10n.addMoment,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : auth.currentGroup == null
              ? Center(child: Text(l10n.joinOrCreate,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary)))
              : _moments.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.photo_library_rounded, size: 80,
                          color: AppTheme.textSecondary),
                      const SizedBox(height: 16),
                      Text(l10n.noMoments,
                          style: const TextStyle(fontSize: 17, color: AppTheme.textSecondary)),
                    ]))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: _moments.length,
                        itemBuilder: (ctx, i) => _MomentCard(
                          moment: _moments[i],
                          l10n: l10n,
                          currentUserId: auth.currentUser?.id ?? '',
                          onDelete: () => _confirmDelete(_moments[i]),
                        ),
                      ),
                    ),
    );
  }
}

// ─── Add Moment Sheet ─────────────────────────────────────────────────────────
class _AddMomentSheet extends StatefulWidget {
  final VoidCallback onPosted;
  const _AddMomentSheet({required this.onPosted});
  @override
  State<_AddMomentSheet> createState() => _AddMomentSheetState();
}

class _AddMomentSheetState extends State<_AddMomentSheet> {
  final _captionCtrl = TextEditingController();
  File? _imageFile;
  bool _posting = false;

  @override
  void dispose() { _captionCtrl.dispose(); super.dispose(); }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: source, imageQuality: 75, maxWidth: 1200);
    if (picked != null) setState(() => _imageFile = File(picked.path));
  }

  Future<void> _post() async {
    final l10n = AppLocalizations.of(context)!;
    if (_captionCtrl.text.trim().isEmpty && _imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.fillAllFields)));
      return;
    }
    setState(() => _posting = true);
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser!;
    final id = const Uuid().v4();

    // Fix #2: Store base64 locally so it displays immediately on this device
    String? base64Image;
    if (_imageFile != null) {
      final bytes = await _imageFile!.readAsBytes();
      base64Image = base64Encode(bytes);
    }

    final moment = Moment(
      id: id, groupId: auth.currentGroup!.id,
      authorId: user.id, authorName: user.name,
      caption: _captionCtrl.text.trim(),
      imageBase64: base64Image,
      createdAt: DateTime.now(),
    );

    // Save locally first — user sees it immediately
    await DataService().createMoment(moment);

    // Upload to server in background (Fix #2: real multipart upload with image file)
    if (_imageFile != null) {
      ApiService().uploadMoment(
        id: id, groupId: auth.currentGroup!.id,
        authorId: user.id, authorName: user.name,
        caption: moment.caption,
        imagePath: _imageFile!.path,
      );
    } else {
      ApiService().uploadMoment(
        id: id, groupId: auth.currentGroup!.id,
        authorId: user.id, authorName: user.name,
        caption: moment.caption,
      );
    }

    if (mounted) Navigator.pop(context);
    widget.onPosted();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.5,
      builder: (ctx, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(controller: ctrl, padding: const EdgeInsets.all(24), children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
          )),
          const SizedBox(height: 16),
          Text(l10n.shareYourDay,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: 20),

          if (_imageFile != null)
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(_imageFile!, width: double.infinity,
                    height: 200, fit: BoxFit.cover),
              ),
              Positioned(top: 8, right: 8,
                child: GestureDetector(
                  onTap: () => setState(() => _imageFile = null),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 18),
                  ),
                )),
            ])
          else
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_rounded),
                label: Text(l10n.pickImage, overflow: TextOverflow.ellipsis),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
              )),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_rounded),
                label: Text(l10n.takePhoto, overflow: TextOverflow.ellipsis),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
              )),
            ]),
          const SizedBox(height: 16),

          TextField(
            controller: _captionCtrl, maxLines: 4,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: l10n.momentCaption,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 20),
          _posting
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
                  onPressed: _post,
                  child: Text(l10n.postMoment,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
        ]),
      ),
    );
  }
}

// ─── Moment Card ──────────────────────────────────────────────────────────────
class _MomentCard extends StatelessWidget {
  final Moment moment;
  final AppLocalizations l10n;
  final String currentUserId;
  final VoidCallback onDelete;

  const _MomentCard({
    required this.moment, required this.l10n,
    required this.currentUserId, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Fix #2: show base64 local image; fall back to server URL
    Widget? imageWidget;
    if (moment.imageBase64 != null) {
      try {
        imageWidget = Image.memory(
          base64Decode(moment.imageBase64!),
          width: double.infinity, height: 220, fit: BoxFit.cover,
        );
      } catch (_) {}
    } else if (moment.imageUrl != null) {
      imageWidget = Image.network(
        ApiService.imageUrl(moment.id),
        width: double.infinity, height: 220, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 3,
      shadowColor: AppTheme.primary.withOpacity(0.1),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (imageWidget != null)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: imageWidget,
          ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.primary.withOpacity(0.12),
                child: Text(
                  moment.authorName.isNotEmpty
                      ? moment.authorName[0].toUpperCase() : '?',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppTheme.primary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(moment.authorName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                Text(DateFormat('dd MMM yyyy, HH:mm').format(moment.createdAt),
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
              ])),
              if (moment.authorId == currentUserId)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppTheme.error, size: 22),
                  onPressed: onDelete,
                ),
            ]),

            if (moment.caption.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(moment.caption, style: const TextStyle(fontSize: 15)),
            ],
          ]),
        ),
      ]),
    );
  }
}
