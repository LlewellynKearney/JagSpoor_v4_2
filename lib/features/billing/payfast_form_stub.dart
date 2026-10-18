/// Non-web stub for the PayFast form submitter.
///
/// The native (Android/iOS) build never uses the PayFast web checkout — the
/// Play Billing flow is used instead — so this stub simply reports that no
/// HTML form can be submitted. It keeps `payfast_form.dart`'s conditional
/// import resolvable on every platform without pulling `package:web` into the
/// native build.
library;

/// Always `false` off the web — no DOM to submit a form into.
bool submitPayFastFormImpl(String processUrl, Map<String, String> fields) =>
    false;

/// Always `false` off the web.
const bool canSubmitHtmlFormImpl = false;
