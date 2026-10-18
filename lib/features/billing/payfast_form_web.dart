/// Web implementation of the PayFast form submitter.
///
/// Injects a hidden `<form>` carrying the signed PayFast fields and submits it,
/// navigating the current tab to PayFast's hosted checkout. This is the
/// standard "server-signed form post" redirect and keeps the merchant key out
/// of the page (it is only present in the signed payload the server built).
library;

import 'package:web/web.dart' as web;

/// Posts [fields] to [processUrl] via a hidden auto-submitted form.
///
/// Returns `true` once the form has been submitted.
bool submitPayFastFormImpl(String processUrl, Map<String, String> fields) {
  final form = web.document.createElement('form') as web.HTMLFormElement;
  form.method = 'POST';
  form.action = processUrl;
  form.target = '_self';
  form.style.display = 'none';

  fields.forEach((key, value) {
    final input = web.document.createElement('input') as web.HTMLInputElement;
    input.type = 'hidden';
    input.name = key;
    input.value = value;
    form.appendChild(input);
  });

  web.document.body?.appendChild(form);
  form.submit();
  return true;
}

/// Always `true` on the web.
const bool canSubmitHtmlFormImpl = true;
