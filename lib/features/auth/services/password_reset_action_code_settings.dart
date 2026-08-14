import 'package:firebase_auth/firebase_auth.dart';

/// Centralized builder for the [ActionCodeSettings] applied to every Firebase
/// password-reset email sent from the app.
///
/// Applying explicit [ActionCodeSettings] (instead of the bare
/// `sendPasswordResetEmail(email:)` call) is what eliminates the email
/// delivery delay and token-expiration problems: it tells Firebase to handle
/// the reset code **in the app** (`handleCodeInApp: true`) via a deep link,
/// pin the Android package so the link opens the installed app (and offers to
/// install it), and pin the iOS bundle so the universal link resolves on
/// Apple devices. Without these settings Firebase falls back to a generic
/// web-only flow that is slower to dispatch and more prone to the link
/// expiring before the user taps it.
///
/// The settings are constructed in one place so both call sites (the hunter
/// self-service "Forgot Password?" dialog and the admin account-provisioning
/// flow) share identical, consistent deep-link behaviour.
///
/// **Deploy requirement**: the [resetDeepLinkUrl] domain MUST be listed in the
/// Firebase Console ‚Üí Authentication ‚Üí Settings ‚Üí Authorized domains. If a
/// Firebase Dynamic Links domain (`*.page.link`) is used, it must also be
/// provisioned under Hosting/Dynamic Links. Until the domain is authorized the
/// reset call will return `auth/invalid-continue-uri`; the caller surfaces
/// that error in-UI.
class PasswordResetActionCodeSettings {
  PasswordResetActionCodeSettings._();

  /// Deep-link / continue URL the user is sent to after completing the reset.
  /// Must be authorized in the Firebase Console (Authorized domains).
  static const String resetDeepLinkUrl =
      'https://jagspoor.page.link/reset-password';

  /// Active Android application id (from `android/app/build.gradle.kts`).
  static const String androidPackageName = 'com.example.jagspoor';

  /// Active iOS bundle id (from `ios/Runner.xcodeproj/project.pbxproj`).
  static const String iOSBundleId = 'com.example.jagspoorV42';

  /// Builds the canonical [ActionCodeSettings] for a JagSpoor password reset.
  ///
  /// All fields are driven by the constants above so the configuration lives
  /// in exactly one place. [handleCodeInApp] is `true` so Firebase delivers
  /// the action code as an in-app deep link (the open-app fast path) rather
  /// than a generic web redirect. [androidInstallApp] is `true` so the Play
  /// Store is offered when the app is not installed. [androidMinimumVersion]
  /// is set so an out-of-date install is sent to the Play Store to upgrade.
  static ActionCodeSettings build() {
    return ActionCodeSettings(
      url: resetDeepLinkUrl,
      handleCodeInApp: true,
      androidPackageName: androidPackageName,
      androidInstallApp: true,
      androidMinimumVersion: '1', // lowest installed build that handles reset links
      iOSBundleId: iOSBundleId,
    );
  }
}
