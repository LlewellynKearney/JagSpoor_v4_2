/// Referral deep-link service — the post-Dynamic-Links replacement.
///
/// Firebase Dynamic Links was shut down by Google on 2025-08-25, so every
/// `https://jagspoor.page.link/...` URL is dead. Referral sharing now uses
/// **standard HTTPS App Links** on the owned domain:
///
///   * canonical share link: `https://jag-spoor.co.za/r/<CODE>`
///   * custom-scheme fallback: `jagspoor://referral?code=<CODE>`
///
/// The HTTPS link resolves on Android via App Links (`android:autoVerify` +
/// `/.well-known/assetlinks.json`) and on iOS via Universal Links
/// (`apple-app-site-association` + the `Associated Domains` entitlement).
///
/// **iOS IS OUT OF SCOPE (Task 2B, 2026-11-14).** The iOS deferred link is
/// deliberately NOT implemented: the AASA still carries the
/// `REPLACE_WITH_TEAM_ID` placeholder and the owner is not an iOS developer
/// yet. An iOS user who taps a referral link therefore uses MANUAL CODE ENTRY
/// on signup (validated against `referralCodes/{code}`) — no Apple Team ID /
/// AASA / AppleProvider work is done here. See
/// `docs/fix-referral-audit/TASK2B_DONE.md`.
///
/// When the app is not installed the same URL is served by the website, which
/// shows a "Download Jagspoor" page with the code pre-filled. The custom
/// scheme is the last-resort fallback for an installed app on a device that
/// has not yet verified the HTTPS association.
///
/// The canonical link format is intentionally `path`-based (`/r/<CODE>`), not
/// query-based, so it survives being pasted into a browser / a web redirect
/// without a query string being stripped.
///
/// Pure + dependency-light: only [share_plus] for the native share sheet, so
/// the link builders are fully unit-testable with no platform plugins.
library;

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

class ReferralLinkService {
  ReferralLinkService._();

  /// The owned production domain that hosts the App-Links / Universal-Links
  /// association files and the `/r/<code>` web fallback page.
  static const String domain = 'https://jag-spoor.co.za';

  /// The path prefix used for referral links (`https://jag-spoor.co.za/r/CODE`).
  static const String referralPathPrefix = '/r/';

  /// The custom URL scheme fallback (`jagspoor://referral?code=CODE`).
  static const String customScheme = 'jagspoor';
  static const String customSchemeHost = 'referral';

  /// The path prefix the website serves the referral landing page from.
  /// Kept identical to [referralPathPrefix] so the app + web agree.
  static const String webLandingPathPrefix = referralPathPrefix;

  /// The referral-code query parameter used by BOTH the custom-scheme link
  /// and the web landing page (`?code=CODE`).
  static const String codeQueryParam = 'code';

  /// The exact path the Android / iOS association files must be reachable at.
  static const String assetLinksPath = '/.well-known/assetlinks.json';
  static const String appleAppSiteAssociationPath =
      '/.well-known/apple-app-site-association';

  /// Human-readable share copy prefix (brand-consistent marketing line).
  ///
  /// Truthful claim only: the REFERRER earns a 30-day premium extension once
  /// the friend genuinely engages (verified email + completed profile + a
  /// qualifying in-app action). The friend is NOT promised a reward, because
  /// the programme does not grant one — promising otherwise is a Play
  /// "misleading claims" violation.
  static const String sharePrefix =
      'Join JagSpoor — you earn 30 days of premium when a friend joins and becomes active!';

  /// Native-share subject.
  static const String shareSubject = 'Join me on JagSpoor!';

  /// Builds the canonical HTTPS App Link for [referralCode], e.g.
  /// `https://jag-spoor.co.za/r/JAGSPOOR7Q3X`.
  ///
  /// [referralCode] is trimmed + upper-cased; the path segment is
  /// percent-encoded via [Uri.encodeComponent] so a code carrying an unusual
  /// character can never break the URL. A blank / null code yields an empty
  /// string (the caller hides the share UI when there is no code).
  static String generateReferralLink(String userId, String referralCode) {
    final cleaned = _cleanCode(referralCode);
    if (cleaned.isEmpty) return '';
    return '$domain$referralPathPrefix${Uri.encodeComponent(cleaned)}';
  }

  /// Convenience overload that ignores the (unused) user id — mirrors the
  /// single-argument call sites and keeps the explicit `(userId, code)`
  /// signature available for analytics / logging use.
  static String generateReferralLinkForCode(String referralCode) =>
      generateReferralLink('', referralCode);

  /// The Play Store application id (matches `android/app/build.gradle.kts`
  /// `applicationId`).
  static const String playPackageId = 'za.co.jagspoor.app';

  /// The Play Store listing URL.
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=$playPackageId';

  /// Builds the Google Play install URL carrying the referral code as the
  /// Install Referrer `referrer` parameter, e.g.
  /// `https://play.google.com/store/apps/details?id=za.co.jagspoor.app&referrer=referral_<CODE>`.
  ///
  /// When the app is NOT installed, the share link opens the website landing
  /// page which sends the user here; the `referrer` value is read back on the
  /// first launch via the Play Install Referrer API (see
  /// `InstallReferrerService`) so the code survives the store install.
  /// [referralCode] is trimmed + upper-cased; the `referrer` value is
  /// URL-encoded per the Install Referrer contract. A blank code yields the
  /// plain listing URL.
  static String buildPlayStoreReferrerUrl(String referralCode) {
    final cleaned = _cleanCode(referralCode);
    if (cleaned.isEmpty) return playStoreUrl;
    final referrer = Uri.encodeComponent('$installReferrerPrefix$cleaned');
    return '$playStoreUrl&referrer=$referrer';
  }

  /// The Install Referrer value prefix (`referral_<CODE>`), matching the
  /// contract parsed by `InstallReferrerService`.
  static const String installReferrerPrefix = 'referral_';

  /// Parses a raw Play Install Referrer string into a referral code.
  ///
  /// Accepts `referral_<CODE>` (the canonical value the share links emit) and
  /// tolerates a leading `?`/`&`, additional `&`-joined params, and a bare
  /// `<CODE>`. Returns the upper-cased code, or null when no code is present.
  static String? parseInstallReferrer(String? referrer) {
    if (referrer == null) return null;
    final raw = referrer.trim();
    if (raw.isEmpty) return null;
    // Split off any additional `&`-joined params and a leading `?`.
    final firstSegment = raw
        .replaceFirst(RegExp(r'^[?&]'), '')
        .split('&')
        .firstWhere((s) => s.trim().isNotEmpty, orElse: () => '');
    if (firstSegment.isEmpty) return null;
    var value = firstSegment;
    final prefixIndex = value.toLowerCase().indexOf(installReferrerPrefix);
    if (prefixIndex >= 0) {
      value = value.substring(prefixIndex + installReferrerPrefix.length);
    } else {
      // A `code=CODE` query form is also accepted.
      final eq = value.indexOf('=');
      if (eq >= 0) value = value.substring(eq + 1);
    }
    final cleaned = _cleanCode(_safeDecode(value));
    return cleaned.isEmpty ? null : cleaned;
  }

  /// `Uri.decodeComponent` that never throws on a malformed percent escape.
  static String _safeDecode(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  /// Builds the custom-scheme fallback deep link, e.g.
  /// `jagspoor://referral?code=JAGSPOOR7Q3X`. Empty for a blank code.
  static String generateCustomSchemeLink(String referralCode) {
    final cleaned = _cleanCode(referralCode);
    if (cleaned.isEmpty) return '';
    return '$customScheme://$customSchemeHost'
        '?$codeQueryParam=${Uri.encodeComponent(cleaned)}';
  }

  /// Builds the full native-share message (the marketing line + the HTTPS
  /// App Link). Empty for a blank code.
  static String buildShareMessage(String referralCode, {String? userId}) {
    final link = generateReferralLink(userId ?? '', referralCode);
    if (link.isEmpty) return '';
    return '$sharePrefix $link';
  }

  /// Launches the native platform share sheet with the referral App Link.
  ///
  /// Never throws: a platform / plugin failure is logged and swallowed so the
  /// caller can surface its own fallback (e.g. a "copy the link" hint).
  static Future<void> shareReferralLink(
    String referralCode, {
    String? userId,
    String? subject,
  }) async {
    final message = buildShareMessage(referralCode, userId: userId);
    if (message.isEmpty) return;
    try {
      await Share.share(message, subject: subject ?? shareSubject);
    } catch (e) {
      debugPrint('ReferralLinkService.shareReferralLink: $e');
    }
  }

  /// Extracts a referral code from an incoming deep link, or null when the
  /// URI is not a referral link.
  ///
  /// Handles BOTH shapes:
  ///   * HTTPS App Link — `https://jag-spoor.co.za/r/<CODE>`
  ///     (the code is the final path segment).
  ///   * Custom scheme — `jagspoor://referral?code=<CODE>`
  ///     (the code is the `code` query parameter).
  ///
  /// Also tolerates a `?code=` query parameter on the HTTPS link (a web
  /// redirect may append one) as a secondary source. Returns the upper-cased
  /// code, or null when neither shape matches.
  static String? extractReferralCode(Uri? uri) {
    if (uri == null) return null;

    // Custom scheme: jagspoor://referral?code=CODE
    if (uri.scheme == customScheme) {
      final queryCode = uri.queryParameters[codeQueryParam];
      if (queryCode != null && queryCode.trim().isNotEmpty) {
        return _cleanCode(queryCode);
      }
      // Fall through: a custom-scheme link may still carry the code as its
      // final path segment (jagspoor://referral/CODE).
      final segments = _nonEmptySegments(uri);
      if (segments.isNotEmpty) return _cleanCode(segments.last);
      return null;
    }

    // HTTPS App Link: https://jag-spoor.co.za/r/CODE
    final isHttps = uri.scheme == 'https' || uri.scheme == 'http';
    if (isHttps) {
      final segments = _nonEmptySegments(uri);
      final prefixIndex =
          segments.indexWhere((s) => s == referralPathPrefix.replaceAll('/', ''));
      if (prefixIndex >= 0 && prefixIndex + 1 < segments.length) {
        return _cleanCode(segments[prefixIndex + 1]);
      }
      // A `?code=` fallback (web redirect / legacy query-shaped link).
      final queryCode = uri.queryParameters[codeQueryParam];
      if (queryCode != null && queryCode.trim().isNotEmpty) {
        return _cleanCode(queryCode);
      }
    }

    return null;
  }

  /// True when [uri] is a referral link for this app (either shape).
  static bool isReferralLink(Uri? uri) => extractReferralCode(uri) != null;

  static List<String> _nonEmptySegments(Uri uri) =>
      uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();

  static String _cleanCode(String? code) {
    if (code == null) return '';
    return code.trim().toUpperCase();
  }
}
