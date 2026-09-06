import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A thin, production-ready HTTP client for the SAPS Central Firearms
/// Register (CFR) status enquiry webhook.
///
/// The deployed Apify Actor (or a Cloud Function) performs the actual form
/// POST against the official `saps.gov.za` CFR enquiry portal and returns a
/// JSON payload carrying the raw status phrase. This client POSTs the
/// application reference + ID number to that webhook URL and parses the
/// response into a [SapsCfrStatus].
///
/// The HTTP client is injectable so tests exercise the real code path with a
/// mocked transport (no live network).
class SapsCfrScraperClient {
  final http.Client _http;
  final String _webhookUrl;

  /// Creates the client. [webhookUrl] may be empty when the webhook is not
  /// configured; [isConfigured] then reports false and [fetchStatus] refuses.
  SapsCfrScraperClient({String webhookUrl = '', http.Client? httpClient})
      : _webhookUrl = webhookUrl,
        _http = httpClient ?? http.Client();

  bool get isConfigured => _webhookUrl.trim().isNotEmpty;

  Uri get webhookUri => Uri.parse(_webhookUrl);

  /// POSTs the enquiry to the webhook and returns the parsed raw status.
  ///
  /// Returns null on transport / HTTP errors or when the payload cannot be
  /// parsed (never throws -- callers treat null as "status unavailable").
  Future<SapsCfrStatus?> fetchStatus({
    required String referenceNumber,
    required String idNumber,
  }) async {
    if (!isConfigured) {
      debugPrint('SapsCfrScraperClient: webhook not configured');
      return null;
    }
    try {
      final response = await _http
          .post(
            webhookUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'referenceNumber': referenceNumber,
              'idNumber': idNumber,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint(
          'SapsCfrScraperClient: webhook returned HTTP ${response.statusCode}',
        );
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final payload = Map<String, dynamic>.from(decoded);

      final rawStatus = (payload['status'] ?? payload['statusMessage'])
          .toString()
          .trim();
      if (rawStatus.isEmpty) return null;

      return SapsCfrStatus(
        rawStatus: rawStatus,
        statusMessage: payload['message'].toString(),
        batchNumber: payload['batchNumber'].toString(),
        submittedAt: _dateTimeOrNull(payload['submittedAt']),
        statusUpdatedAt: _dateTimeOrNull(payload['statusUpdatedAt']),
        trackUrl: payload['trackUrl'].toString(),
        raw: payload,
      );
    } catch (e) {
      debugPrint('SapsCfrScraperClient: fetch failed: $e');
      return null;
    }
  }

  static DateTime? _dateTimeOrNull(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// Parsed CFR enquiry result carrying the RAW portal status phrase plus any
/// optional enrichment the webhook surfaced.
class SapsCfrStatus {
  final String rawStatus;

  /// Optional API-level message / notice returned alongside the status.
  final String statusMessage;

  /// Optional batch identifier grouping this application.
  final String batchNumber;

  final DateTime? submittedAt;
  final DateTime? statusUpdatedAt;
  final String trackUrl;

  /// The full unparsed payload (for diagnostics / future fields).
  final Map<String, dynamic>? raw;

  const SapsCfrStatus({
    required this.rawStatus,
    this.statusMessage = '',
    this.batchNumber = '',
    this.submittedAt,
    this.statusUpdatedAt,
    this.trackUrl = '',
    this.raw,
  });
}