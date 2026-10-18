/// Conditional PayFast form submitter.
///
/// The web build posts the signed PayFast form to the hosted checkout by
/// injecting a hidden `<form>` and calling `submit()`. That requires
/// `package:web` (DOM access), which is only available on the web — importing
/// it on Android/iOS would break the native build. The conditional import
/// below selects the real implementation on the web and a no-op stub
/// elsewhere, mirroring `lib/services/tflite/tflite_helper.dart`.
///
/// `dart.library.js_interop` is the discriminator used by the dart2js web
/// compiler.
library;

import 'payfast_form_stub.dart'
    if (dart.library.js_interop) 'payfast_form_web.dart';

/// Posts [fields] to [processUrl] in the current browser tab (auto-submit).
///
/// On the web this injects a hidden form and submits it, navigating the tab to
/// PayFast's hosted checkout. On a non-web platform it returns `false` (the
/// caller falls back to opening the URL via `url_launcher`).
bool submitPayFastForm(String processUrl, Map<String, String> fields) =>
    submitPayFastFormImpl(processUrl, fields);

/// Whether the current platform can submit an HTML form (web only).
bool get canSubmitHtmlForm => canSubmitHtmlFormImpl;
