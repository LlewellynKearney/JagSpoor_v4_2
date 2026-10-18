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

  /// Content cap (logical px) for the **browser** dashboards. The web design
  /// spec uses 1000px for the hunter / outfitter dashboards (slightly wider
  /// than the 800px checkout, narrower than the 1280px native desktop cap) so
  /// a monitor shows the module grids without over-stretched card rows.
  static const double webDashboardMaxWidth = 1000;

  /// Content cap (logical px) for the **browser** tables / data screens
  /// (farm control panel, booking requests, revenue BI). Wider than the
  /// dashboards so data-dense tables have room, still capped so text lines
  /// never run edge-to-edge on a large monitor.
  static const double webTableMaxWidth = 1200;

  /// Content cap (logical px) for the **browser** single-column forms and
  /// reading screens (profile, settings, checkout).
  static const double webFormMaxWidth = 800;

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

  /// Convenience alias matching the web design spec — `true` on a wide
  /// viewport. Identical to [isDesktopLayout]; provided so screens can read
  /// `WebLayout.isDesktop(context)`.
  static bool isDesktop(BuildContext context) => isDesktopLayout(context);

  /// Wraps [child] in the standard responsive container for the desktop
  /// presentation:
  ///   * desktop (`> 800`) -> `Center > ConstrainedBox(maxWidth: 1280) >
  ///     Padding(24) > child`;
  ///   * mobile (`<= 800`) -> [child] unchanged.
  ///
  /// This is the single helper every dashboard / screen should use so the
  /// desktop treatment is consistent across ALL roles (hunter, outfitter,
  /// admin) instead of each screen re-implementing the container.
  static Widget responsive({
    required Widget child,
    BuildContext? context,
    double maxWidth = maxContentWidth,
    double horizontalPadding = 24,
  }) {
    // `context` is optional so callers inside a `LayoutBuilder` (which
    // already knows the width) can pass it explicitly; when omitted the
    // child is wrapped unconditionally, letting a LayoutBuilder decide the
    // breakpoint itself.
    if (context != null && !isDesktopLayout(context)) return child;
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

  /// Viewport width (logical px) below which a browser window is treated as
  /// "mobile web" (a phone-sized browser / a narrow desktop window). Matches
  /// the `600` breakpoint the web design spec uses for the single-column
  /// mobile-web presentation.
  static const double mobileWebBreakpoint = 600;

  /// Whether the viewport is a **mobile-web** (narrow browser) presentation.
  static bool isMobileWebWidth(double width) => width < mobileWebBreakpoint;

  /// The strict **web-only** responsive container.
  ///
  /// On a **desktop browser** (viewport ≥ [mobileWebBreakpoint]) the content is
  /// centred in a max-width column with symmetric 24px gutters so a wide
  /// window never stretches the mobile layout edge-to-edge. On a **narrow
  /// (mobile-web) browser**, and on **every native platform** (Android / iOS)
  /// plus the VM test host, the child is returned completely unchanged.
  ///
  /// The `!kIsWeb` short-circuit is what guarantees the Android / iOS native
  /// UI is byte-for-byte untouched — `kIsWeb` is a compile-time constant that
  /// is `false` on the native platforms (and on the VM test host), so this
  /// helper is a no-op there. The `>= breakpoint` guard additionally keeps a
  /// phone-sized browser window on the exact native mobile layout (the layout
  /// proven to fit a 320px screen), so only genuinely wide windows are
  /// re-centred. Use it for every screen that must gain the centred browser
  /// presentation without risking the native layout.
  static Widget webResponsive({
    required Widget child,
    double maxWidth = 1100,
    double horizontalPadding = 24,
    bool topPadding = false,
  }) {
    if (!kIsWeb) return child; // Native (Android/iOS) + VM tests: NO CHANGE.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Mobile-web keeps the native single-column layout verbatim.
        if (isMobileWebWidth(constraints.maxWidth)) return child;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: topPadding ? 24 : 0,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }

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
