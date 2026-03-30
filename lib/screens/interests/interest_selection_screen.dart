import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../services/event_service.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Maps the English API category key to its localized display name.
String localizeCategory(String key, AppLocalizations l10n) {
  switch (key) {
    case 'Exercise & Wellness':    return l10n.catExerciseWellness;
    case 'Arts & Crafts':          return l10n.catArtsCrafts;
    case 'Music & Entertainment':  return l10n.catMusicEntertainment;
    case 'Social & Community':     return l10n.catSocialCommunity;
    case 'Learning & Education':   return l10n.catLearningEducation;
    case 'Nature & Gardening':     return l10n.catNatureGardening;
    case 'Food & Cooking':         return l10n.catFoodCooking;
    case 'Technology & Digital':   return l10n.catTechnologyDigital;
    case 'Religious & Spiritual':  return l10n.catReligiousSpiritual;
    case 'Games & Recreation':     return l10n.catGamesRecreation;
    default:                       return key; // fallback: show raw
  }
}

/// Interest icons paired to each category
const Map<String, IconData> kCategoryIcons = {
  'Exercise & Wellness':    Icons.directions_run_rounded,
  'Arts & Crafts':          Icons.palette_rounded,
  'Music & Entertainment':  Icons.music_note_rounded,
  'Social & Community':     Icons.people_rounded,
  'Learning & Education':   Icons.school_rounded,
  'Nature & Gardening':     Icons.eco_rounded,
  'Food & Cooking':         Icons.restaurant_rounded,
  'Technology & Digital':   Icons.devices_rounded,
  'Religious & Spiritual':  Icons.temple_hindu_rounded,
  'Games & Recreation':     Icons.sports_esports_rounded,
};

const Map<String, Color> kCategoryColors = {
  'Exercise & Wellness':    Color(0xFF26C6DA),
  'Arts & Crafts':          Color(0xFFAB47BC),
  'Music & Entertainment':  Color(0xFFEF5350),
  'Social & Community':     Color(0xFF42A5F5),
  'Learning & Education':   Color(0xFFFF7043),
  'Nature & Gardening':     Color(0xFF66BB6A),
  'Food & Cooking':         Color(0xFFFFCA28),
  'Technology & Digital':   Color(0xFF5C6BC0),
  'Religious & Spiritual':  Color(0xFF8D6E63),
  'Games & Recreation':     Color(0xFFEC407A),
};

class InterestSelectionScreen extends StatefulWidget {
  /// If true, shown as a settings sub-page (not onboarding)
  final bool isEditing;
  const InterestSelectionScreen({super.key, this.isEditing = false});

  @override
  State<InterestSelectionScreen> createState() => _InterestSelectionScreenState();
}

class _InterestSelectionScreenState extends State<InterestSelectionScreen> {
  final Set<String> _selected = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?.id ?? '';
    if (userId.isNotEmpty) {
      final existing = await EventService().getUserInterests(userId);
      setState(() {
        _selected.addAll(existing);
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  void _toggle(String cat) {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      if (_selected.contains(cat)) {
        _selected.remove(cat);
      } else {
        if (_selected.length < 5) {
          _selected.add(cat);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.selectedMaxInterests),
              backgroundColor: AppTheme.warning,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    if (_selected.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.selectMinInterests),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?.id ?? '';
    await EventService().saveUserInterests(userId, _selected.toList());
    setState(() => _saving = false);
    if (mounted) {
      if (widget.isEditing) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.interestsUpdated),
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        // Onboarding: pop back to home which will now show events
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const cats = kAllInterestCategories;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.isEditing ? l10n.editMyInterests : l10n.whatDoYouEnjoy),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isEditing
                            ? l10n.updateInterestsDesc
                            : l10n.selectInterestsDesc,
                        style: const TextStyle(
                            fontSize: 15, color: AppTheme.textSecondary, height: 1.5),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: _selected.length >= 3
                                ? AppTheme.primary.withOpacity(0.1)
                                : AppTheme.warning.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${l10n.selectedCount(_selected.length)}  •  ${l10n.minRequired}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _selected.length >= 3 ? AppTheme.primary : AppTheme.warning,
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),

                // Grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 1.15,
                    ),
                    itemCount: cats.length,
                    itemBuilder: (_, idx) {
                      final cat = cats[idx];
                      final selected = _selected.contains(cat);
                      final color = kCategoryColors[cat] ?? AppTheme.primary;
                      final icon = kCategoryIcons[cat] ?? Icons.star_rounded;
                      return GestureDetector(
                        onTap: () => _toggle(cat),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            color: selected ? color : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: selected ? color : const Color(0xFFE0E0E0),
                                width: selected ? 0 : 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: selected
                                    ? color.withOpacity(0.35)
                                    : Colors.black.withOpacity(0.04),
                                blurRadius: selected ? 14 : 6,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(icon,
                                  size: 40,
                                  color: selected ? Colors.white : color),
                              const SizedBox(height: 10),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  localizeCategory(cat, l10n),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: selected ? Colors.white : AppTheme.textPrimary,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              if (selected) ...[
                                const SizedBox(height: 6),
                                const Icon(Icons.check_circle_rounded,
                                    color: Colors.white, size: 18),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Save button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                        elevation: 0,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(
                              widget.isEditing ? l10n.saveInterests : l10n.findMyEvents,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
