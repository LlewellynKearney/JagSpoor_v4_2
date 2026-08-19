import 'package:flutter/material.dart';

/// A subtle, centered copyright caption rendered at the bottom of the major
/// app screens (auth, splash, hunter/outfitter profile + settings).
///
/// Renders "© 2026 JagSpoor. All Rights Reserved." in a small, muted,
/// theme-aware style (adapts to Day/Night via [Theme.of]). It is a leaf
/// widget -- callers embed it as the last child of a scrollable `Column`
/// (or directly in a `Column` for fixed layouts). It is non-interactive.
class CopyrightFooter extends StatelessWidget {
  static const String caption = '© 2026 JagSpoor. All Rights Reserved.';

  final EdgeInsetsGeometry padding;
  final double fontSize;

  const CopyrightFooter({
    super.key,
    this.padding = const EdgeInsets.only(top: 24, bottom: 8),
    this.fontSize = 11,
  });

  /// Convenience constructor that injects no top padding -- useful when the
  /// footer is the natural tail of a section that already provides spacing.
  const CopyrightFooter.tight({super.key, this.fontSize = 11})
      : padding = const EdgeInsets.only(top: 8, bottom: 8);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleColor = (isDark ? const Color(0xFFB0B0B0) : const Color(0xFF5D4037))
        .withValues(alpha: 0.7);
    // NOTE: do NOT use a `Center` here. When this widget is placed in a
    // Scaffold's `bottomNavigationBar` slot the slot is offered loose
    // constraints with the FULL screen height as the max, and a `Center`
    // expands to fill it -- the footer then covers the whole screen with an
    // invisible widget whose centered text absorbs taps in the middle band
    // (the bottomNavigationBar slot is hit-tested before the body slot, so
    // body buttons under the text never receive the tap). A
    // `SizedBox(width: double.infinity)` keeps the horizontal centring via
    // TextAlign.center while shrink-wrapping the height to the caption.
    return Padding(
      padding: padding,
      child: SizedBox(
        width: double.infinity,
        child: Text(
          caption,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            color: subtitleColor,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

