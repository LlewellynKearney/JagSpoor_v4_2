/// Browser-URL path probe.
///
/// Flutter's web engine derives its initial route from the URL **hash**
/// (`browserHistory.currentPath`), because this app uses hash-based routing.
/// A *path*-based deep link — `https://jag-spoor.co.za/admin_portal_v2` — has
/// an empty hash, so `WidgetsApp` falls back to its hard-coded `initialRoute`
/// (`/splash`) and the deep link is lost. This façade lets the router read the
/// real `location.pathname` so a path deep link can be honoured.
///
/// The conditional import keeps `package:web` out of the native build,
/// mirroring `lib/core/services/web_barcode_service.dart` and
/// `lib/features/billing/payfast_form.dart`.
library;

import 'browser_path_stub.dart'
    if (dart.library.js_interop) 'browser_path_web.dart';

/// The browser's current URL path (e.g. `/admin_portal_v2`).
///
/// Returns an empty string on native builds and when the path is the site
/// root, so callers can treat "empty" as "no path deep link".
String currentBrowserPath() => currentBrowserPathImpl();
