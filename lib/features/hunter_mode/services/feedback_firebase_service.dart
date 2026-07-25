import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

/// FeedbackFirebaseService provides data-layer operations for submitting
/// bug reports and feature suggestions to Cloud Firestore, along with
/// native email launching capabilities.
class FeedbackFirebaseService {
  static const String _bugReportsCollection = 'bug_reports';
  static const String _featureSuggestionsCollection = 'feature_suggestions';
  static const String _supportEmail = 'llewellynkearney@gmail.com';

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
  /// - [body]: Email body content
  ///
  /// Returns a [Future<bool>] indicating whether the URL was successfully launched.
  Future<bool> launchNativeEmail({
    required String subject,
    required String body,
  }) async {
    final encodedSubject = Uri.encodeComponent(subject);
    final encodedBody = Uri.encodeComponent(body);

    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {
        'subject': encodedSubject,
        'body': encodedBody,
      },
    );

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
