/// Pure, dependency-light composer for the JagSpoor referral share flow.
///
/// Owns the deep-link URL, the human-readable share text, and the WhatsApp
/// `wa.me` deep link — all derived from a user's [ReferralProfile] referral
/// code. Fully unit-testable with no Flutter / platform plugins (mirrors the
/// [TrophyShareComposer] / [SupportEmailComposer] pattern).
library;

import 'package:jagspoor/features/referral/models/referral_profile.dart';

/// Builds shareable referral strings + links for a referral code.
///
/// The canonical share URL is a Firebase Dynamic Links deep link on the
/// `jagspoor.page.link` domain (the same domain the password-reset flow
/// uses) so a tapped link can be handed to the installed app or web checker
/// (`jagspoor.page.link/referral?code=<CODE>`). `wa.me` links are used for
/// the "Share via WhatsApp" action (the native WhatsApp share intent).
class ReferralShareComposer {
  ReferralShareComposer._();

  /// The Firebase Dynamic Links base domain used for the referral deep link.
  /// Must stay authorized in the Firebase Console (Authentication -> Settings
  /// -> Authorized domains) for the link to resolve.
  static const String kReferralLinkBaseUrl = 'https://jagspoor.page.link/referral';

  /// WhatsApp web/mobile deep-link base for the share intent.
  static const String kWhatsAppBaseUrl = 'https://wa.me/';

  /// The default share subject used by the native share sheet.
  static const String kDefaultShareSubject = 'Join me on JagSpoor!';

  /// The app display-name used in the composed share message.
  static const String kAppName = 'JagSpoor';

  /// The support / contact email appended to the share message.
  static const String kSupportEmail = 'support@jagspoor.co.za';

  /// Builds the shareable referral deep link for [code], e.g.
  /// `https://jagspoor.page.link/referral?code=JAGSPOOR7Q3X`.
  ///
  /// [code] is upper-cased + trimmed; a blank/null code yields an empty
  /// string (the caller should hide the share UI when there is no code).
  static String buildReferralLink(String? code) {
    final cleaned = _cleanCode(code);
    if (cleaned.isEmpty) return '';
    return '$kReferralLinkBaseUrl?code=$cleaned';
  }

  /// Builds the human-readable share message for [code] (WhatsApp / native
  /// share text). Multi-line, brand-consistent, with the deep link.
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