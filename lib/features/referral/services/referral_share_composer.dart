/// Pure, dependency-light composer for the JagSpoor referral share flow.
///
/// Owns the human-readable share text + the WhatsApp `wa.me` deep link, and
/// delegates the canonical referral URL to [ReferralLinkService] (the
/// post-Dynamic-Links App Links service). Fully unit-testable with no
/// Flutter / platform plugins (mirrors the [TrophyShareComposer] /
/// [SupportEmailComposer] pattern).
library;

import 'package:jagspoor/services/referral_link_service.dart';

/// Builds shareable referral strings + links for a referral code.
///
/// The canonical share URL is now a plain HTTPS App Link on the owned
/// `jagspoor.co.za` domain — `https://jagspoor.co.za/r/<CODE>` — because
/// Firebase Dynamic Links (`jagspoor.page.link`) was shut down by Google on
/// 2025-08-25. The link is verified by Android App Links / iOS Universal
/// Links and falls back to a website landing page when the app is not
/// installed. See [ReferralLinkService] for the full contract.
class ReferralShareComposer {
  ReferralShareComposer._();

  /// The canonical HTTPS App Link base for the referral landing route.
  static const String kReferralLinkBaseUrl =
      '${ReferralLinkService.domain}${ReferralLinkService.referralPathPrefix}';

  /// WhatsApp web/mobile deep-link base for the share intent.
  static const String kWhatsAppBaseUrl = 'https://wa.me/';

  /// The default share subject used by the native share sheet.
  static const String kDefaultShareSubject = ReferralLinkService.shareSubject;

  /// The app display-name used in the composed share message.
  static const String kAppName = 'JagSpoor';

  /// The support / contact email appended to the share message.
  static const String kSupportEmail = 'support@jagspoor.co.za';

  /// Builds the shareable referral App Link for [code], e.g.
  /// `https://jagspoor.co.za/r/JAGSPOOR7Q3X`.
  ///
  /// [code] is upper-cased + trimmed; a blank/null code yields an empty
  /// string (the caller should hide the share UI when there is no code).
  static String buildReferralLink(String? code) =>
      ReferralLinkService.generateReferralLinkForCode(code ?? '');

  /// Builds the custom-scheme fallback link (`jagspoor://referral?code=CODE`).
  /// Empty for a blank code.
  static String buildCustomSchemeLink(String? code) =>
      ReferralLinkService.generateCustomSchemeLink(code ?? '');

  /// Builds the human-readable share message for [code] (WhatsApp / native
  /// share text). Multi-line, brand-consistent, with the App Link.
  static String buildShareMessage(String? code) {
    final cleaned = _cleanCode(code);
    if (cleaned.isEmpty) return '';
    final link = buildReferralLink(cleaned);
    return 'Join me on JagSpoor — my referral code is $cleaned! '
        'Refer a friend and we both unlock rewards.\n\n'
        'Use my link: $link\n\n'
        'Get started: install the JagSpoor app and enter my code when '
        'you sign up.\n\n'
        'Questions? contact $kSupportEmail';
  }

  /// Builds the WhatsApp deep link for [code], e.g.
  /// `https://wa.me/?text=<encoded share message>`. WhatsApp's `wa.me` link
  /// accepts a `text=` query param pre-filling the draft; percent-encoded via
  /// [Uri.encodeComponent] so spaces/newlines are safe.
  ///
  /// Returns an empty string when there is no code.
  static String buildWhatsAppShareLink(String? code) {
    final message = buildShareMessage(code);
    if (message.isEmpty) return '';
    return '$kWhatsAppBaseUrl?text=${Uri.encodeComponent(message)}';
  }

  /// Formats a referral code for display on the card, e.g. `JAGSPOOR 7Q3X`
  /// (space-grouped every 4 chars). Upper-cases + trims; blank/null -> ''.
  static String formatCodeForDisplay(String? code) {
    final cleaned = _cleanCode(code);
    if (cleaned.isEmpty) return '';
    final sb = StringBuffer();
    for (var i = 0; i < cleaned.length; i++) {
      if (i > 0 && i % 4 == 0) sb.write(' ');
      sb.write(cleaned[i]);
    }
    return sb.toString();
  }

  static String _cleanCode(String? code) {
    if (code == null) return '';
    return code.trim().toUpperCase();
  }
}
