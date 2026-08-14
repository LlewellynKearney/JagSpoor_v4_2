import 'dart:io' show Platform;

import 'package:url_launcher/url_launcher.dart';

/// Automated support-email generator for the JagSpoor bug-report and
/// feature-suggestion submission flows.
///
/// Builds a structured `mailto:support@jag-spoor.co.za` target whose subject
/// and body are escaped with [Uri.encodeComponent] so multi-line bodies and
/// special characters (`&`, `=`, `+`, newlines, quotes) survive the handoff to
/// the device's native mail client without line-wrap breaks or parameter
/// injection. The body template injects the reporter's User ID, the free-text
/// description, and a System Context block (platform, OS version, locale,
/// submission timestamp) so the support team receives a self-contained
/// diagnostic brief on every submission.
///
/// The class is intentionally dependency-light (pure `dart:io Platform` +
/// `url_launcher` only — no extra platform plugins) so the body/URI builders
/// are fully unit-testable and stable on the CI Flutter 3.29.1 pin.
class SupportEmailComposer {
  SupportEmailComposer._();

  /// Canonical JagSpoor support inbox targeted by every automated email.
  static const String supportEmail = 'support@jag-spoor.co.za';

  /// Build a `mailto:` URI for a bug report.
  ///
  /// [userId], [title], [steps], [severity] are injected into the body.
  /// Returns a `Uri` whose `toString()` is a ready-to-launch mailto link with
  /// every component percent-encoded.
  static Uri buildBugReportMailtoUri({
    required String userId,
    required String title,
    required String steps,
    required String severity,
  }) {
    final subject = '[Bug Report] ${_safe(title)}';
    final body = buildBugReportEmailBody(
      userId: userId,
      title: title,
      steps: steps,
      severity: severity,
    );
    return _mailtoUri(subject, body);
  }

  /// Build a `mailto:` URI for a feature suggestion.
  static Uri buildFeatureSuggestionMailtoUri({
    required String userId,
    required String title,
    required String description,
    required String benefits,
  }) {
    final subject = '[Feature Suggestion] ${_safe(title)}';
    final body = buildFeatureSuggestionEmailBody(
      userId: userId,
      title: title,
      description: description,
      benefits: benefits,
    );
    return _mailtoUri(subject, body);
  }

  /// Launch the native email client with a pre-built [mailtoUri].
  ///
  /// Returns whether the OS successfully handed off to a mail client. The
  /// caller should treat `false` as "no mail app configured" and surface a
  /// fallback message rather than crashing.
  static Future<bool> launch(Uri mailtoUri) =>
      launchUrl(mailtoUri, mode: LaunchMode.externalApplication);

  /// Structured tactical brief email body for bug reports.
  ///
  /// Pure function (no I/O) — safe to unit-test. Injects the reporter's User
  /// ID, the reproduction steps, the severity, and a System Context block.
  static String buildBugReportEmailBody({
    required String userId,
    required String title,
    required String steps,
    required String severity,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('===============================================');
    buffer.writeln('     JAGSPOOR TACTICAL SUPPORT BRIEF');
    buffer.writeln('===============================================');
    buffer.writeln();
    buffer.writeln('▶ INCIDENT REPORT');
    buffer.writeln('-----------------------------------------------');
    buffer.writeln('  Title      : ${_safe(title)}');
    buffer.writeln('  Severity   : ${_safe(severity)}');
    buffer.writeln('  Status     : OPEN');
    buffer.writeln('  User ID    : ${_safe(userId)}');
    buffer.writeln('-----------------------------------------------');
    buffer.writeln();
    buffer.writeln('▶ REPRODUCTION SEQUENCE');
    buffer.writeln('-----------------------------------------------');
    _writeBulleted(buffer, steps, prefix: '•');
    buffer.writeln();
    buffer.writeln('▶ SYSTEM CONTEXT');
    buffer.writeln('-----------------------------------------------');
    buffer.write(systemContextBlock());
    buffer.writeln('-----------------------------------------------');
    buffer.writeln();
    buffer.writeln('===============================================');
    buffer.writeln('  Submitted via JagSpoor Hunter Dashboard');
    buffer.writeln('  Timestamp: ${_utcTimestamp()}');
    buffer.writeln('===============================================');
    return buffer.toString();
  }

  /// Structured platform-expansion brief email body for feature suggestions.
  ///
  /// Pure function (no I/O) — safe to unit-test. Injects the reporter's User
  /// ID, the feature description, the expected benefits, and a System Context
  /// block.
  static String buildFeatureSuggestionEmailBody({
    required String userId,
    required String title,
    required String description,
    required String benefits,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('===============================================');
    buffer.writeln('     JAGSPOOR PLATFORM EXPANSION BRIEF');
    buffer.writeln('===============================================');
    buffer.writeln();
    buffer.writeln('▶ PROPOSAL DETAILS');
    buffer.writeln('-----------------------------------------------');
    buffer.writeln('  Feature    : ${_safe(title)}');
    buffer.writeln('  Priority   : PENDING REVIEW');
    buffer.writeln('  User ID    : ${_safe(userId)}');
    buffer.writeln('-----------------------------------------------');
    buffer.writeln();
    buffer.writeln('▶ FUNCTIONAL SPECIFICATION');
    buffer.writeln('-----------------------------------------------');
    _writeBulleted(buffer, description, prefix: '▶');
    buffer.writeln();
    buffer.writeln('▶ TACTICAL BENEFITS ANALYSIS');
    buffer.writeln('-----------------------------------------------');
    _writeBulleted(buffer, benefits, prefix: '•');
    buffer.writeln();
    buffer.writeln('▶ SYSTEM CONTEXT');
    buffer.writeln('-----------------------------------------------');
    buffer.write(systemContextBlock());
    buffer.writeln('-----------------------------------------------');
    buffer.writeln();
    buffer.writeln('===============================================');
    buffer.writeln('  Submitted via JagSpoor Hunter Dashboard');
    buffer.writeln('  Timestamp: ${_utcTimestamp()}');
    buffer.writeln('===============================================');
    return buffer.toString();
  }

  /// Gather a best-effort System Context block for the support team.
  ///
  /// Pulls platform / OS version / locale from pure `dart:io` (no platform
  /// plugins), so it works everywhere and stays unit-testable on the desktop
  /// test runner. Each field is on its own line for easy triage.
  static String systemContextBlock() {
    String os;
    String osVersion;
    String locale;
    String processorCount;
    // Platform is available on native (Android/iOS/desktop) builds; on web it
    // throws, so guard for safety.
    try {
      os = Platform.operatingSystem;
      osVersion = Platform.operatingSystemVersion;
      locale = Platform.localeName;
      processorCount = Platform.numberOfProcessors.toString();
    } catch (_) {
      os = 'web';
      osVersion = 'unknown';
      locale = 'unknown';
      processorCount = 'unknown';
    }

    final buffer = StringBuffer()
      ..writeln('  Platform      : $os')
      ..writeln('  OS Version    : $osVersion')
      ..writeln('  Locale        : $locale')
      ..writeln('  CPU Cores     : $processorCount')
      ..writeln('  App Package   : com.jagspoor.app')
      ..writeln('  Channel       : hunter_dashboard');
    return buffer.toString();
  }

  /// Compose the final `mailto:` [Uri] with explicit percent-encoding.
  ///
  /// Uses [Uri.encodeComponent] (not `Uri.queryParameters`) so spaces become
  /// `%20` (not `+`) and newlines become `%0D%0A`, which is the encoding every
  /// major mobile mail client decodes correctly — preventing the line-wrap
  /// breaks and literal `+` artifacts that the `Uri.queryParameters` path
  /// produces in some clients.
  static Uri _mailtoUri(String subject, String body) {
    final encodedSubject = Uri.encodeComponent(subject);
    final encodedBody = Uri.encodeComponent(body);
    return Uri.parse(
      'mailto:$supportEmail?subject=$encodedSubject&body=$encodedBody',
    );
  }

  static String _safe(String? value) =>
      (value == null || value.trim().isEmpty) ? 'N/A' : value.trim();

  static void _writeBulleted(StringBuffer buffer, String text,
      {required String prefix}) {
    final lines = text.split('\n');
    var wroteAny = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        buffer.writeln('  $prefix $trimmed');
        wroteAny = true;
      }
    }
    if (!wroteAny) {
      buffer.writeln('  $prefix N/A');
    }
  }

  static String _utcTimestamp() => DateTime.now().toUtc().toIso8601String();
}
