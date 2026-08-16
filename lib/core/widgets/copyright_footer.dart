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
    return Padding(
      padding: padding,
      child: Center(
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

