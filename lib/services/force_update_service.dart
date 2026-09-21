import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Firebase Remote Config force-update kill switch.
///
/// A server-controlled gate that lets the team hard-block an app build without
/// publishing a new version: Remote Config carries
/// `min_required_version_code` (the lowest Android `versionCode` allowed to
/// keep running) and `force_update_message` (the copy shown in the block
/// dialog). When the installed build's `versionCode` is below the value
/// fetched from Remote Config, [shouldForceUpdate] reports `true` and the
/// splash screen shows a non-dismissible "Update Required" dialog that hands
/// off to the Google Play in-app update flow (see `UpdateService`).
///
/// This complements the Play in-app update check: in-app updates only fire
/// when the Play *store* offers a newer build, whereas Remote Config lets us
/// raise the floor for a specific build even before/without a store release
/// (staged rollouts, a pulled release, a broken migration).
///
/// Failure policy is **fail-open**: any error (Remote Config unavailable,
/// offline with no cached values, Firebase not initialised, a parse error) is
/// logged and resolves to `false`, so a Remote Config outage can never lock
/// every user out of the app. The gate is a kill switch, not a hard
/// dependency.
class ForceUpdateService {
  const ForceUpdateService._();

  /// Remote Config key carrying the minimum allowed Android `versionCode`.
  static const String minVersionCodeKey = 'min_required_version_code';

  /// Remote Config key carrying the message shown in the block dialog.
  static const String forceUpdateMessageKey = 'force_update_message';

  /// Default copy, used when Remote Config has no `force_update_message` value
  /// (including the very first launch before any fetch has ever succeeded).
  static const String defaultForceUpdateMessage =
      'A critical update is required for JagSpoor to continue. '
      'Please update to continue hunting.';

  /// Conservative default for `min_required_version_code`: `0` means "no
  /// build is below the floor", so an unconfigured/failed fetch never blocks
  /// a launch.
  static const int defaultMinVersionCode = 0;

  /// Pure comparison behind the kill switch: a build is blocked when its
  /// `versionCode` is strictly below the Remote Config floor.
  ///
  /// Extracted so the gating rule is unit-testable without Firebase. A
  /// non-positive [minVersionCode] (the default / an unset key) can never
  /// block, keeping the gate fail-open.
  @visibleForTesting
  static bool shouldBlock({
    required int minVersionCode,
    required int currentVersionCode,
  }) {
    if (minVersionCode <= 0) return false;
    return currentVersionCode < minVersionCode;
  }

  /// Returns `true` when the installed build must be updated before the app
  /// may continue. Never throws — a failure resolves to `false`.
  static Future<bool> shouldForceUpdate() async {
    final decision = await evaluate();
    return decision.needsUpdate;
  }

  /// Full decision (needs-update flag + the Remote Config message + the two
  /// version codes) so callers can render the server-authored copy and log
  /// the comparison. Never throws.
  static Future<ForceUpdateDecision> evaluate() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;

      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );

      // Seed defaults so a first-ever launch (no cached Remote Config values
      // yet) still resolves: min 0 -> never blocks; a sensible message.
      await remoteConfig.setDefaults(const {
        minVersionCodeKey: defaultMinVersionCode,
        forceUpdateMessageKey: defaultForceUpdateMessage,
      });

      await remoteConfig.fetchAndActivate();

      final minVersion = remoteConfig.getInt(minVersionCodeKey);
      final forceMessage = remoteConfig.getString(forceUpdateMessageKey);

      final packageInfo = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(packageInfo.buildNumber) ?? 0;

      debugPrint(
        'Remote Config force-update: minVersion=$minVersion '
        'current=$currentCode message="$forceMessage"',
      );

      return ForceUpdateDecision(
        needsUpdate: shouldBlock(
          minVersionCode: minVersion,
          currentVersionCode: currentCode,
        ),
        message: forceMessage.isEmpty
            ? defaultForceUpdateMessage
            : forceMessage,
        minVersionCode: minVersion,
        currentVersionCode: currentCode,
      );
    } catch (e) {
      // Uninitialised Firebase, offline with no cache, a malformed Remote
      // Config value, a plugin gap on an unsupported platform — fail open.
      debugPrint('Remote Config check failed (failing open): $e');
      return ForceUpdateDecision.allow;
    }
  }
}

/// The outcome of a force-update check.
///
/// A top-level (rather than nested) class because Dart does not allow class
/// declarations inside another class body.
@immutable
class ForceUpdateDecision {
  /// Whether the installed build is below the Remote Config floor.
  final bool needsUpdate;

  /// The message to display when [needsUpdate] is true.
  final String message;

  /// The `min_required_version_code` Remote Config returned (0 when the key
  /// is unset or the fetch failed).
  final int minVersionCode;

  /// The installed build's `versionCode` (`0` if it could not be parsed).
  final int currentVersionCode;

  const ForceUpdateDecision({
    required this.needsUpdate,
    required this.message,
    required this.minVersionCode,
    required this.currentVersionCode,
  });

  /// A fail-open "continue normally" decision.
  static const ForceUpdateDecision allow = ForceUpdateDecision(
    needsUpdate: false,
    message: ForceUpdateService.defaultForceUpdateMessage,
    minVersionCode: ForceUpdateService.defaultMinVersionCode,
    currentVersionCode: 0,
  );
}