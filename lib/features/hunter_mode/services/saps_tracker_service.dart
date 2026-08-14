import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Cloud bridge service for SAPS License Tracker.
/// Handles communication with Apify scraper API and status mapping.
class SapsTrackerService {
  final FirebaseFirestore _firestore;

  SapsTrackerService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Triggers a remote scraper check via Apify API webhook.
  ///
  /// In production, this sends a POST request to the configured Apify Actor webhook URL.
  /// Currently implemented as a mock for offline development.
  ///
  /// Returns the scraped status response or null on failure.
  Future<SapsScraperResult?> triggerRemoteScraperCheck(
    String applicationId,
  ) async {
    try {
      // Fetch the application document to get details
      final docSnapshot =
          await _firestore
              .collection('license_applications')
              .doc(applicationId)
              .get();

      if (!docSnapshot.exists) {
        debugPrint('SapsTrackerService: Application $applicationId not found');
        return null;
      }

      final data = docSnapshot.data()!;
      // Reserved for the production Apify webhook call (currently mocked below).
      // Read here so the production migration is a one-line swap, not a schema dig.
      // ignore: unused_local_variable
      final idNumber = data['idNumber'] as String? ?? '';
      // ignore: unused_local_variable
      final referenceNumber = data['referenceNumber'] as String? ?? '';

      // Mock response for offline development
      // In production, replace with actual Apify API call:
      // final response = await _callApifyWebhook(applicationId, idNumber, referenceNumber);

      final mockStatus = _generateMockStatus();

      return SapsScraperResult(
        applicationId: applicationId,
        status: mockStatus,
        statusCode: convertRawStatusToStage(mockStatus),
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
  static int convertRawStatusToStage(String? rawStatus) {
    if (rawStatus == null || rawStatus.trim().isEmpty) {
      return 0; // Default to Submitted
    }

    final normalizedStatus = rawStatus.toLowerCase().trim();

    // Stage -> patterns. Evaluated as a group so the LONGEST matching pattern
    // across ALL stages wins (most-specific match), which prevents a short
    // Stage-0 pattern like 'submitted' from shadowing a more-specific
    // Stage-1 pattern like 'submitted to provincial' (the v4.5 audit bug).
    const stagePatterns = <int, List<String>>{
      0: [
        'submitted',
        'received',
        'received at dfo',
        'application received',
        'district firearms',
        'pending',
        'pending review',
      ],
      1: [
        'provincial',
        'province',
        'provincial office',
        'at provincial',
        'submitted to provincial',
        'forwarded to provincial',
      ],
      2: [
        'cfr',
        'central firearms registry',
        'registry',
        'at cfr',
        'forwarded to cfr',
        'forwarded to registry',
      ],
      3: [
        'printed',
        'ready for collection',
        'ready',
        'approved',
        'completed',
        'licence printed',
        'license printed',
      ],
      -1: [
        'not found in system',
        'not found',
        'no record',
        'unable to locate',
        'invalid',
        'error',
      ],
    };

    int bestStage = 0; // default Submitted; overwritten if a pattern matches
    int bestLen = -1;
    stagePatterns.forEach((stage, patterns) {
      for (final pattern in patterns) {
        if (normalizedStatus.contains(pattern) && pattern.length > bestLen) {
          bestStage = stage;
          bestLen = pattern.length;
        }
      }
    });

    if (bestLen >= 0) {
      return bestStage;
    }

    // Default to Submitted (0) for any unrecognized status
    debugPrint(
      'SapsTrackerService: Unrecognized status "$rawStatus", defaulting to Submitted',
    );
    return 0;
  }

  /// Maps raw status string to a display-friendly status label.
  ///
  /// Returns 'Pending Review' for null, empty, or unrecognized inputs
  /// to ensure safe display without runtime crashes.
  static String convertRawStatusToDisplay(String? rawStatus) {
    if (rawStatus == null || rawStatus.trim().isEmpty) {
      return 'Pending Review';
    }

    final normalizedStatus = rawStatus.toLowerCase().trim();

    // Already at a known stage
    if (normalizedStatus.contains('submitted') ||
        normalizedStatus.contains('received') ||
        normalizedStatus.contains('dfos')) {
      return 'Submitted to DFO';
    }

    if (normalizedStatus.contains('provincial')) {
      return 'At Provincial Office';
    }

    if (normalizedStatus.contains('cfr') ||
        normalizedStatus.contains('registry') ||
        normalizedStatus.contains('central firearms')) {
      return 'At Central Registry';
    }

    if (normalizedStatus.contains('printed') ||
        normalizedStatus.contains('ready') ||
        normalizedStatus.contains('approved') ||
        normalizedStatus.contains('completed')) {
      return 'Ready for Collection';
    }

    if (normalizedStatus.contains('not found') ||
        normalizedStatus.contains('invalid') ||
        normalizedStatus.contains('error')) {
      return 'Status Unavailable';
    }

    // Default fallback for any unrecognized input
    return 'Pending Review';
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
      lastChecked:
          json['lastChecked'] != null
              ? DateTime.tryParse(json['lastChecked'] as String) ??
                  DateTime.now()
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
