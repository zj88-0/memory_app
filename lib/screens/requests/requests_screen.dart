import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/request_model.dart';
import '../../services/auth_provider.dart';
import '../../services/data_service.dart';
import '../../services/tts_service.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});
  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen>
    with SingleTickerProviderStateMixin {
  List<ActionRequest> _all = [];
  bool _loading = true;
  late TabController _tabs;

  StreamSubscription<List<ActionRequest>>? _sub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void _listen() {
    final auth = context.read<AuthProvider>();
    final gid = auth.currentGroup?.id;
    if (gid == null) { setState(() => _loading = false); return; }
    _sub?.cancel();
    _sub = DataService().streamRequestsByGroup(gid).listen((reqs) {
      if (mounted) setState(() { _all = reqs; _loading = false; });
    });
  }

  Future<void> _load() async {
    _listen();
  }

  List<ActionRequest> get _pending  => _all.where((r) => r.status == RequestStatus.pending).toList();
  List<ActionRequest> get _claimed  => _all.where((r) => r.status == RequestStatus.claimed).toList();
  List<ActionRequest> get _done     => _all.where((r) => r.status == RequestStatus.completed).toList();

  Future<void> _claim(ActionRequest req) async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser!;
    await DataService().updateRequest(req.copyWith(
      status: RequestStatus.claimed,
      claimedById: user.id,
      claimedByName: user.name,
      claimedAt: DateTime.now(),
    ));
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.requestClaimed),
        backgroundColor: AppTheme.primary,
      ));
    }
  }

  Future<void> _complete(ActionRequest req) async {
    await DataService().updateRequest(
        req.copyWith(status: RequestStatus.completed, completedAt: DateTime.now()));
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.requestCompleted),
        backgroundColor: AppTheme.success,
      ));
    }
  }

  // Fix #5: Clear all completed requests
  Future<void> _clearCompleted() async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.clearCompleted),
        content: Text(l10n.clearCompletedConfirm),
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
    if (confirm == true) {
      for (final r in _done) {
        await DataService().deleteRequest(r.id);
      }
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthProvider>();
    final isCaregiver = auth.isCaregiver;
    final lang = auth.currentUser?.preferredLanguage ?? 'en';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.requests),
        // Fix #5: Clear completed button
        actions: [
          if (_done.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
              tooltip: l10n.clearCompleted,
              onPressed: _clearCompleted,
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          // Fix #5: white text on coloured AppBar
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          tabs: [
            Tab(text: '${l10n.pending} (${_pending.length})'),
            Tab(text: '${l10n.claimed} (${_claimed.length})'),
            Tab(text: l10n.completed),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : auth.currentGroup == null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(l10n.joinOrCreate,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                ))
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildList(_pending, l10n, isCaregiver, lang,
                        onClaim: _claim, onComplete: null),
                    _buildList(_claimed, l10n, isCaregiver, lang,
                        onClaim: null, onComplete: _complete),
                    _buildList(_done, l10n, isCaregiver, lang,
                        onClaim: null, onComplete: null, showClear: true),
                  ],
                ),
    );
  }

  Widget _buildList(
    List<ActionRequest> reqs, AppLocalizations l10n,
    bool isCaregiver, String lang, {
    Future<void> Function(ActionRequest)? onClaim,
    Future<void> Function(ActionRequest)? onComplete,
    bool showClear = false,
  }) {
    if (reqs.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.inbox_rounded, size: 64, color: AppTheme.textSecondary),
        const SizedBox(height: 12),
        Text(l10n.noRequests,
            style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: reqs.length,
        itemBuilder: (ctx, i) => _RequestCard(
          req: reqs[i], l10n: l10n, isCaregiver: isCaregiver,
          onClaim: onClaim, onComplete: onComplete, lang: lang,
        ),
      ),
    );
  }
}

// ─── Request Card ─────────────────────────────────────────────────────────────
class _RequestCard extends StatelessWidget {
  final ActionRequest req;
  final AppLocalizations l10n;
  final bool isCaregiver;
  final Future<void> Function(ActionRequest)? onClaim;
  final Future<void> Function(ActionRequest)? onComplete;
  final String lang;

  const _RequestCard({
    required this.req, required this.l10n, required this.isCaregiver,
    required this.onClaim, required this.onComplete, required this.lang,
  });

  Color get _statusColor {
    switch (req.status) {
      case RequestStatus.pending:   return AppTheme.warning;
      case RequestStatus.claimed:   return AppTheme.primary;
      case RequestStatus.completed: return AppTheme.success;
    }
  }

  String _statusLabel(AppLocalizations l) {
    switch (req.status) {
      case RequestStatus.pending:   return l.pending;
      case RequestStatus.claimed:   return l.claimed;
      case RequestStatus.completed: return l.completed;
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return DateFormat('dd MMM HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(req.buttonColorValue);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 3,
      shadowColor: color.withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(AppIcons.getIcon(req.buttonIconName), color: color, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(req.buttonLabel,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
              Text('${l10n.requestFrom} ${req.elderlyName}',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(_statusLabel(l10n),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: _statusColor)),
            ),
          ]),

          if (req.additionalDetails.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppTheme.background, borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.notes_rounded, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Expanded(child: Text(req.additionalDetails,
                    style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary))),
                IconButton(
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  icon: const Icon(Icons.volume_up_rounded, size: 18, color: AppTheme.primary),
                  onPressed: () =>
                      TtsService().speak(req.additionalDetails, langCode: lang),
                ),
              ]),
            ),
          ],

          if (req.claimedByName != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.person_rounded, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Text('${l10n.claimedBy} ${req.claimedByName}',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ]),
          ],

          const SizedBox(height: 8),
          Text(_timeAgo(req.createdAt),
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),

          if (isCaregiver && (onClaim != null || onComplete != null)) ...[
            const SizedBox(height: 14),
            Row(children: [
              if (onClaim != null)
                Expanded(child: ElevatedButton.icon(
                  onPressed: () => onClaim!(req),
                  icon: const Icon(Icons.pan_tool_rounded, size: 18),
                  label: Text(l10n.claimRequest,
                      style: const TextStyle(fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                      backgroundColor: AppTheme.primary),
                )),
              if (onComplete != null) ...[
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton.icon(
                  onPressed: () => onComplete!(req),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(l10n.completeRequest,
                      style: const TextStyle(fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                      backgroundColor: AppTheme.success),
                )),
              ],
            ]),
          ],
        ]),
      ),
    );
  }
}
