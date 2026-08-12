import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

/// FeedbackFirebaseService provides data-layer operations for submitting
/// bug reports and feature suggestions to Cloud Firestore, along with
/// native email launching capabilities.
class FeedbackFirebaseService {
  static const String _bugReportsCollection = 'bug_reports';
  static const String _featureSuggestionsCollection = 'feature_suggestions';
  static const String _supportEmail = 'support@jag-spoor.co.za';

  /// Submits a bug report to the 'bug_reports' Firestore collection.
  ///
  /// Parameters:
  /// - [title]: The bug title/subject
  /// - [steps]: Steps to reproduce the bug
  /// - [severity]: Severity level (Low, Medium, Critical)
  ///
  /// Returns a [Future] that completes when the document is successfully written.
  Future<void> submitBugReport({
    required String title,
    required String steps,
    required String severity,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final hunterId = user?.uid;

    final document = <String, dynamic>{
      'title': title,
      'steps': steps,
      'severity': severity,
      'hunterId': hunterId,
      'timestamp': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection(_bugReportsCollection)
        .add(document);
  }

  /// Submits a feature suggestion to the 'feature_suggestions' Firestore collection.
  ///
  /// Parameters:
  /// - [title]: The proposed feature title
  /// - [description]: Detailed description of the feature
  /// - [benefits]: Expected benefits to hunting teams
  ///
  /// Returns a [Future] that completes when the document is successfully written.
  Future<void> submitFeatureSuggestion({
    required String title,
    required String description,
    required String benefits,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final hunterId = user?.uid;

    final document = <String, dynamic>{
      'title': title,
      'description': description,
      'benefits': benefits,
      'hunterId': hunterId,
      'timestamp': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection(_featureSuggestionsCollection)
        .add(document);
  }

  /// Launches the native email application with a pre-filled email.
  ///
  /// Parameters:
  /// - [subject]: Email subject line
  /// - [body]: Email body content (plain text layout)
  ///
  /// Returns a [Future<bool>] indicating whether the URL was successfully launched.
  Future<bool> launchNativeEmail({
    required String subject,
    required String body,
  }) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {'subject': subject, 'body': body},
    );

    return launchUrl(emailUri, mode: LaunchMode.externalApplication);
  }

  /// Builds a structured tactical brief email body for bug reports.
  ///
  /// Parameters:
  /// - [title]: Bug title
  /// - [steps]: Steps to reproduce
  /// - [severity]: Severity level
  ///
  /// Returns a formatted [String] with geometric dividers and bullet indicators.
  static String buildBugReportEmailBody({
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
    buffer.writeln('  Title    : $title');
    buffer.writeln('  Severity : $severity');
    buffer.writeln('  Status   : OPEN');
    buffer.writeln('-----------------------------------------------');
    buffer.writeln();
    buffer.writeln('▶ REPRODUCTION SEQUENCE');
    buffer.writeln('-----------------------------------------------');

    final stepLines = steps.split('\n');
    for (final line in stepLines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        buffer.writeln('  • $trimmed');
      }
    }

    buffer.writeln();
    buffer.writeln('===============================================');
    buffer.writeln('  Submitted via Jagspoor Hunter Dashboard');
    buffer.writeln('  Timestamp: ${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('===============================================');

    return buffer.toString();
  }

  /// Builds a structured platform expansion brief email body for feature suggestions.
  ///
  /// Parameters:
  /// - [title]: Feature title
  /// - [description]: Detailed description
  /// - [benefits]: Expected benefits
  ///
  /// Returns a formatted [String] with geometric dividers and bullet indicators.
  static String buildFeatureSuggestionEmailBody({
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
    buffer.writeln('  Feature  : $title');
    buffer.writeln('  Priority : PENDING REVIEW');
    buffer.writeln('-----------------------------------------------');
    buffer.writeln();
    buffer.writeln('▶ FUNCTIONAL SPECIFICATION');
    buffer.writeln('-----------------------------------------------');

    final descLines = description.split('\n');
    for (final line in descLines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        buffer.writeln('  ▶ $trimmed');
      }
    }

    buffer.writeln();
    buffer.writeln('▶ TACTICAL BENEFITS ANALYSIS');
    buffer.writeln('-----------------------------------------------');

    final benefitLines = benefits.split('\n');
    for (final line in benefitLines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        buffer.writeln('  • $trimmed');
      }
    }

    buffer.writeln();
    buffer.writeln('===============================================');
    buffer.writeln('  Submitted via Jagspoor Hunter Dashboard');
    buffer.writeln('  Timestamp: ${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('===============================================');

    return buffer.toString();
  }
}
