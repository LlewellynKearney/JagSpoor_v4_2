import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../constants/app_screen_help_scripts.dart';

export '../constants/app_screen_help_scripts.dart';

/// Shows the universal, theme-aware information modal for [screenKey].
///
/// The script is resolved from [AppScreenHelpScripts]; unknown keys fall back
/// to a generic script so the modal always renders meaningful content.
Future<void> showAppInfoModal(BuildContext context, String screenKey) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AppInfoModal(screenKey: screenKey),
  );
}

/// A plain `Icons.info_outline` AppBar action that opens the universal info
/// modal for [screenKey]. Matches the hunter-portal AppBar action style
/// (outfitter screens use `OutfitterActionChip` with the same callback).
class AppInfoIconButton extends StatelessWidget {
  const AppInfoIconButton({
    super.key,
    required this.screenKey,
    this.iconColor,
  });

  /// Key into [AppScreenHelpScripts.scripts].
  final String screenKey;

  /// Icon tint; defaults to the theme's primary accent.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Screen info',
      icon: Icon(
        Icons.info_outline,
        color: iconColor ?? Theme.of(context).colorScheme.primary,
      ),
      onPressed: () => showAppInfoModal(context, screenKey),
    );
  }
}

/// Universal, theme-aware help modal shared by every core screen in the
/// Hunter and Outfitter portals.
///
/// The palette adapts to the ambient theme brightness while staying on the
/// JagSpoor bushveld palette: a warm cream surface with deep-espresso text in
/// Day mode, and a dark card surface with gold accents and high-contrast
/// off-white text in Night mode.
class AppInfoModal extends StatelessWidget {
  const AppInfoModal({super.key, required this.screenKey});

  /// Key into [AppScreenHelpScripts.scripts].
  final String screenKey;

  // ------------------------------------------------------------------
  // Mode-aware bushveld palette (exposed for tests).
  // ------------------------------------------------------------------

  /// Warm cream card surface (Day mode).
  static const Color lightSurface = Color(0xFFEFE7DC);

  /// Dark card surface (Night mode).
  static const Color darkSurface = AppColors.darkCard;

  /// Deep espresso title / high-contrast primary text (Day mode).
  static const Color lightTitle = Color(0xFF2C221E);

  /// High-contrast off-white title text (Night mode).
  static const Color darkTitle = Color(0xFFE0E0E0);

  /// Warm-brown body text (Day mode).
  static const Color lightBody = Color(0xFF4A3B32);

  /// Muted light body text (Night mode).
  static const Color darkBody = AppColors.darkSubtitle;

  /// Defined warm border for the Day-mode surface.
  static const Color lightBorder = Color(0xFFC4B29E);

  /// Surface color for the current brightness.
  static Color surfaceColor(Brightness brightness) =>
      brightness == Brightness.dark ? darkSurface : lightSurface;

  /// Accent color for the current brightness (gold Night / saddle Day).
  static Color accentColor(Brightness brightness) => brightness ==
          Brightness.dark
      ? AppColors.darkAccentAlt
      : AppColors.lightAccent;

  /// Primary (title) text color for the current brightness.
  static Color titleColor(Brightness brightness) =>
      brightness == Brightness.dark ? darkTitle : lightTitle;

  /// Body / description text color for the current brightness.
  static Color bodyColor(Brightness brightness) =>
      brightness == Brightness.dark ? darkBody : lightBody;

  /// Border color for the current brightness.
  static Color borderColor(Brightness brightness) =>
      brightness == Brightness.dark
          ? Colors.white.withAlpha(36)
          : lightBorder;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final script = AppScreenHelpScripts.forKey(screenKey);
    final surface = surfaceColor(brightness);
    final accent = accentColor(brightness);
    final titleCol = titleColor(brightness);
    final bodyCol = bodyColor(brightness);

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: borderColor(brightness), width: 1.2),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: titleCol.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.info_outline, color: accent, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      script.title.toUpperCase(),
                      style: TextStyle(
                        color: accent,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                script.description,
                style: TextStyle(color: titleCol, fontSize: 13, height: 1.45),
              ),
              if (script.concepts.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'KEY CONCEPTS',
                  style: TextStyle(
                    color: bodyCol,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                ...script.concepts.map(
                  (c) => _HelpConceptRow(
                    concept: c,
                    accent: accent,
                    textColor: titleCol,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: brightness == Brightness.dark
                        ? Colors.black
                        : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'GOT IT',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpConceptRow extends StatelessWidget {
  const _HelpConceptRow({
    required this.concept,
    required this.accent,
    required this.textColor,
  });

  final AppHelpConcept concept;
  final Color accent;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Icon(Icons.chevron_right, color: accent, size: 16),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: '${concept.label}: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: concept.detail),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
