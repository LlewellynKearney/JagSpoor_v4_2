import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// FeedbackFirebaseService provides the Firestore data-layer operations for
/// submitting bug reports and feature suggestions.
///
/// The automated support-email generation (mailto URI building + native mail
/// client handoff) now lives in [SupportEmailComposer]
/// (`lib/features/support/services/support_email_composer.dart`), which uses
/// `Uri.encodeComponent`-safe escaping and injects User ID + System Context.
class FeedbackFirebaseService {
  static const String _bugReportsCollection = 'bug_reports';
  static const String _featureSuggestionsCollection = 'feature_suggestions';

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
}
