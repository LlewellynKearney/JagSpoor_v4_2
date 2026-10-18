import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// The bounded JagSpoor brand emblem shown on the splash / boot screen.
///
/// Extracted from `SplashScreen` so the sizing contract is directly testable
/// (the splash itself runs a boot gate with timers, which makes it awkward to
/// mount in a widget test).
///
/// The emblem is deliberately **bounded** so it can never fill the viewport:
/// a hard `maxWidth` cap (340 on web / 280 on mobile) PLUS a
/// 40%-of-viewport `maxHeight`, with `BoxFit.contain` so the aspect ratio is
/// preserved (never stretched). 24px of padding gives it breathing room, and
/// the enclosing `Center` keeps it centred — critical on the web, where the
/// window can be far wider than the logo.
class SplashLogo extends StatelessWidget {
  /// The bundled app emblem.
  static const String assetPath = 'assets/app logo/logo1.png';

  /// The maximum logo width on the web build.
  static const double webMaxWidth = 340;

  /// The maximum logo width on the mobile / native build.
  static const double mobileMaxWidth = 280;

  /// The fraction of the viewport height the logo may occupy at most.
  static const double maxViewportHeightFraction = 0.4;

  const SplashLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: kIsWeb ? webMaxWidth : mobileMaxWidth,
          maxHeight:
              MediaQuery.of(context).size.height * maxViewportHeightFraction,
        ),
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
