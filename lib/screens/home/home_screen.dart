import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../utils/app_theme.dart';
import '../schedule/schedule_screen.dart';
import '../quickactions/quick_actions_screen.dart';
import '../groups/group_screen.dart';
import '../settings/settings_screen.dart';
import '../requests/requests_screen.dart';
import '../moments/moments_screen.dart';
import 'events_banner.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    _HomePage(),
    QuickActionsScreen(),
    SettingsScreen(),
  ];

  void navigateTo(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: Colors.white,
        indicatorColor: AppTheme.primary.withOpacity(0.15),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined, size: 30),
            selectedIcon: const Icon(Icons.home_rounded, size: 30, color: AppTheme.primary),
            label: l10n.home,
          ),
          NavigationDestination(
            icon: const Icon(Icons.touch_app_outlined, size: 30),
            selectedIcon: const Icon(Icons.touch_app_rounded, size: 30, color: AppTheme.primary),
            label: l10n.quickActions,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined, size: 28),
            selectedIcon: const Icon(Icons.settings_rounded, size: 28, color: AppTheme.primary),
            label: l10n.settings,
          ),
        ],
      ),
    );
  }
}

// ─── Home Page ────────────────────────────────────────────────────────────────
class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  final bool _interestsBannerKey = false; // used to force rebuild after interest setup

  String _greeting(AppLocalizations l10n) {
    final h = DateTime.now().hour;
    if (h < 12) return '🌅 ${l10n.goodMorning}';
    if (h < 17) return '☀️ ${l10n.goodAfternoon}';
    return '🌙 ${l10n.goodEvening}';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final l10n = AppLocalizations.of(context)!;
    final user = auth.currentUser;
    final group = auth.currentGroup;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────────────────────
              Row(children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.primaryLight],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_greeting(l10n),
                      style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
                  Text(user?.name ?? '',
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: auth.isCaregiver
                        ? AppTheme.primary.withOpacity(0.12)
                        : AppTheme.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    auth.isCaregiver ? l10n.roleCaregiver : l10n.roleElderly,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: auth.isCaregiver ? AppTheme.primary : AppTheme.accent),
                  ),
                ),
              ]),
              const SizedBox(height: 24),

              // ── Events Banner (NEW) ────────────────────────────────────────
              // Only show for elderly users (caregivers manage; elderly enjoy)
              EventsBanner(key: ValueKey(_interestsBannerKey)),
              const SizedBox(height: 24),

              // ── Group card ────────────────────────────────────────────────
              if (group == null)
                _NoGroupCard(l10n: l10n)
              else
                _GroupStatusCard(groupName: group.name, inviteCode: group.inviteCode, l10n: l10n),
              const SizedBox(height: 24),

              Text(l10n.features, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),

              // Row 1: Schedule + Requests
              Row(children: [
                Expanded(child: _FeatureCard(
                  icon: Icons.calendar_month_rounded,
                  label: l10n.schedule,
                  color: AppTheme.primary,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ScheduleScreen())),
                )),
                const SizedBox(width: 16),
                Expanded(child: _FeatureCard(
                  icon: Icons.notifications_active_rounded,
                  label: l10n.requests,
                  color: AppTheme.warning,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const RequestsScreen())),
                )),
              ]),
              const SizedBox(height: 16),

              // Row 2: Group + Moments
              Row(children: [
                Expanded(child: _FeatureCard(
                  icon: Icons.group_rounded,
                  label: l10n.myGroup,
                  color: const Color(0xFF7B61FF),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const GroupScreen())),
                )),
                const SizedBox(width: 16),
                Expanded(child: _FeatureCard(
                  icon: Icons.photo_library_rounded,
                  label: l10n.moments,
                  color: const Color(0xFFAB47BC),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const MomentsScreen())),
                )),
              ]),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Feature Card ─────────────────────────────────────────────────────────────
class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _FeatureCard({required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color, color.withOpacity(0.75)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(
              color: color.withOpacity(0.3), blurRadius: 14,
              offset: const Offset(0, 6))],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 42),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(label, textAlign: TextAlign.center, maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

class _NoGroupCard extends StatelessWidget {
  final AppLocalizations l10n;
  const _NoGroupCard({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.group_add_rounded, size: 40, color: AppTheme.warning),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.noGroup,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          Text(l10n.joinOrCreate,
              style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
        ])),
      ]),
    );
  }
}

class _GroupStatusCard extends StatelessWidget {
  final String groupName;
  final String inviteCode;
  final AppLocalizations l10n;
  const _GroupStatusCard({required this.groupName, required this.inviteCode,
      required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primary, AppTheme.primaryLight],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
            color: AppTheme.primary.withOpacity(0.3),
            blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Row(children: [
        const Icon(Icons.group_rounded, color: Colors.white, size: 40),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(groupName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700,
                  fontSize: 18),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text('${l10n.inviteCodeLabel}: $inviteCode',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ])),
      ]),
    );
  }
}
