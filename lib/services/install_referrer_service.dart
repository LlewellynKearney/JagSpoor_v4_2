/// Google Play Install Referrer reader (Android deferred deep link).
///
/// The referral share link for a NOT-installed user points at the Play Store
/// with a `referrer` parameter (`...&referrer=referral_<CODE>`). On the FIRST
/// launch after install this service reads that value back via the official
/// **Play Install Referrer Library 2.2** (bridged in
/// `android/app/src/main/kotlin/za/co/jagspoor/app/MainActivity.kt`), parses
/// the `<CODE>`, validates it against the `referralCodes/{code}` reverse index
/// and caches it so the signup screen can pre-fill + redeem it.
///
/// Per the Play docs the native bridge calls `endConnection()` after reading
/// (or on any failure); this Dart layer never re-opens a connection. The
/// referrer value is available for 90 days after install.
///
/// Design notes:
///   * **Android only** — the Install Referrer API does not exist on iOS. On
///     iOS the flow falls back to MANUAL CODE ENTRY on signup (the iOS
///     deferred link is deliberately NOT implemented — the owner is not an
///     iOS developer yet; see `docs/fix-referral-audit/TASK2B_DONE.md`).
///   * **First launch only** — guarded by a `SharedPreferences` flag so the
///     Play Store is queried once; the resolved code lives in
///     [ReferralLinkHandler] from then on.
///   * **Never throws** — a missing plugin / channel error / malformed
///     referrer is logged and swallowed so startup is never blocked.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jagspoor/features/referral/services/referral_repository.dart';
import 'package:jagspoor/services/incoming_referral_handler.dart';
import 'package:jagspoor/services/referral_link_service.dart';

/// Result of a referrer read.
class InstallReferrerResult {
  final String? rawReferrer;
  final String? referralCode;
  final bool validated;
  final String? error;

  const InstallReferrerResult({
    this.rawReferrer,
    this.referralCode,
    this.validated = false,
    this.error,
  });

  bool get hasCode => (referralCode ?? '').isNotEmpty;
}

class InstallReferrerService {
  InstallReferrerService._internal();

  static final InstallReferrerService instance =
      InstallReferrerService._internal();

  /// The platform method channel the native bridge listens on.
  static const String channelName = 'com.jagspoor/install_referrer';
  static const String methodGetInstallReferrer = 'getInstallReferrer';

  /// `SharedPreferences` flag marking that the referrer has been read once.
  static const String checkedPrefsKey = 'install_referrer_checked';

  /// Test seam: override the platform check (defaults to `Platform.isAndroid`).
  @visibleForTesting
  bool? isAndroidForTesting;

  /// Test seam: override the raw referrer string (bypasses the channel).
  @visibleForTesting
  String? rawReferrerForTesting;

  /// Test seam: override the code validator.
  @visibleForTesting
  Future<bool> Function(String code)? validateCodeForTesting;

  /// Test seam: force the "already checked" flag (defaults to the stored pref).
  @visibleForTesting
  bool? alreadyCheckedForTesting;

  bool get _isAndroid {
    if (isAndroidForTesting != null) return isAndroidForTesting!;
    try {
      return defaultTargetPlatform == TargetPlatform.android && !kIsWeb;
    } catch (_) {
      return false;
    }
  }

  /// Reads + caches the Play Install Referrer on the first Android launch.
  ///
  /// Returns the resolved [InstallReferrerResult]. Safe to call before
  /// `Firebase.initializeApp()` and on every platform.
  Future<InstallReferrerResult> initialize() async {
    if (!_isAndroid) {
      return const InstallReferrerResult(
        error: 'install referrer is Android-only',
      );
    }
    try {
      final checked = alreadyCheckedForTesting ?? await _wasChecked();
      if (checked) {
        return const InstallReferrerResult(
          error: 'install referrer already read',
        );
      }
      final raw = rawReferrerForTesting ?? await _readRawReferrer();
      await _markChecked();
      if (raw == null || raw.trim().isEmpty) {
        return const InstallReferrerResult();
      }
      final code = ReferralLinkService.parseInstallReferrer(raw);
      if (code == null || code.isEmpty) {
        return InstallReferrerResult(rawReferrer: raw);
      }
      final validator = validateCodeForTesting ?? _defaultValidateCode;
      var valid = false;
      try {
        valid = await validator(code);
      } catch (e) {
        debugPrint('InstallReferrerService: validate failed: $e');
      }
      await ReferralLinkHandler.instance.registerCode(code, validated: valid);
      return InstallReferrerResult(
        rawReferrer: raw,
        referralCode: code,
        validated: valid,
      );
    } catch (e) {
      debugPrint('InstallReferrerService.initialize: $e');
      return InstallReferrerResult(error: '$e');
    }
  }

  /// Invokes the native bridge and returns the raw `installReferrer` string.
  Future<String?> _readRawReferrer() async {
    try {
      const channel = MethodChannel(channelName);
      final result = await channel
          .invokeMethod<Map<dynamic, dynamic>>(methodGetInstallReferrer);
      final value = result?['installReferrer'];
      return value?.toString();
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('InstallReferrerService: platform error: ${e.code}');
      return null;
    } catch (e) {
      debugPrint('InstallReferrerService._readRawReferrer: $e');
      return null;
    }
  }

  Future<bool> _wasChecked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(checkedPrefsKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _markChecked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(checkedPrefsKey, true);
    } catch (e) {
      debugPrint('InstallReferrerService._markChecked: $e');
    }
  }

  Future<bool> _defaultValidateCode(String code) async {
    final index = await ReferralRepository.instance.getReferralCode(code);
    return index != null && index.isRedeemable;
  }

  /// @visibleForTesting — clear the seams between tests.
  @visibleForTesting
  void resetForTesting() {
    isAndroidForTesting = null;
    rawReferrerForTesting = null;
    validateCodeForTesting = null;
    alreadyCheckedForTesting = null;
  }
}
