import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The app mode a bug report / feature suggestion originates from.
///
/// Hunter Mode and Outfitter Mode share the same submission pipeline
/// (Firestore collections + support-email composer); every document carries
/// this mode tag so the support/admin triage can see which portal the
/// reporter was using.
abstract final class FeedbackMode {
  /// Submission originated from the Hunter portal (default).
  static const String hunter = 'Hunter';

  /// Submission originated from the Outfitter portal.
  static const String outfitter = 'Outfitter';
}

/// FeedbackFirebaseService provides the Firestore data-layer operations for
/// submitting bug reports and feature suggestions.
///
/// Shared by Hunter Mode and Outfitter Mode: both portals write to the same
/// `bug_reports` / `feature_suggestions` collections with the submitter's
/// uid (`hunterId` key preserved for backward compatibility + the existing
/// security rules), a [FeedbackMode] tag, and a best-effort device-platform
/// marker, so an outfitter submission records the user ID, the originating
/// mode, device metadata, and the feedback content to the same backend
/// target the Hunter portal uses.
///
/// The automated support-email generation (mailto URI building + native mail
/// client handoff) now lives in `SupportEmailComposer`
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
  /// - [mode]: The app mode the report originates from ([FeedbackMode.hunter]
  ///   by default; pass [FeedbackMode.outfitter] from the Outfitter portal).
  ///
  /// Returns a [Future] that completes when the document is successfully written.
  Future<void> submitBugReport({
    required String title,
    required String steps,
    required String severity,
    List<String> screenshotUrls = const [],
    String mode = FeedbackMode.hunter,
  }) async {
    final document = <String, dynamic>{
      'title': title,
      'steps': steps,
      'severity': severity,
      'hunterId': _currentUserIdResolver(),
      'mode': mode,
      'devicePlatform': devicePlatform(),
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
  /// - [mode]: The app mode the suggestion originates from
  ///   ([FeedbackMode.hunter] by default; pass [FeedbackMode.outfitter] from
  ///   the Outfitter portal).
  ///
  /// Returns a [Future] that completes when the document is successfully written.
  Future<void> submitFeatureSuggestion({
    required String title,
    required String description,
    required String benefits,
    String mode = FeedbackMode.hunter,
  }) async {
    final document = <String, dynamic>{
      'title': title,
      'description': description,
      'benefits': benefits,
      'hunterId': _currentUserIdResolver(),
      'mode': mode,
      'devicePlatform': devicePlatform(),
      'timestamp': FieldValue.serverTimestamp(),
    };

    await _firestore.collection(_featureSuggestionsCollection).add(document);
  }

  /// Best-effort device-platform marker (device metadata) stamped on every
  /// feedback document. Pure `dart:io Platform` (guarded for web, where
  /// `Platform` throws) so it is unit-testable on the desktop test runner.
  static String devicePlatform() {
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return 'web';
    }
  }
}
