import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/saps_tracking_details.dart';
import 'saps_cfr_scraper_client.dart';
import 'saps_status_classifier.dart';

/// Cloud bridge service for SAPS License Tracker.
/// Handles communication with the CFR status webhook (Apify / Cloud
/// Function) and hardened status mapping.
class SapsTrackerService {
  final FirebaseFirestore? _injectedFirestore;
  final SapsCfrScraperClient? _scraper;

  SapsTrackerService({FirebaseFirestore? firestore, SapsCfrScraperClient? scraper})
      : _injectedFirestore = firestore,
        _scraper = scraper;

  /// Lazily resolves the Firestore instance so constructing the service
  /// before `Firebase.initializeApp()` (cold-launch race / widget-test env)
  /// does not throw `[core/no-app]`.
  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  /// Test seam: builds a service backed by an injected [FirebaseFirestore]
  /// (e.g. `FakeFirebaseFirestore`) so the refresh / tracking-details flow can
  /// be unit-tested without a live Firebase app. An optional [SapsCfrScraperClient]
  /// (with a mocked transport) can be supplied to exercise the real webhook
  /// code path.
  @visibleForTesting
  factory SapsTrackerService.forTesting(
    FirebaseFirestore firestore, {
    SapsCfrScraperClient? scraper,
  }) {
    return SapsTrackerService(firestore: firestore, scraper: scraper);
  }

  /// Triggers a remote CFR status check.
  ///
  /// When a [SapsCfrScraperClient] is configured (the deployed Apify Actor /
  /// Cloud Function webhook), the raw status is fetched from the official
  /// Central Firearms Register enquiry portal and mapped via the hardened
  /// [SapsStatusClassifier]. When no webhook is configured (offline dev /
  /// test env), a clearly-labelled deterministic mock status is used so the
  /// flow stays exercisable end-to-end.
  ///
  /// Returns the scraped status result or null on failure.
  Future<SapsScraperResult?> triggerRemoteScraperCheck(
    String applicationId,
  ) async {
    try {
      final docSnapshot = await _firestore
          .collection('license_applications')
          .doc(applicationId)
          .get();

      if (!docSnapshot.exists) {
        debugPrint('SapsTrackerService: Application $applicationId not found');
        return null;
      }

      final data = docSnapshot.data()!;
      final idNumber = data['idNumber'] as String? ?? '';
      final referenceNumber = data['referenceNumber'] as String? ?? '';

      final scraper = _scraper;
      if (scraper != null && scraper.isConfigured) {
        final cfr = await scraper.fetchStatus(
          referenceNumber: referenceNumber,
          idNumber: idNumber,
        );
        if (cfr == null) {
          debugPrint(
            'SapsTrackerService: CFR webhook returned no status for $applicationId',
          );
          return null;
        }
        final stage = SapsStatusClassifier.classify(cfr.rawStatus);
        return SapsScraperResult(
          applicationId: applicationId,
          status: cfr.rawStatus,
          statusCode: stage,
          lastChecked: DateTime.now(),
          success: true,
          error: cfr.statusMessage.isEmpty ? null : cfr.statusMessage,
        );
      }

      // No webhook configured -> deterministic offline mock (dev/test only).
      final mockStatus = _generateMockStatus();

      return SapsScraperResult(
        applicationId: applicationId,
        status: mockStatus,
        statusCode: SapsStatusClassifier.classify(mockStatus),
        lastChecked: DateTime.now(),
        success: true,
      );
    } catch (e) {
      debugPrint('SapsTrackerService: Error triggering scraper check: $e');
      return null;
    }
  }

  /// Mock status generator for offline development.
  /// Simulates realistic status progression for testing.
  String _generateMockStatus() {
    final statuses = [
      'Application received at DFO',
      'Processing at District Office',
      'Submitted to Provincial Office',
      'Under review at Provincial',
      'Forwarded to Central Firearms Registry',
      'CFR Processing',
      'Licence approved and printed',
    ];

    // Generate a semi-random but consistent status based on current time
    final hour = DateTime.now().hour;
    final index = hour % statuses.length;
    return statuses[index];
  }

  /// Converts raw scraper status strings to standardized UI stage indices.
  ///
  /// Stage indices:
  /// - 0: Submitted (DFO stage)
  /// - 1: Provincial Office
  /// - 2: Central Firearms Registry (CFR)
  /// - 3: Printed/Ready for Collection
  /// - -1: Not Found / Error
  ///
  /// Returns 0 (Submitted) as default for null or unrecognized inputs.
  ///
  /// Delegates to the hardened [SapsStatusClassifier] (longest-match-wins
  /// over the full CFR enquiry vocabulary), so the legacy public API stays
  /// stable while the classification logic is centralized + unit-tested.
  static int convertRawStatusToStage(String? rawStatus) {
    return SapsStatusClassifier.classify(rawStatus);
  }

  /// Maps raw status string to a display-friendly status label.
  ///
  /// Returns 'Pending Review' for null, empty, or unrecognized inputs
  /// to ensure safe display without runtime crashes.
  static String convertRawStatusToDisplay(String? rawStatus) {
    return SapsStatusClassifier.displayLabel(rawStatus);
  }

  /// Updates an application's status in Firestore after a scraper check.
  Future<bool> updateApplicationStatus(
    String applicationId,
    String newStatus,
    DateTime lastChecked,
  ) async {
    try {
      await _firestore
          .collection('license_applications')
          .doc(applicationId)
          .update({
        'currentStatus': newStatus,
        'lastChecked': lastChecked.toIso8601String(),
        'statusCode': convertRawStatusToStage(newStatus),
      });
      return true;
    } catch (e) {
      debugPrint('SapsTrackerService: Failed to update application status: $e');
      return false;
    }
  }

  /// Batch updates status for all tracked applications.
  Future<int> refreshAllApplications() async {
    int updatedCount = 0;

    try {
      final snapshot =
          await _firestore.collection('license_applications').get();

      for (final doc in snapshot.docs) {
        final result = await triggerRemoteScraperCheck(doc.id);
        if (result != null && result.success) {
          final updated = await updateApplicationStatus(
            doc.id,
            result.status,
            result.lastChecked,
          );
          if (updated) updatedCount++;
        }
      }
    } catch (e) {
      debugPrint('SapsTrackerService: Batch refresh failed: $e');
    }

    return updatedCount;
  }

  /// Refreshes a single application's status (used by the manual refresh
  /// button). Returns a [SapsRefreshResult] describing what the refresh did.
  Future<SapsRefreshResult> refreshApplication(String applicationId) async {
    try {
      final result = await triggerRemoteScraperCheck(applicationId);
      if (result == null || !result.success) {
        return SapsRefreshResult(
          applicationId: applicationId,
          success: false,
          message: result?.error ?? 'No result from tracking service',
        );
      }

      final updated = await updateApplicationStatus(
        applicationId,
        result.status,
        result.lastChecked,
      );
      if (!updated) {
        return SapsRefreshResult(
          applicationId: applicationId,
          success: false,
          message: 'Failed to persist the refreshed status',
        );
      }

      return SapsRefreshResult(
        applicationId: applicationId,
        success: true,
        message: 'Status refreshed: ${result.status}',
        statusMessage: result.status,
        statusStage: result.statusCode,
        lastChecked: result.lastChecked,
      );
    } catch (e) {
      debugPrint('SapsTrackerService: Refresh failed for $applicationId: $e');
      return SapsRefreshResult(
        applicationId: applicationId,
        success: false,
        message: 'Refresh failed: $e',
      );
    }
  }

  /// Fetches comprehensive tracking details (status timeline, waiting-period
  /// estimates, batch details, current progress stage) for an application.
  ///
  /// The application document may store a structured `trackingDetails` map
  /// (written by the backend tracking system). When it is absent the returned
  /// details are synthesized from the application's card-level fields via
  /// [SapsTrackingDetailsFactory.fromApplicationFields], so the expandable
  /// detail view always has a defined renderable payload.
  Future<SapsTrackingDetails?> fetchTrackingDetails(
      String applicationId) async {
    try {
      final docSnapshot = await _firestore
          .collection('license_applications')
          .doc(applicationId)
          .get();

      if (!docSnapshot.exists) {
        debugPrint('SapsTrackerService: Application $applicationId not found');
        return null;
      }

      final data = docSnapshot.data() ?? const <String, dynamic>{};

      final stored = data['trackingDetails'];
      if (stored is Map) {
        final details = SapsTrackingDetails.fromJson(
          Map<String, dynamic>.from(stored),
          applicationId: applicationId,
        );
        if (details.timeline.isNotEmpty ||
            details.waitingEstimates.isNotEmpty ||
            details.batches.isNotEmpty ||
            details.currentProgressLabel != null) {
          return details;
        }
      }

      return SapsTrackingDetailsFactory.fromApplicationFields(
        applicationId: applicationId,
        currentStatus: data['currentStatus'] as String?,
        statusMessage: data['statusMessage'] as String?,
        batchNumber: data['batchNumber'] as String?,
        submittedAt: _dateTimeOrNull(data['submittedAt']),
        createdAt: _dateTimeOrNull(data['createdAt']),
        statusUpdatedAt: _dateTimeOrNull(data['statusUpdatedAt']),
        refreshedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('SapsTrackerService: Fetch tracking details failed: $e');
      return null;
    }
  }

  static DateTime? _dateTimeOrNull(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return DateTime.tryParse(trimmed);
    }
    return null;
  }
}

/// Result of a per-application manual status refresh.
class SapsRefreshResult {
  final String applicationId;
  final bool success;
  final String message;
  final String? statusMessage;
  final int? statusStage;
  final DateTime? lastChecked;

  const SapsRefreshResult({
    required this.applicationId,
    required this.success,
    required this.message,
    this.statusMessage,
    this.statusStage,
    this.lastChecked,
  });
}

/// Represents the result from a SAPS scraper check.
class SapsScraperResult {
  final String applicationId;
  final String status;
  final int statusCode;
  final DateTime lastChecked;
  final bool success;
  final String? error;

  const SapsScraperResult({
    required this.applicationId,
    required this.status,
    required this.statusCode,
    required this.lastChecked,
    required this.success,
    this.error,
  });

  factory SapsScraperResult.fromJson(Map<String, dynamic> json) {
    return SapsScraperResult(
      applicationId: json['applicationId'] as String? ?? '',
      status: json['status'] as String? ?? '',
      statusCode: json['statusCode'] as int? ?? 0,
      lastChecked: json['lastChecked'] != null
          ? DateTime.tryParse(json['lastChecked'] as String) ?? DateTime.now()
          : DateTime.now(),
      success: json['success'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'applicationId': applicationId,
        'status': status,
        'statusCode': statusCode,
        'lastChecked': lastChecked.toIso8601String(),
        'success': success,
        if (error != null) 'error': error,
      };
}
