import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shared responsive layout contract for the Flutter **web** build.
///
/// The app is designed mobile-first (Android/iOS) and the desktop browser
/// previously rendered the mobile layout stretched edge-to-edge across the
/// whole viewport — full-width cards with no max-width container. These
/// helpers centralise the desktop treatment so every screen agrees on the
/// breakpoint, the content width and the header height:
///
/// * [desktopBreakpoint] — `800` logical px. Above this width the layout
///   switches to its desktop presentation (centred, wider gutters,
///   multi-column grids).
/// * [maxContentWidth] — `1280` logical px cap so text lines and cards never
///   stretch uncomfortably wide on a large monitor.
/// * [isDesktopLayout] — `true` on a wide viewport, so a browser window (or a
///   wide test surface) gets the desktop presentation while a phone keeps the
///   mobile one.
/// * [headerHeight] — `64` px on the web build (per the web design spec),
///   `kToolbarHeight` (56) on every native platform so the Android/iOS
///   layout is untouched.
///
/// The breakpoint logic is exposed as a pure function ([isDesktopWidth]) so
/// it is unit-testable without pumping a widget tree.
class WebLayout {
  WebLayout._();

  /// Viewport width (logical px) at which the desktop layout engages.
  static const double desktopBreakpoint = 800;

  /// Maximum content width for the centred desktop container.
  static const double maxContentWidth = 1280;

  /// Maximum width for a centred single-column form (auth / login). Keeps the
  /// sign-in card a comfortable reading width in the browser instead of
  /// stretching a text field edge-to-edge across a wide monitor.
  static const double authContentWidth = 480;

  /// Web header height (the native platforms keep `kToolbarHeight`).
  static const double webHeaderHeight = 64;

  /// Pure width test — `true` when [width] is strictly above the breakpoint.
  ///
  /// Strictly greater (not `>=`) is deliberate: it matches the web design
  /// spec (`> 800px`) and keeps the 800x600 default widget-test surface on the
  /// mobile presentation, so the existing mobile layout tests are unaffected.
  static bool isDesktopWidth(double width) => width > desktopBreakpoint;

  /// Whether the layout should use the desktop presentation.
  ///
  /// True when the viewport is wider than [desktopBreakpoint] — so a browser
  /// window (and a deliberately widened test surface) gets the desktop
  /// layout, while a narrow phone keeps the mobile one.
  static bool isDesktopLayout(BuildContext context) =>
      isDesktopWidth(MediaQuery.sizeOf(context).width);

  /// Header height for the ambient platform: [webHeaderHeight] on the web
  /// build so the branded header reads as a proper app bar in the browser;
  /// the standard `kToolbarHeight` on the native platforms so the Android /
  /// iOS build is unchanged.
  static double headerHeight() => kIsWeb ? webHeaderHeight : kToolbarHeight;

  /// Wraps [child] in a centred, max-width container for the desktop
  /// presentation. On a mobile-width viewport the child is returned as-is so
  /// the existing mobile layout is unchanged.
  static Widget constrain(
    BuildContext context,
    Widget child, {
    double maxWidth = maxContentWidth,
    double horizontalPadding = 24,
  }) {
    if (!isDesktopLayout(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: child,
        ),
      ),
    );
  }
}
