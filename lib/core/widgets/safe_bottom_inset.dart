import 'package:flutter/material.dart';

/// Standard bottom inset appended to scrollable content so the last item never
/// renders under the Android 3-button nav bar / iOS gesture line.
///
/// Global bottom-padding audit (2026-08-13): primary screen scrollables
/// (`ListView` / `SingleChildScrollView` used directly as a `Scaffold.body`)
/// were cutting off their last card/button under the system navigation bar.
/// Every body-level scrollable now reserves [extraSpacing] plus the device's
/// bottom safe-area inset, so all content scrolls cleanly above the gesture
/// bar. Nested scrollables inside bottom sheets / dialogs are excluded (those
/// containers already inject their own `MediaQuery` view-inset padding).
class SafeBottomInset {
  SafeBottomInset._();

  /// Extra breathing room beyond the safe-area inset.
  static const double extraSpacing = 24.0;

  /// Returns the bottom padding to append to a scrollable's `padding`.
  ///
  /// Pass the [BuildContext] so the device bottom safe-area inset is read, or
  /// omit it for a plain [extraSpacing]-only inset (useful where the parent
  /// already wraps in a `SafeArea`).
  static double of(BuildContext? context) {
    final viewPadding = context == null ? 0.0 : MediaQuery.of(context).padding.bottom;
    return viewPadding + extraSpacing;
  }

  /// A ready-made [EdgeInsets] usable as a scrollable's `padding` bottom value.
  static EdgeInsets paddingFor(BuildContext context,
      {double horizontal = 0.0, double top = 0.0}) {
    return EdgeInsets.only(
      left: horizontal,
      right: horizontal,
      top: top,
      bottom: of(context),
    );
  }
}
