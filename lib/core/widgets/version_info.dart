import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The single source of truth for the app-version metadata shown on the
/// profile / settings screens.
///
/// The values are read dynamically from the platform via `package_info_plus`
/// (`PackageInfo.fromPlatform()`), so the displayed version always reflects
/// the actual installed build:
///   - Android: `versionCode` / `versionName` from the bundle manifest
///   - iOS / desktop: the pubspec `version` / build number
///
/// On platforms where the metadata is unavailable (e.g. the widget-test /
/// headless host) the widget degrades gracefully to a documented static
/// fallback so it never throws or crashes the profile screen.
class VersionInfo {
  /// Static fallback used only when `package_info_plus` cannot resolve the
  /// live bundle metadata (billing/test host). Mirrors the current Android
  /// Play Console build (see `android/app/build.gradle.kts`).
  static const String fallbackVersionCode = '4';
  static const String fallbackVersionName = '4.3';

  /// Asynchronously resolves the installed app version + build number.
  ///
  /// Returns a map of `{name, code, display}`. `name` is the human-readable
  /// version (e.g. "4.3"), `code` is the build/version code (e.g. "4"),
  /// and `display` is the combined `"4.3 (build 4)"` label used by the
  /// widgets. Never throws -- any platform failure falls back to the
  /// documented [fallbackVersionName] / [fallbackVersionCode].
  static Future<Map<String, String>> resolve() async {
    try {
      final info = await PackageInfo.fromPlatform();
      var name = info.version.trim();
      var code = info.buildNumber.trim();
      if (name.isEmpty) name = fallbackVersionName;
      if (code.isEmpty) code = fallbackVersionCode;
      return {
        'name': name,
        'code': code,
        'display': '$name (build $code)',
      };
    } catch (_) {
      return {
        'name': fallbackVersionName,
        'code': fallbackVersionCode,
        'display': '$fallbackVersionName (build $fallbackVersionCode)',
      };
    }
  }
}

/// A compact, theme-aware version caption ("v4.3 · build 4") rendered in
/// the footer area of the profile / settings screens.
///
/// Fetches the version dynamically from `package_info_plus` on first mount
/// and re-renders once the data resolves. While loading (and on unsupported
/// hosts) it falls back to [VersionInfo.fallbackVersionName] /
/// [VersionInfo.fallbackVersionCode] so the line is never blank.
class VersionInfoCaption extends StatefulWidget {
  const VersionInfoCaption({super.key});

  @override
  State<VersionInfoCaption> createState() => _VersionInfoCaptionState();
}

class _VersionInfoCaptionState extends State<VersionInfoCaption> {
  String _label = '';

  @override
  void initState() {
    super.initState();
    VersionInfo.resolve().then((map) {
      if (mounted) {
        _label = map['display'] ?? '';
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final captionColor = (isDark ? const Color(0xFFB0B0B0) : const Color(0xFF5D4037))
        .withValues(alpha: 0.7);
    final label = _label.isEmpty
        ? 'v${VersionInfo.fallbackVersionName} · build ${VersionInfo.fallbackVersionCode}'
        : 'v$_label';
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: captionColor,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}