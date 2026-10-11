import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../admin/services/usage_analytics_service.dart';
import '../models/review_config.dart';

/// Drives the JagSpoor review prompt: reads the `admin_config/review_config`
/// control plane, tracks the device launch count + last prompt time locally,
/// and decides when to surface the review modal.
///
/// Gating (all must hold for [shouldPrompt] to return `true`):
///  1. `enabled` is true in `admin_config/review_config`;
///  2. the device has launched the app at least `min_launches` times;
///  3. at least `cooldown_days` have passed since the last prompt.
///
/// The launch count + last-prompt timestamp live in [SharedPreferences] (a
/// per-device concern, not per-account) so the cadence survives restarts.
/// Every Firestore / prefs access is failure-tolerant: an uninitialised
/// Firebase app, offline device, or missing config document degrades to the
/// documented defaults instead of throwing.
class ReviewService {
  ReviewService._();

  static final ReviewService instance = ReviewService._();

  static const String _launchCountKey = 'review_launch_count';
  static const String _lastPromptKey = 'review_last_prompt_at';

  /// Event name recorded to `feature_usage_events` when the modal is shown.
  static const String promptShownEvent = 'review_prompt_shown';

  /// Test seams (mirror `ReferralRepository` / `UsageAnalyticsService`):
  /// inject a Firestore instance so the config + event contract is unit
  /// testable without a live Firebase app.
  @visibleForTesting
  FirebaseFirestore? firestoreForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    instance.firestoreForTesting = null;
  }

  FirebaseFirestore get _db =>
      firestoreForTesting ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _configDoc => _db
      .collection(ReviewConfig.collection)
      .doc(ReviewConfig.documentId);

  /// Reads `admin_config/review_config`, falling back to [ReviewConfig.defaults]
  /// when the document is absent / unreadable (offline, cold-launch, or an
  /// uninitialised Firebase app).
  Future<ReviewConfig> loadConfig() async {
    try {
      final snap = await _configDoc.get();
      return ReviewConfig.fromMap(snap.data());
    } catch (e) {
      debugPrint('ReviewService.loadConfig: $e');
      return ReviewConfig.defaults;
    }
  }

  /// Ensures `admin_config/review_config` exists: reads the document and, when
  /// it is absent, writes the canonical defaults
  /// (`enabled:true`, `min_launches:3`, `cooldown_days:30`, the Facebook /
  /// Play Store URLs, and the hunter/outfitter prompt copy).
  ///
  /// Best-effort: `admin_config` writes are admin-only per `firestore.rules`,
  /// so a non-admin call is denied and simply logged — the feature then runs
  /// on [ReviewConfig.defaults]. Idempotent: an existing document is left
  /// untouched.
  Future<void> ensureConfig() async {
    try {
      final snap = await _configDoc.get();
      if (snap.exists) return;
      await _configDoc.set({
        ...ReviewConfig.defaults.toMap(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('ReviewService.ensureConfig: $e');
    }
  }

  /// The persisted device launch count (0 when unset / unreadable).
  Future<int> launchCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_launchCountKey) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Increments the device launch count. Call once per cold start.
  Future<void> recordLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = (prefs.getInt(_launchCountKey) ?? 0) + 1;
      await prefs.setInt(_launchCountKey, next);
    } catch (e) {
      debugPrint('ReviewService.recordLaunch: $e');
    }
  }

  /// The timestamp of the last prompt (null when never prompted).
  Future<DateTime?> lastPromptAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final millis = prefs.getInt(_lastPromptKey);
      return millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (_) {
      return null;
    }
  }

  /// Whether the review modal should be shown for this device right now.
  /// See the class doc for the gating rules. Never throws.
  Future<bool> shouldPrompt() async {
    try {
      final config = await loadConfig();
      if (!config.enabled) return false;

      final launches = await launchCount();
      if (launches < config.minLaunches) return false;

      final last = await lastPromptAt();
      if (last != null && config.cooldownDays > 0) {
        final elapsed = DateTime.now().difference(last);
        if (elapsed.inDays < config.cooldownDays) return false;
      }
      return true;
    } catch (e) {
      debugPrint('ReviewService.shouldPrompt: $e');
      return false;
    }
  }

  /// Records that the modal was shown (starts the cooldown window) and logs
  /// the [promptShownEvent] to `feature_usage_events`.
  Future<void> markPrompted() async {
    await logPromptShown();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _lastPromptKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('ReviewService.markPrompted: $e');
    }
  }

  /// Appends the review-prompt-shown telemetry to `feature_usage_events`,
  /// mirroring the [UsageAnalyticsService] event shape (`event` / `type` /
  /// `role` / `userId` / `timestamp`). Fire-and-forget: failures are logged,
  /// never surfaced.
  Future<void> logPromptShown() async {
    try {
      String? uid;
      try {
        uid = FirebaseAuth.instance.currentUser?.uid;
      } catch (_) {
        uid = null;
      }
      await _db.collection(UsageAnalyticsService.eventsCollection).add({
        'event': promptShownEvent,
        'type': 'feature_usage',
        'role': 'hunter',
        'userId': uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('ReviewService.logPromptShown: $e');
    }
  }
}
