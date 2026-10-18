import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/review/models/review_config.dart';

/// The JagSpoor brand palette used by the review modal. These are fixed
/// (independent of the Day/Night toggle) because the review prompt is a
/// branded surface: obsidian black canvas, brushed-gold accents, and a Bush
/// Karoo / Kalahari sand-brown warmth.
class JagspoorReviewPalette {
  JagspoorReviewPalette._();

  /// Obsidian black canvas.
  static const Color black = Color(0xFF0A0A0A);

  /// Brushed gold accent (primary CTA + wordmark).
  static const Color gold = Color(0xFFD4AF37);

  /// Bush Karoo / Kalahari sand-ochre — the warm secondary tone that echoes
  /// the semi-arid Karoo veld at golden hour.
  static const Color bushKarooKalahari = Color(0xFFC08A3E);

  /// Deep Kalahari soil brown (gradient tail + borders).
  static const Color kalahariBrown = Color(0xFF3A2A17);

  /// Warm off-white body text on the black canvas.
  static const Color sandText = Color(0xFFE8DCC8);

  /// WhatsApp brand green.
  static const Color whatsapp = Color(0xFF25D366);

  /// Facebook brand blue.
  static const Color facebook = Color(0xFF1877F2);
}

/// The JagSpoor review prompt.
///
/// Shown by the dashboards via `ReviewPromptCoordinator.maybeShow` after a
/// trophy is saved or a booking is confirmed. The modal offers three
/// destinations:
///  * **WhatsApp** — share the hunt story (hunter) / farm (outfitter),
///  * **Facebook** — leave a review on the JagSpoor Facebook page,
///  * **Google Play Rate** — a native store rating ([InAppReview]).
///
/// Every action is failure-tolerant: an unavailable store or a failed launch
/// simply dismisses the modal (the "maybe later" affordance always works).
class JagspoorReviewModal extends StatelessWidget {
  /// Firestore-backed config driving the destination URLs.
  final ReviewConfig config;

  /// Whether the caller is in Outfitter mode (drives the WhatsApp sub-label).
  final bool isOutfitter;

  const JagspoorReviewModal({
    super.key,
    required this.config,
    this.isOutfitter = false,
  });

  /// Brand asset used in the header. Resolved from the app bundle; a graceful
  /// gold-star fallback renders if the asset is unavailable.
  static const String logoAsset = 'assets/app logo/logo1.png';

  /// Default WhatsApp share copy (hunter mode).
  static const String whatsappHunterMessage =
      'I am loving JagSpoor for my hunts — Bush • Karoo • Kalahari!';

  /// Default WhatsApp share copy (outfitter mode).
  static const String whatsappOutfitterMessage =
      'I am loving JagSpoor for running my hunting operation!';

  // ── Test seams ────────────────────────────────────────────────────────
  // The plugin / url_launcher / share calls are non-deterministic in a widget
  // test, so all three are injectable. Production paths fall through to the
  // real plugins.
  @visibleForTesting
  static Future<void> Function(String url)? launchUrlForTesting;

  @visibleForTesting
  static Future<void> Function(ReviewConfig config)? requestReviewForTesting;

  @visibleForTesting
  static Future<void> Function(String message)? shareWhatsAppForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    launchUrlForTesting = null;
    requestReviewForTesting = null;
    shareWhatsAppForTesting = null;
  }

  /// Presents the modal and returns `true` when the user took a review
  /// action, or `false` / `null` when dismissed.
  static Future<bool?> show(
    BuildContext context, {
    required ReviewConfig config,
    bool isOutfitter = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) =>
          JagspoorReviewModal(config: config, isOutfitter: isOutfitter),
    );
  }

  /// Opens the native share sheet with the WhatsApp share copy.
  Future<void> _shareWhatsApp(NavigatorState navigator) async {
    final message =
        isOutfitter ? whatsappOutfitterMessage : whatsappHunterMessage;
    try {
      if (shareWhatsAppForTesting != null) {
        await shareWhatsAppForTesting!(message);
      } else {
        await Share.share(message, subject: 'JagSpoor');
      }
    } catch (_) {
      // Best-effort: a failed share never blocks the dismiss.
    }
    if (navigator.canPop()) navigator.pop(true);
  }

  /// Requests a native store review (Google Play In-App Review on Android /
  /// SKStoreReviewController on iOS), falling back to the store listing when
  /// the in-app dialog is unavailable.
  Future<void> _launchPlayStore(NavigatorState navigator) async {
    try {
      if (requestReviewForTesting != null) {
        await requestReviewForTesting!(config);
      } else {
        final review = InAppReview.instance;
        if (await review.isAvailable()) {
          await review.requestReview();
        } else {
          await review.openStoreListing();
        }
      }
    } catch (_) {
      // Fall through to opening the store listing URL directly.
      await _openUrl(navigator, config.playStoreUrl);
      return;
    }
    if (navigator.canPop()) navigator.pop(true);
  }

  Future<void> _launchFacebook(NavigatorState navigator) async {
    await _openUrl(navigator, config.facebookUrl);
  }

  Future<void> _openUrl(NavigatorState navigator, String url) async {
    try {
      if (launchUrlForTesting != null) {
        await launchUrlForTesting!(url);
      } else {
        final uri = Uri.parse(url);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Best-effort: a failed launch never blocks the dismiss.
    }
    if (navigator.canPop()) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const ValueKey('jagspoorReviewModal'),
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              JagspoorReviewPalette.black,
              Color(0xFF16110A),
              JagspoorReviewPalette.kalahariBrown,
            ],
            stops: [0.0, 0.55, 1.0],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: JagspoorReviewPalette.gold.withValues(alpha: 0.55),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: JagspoorReviewPalette.gold.withValues(alpha: 0.18),
              blurRadius: 28,
              spreadRadius: 1,
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLogo(),
              const SizedBox(height: 18),
              Text(
                config.promptTitleFor(isOutfitter),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: JagspoorReviewPalette.gold,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                config.promptMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: JagspoorReviewPalette.sandText,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              _buildStars(),
              const SizedBox(height: 20),
              _buildActionButton(
                context,
                key: const ValueKey('reviewWhatsAppButton'),
                icon: Icons.chat_rounded,
                iconColor: JagspoorReviewPalette.whatsapp,
                label: 'WHATSAPP',
                subtitle:
                    isOutfitter ? 'Share your farm' : 'Share your hunt story',
                onTap: (navigator) => _shareWhatsApp(navigator),
              ),
              const SizedBox(height: 10),
              _buildActionButton(
                context,
                key: const ValueKey('reviewFacebookButton'),
                icon: Icons.facebook_rounded,
                iconColor: JagspoorReviewPalette.facebook,
                label: 'FACEBOOK',
                subtitle: 'Leave a review on Facebook',
                onTap: (navigator) => _launchFacebook(navigator),
              ),
              const SizedBox(height: 10),
              // The Google Play rating affordance is a NATIVE store action —
              // `InAppReview` / the Play Store listing do not exist in a
              // browser, so it is hidden on the web build. The web prompt
              // keeps WhatsApp + Facebook.
              if (!kIsWeb)
                _buildActionButton(
                  context,
                  key: const ValueKey('reviewRatePlayStoreButton'),
                  icon: Icons.rate_review_rounded,
                  iconColor: JagspoorReviewPalette.gold,
                  label: 'GOOGLE PLAY RATE',
                  subtitle: 'Rate us on Google Play Store',
                  onTap: (navigator) => _launchPlayStore(navigator),
                ),
              if (!kIsWeb) const SizedBox(height: 8),
              TextButton(
                key: const ValueKey('reviewMaybeLaterButton'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  'MAYBE LATER',
                  style: TextStyle(
                    color: JagspoorReviewPalette.sandText,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: JagspoorReviewPalette.black,
        border: Border.all(
          color: JagspoorReviewPalette.bushKarooKalahari,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        logoAsset,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.star_rounded,
          color: JagspoorReviewPalette.gold,
          size: 44,
        ),
      ),
    );
  }

  Widget _buildStars() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        5,
        (i) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 3),
          child: Icon(
            Icons.star_rounded,
            color: JagspoorReviewPalette.gold,
            size: 26,
          ),
        ),
      ),
    );
  }

  /// A full-width action row: brand-tinted icon + label + subtitle.
  Widget _buildActionButton(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String subtitle,
    required Future<void> Function(NavigatorState navigator) onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        key: key,
        onPressed: () => onTap(Navigator.of(context)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          alignment: Alignment.centerLeft,
          side: BorderSide(color: iconColor.withValues(alpha: 0.55)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: JagspoorReviewPalette.sandText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: JagspoorReviewPalette.sandText
                          .withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
