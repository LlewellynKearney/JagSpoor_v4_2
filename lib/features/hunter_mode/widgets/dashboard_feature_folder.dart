import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'hunter_scaffold.dart';

/// A theme-aware, collapsible "folder" card that groups a set of related
/// Hunter Dashboard feature cards under a single expandable header.
///
/// Visual language matches the bushveld/aesthetic of the hunter portal:
/// * **Light mode** — a warm cream surface ([HunterUi.lightCard]) with a
///   defined warm border and dark espresso title text.
/// * **Dark mode** — the theme's dark card surface with a brushed-gold
///   accent ([HunterAcaciaBackground.kOverlayGold]) on the folder glyph,
///   count badge and chevron.
///
/// Tapping the header toggles the body with a smooth [AnimatedSize]
/// expand/collapse animation; the header chevron rotates with
/// [AnimatedRotation]. Nested feature cards are supplied by the caller via
/// [children] so the dashboard keeps ownership of navigation + favorites.
class DashboardFeatureFolder extends StatefulWidget {
  final ThemeController theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool initiallyExpanded;
  final Duration animationDuration;

  const DashboardFeatureFolder({
    super.key,
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.initiallyExpanded = false,
    this.animationDuration = const Duration(milliseconds: 280),
  });

  /// Gold accent used for the folder glyph / count badge / chevron in dark
  /// mode (the light mode accent is the theme's deep bushveld brown).
  static Color accentColor(ThemeController theme) =>
      theme.isDarkMode ? HunterAcaciaBackground.kOverlayGold : theme.accentColor;

  @override
  State<DashboardFeatureFolder> createState() => DashboardFeatureFolderState();
}

class DashboardFeatureFolderState extends State<DashboardFeatureFolder>
    with SingleTickerProviderStateMixin {
  late bool _expanded = widget.initiallyExpanded;

  bool get isExpanded => _expanded;

  void toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final accent = DashboardFeatureFolder.accentColor(theme);
    return Container(
      decoration: BoxDecoration(
        color: HunterUi.cardColor(theme),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HunterUi.cardBorderColor(theme)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(theme.isDarkMode ? 60 : 18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: ValueKey('folderHeader_${widget.title}'),
              borderRadius: BorderRadius.circular(14),
              onTap: toggle,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: accent.withAlpha(theme.isDarkMode ? 38 : 26),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: accent.withAlpha(90)),
                      ),
                      child: Icon(
                        widget.icon,
                        color: accent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: HunterUi.titleColor(theme),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: HunterUi.subtitleColor(theme),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent.withAlpha(theme.isDarkMode ? 38 : 26),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: accent.withAlpha(90)),
                      ),
                      child: Text(
                        '${widget.children.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: widget.animationDuration,
                      curve: Curves.easeInOutCubic,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: accent,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: widget.animationDuration,
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: HunterUi.cardBorderColor(theme),
                          ),
                          const SizedBox(height: 8),
                          for (var i = 0; i < widget.children.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            widget.children[i],
                          ],
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ),
        ],
      ),
    );
  }
}
