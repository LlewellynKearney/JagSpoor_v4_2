/// Incoming referral deep-link handler (post-Dynamic-Links).
///
/// Replaces the dead Firebase Dynamic Links receiver with a plain
/// `app_links` listener. On cold start and every subsequent launch it
/// inspects the incoming URI for a referral code (either the HTTPS App Link
/// `https://jagspoor.co.za/r/<CODE>` or the custom-scheme fallback
/// `jagspoor://referral?code=<CODE>`), extracts the code with
/// [ReferralLinkService.extractReferralCode], validates it against the
/// `referralCodes/{code}` reverse index, and caches it so the signup screen
/// can pre-fill + redeem it.
///
/// Design notes:
///   * **Never throws** — a missing platform plugin (`[core/no-app]`-style
///     failure), an uninitialised Firebase, or a malformed URI is logged and
///     ignored so startup is never blocked.
///   * **Late signup** — the incoming code may arrive BEFORE the user signs
///     in (the common case: they tap the link, land in the app, then create
///     an account). The resolved + raw codes are therefore persisted in a
///     process-wide singleton ([ReferralLinkHandler.instance]) that the
///     signup UI reads, in addition to the durable
///     [SharedPreferences] copy so a mid-flow process death still recovers it.
///   * **Testable** — the URI stream + the code-validation callback are
///     injectable seams, so the full handler contract is unit-testable
///     without the native plugin.
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jagspoor/features/referral/services/referral_repository.dart';
import 'package:jagspoor/services/referral_link_service.dart';

/// Thin abstraction over the native link source so the handler is testable
/// without the platform plugin (the real implementation wraps `AppLinks`).
abstract class AppLinkSource {
  Future<Uri?> getInitialLink();
  Stream<Uri> get uriLinkStream;
}

/// Production [AppLinkSource] backed by the `app_links` plugin.
class PluginAppLinkSource implements AppLinkSource {
  PluginAppLinkSource([AppLinks? appLinks]) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  @override
  Future<Uri?> getInitialLink() => _appLinks.getInitialLink();

  @override
  Stream<Uri> get uriLinkStream => _appLinks.uriLinkStream;
}

/// Process-wide store for the most recently seen incoming referral code.
///
/// The signup screen reads [pendingCode] to pre-fill the referral field; the
/// value survives navigation (a singleton, not a screen field) and a cold
/// start (durably mirrored to SharedPreferences).
class ReferralLinkHandler {
  ReferralLinkHandler._internal();

  static final ReferralLinkHandler instance = ReferralLinkHandler._internal();

  /// SharedPreferences key holding the durable copy of the pending code.
  static const String pendingCodePrefsKey = 'pending_referral_code';

  String? _pendingCode;
  StreamSubscription<Uri>? _subscription;

  /// The most recently received, un-consumed referral code (upper-cased), or
  /// null when there is none.
  String? get pendingCode => _pendingCode;

  /// True when a referral code is waiting to be redeemed.
  bool get hasPendingCode =>
      _pendingCode != null && _pendingCode!.isNotEmpty;

  /// Initialises the App Links listener.
  ///
  /// [onCodeResolved] (optional) is invoked with the extracted code whenever
  /// one arrives — the signup screen can use it to react immediately.
  /// [appLinks] / [validateCode] are test seams; production uses the real
  /// `AppLinks()` + the `referralCodes` reverse index.
  ///
  /// Safe to call before `Firebase.initializeApp()` and on platforms without
  /// App Link support — every failure path is caught and logged.
  Future<void> initialize({
    void Function(String code)? onCodeResolved,
    AppLinkSource? appLinks,
    Future<bool> Function(String code)? validateCode,
  }) async {
    // Restore any durable pending code from a previous session first, so a
    // link tapped before a process restart is not lost.
    await _restorePendingCode();

    final resolver = appLinks ?? PluginAppLinkSource();
    final validator = validateCode ?? _defaultValidateCode;

    // Cold-start link: getInitialLink() resolves the URI that launched the
    // app (Android) / null when the app was opened normally.
    try {
      final initial = await resolver.getInitialLink();
      if (initial != null) {
        await _handleUri(initial, validator, onCodeResolved);
      }
    } catch (e) {
      debugPrint('ReferralLinkHandler: getInitialLink failed: $e');
    }

    // Warm links: every subsequent URI delivered while the app is running
    // (Android onNewIntent / iOS continueUserActivity / custom scheme).
    try {
      _subscription?.cancel();
      _subscription = resolver.uriLinkStream.listen(
        (uri) => _handleUri(uri, validator, onCodeResolved),
        onError: (Object e) =>
            debugPrint('ReferralLinkHandler: uriLinkStream error: $e'),
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('ReferralLinkHandler: uriLinkStream subscribe failed: $e');
    }
  }

  /// Cancels the URI listener (used by tests / teardown).
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Manually feeds a URI through the handler (used by tests + any caller
  /// that already has the raw link, e.g. a web `?code=` redirect).
  Future<void> handleUri(Uri? uri, {Future<bool> Function(String)? validateCode}) =>
      _handleUri(uri, validateCode ?? _defaultValidateCode, null);

  /// Records [code] as the pending referral code (upper-cased) and returns
  /// true when it is a valid, redeemable code.
  Future<bool> registerCode(String code, {bool validated = true}) async {
    final cleaned = code.trim().toUpperCase();
    if (cleaned.isEmpty) return false;
    _pendingCode = cleaned;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(pendingCodePrefsKey, cleaned);
    } catch (e) {
      debugPrint('ReferralLinkHandler: persist pending code failed: $e');
    }
    return validated;
  }

  /// Clears the pending code (called after a successful redemption so the
  /// same link does not re-apply on the next launch).
  Future<void> clearPendingCode() async {
    _pendingCode = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(pendingCodePrefsKey);
    } catch (e) {
      debugPrint('ReferralLinkHandler: clear pending code failed: $e');
    }
  }

  /// @visibleForTesting — reset in-memory state between tests.
  @visibleForTesting
  void resetForTesting() {
    _pendingCode = null;
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _handleUri(
    Uri? uri,
    Future<bool> Function(String code) validate,
    void Function(String code)? onCodeResolved,
  ) async {
    final code = ReferralLinkService.extractReferralCode(uri);
    if (code == null || code.isEmpty) return;
    var valid = false;
    try {
      valid = await validate(code);
    } catch (e) {
      debugPrint('ReferralLinkHandler: code validation failed: $e');
    }
    await registerCode(code, validated: valid);
    if (valid) {
      try {
        onCodeResolved?.call(code);
      } catch (e) {
        debugPrint('ReferralLinkHandler: onCodeResolved callback failed: $e');
      }
    }
  }

  Future<void> _restorePendingCode() async {
    if (_pendingCode != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(pendingCodePrefsKey);
      if (stored != null && stored.trim().isNotEmpty) {
        _pendingCode = stored.trim().toUpperCase();
      }
    } catch (e) {
      debugPrint('ReferralLinkHandler: restore pending code failed: $e');
    }
  }

  Future<bool> _defaultValidateCode(String code) async {
    final index = await ReferralRepository.instance.getReferralCode(code);
    return index != null && index.isRedeemable;
  }
}
