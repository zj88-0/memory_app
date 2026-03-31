import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_provider.dart';
import '../../services/data_service.dart';
import '../../utils/app_theme.dart';
import 'elderly_management_page.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key});
  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final l10n = AppLocalizations.of(context)!;
    final group = auth.currentGroup;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l10n.myGroup)),
      body: group == null
          ? _NoGroupView(l10n: l10n, auth: auth, onRefresh: () => auth.refreshGroup())
          : _GroupDetailView(group: group, auth: auth, l10n: l10n),
    );
  }
}

// ─── No Group View ────────────────────────────────────────────────────────────
class _NoGroupView extends StatelessWidget {
  final AppLocalizations l10n;
  final AuthProvider auth;
  final VoidCallback onRefresh;
  const _NoGroupView({required this.l10n, required this.auth, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_add_rounded, size: 90, color: AppTheme.primary),
            const SizedBox(height: 16),
            Text(l10n.noGroup, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(l10n.joinOrCreate,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showCreateDialog(context),
              icon: const Icon(Icons.add_rounded, size: 26),
              label: Text(l10n.createGroup),
            ),
            if (auth.isCaregiver) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _showJoinDialog(context),
                icon: const Icon(Icons.login_rounded, size: 26),
                label: Text(l10n.joinGroup),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final ctrl = TextEditingController();
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l.createGroup, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(fontSize: 17),
          decoration: InputDecoration(labelText: l.groupName, prefixIcon: const Icon(Icons.group_rounded)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              final user = auth.currentUser!;
              final group = CareGroup(
                id: const Uuid().v4(),
                name: ctrl.text.trim(),
                adminId: user.id,
                memberIds: user.role == UserRole.caregiver ? [user.id] : [],
                elderlyId: user.role == UserRole.elderly ? user.id : '',
                createdAt: DateTime.now(),
              );
              await DataService().createGroup(group);
              await DataService().updateUser(user.copyWith(groupId: group.id));
              await auth.refreshGroup();
              onRefresh();
            },
            child: Text(l.save),
          ),
        ],
      ),
    );
  }

  void _showJoinDialog(BuildContext context) {
    final ctrl = TextEditingController();
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l.joinGroup, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl, autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontSize: 20, letterSpacing: 2, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
              labelText: l.inviteCode, prefixIcon: const Icon(Icons.vpn_key_rounded)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ds = DataService();
              final group = await ds.getGroupByInviteCode(ctrl.text.trim());
              if (!context.mounted) return;
              if (group == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.invalidCode), backgroundColor: AppTheme.error));
                return;
              }
              if (group.isFull) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.groupFull), backgroundColor: AppTheme.error));
                return;
              }
              final joined = await ds.joinGroup(group.id, auth.currentUser!.id);
              if (joined) {
                await ds.updateUser(auth.currentUser!.copyWith(groupId: group.id));
                await auth.refreshGroup();
                onRefresh();
              }
            },
            child: Text(l.joinGroup),
          ),
        ],
      ),
    );
  }
}

// ─── Group Detail View ────────────────────────────────────────────────────────
class _GroupDetailView extends StatefulWidget {
  final CareGroup group;
  final AuthProvider auth;
  final AppLocalizations l10n;
  const _GroupDetailView({required this.group, required this.auth, required this.l10n});
  @override
  State<_GroupDetailView> createState() => _GroupDetailViewState();
}

class _GroupDetailViewState extends State<_GroupDetailView> {
  List<UserModel> _members = [];
  UserModel? _elderly;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final ds = DataService();
    final members = <UserModel>[];
    for (final id in widget.group.memberIds) {
      final u = await ds.getUserById(id);
      if (u != null) members.add(u);
    }
    final elderly = await ds.getUserById(widget.group.elderlyId);
    if (mounted) setState(() { _members = members; _elderly = elderly; });
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.group.inviteCode));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.l10n.copied), duration: const Duration(seconds: 2)));
    }
  }

  void _showEmailInviteDialog() {
    final l = widget.l10n;
    final emailCtrl = TextEditingController();
    UserModel? foundUser;
    String? resultMsg;
    bool isError = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l.inviteByEmail,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  labelText: l.email,
                  prefixIcon: const Icon(Icons.email_rounded),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search_rounded),
                    onPressed: () async {
                      final email = emailCtrl.text.trim();
                      if (email.isEmpty) return;
                      final user = await DataService().getUserByEmail(email);
                      if (!ctx.mounted) return;
                      if (user == null) {
                        setDlg(() { foundUser = null; resultMsg = l.emailNotFound; isError = true; });
                        return;
                      }
                      if (user.id == widget.auth.currentUser?.id) {
                        setDlg(() { foundUser = null; resultMsg = l.alreadyMember; isError = true; });
                        return;
                      }
                      final alreadyIn = widget.group.memberIds.contains(user.id) ||
                          widget.group.elderlyId == user.id;
                      if (alreadyIn) {
                        setDlg(() { foundUser = null; resultMsg = l.alreadyMember; isError = true; });
                        return;
                      }
                      if (widget.group.isFull) {
                        setDlg(() { foundUser = null; resultMsg = l.groupFull; isError = true; });
                        return;
                      }
                      setDlg(() { foundUser = user; resultMsg = null; isError = false; });
                    },
                  ),
                ),
              ),
              if (resultMsg != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (isError ? AppTheme.error : AppTheme.success).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: (isError ? AppTheme.error : AppTheme.success).withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                        color: isError ? AppTheme.error : AppTheme.success, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(resultMsg!,
                        style: TextStyle(fontSize: 14,
                            color: isError ? AppTheme.error : AppTheme.success))),
                  ]),
                ),
              ],
              if (foundUser != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.primary.withOpacity(0.15),
                      child: Text(foundUser!.name[0].toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(foundUser!.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(foundUser!.email,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          overflow: TextOverflow.ellipsis),
                    ])),
                  ]),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Icons.vpn_key_rounded, color: AppTheme.success, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      '${l.inviteCode}: ${widget.group.inviteCode}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                          color: AppTheme.success),
                    )),
                    IconButton(
                      padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                      icon: const Icon(Icons.copy_rounded, color: AppTheme.success, size: 18),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: widget.group.inviteCode));
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(l.copied)));
                        }
                      },
                    ),
                  ]),
                ),
                const SizedBox(height: 4),
                Text(l.userInvited,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          ],
        ),
      ),
    );
  }

  Future<void> _removeMember(UserModel member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.l10n.removeUser),
        content: Text('${member.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(widget.l10n.cancel)),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(widget.l10n.delete)),
        ],
      ),
    );
    if (confirmed == true) {
      await DataService().leaveGroup(widget.group.id, member.id);
      await DataService().updateUser(member.copyWith(groupId: null));
      await widget.auth.refreshGroup();
      _loadMembers();
    }
  }

  Future<void> _makeAdmin(UserModel member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.l10n.makeAdmin),
        content: Text(widget.l10n.confirmMakeAdmin),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(widget.l10n.cancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(widget.l10n.confirm)),
        ],
      ),
    );
    if (confirmed == true) {
      final updated = widget.group.copyWith(adminId: member.id);
      await DataService().updateGroup(updated);
      await widget.auth.refreshGroup();
      _loadMembers();
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.l10n.leaveGroup),
        content: Text(widget.l10n.deleteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(widget.l10n.cancel)),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(widget.l10n.yes)),
        ],
      ),
    );
    if (confirmed == true) {
      final user = widget.auth.currentUser!;
      await DataService().leaveGroup(widget.group.id, user.id);
      await DataService().updateUser(user.copyWith(groupId: null));
      await widget.auth.refreshGroup();
    }
  }

  Future<void> _renameGroup() async {
    final ctrl = TextEditingController(text: widget.group.name);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.l10n.groupName),
        content: TextField(
            controller: ctrl, autofocus: true,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.edit_rounded))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(widget.l10n.cancel)),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              await DataService().updateGroup(widget.group.copyWith(name: ctrl.text.trim()));
              await widget.auth.refreshGroup();
            },
            child: Text(widget.l10n.save),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.group.adminId == widget.auth.currentUser?.id;
    final l = widget.l10n;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header card
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryLight],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(
                  color: AppTheme.primary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.group_rounded, color: Colors.white, size: 36),
                const SizedBox(width: 12),
                Expanded(child: Text(widget.group.name,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis)),
                if (isAdmin)
                  IconButton(
                      icon: const Icon(Icons.edit_rounded, color: Colors.white),
                      onPressed: _renameGroup),
              ]),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${l.inviteCodeLabel}: ',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(widget.group.inviteCode,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.w800, letterSpacing: 2)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: _copyCode,
                    child: const Icon(Icons.copy_rounded, color: Colors.white, size: 18),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _showEmailInviteDialog,
                      child: const Icon(Icons.person_add_rounded, color: Colors.white, size: 20),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 8),
              Text(
                '${_members.length}/${CareGroup.maxCaregivers} ${l.caregiverCount}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          if (isAdmin) ...[
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copyCode,
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  label: Text(l.inviteCode,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                      side: const BorderSide(color: AppTheme.primary)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showEmailInviteDialog,
                  icon: const Icon(Icons.email_rounded, size: 20),
                  label: Text(l.inviteByEmail,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14)),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 46)),
                ),
              ),
            ]),
            const SizedBox(height: 20),
          ],

          // Elderly member — tappable for admin caregivers
          if (_elderly != null) ...[
            Text(l.roleElderly, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _ElderlyCard(
              elderly: _elderly!,
              isAdminCaregiver: isAdmin && widget.auth.isCaregiver,
            ),
            const SizedBox(height: 24),
          ],

          Row(children: [
            Text(l.members, style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            Text('${_members.length}/${CareGroup.maxCaregivers}',
                style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
          ]),
          const SizedBox(height: 12),

          if (_members.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE0E0E0))),
              child: Center(child: Text(l.noCaregivers,
                  style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary))),
            )
          else
            ...(_members.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MemberTile(
                user: m,
                isAdmin: m.id == widget.group.adminId,
                isElderly: false,
                showRemove: isAdmin && m.id != widget.auth.currentUser?.id,
                showMakeAdmin: isAdmin && m.id != widget.group.adminId,
                showChangeAdmin: isAdmin && m.id == widget.group.adminId && m.id != widget.auth.currentUser?.id,
                onRemove: () => _removeMember(m),
                onMakeAdmin: () => _makeAdmin(m),
                onChangeAdmin: () => _makeAdmin(m),
              ),
            ))),

          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: _leaveGroup,
            icon: const Icon(Icons.exit_to_app_rounded, color: AppTheme.error, size: 24),
            label: Text(l.leaveGroup,
                style: const TextStyle(color: AppTheme.error, fontSize: 16)),
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.error, width: 2),
                minimumSize: const Size(double.infinity, 52)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Elderly card — tappable for admin caregivers ──────────────────────────────
class _ElderlyCard extends StatelessWidget {
  final UserModel elderly;
  final bool isAdminCaregiver;
  const _ElderlyCard({required this.elderly, required this.isAdminCaregiver});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: isAdminCaregiver
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ElderlyManagementPage(elderly: elderly),
                ),
              )
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppTheme.accent.withOpacity(0.15),
            child: Text(
              elderly.name.isNotEmpty ? elderly.name[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.accent),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(elderly.name,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
            Text(elderly.email,
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                overflow: TextOverflow.ellipsis),
          ])),
          if (isAdminCaregiver) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(l10n.manage,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: AppTheme.accent)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppTheme.accent, size: 16),
          ],
        ]),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final UserModel user;
  final bool isAdmin;
  final bool isElderly;
  final bool showRemove;
  final bool showMakeAdmin;
  final VoidCallback onRemove;
  final VoidCallback onMakeAdmin;
  final bool showChangeAdmin;
  final VoidCallback onChangeAdmin;
  const _MemberTile({
    required this.user, required this.isAdmin, required this.isElderly,
    required this.showRemove, required this.showMakeAdmin,
    required this.showChangeAdmin, required this.onRemove,
    required this.onMakeAdmin, required this.onChangeAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isAdmin ? AppTheme.primary.withOpacity(0.4) : const Color(0xFFE0E0E0)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: isElderly
              ? AppTheme.accent.withOpacity(0.15)
              : AppTheme.primary.withOpacity(0.12),
          child: Text(
            user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700,
                color: isElderly ? AppTheme.accent : AppTheme.primary),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
          Text(user.email,
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              overflow: TextOverflow.ellipsis),
        ])),
        if (isAdmin)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20)),
            child: Text(l10n.admin,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary)),
          ),
        if (showMakeAdmin)
          IconButton(
            icon: const Icon(Icons.shield_rounded, color: AppTheme.warning, size: 26),
            tooltip: l10n.makeAdmin,
            onPressed: onMakeAdmin,
          ),
        if (showChangeAdmin)
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded, color: AppTheme.accent, size: 26),
            tooltip: l10n.changeAdmin,
            onPressed: onChangeAdmin,
          ),
        if (showRemove)
          IconButton(
            icon: const Icon(Icons.remove_circle_rounded, color: AppTheme.error, size: 28),
            onPressed: onRemove,
          ),
      ]),
    );
  }
}
