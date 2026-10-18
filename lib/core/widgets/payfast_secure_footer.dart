import 'package:flutter/material.dart';

/// The branded "Secure payments by PayFast" trust footer for the subscription
/// checkout surfaces.
///
/// Renders the official PayFast logo (bundled at
/// `assets/images/payfast_logo.png`, rasterized from PayFast's published
/// `Payfast-logo.svg`) above a small muted caption, centred and at low
/// opacity so it reads as a quiet trust mark rather than a primary action.
///
/// Used at the tail of the subscription checkout, so it is visible on every
/// plan view (Hunter / Outfitter, Monthly / Yearly) on both the web and the
/// native builds — PayFast is the web (PayFast) checkout provider, and on
/// Android/iOS the same screen still shows it as the website-billing trust
/// mark. It is non-interactive.
class PayFastSecureFooter extends StatelessWidget {
  /// The bundled official PayFast logo.
  static const String logoAsset = 'assets/images/payfast_logo.png';

  /// The caption shown beneath the logo.
  static const String caption = 'Secure payments by PayFast';

  /// The rendered logo height (the width follows the logo's aspect ratio).
  final double logoHeight;

  /// The overall footer opacity (a low-opacity footer per the design brief).
  final double opacity;

  const PayFastSecureFooter({
    super.key,
    this.logoHeight = 32,
    this.opacity = 0.75,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The logo is a two-colour (blue + red) mark on transparency; it reads on
    // both Day and Night surfaces. The caption is muted and theme-aware.
    final captionColor =
        (isDark ? const Color(0xFFB0B0B0) : const Color(0xFF5D4037));
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 32),
      child: Opacity(
        opacity: opacity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A bounded, aspect-preserving logo so it never stretches. The
            // bundled PNG is 672x240 (~2.8:1).
            Image.asset(
              logoAsset,
              height: logoHeight,
              fit: BoxFit.contain,
              // Never let a missing/broken asset break the checkout: fall back
              // to the caption-only trust mark.
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.3,
                color: captionColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
