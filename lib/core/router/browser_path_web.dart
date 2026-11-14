/// Browser URL path probe (web build only).
///
/// Flutter's web engine derives `defaultRouteName` from the URL **hash**
/// (`browserHistory.currentPath`), because the app uses hash-based routing.
/// A path-based deep link such as `https://jag-spoor.co.za/admin_portal_v2`
/// therefore leaves the hash empty, and `WidgetsApp` falls back to its
/// hard-coded `initialRoute` — which is how a path deep link used to land on
/// the splash and get redirected to the old admin dashboard.
///
/// This probe reads the real `location.pathname` so the router can honour a
/// path deep link on the web build.
library;

import 'package:web/web.dart' as web;

/// The current browser path (e.g. `/admin_portal_v2`), or an empty string
/// when the path is the site root.
String currentBrowserPathImpl() {
  final path = web.window.location.pathname;
  if (path == '/' || path.isEmpty) return '';
  return path;
}
