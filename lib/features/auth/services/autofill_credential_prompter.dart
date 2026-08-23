import 'package:flutter/services.dart';

/// Thin, testable wrapper around [TextInput.finishAutofillContext].
///
/// When a login / registration form wrapped in an `AutofillGroup` completes
/// successfully, calling `TextInput.finishAutofillContext()` commits the
/// autofill context and triggers the device's native credential manager
/// (Android Credential Manager / iOS Keychain) to prompt the user to save the
/// username + password they just authenticated with.
///
/// The platform channel may be unavailable in unit/widget tests or on
/// unsupported platforms; failures are swallowed so the auth flow is never
/// blocked by the credential-save prompt.
class AutofillCredentialPrompter {
  AutofillCredentialPrompter._();

  /// The platform-channel method this helper invokes. Exposed for tests.
  static const String finishMethod = 'TextInput.finishAutofillContext';

  /// Commits the current autofill context, prompting the native credential
  /// manager to offer saving the credentials. Best-effort: never throws.
  static void promptSaveCredentials() {
    try {
      TextInput.finishAutofillContext();
    } catch (_) {
      // Platform channel unavailable (tests, unsupported platforms) — the
      // credential-save prompt is a convenience, not a hard requirement.
    }
  }
}
