import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../models/event_model.dart';
import '../../services/event_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/app_theme.dart';
import '../interests/interest_selection_screen.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Horizontal auto-scrolling events banner shown at the top of the home page.
/// Shows events filtered by the user's saved interests.
class EventsBanner extends StatefulWidget {
  const EventsBanner({super.key});

  @override
  State<EventsBanner> createState() => _EventsBannerState();
}

class _EventsBannerState extends State<EventsBanner> {
  List<EventItem> _events = [];
  bool _loading = true;
  bool _hasInterests = false;
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    if (_events.isEmpty) return;
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) return;
      if (_pageCtrl.hasClients) {
        int nextPage = _currentPage + 1;
        if (nextPage >= _events.length) nextPage = 0;
        _pageCtrl.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _loadEvents() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?.id ?? '';
    final hasInterests = EventService().hasSetInterests(userId);

    setState(() => _hasInterests = hasInterests);

    if (!hasInterests) {
      setState(() => _loading = false);
      return;
    }

    try {
      final events = await EventService().getRecommendedEvents(userId);
      if (mounted) {
        setState(() { _events = events; _loading = false; });
        _startAutoScroll();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openInterestSetup() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const InterestSelectionScreen()),
    );
    if (result == true) _loadEvents();
  }

  void _onEventTap(EventItem event) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
        contentPadding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        title: Row(children: [
          const Icon(Icons.open_in_browser_rounded, color: AppTheme.primary, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.openWebpageTitle,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary),
            ),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: AppTheme.primary),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.openWebpageDesc,
              style: const TextStyle(
                  fontSize: 17, color: AppTheme.textSecondary, height: 1.5),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          SizedBox(
            width: 120,
            height: 52,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                side: const BorderSide(color: Color(0xFFCFD8DC), width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(l10n.no,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ),
          SizedBox(
            width: 120,
            height: 52,
            child: ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final uri = Uri.parse(event.eventUrl);
                if (await canLaunchUrl(uri)) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(l10n.yes,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Not set up interests yet
    if (!_hasInterests) {
      return _SetupInterestsBanner(onTap: _openInterestSetup, l10n: l10n);
    }

    // No events found
    if (_events.isEmpty) {
      return _EmptyEventsBanner(onRefresh: _loadEvents, l10n: l10n);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            const Icon(Icons.event_rounded, color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l10n.eventsForYou,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
            ),
            // Dot indicators
            Row(
              children: List.generate(_events.length.clamp(0, 6), (i) =>
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: _currentPage == i ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _currentPage == i ? AppTheme.primary : const Color(0xFFCFD8DC),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ]),
        ),
        SizedBox(
          height: 170,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: _events.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (_, idx) => _EventCard(
              event: _events[idx],
              onTap: () => _onEventTap(_events[idx]),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Individual event card ─────────────────────────────────────────────────────
class _EventCard extends StatelessWidget {
  final EventItem event;
  final VoidCallback onTap;
  const _EventCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              // Background image
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: event.imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: AppTheme.primary.withOpacity(0.2),
                    child: const Icon(Icons.event_rounded, size: 50, color: AppTheme.primary),
                  ),
                ),
              ),
              // Gradient overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                      stops: const [0.35, 1.0],
                    ),
                  ),
                ),
              ),
              // Category badge
              Positioned(
                top: 12,
                left: 14,
                child: Builder(
                  builder: (bCtx) {
                    final l10n = AppLocalizations.of(bCtx)!;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        localizeCategory(event.category, l10n),
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary),
                      ),
                    );
                  },
                ),
              ),
              // Today badge
              if (event.isToday)
                Positioned(
                  top: 12,
                  right: 14,
                  child: Builder(
                    builder: (bCtx) {
                      final l10n = AppLocalizations.of(bCtx)!;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.warning,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(l10n.today,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                      );
                    },
                  ),
                ),
              // Text at bottom
              Positioned(
                bottom: 14,
                left: 14,
                right: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15,
                            fontWeight: FontWeight.w800, height: 1.25)),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.schedule_rounded, size: 13, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('d MMM · h:mm a').format(event.startTime),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Setup prompt banner ───────────────────────────────────────────────────────
class _SetupInterestsBanner extends StatelessWidget {
  final VoidCallback onTap;
  final AppLocalizations l10n;
  const _SetupInterestsBanner({required this.onTap, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7B61FF), Color(0xFFAB47BC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7B61FF).withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(children: [
          const Icon(Icons.event_available_rounded, color: Colors.white, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.discoverEvents,
                  style: const TextStyle(color: Colors.white, fontSize: 17,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(l10n.discoverEventsDesc,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(l10n.setUp,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ),
        ]),
      ),
    );
  }
}

// ── Empty events banner ───────────────────────────────────────────────────────
class _EmptyEventsBanner extends StatelessWidget {
  final VoidCallback onRefresh;
  final AppLocalizations l10n;
  const _EmptyEventsBanner({required this.onRefresh, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(children: [
        const Icon(Icons.event_busy_rounded, size: 40, color: AppTheme.textSecondary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.noEventsFound,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 4),
            Text(l10n.checkBackTomorrow,
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          ]),
        ),
        IconButton(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded, color: AppTheme.primary),
        ),
      ]),
    );
  }
}
