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

  /// Test seam: when set, the refresh paths persist through this persister
  /// instead of the real `updateApplicationStatus` (so a widget/unit test can
  /// assert the live payload write without a Firebase app).
  @visibleForTesting
  Future<void> Function(String status, DateTime lastChecked)? statusPersisterForTesting;

  /// Test seam: overrides the live-enquiry client used by the refresh paths.
  @visibleForTesting
  SapsCfrScraperClient Function()? scraperFactoryForTesting;

  SapsTrackerService({
    FirebaseFirestore? firestore,
    SapsCfrScraperClient? scraper,
    bool enableDebugFallback = false,
  })  : _injectedFirestore = firestore,
        // When enabled (debug builds), fall back to the direct portal client
        // so a manual refresh performs a REAL CFR enquiry instead of the
        // offline mock. The client itself only activates on a kDebugMode build
        // with an saps.gov.za host, so a release build never reaches the
        // portal directly.
        _scraper = scraper ??
            (enableDebugFallback ? SapsCfrScraperClient() : null);

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

  /// Triggers a CFR status check for [applicationId].
  ///
  /// Priority:
  /// 1. **Existing live payload** — if the doc already carries a `rawStatus`
  ///    (a prior live enquiry), it is returned VERBATIM. The offline mock can
  ///    never overwrite real CFR data.
  /// 2. **Webhook / direct-debug client** — when a configured webhook exists,
  ///    or a `kDebugMode` build with the direct portal path (or an explicitly
  ///    injected scraper), the REAL enquiry runs and its classified result is
  ///    returned.
  /// 3. **Offline mock** — ONLY for a doc with no live payload AND no live
  ///    client (dev / test without portal access).
  Future<SapsScraperResult?> triggerRemoteScraperCheck(
    String applicationId,
  ) async {
    if (applicationId.isEmpty) return null;
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

      // 1. Never downgrade / overwrite an existing live payload.
      final storedRaw = (data['rawStatus'] as String?)?.trim() ?? '';
      if (storedRaw.isNotEmpty) {
        return SapsScraperResult(
          applicationId: applicationId,
          status: storedRaw,
          statusCode: (data['liveStage'] as num?)?.toInt() ??
              SapsStatusClassifier.classify(storedRaw),
          displayLabel: (data['currentStatus'] as String?) ?? '',
          lastChecked: DateTime.now(),
          success: true,
        );
      }

      final idNumber = data['idNumber'] as String? ?? '';
      final referenceNumber = data['referenceNumber'] as String? ?? '';
      final serialNumber = data['serialNumber'] as String? ?? '';

      // 2. A configured webhook, an injected worker, or the kDebugMode direct
      //    path -> run the REAL CFR enquiry.
      final scraper =
          scraperFactoryForTesting?.call() ?? _scraper;
      if (scraper != null &&
          (scraper.isConfigured || scraper.isDirectDebugEnabled)) {
        final cfr = await scraper.fetchStatus(
          referenceNumber: referenceNumber,
          idNumber: idNumber,
          serialNumber: serialNumber,
        );
        if (cfr == null) {
          debugPrint(
            'SapsTrackerService: CFR enquiry returned no status for $applicationId',
          );
          return null;
        }
        return SapsScraperResult(
          applicationId: applicationId,
          status: cfr.rawStatus,
          statusCode: cfr.stage,
          displayLabel: cfr.displayLabel,
          sapsUpdatedAt: cfr.sapsUpdatedAt,
          lastChecked: DateTime.now(),
          success: true,
          error: cfr.statusMessage.isEmpty ? null : cfr.statusMessage,
        );
      }

      // 3. Offline mock — only for a doc with no live payload and no client.
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

  /// Persists a refreshed status onto the doc, routing through
  /// [statusPersisterForTesting] when a test seam is installed.
  Future<bool> _persistStatus(
    String applicationId,
    String status,
    DateTime lastChecked,
  ) async {
    if (statusPersisterForTesting != null) {
      await statusPersisterForTesting!(status, lastChecked);
      return true;
    }
    return updateApplicationStatus(applicationId, status, lastChecked);
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

  /// Runs a REAL live CFR enquiry for [applicationId] using the webhook /
  /// direct-debug client, then persists the FULL live payload via
  /// [applyLiveStatus]. Returns the enquiry result when a live client is
  /// available, else `null` (the caller falls back to the plainly-labelled
  /// offline mock).
  Future<SapsCfrStatus?> _liveEnquiryFor(String applicationId) async {
    try {
      final scraper = scraperFactoryForTesting?.call() ?? _scraper;
      if (scraper == null ||
          !(scraper.isConfigured || scraper.isDirectDebugEnabled)) {
        return null;
      }
      final doc =
          await _firestore.collection('license_applications').doc(applicationId).get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      final cfr = await scraper.fetchStatus(
        referenceNumber: data['referenceNumber'] as String? ?? '',
        idNumber: data['idNumber'] as String? ?? '',
        serialNumber: data['serialNumber'] as String? ?? '',
      );
      if (cfr == null) return null;
      await applyLiveStatus(applicationId, cfr);
      return cfr;
    } catch (e) {
      debugPrint('SapsTrackerService: live enquiry failed for $applicationId: $e');
      return null;
    }
  }

  /// Batch updates status for all tracked applications.
  Future<int> refreshAllApplications() async {
    int updatedCount = 0;

    try {
      final snapshot =
          await _firestore.collection('license_applications').get();

      for (final doc in snapshot.docs) {
        // Try a REAL live enquiry first (persists the full payload).
        final live = await _liveEnquiryFor(doc.id);
        if (live != null) {
          updatedCount++;
          continue;
        }
        // Fall back to the mock/live triggerRemoteScraperCheck path.
        final result = await triggerRemoteScraperCheck(doc.id);
        if (result != null && result.success) {
          final updated = await _persistStatus(
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
  ///
  /// Prefers a REAL live CFR enquiry (which persists the full payload:
  /// rawStatus / liveStage / statusDate / calibre / make / serial / …). When
  /// no live client is available, falls back to
  /// [triggerRemoteScraperCheck] (which itself preserves an existing live
  /// payload before ever using the mock).
  Future<SapsRefreshResult> refreshApplication(String applicationId) async {
    try {
      final live = await _liveEnquiryFor(applicationId);
      if (live != null) {
        return SapsRefreshResult(
          applicationId: applicationId,
          success: true,
          message: 'Status refreshed: ${live.rawStatus}',
          statusMessage: live.rawStatus,
          statusStage: live.stage,
          lastChecked: DateTime.now(),
        );
      }

      final result = await triggerRemoteScraperCheck(applicationId);
      if (result == null || !result.success) {
        return SapsRefreshResult(
          applicationId: applicationId,
          success: false,
          message: result?.error ?? 'No result from tracking service',
        );
      }

      final updated = await _persistStatus(
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

  /// Applies a LIVE [SapsCfrStatus] enquiry result onto a tracked
  /// application, persisting the full portal payload (raw status + classified
  /// stage + display label + SAPS status date + description + next step +
  /// the raw payload map) so the tracked card renders the live CFR
  /// information instead of the stale mock stage.
  ///
  /// Best-effort: returns `false` (never throws) when the application id is
  /// empty or the write fails (offline / permissions).
  Future<bool> applyLiveStatus(
    String applicationId,
    SapsCfrStatus status, {
    String? hunterId,
    String? referenceNumber,
    DateTime? lastChecked,
  }) async {
    if (applicationId.isEmpty) return false;
    try {
      final raw = <String, dynamic>{
        'applicationType': status.applicationType,
        'applicationNumber': status.applicationNumber,
        'calibre': status.calibre,
        'make': status.make,
        'serialNumber': SapsStatusClassifier.normalizeSerial(
          status.serialNumber,
        ),
        'statusDate': status.statusDate,
        'status': status.rawStatus,
        'statusDescription': status.statusDescription,
        'nextStep': status.nextStep,
        'htmlSnippet': status.htmlSnippet,
      };
      await _firestore
          .collection('license_applications')
          .doc(applicationId)
          .set({
        if (hunterId != null && hunterId.isNotEmpty) 'hunterId': hunterId,
        if (referenceNumber != null && referenceNumber.isNotEmpty)
          'referenceNumber': referenceNumber,
        'currentStatus': status.displayLabel.isNotEmpty
            ? status.displayLabel
            : status.rawStatus,
        'rawStatus': status.rawStatus,
        'liveStage': status.stage,
        'statusCode': status.stage,
        'statusDate': status.statusDate,
        'statusDescription': status.statusDescription,
        'nextStep': status.nextStep,
        'approved': SapsStatusClassifier.isApproved(status.rawStatus),
        'rawPayload': raw,
        if (status.applicationType.isNotEmpty)
          'applicationType': status.applicationType,
        if (status.calibre.isNotEmpty) 'calibre': status.calibre,
        if (status.make.isNotEmpty)
          'firearmMake': status.make,
        if (status.make.isNotEmpty) 'make': status.make,
        if (status.serialNumber.isNotEmpty)
          'serialNumber': SapsStatusClassifier.normalizeSerial(
            status.serialNumber,
          ),
        'lastChecked': (lastChecked ?? DateTime.now()).toIso8601String(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('SapsTrackerService: applyLiveStatus failed: $e');
      return false;
    }
  }

  /// Updates a tracked application's reference / serial (used by the card's
  /// edit action) via the injected Firestore. Returns true on success.
  Future<bool> updateReferenceAndSerial(
    String applicationId, {
    required String referenceNumber,
    required String serialNumber,
  }) async {
    if (applicationId.isEmpty) return false;
    try {
      await _firestore
          .collection('license_applications')
          .doc(applicationId)
          .set({
        'referenceNumber': referenceNumber,
        'serialNumber': SapsStatusClassifier.normalizeSerial(serialNumber),
        'lastChecked': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint(
        'SapsTrackerService: updateReferenceAndSerial failed: $e',
      );
      return false;
    }
  }

  /// Deletes a tracked application from Firestore (used by the card's delete
  /// action). The full document map is returned first so the caller can offer
  /// an undo that restores it verbatim. Returns the deleted map, or null when
  /// the id is empty / the document does not exist / the delete failed.
  Future<Map<String, dynamic>?> deleteApplication(String applicationId) async {
    if (applicationId.isEmpty) return null;
    try {
      final doc = await _firestore
          .collection('license_applications')
          .doc(applicationId)
          .get();
      if (!doc.exists) return null;
      final data = doc.data();
      await _firestore
          .collection('license_applications')
          .doc(applicationId)
          .delete();
      return data;
    } catch (e) {
      debugPrint('SapsTrackerService: deleteApplication failed: $e');
      return null;
    }
  }

  /// Restores a previously-deleted application document verbatim (the undo
  /// path for [deleteApplication]). Returns true on success.
  Future<bool> restoreApplication(
    String applicationId,
    Map<String, dynamic> data,
  ) async {
    if (applicationId.isEmpty) return false;
    try {
      await _firestore
          .collection('license_applications')
          .doc(applicationId)
          .set(data);
      return true;
    } catch (e) {
      debugPrint('SapsTrackerService: restoreApplication failed: $e');
      return false;
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

  /// Human-friendly display label for [statusCode] (via
  /// [SapsStatusClassifier]). Empty when not resolved.
  final String displayLabel;

  /// The date the SAPS portal reports its data was last updated (from the
  /// "data on this page were updated on <b>DATE</b>" notice). Null when
  /// unavailable.
  final DateTime? sapsUpdatedAt;

  final DateTime lastChecked;
  final bool success;
  final String? error;

  const SapsScraperResult({
    required this.applicationId,
    required this.status,
    required this.statusCode,
    required this.lastChecked,
    required this.success,
    this.displayLabel = '',
    this.sapsUpdatedAt,
    this.error,
  });

  factory SapsScraperResult.fromJson(Map<String, dynamic> json) {
    return SapsScraperResult(
      applicationId: json['applicationId'] as String? ?? '',
      status: json['status'] as String? ?? '',
      statusCode: json['statusCode'] as int? ?? 0,
      displayLabel: json['displayLabel'] as String? ?? '',
      sapsUpdatedAt: json['sapsUpdatedAt'] != null
          ? DateTime.tryParse(json['sapsUpdatedAt'] as String)
          : null,
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
        if (displayLabel.isNotEmpty) 'displayLabel': displayLabel,
        if (sapsUpdatedAt != null)
          'sapsUpdatedAt': sapsUpdatedAt!.toIso8601String(),
        'lastChecked': lastChecked.toIso8601String(),
        'success': success,
        if (error != null) 'error': error,
      };
}
