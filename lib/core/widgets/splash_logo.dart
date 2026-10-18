import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// The bounded JagSpoor brand emblem shown on the splash / boot screen.
///
/// Extracted from `SplashScreen` so the sizing contract is directly testable
/// (the splash itself runs a boot gate with timers, which makes it awkward to
/// mount in a widget test).
///
/// The emblem is deliberately **small and bounded** so it can never fill the
/// viewport: a hard `maxWidth` cap (200 on web / 160 on mobile) PLUS a
/// 22%-of-viewport `maxHeight`, with `BoxFit.contain` so the aspect ratio is
/// preserved (never stretched). 32px of padding gives it breathing room, and
/// the enclosing `Center` keeps it centred — critical on the web, where the
/// window can be far wider than the logo.
class SplashLogo extends StatelessWidget {
  /// The bundled app emblem.
  static const String assetPath = 'assets/app logo/logo1.png';

  /// The maximum logo width on the web build.
  static const double webMaxWidth = 200;

  /// The maximum logo width on the mobile / native build.
  static const double mobileMaxWidth = 160;

  /// The fraction of the viewport height the logo may occupy at most.
  static const double maxViewportHeightFraction = 0.22;

  /// The breathing-room padding around the emblem.
  static const double padding = 32;

  const SplashLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(padding),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: kIsWeb ? webMaxWidth : mobileMaxWidth,
            maxHeight: MediaQuery.of(context).size.height *
                maxViewportHeightFraction,
          ),
          child: Image.asset(
            assetPath,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
