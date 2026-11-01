import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Firestore-driven forced-update gate.
///
/// Reads `admin_config/app_version` (the Admin Portal control-plane doc) and,
/// when `force_update` is true AND the installed build's Android `versionCode`
/// is below `min_required_version`, shows a **non-dismissible** "Update
/// Required" dialog whose only action opens the Play Store listing.
///
/// This is the direct-Firestore counterpart to [ForceUpdateService]
/// (Firebase Remote Config). It lets the team hard-block a closed-test build
/// the moment the control-plane doc is set, without waiting for a Remote
/// Config publish.
///
/// Failure policy is **fail-open**: any error (Firestore unavailable, Firebase
/// not initialised, offline with no cache, a malformed doc) is logged and
/// resolves to `false` so a control-plane outage can never lock users out.
class AppVersionCheck {
  const AppVersionCheck._();

  /// Control-plane doc holding the version floor.
  static const String configPath = 'admin_config/app_version';

  /// The production Play Store listing for JagSpoor.
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=za.co.jagspoor.app';

  /// Fallback copy when the doc carries no `force_update_message`.
  static const String defaultMessage =
      'A required update is available. Please update to continue.';

  /// Resolves the decision from the control-plane doc without showing any UI.
  ///
  /// Extracted so the gating rule is unit-testable without a widget tree.
  /// [currentBuildNumber] is the installed `versionCode` (`0` when it could
  /// not be parsed — treated as "unknown"). A non-positive floor, a missing
  /// doc or `force_update == false` never blocks.
  ///
  /// Two fail-open guards matter here (they produced the web "Update
  /// Required" loop):
  ///   - a web build is NEVER blocked — the browser app is served straight
  ///     from Hosting so it is always the latest deploy, and `package_info`
  ///     reports no meaningful build number in a browser;
  ///   - an unparsed build number (`0`) is skipped so a platform that does
  ///     not report a versionCode cannot be locked out by a positive floor.
  @visibleForTesting
  static bool shouldForceUpdate({
    required bool docExists,
    required int minRequiredVersion,
    required bool forceUpdate,
    required int currentBuildNumber,
    bool isWeb = false,
  }) {
    if (isWeb) return false;
    if (!docExists) return false;
    if (!forceUpdate) return false;
    if (minRequiredVersion <= 0) return false;
    if (currentBuildNumber <= 0) return false;
    return currentBuildNumber < minRequiredVersion;
  }

  /// True when the installed build must be updated before the app is usable.
  ///
  /// When true, a blocking dialog has been shown and the caller must abandon
  /// its normal navigation (the dialog cannot be dismissed).
  static Future<bool> isUpdateRequired(BuildContext context) async {
    // Never gate the web build: it is served straight from Hosting (always
    // the latest deploy) and has no meaningful `versionCode`, so enforcing a
    // floor there only produced an "Update Required" loop on the browser.
    if (kIsWeb) return false;
    try {
      final doc = await FirebaseFirestore.instance
          .doc(configPath)
          .get();
      final data = doc.data();
      final minRequired = (data?['min_required_version'] as num?)?.toInt() ?? 0;
      final forceUpdate = data?['force_update'] as bool? ?? false;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      final blocked = shouldForceUpdate(
        docExists: doc.exists,
        minRequiredVersion: minRequired,
        forceUpdate: forceUpdate,
        currentBuildNumber: currentBuildNumber,
        isWeb: kIsWeb,
      );
      if (!blocked) return false;

      final message =
          data?['force_update_message'] as String? ?? defaultMessage;

      if (!context.mounted) return true;
      await showDialog<void>(
        barrierDismissible: false,
        context: context,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Update Required'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () async {
                  final url = Uri.parse(playStoreUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(
                      url,
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                child: const Text('UPDATE NOW'),
              ),
            ],
          ),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Version check error: $e');
      return false;
    }
  }
}
