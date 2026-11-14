/// Non-web stub for the browser-URL path probe.
///
/// Native builds (Android / iOS) are never deep-linked through a browser path,
/// so the probe reports an empty string. The stub keeps `browser_path.dart`'s
/// conditional import resolvable on every platform without pulling
/// `package:web` into the native build.
library;

/// Always empty off the web — there is no browser location.
String currentBrowserPathImpl() => '';
