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

  final FirebaseFirestore _firestore;
  final String? Function() _currentUserIdResolver;

  /// Creates a service. Defaults to the global [FirebaseFirestore.instance]
  /// + the live [FirebaseAuth] current user; tests may inject a
  /// `fake_cloud_firestore` instance via [firestore] and a stub uid resolver
  /// via [currentUserIdResolver] so the service runs without a Firebase app.
  FeedbackFirebaseService({
    FirebaseFirestore? firestore,
    String? Function()? currentUserIdResolver,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _currentUserIdResolver =
            currentUserIdResolver ?? _defaultUserIdResolver;

  static String? _defaultUserIdResolver() =>
      FirebaseAuth.instance.currentUser?.uid;

  /// Submits a bug report to the 'bug_reports' Firestore collection.
  ///
  /// Parameters:
  /// - [title]: The bug title/subject
  /// - [steps]: Steps to reproduce the bug
  /// - [severity]: Severity level (Low, Medium, Critical)
  /// - [screenshotUrls]: Optional list of Firebase Storage download URLs for
  ///   screenshot attachments the reporter added as visual proof. Omitted from
  ///   the document when empty so legacy reports are unaffected.
  ///
  /// Returns a [Future] that completes when the document is successfully written.
  Future<void> submitBugReport({
    required String title,
    required String steps,
    required String severity,
    List<String> screenshotUrls = const [],
  }) async {
    final document = <String, dynamic>{
      'title': title,
      'steps': steps,
      'severity': severity,
      'hunterId': _currentUserIdResolver(),
      'timestamp': FieldValue.serverTimestamp(),
      if (screenshotUrls.isNotEmpty) 'screenshotUrls': screenshotUrls,
    };

    await _firestore.collection(_bugReportsCollection).add(document);
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
    final document = <String, dynamic>{
      'title': title,
      'description': description,
      'benefits': benefits,
      'hunterId': _currentUserIdResolver(),
      'timestamp': FieldValue.serverTimestamp(),
    };

    await _firestore.collection(_featureSuggestionsCollection).add(document);
  }
}
