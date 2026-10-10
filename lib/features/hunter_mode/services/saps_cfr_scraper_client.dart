import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'saps_status_classifier.dart';

/// HTTP client for the SAPS Central Firearms Register (CFR) firearm /
/// competency status enquiry.
///
/// Two transport paths are supported:
///
/// 1. **Webhook (production)** — when [isConfigured] (a deployed Apify Actor /
///    Cloud Function URL is supplied) the enquiry is POSTed to that endpoint,
///    which performs the portal scrape server-side and returns a JSON payload.
///
/// 2. **Direct (debug only)** — when running a `kDebugMode` build with NO
///    webhook configured, [fetchStatus] performs the enquiry against the
///    official portal (`saps.gov.za`) directly from the device. This exists so
///    a developer can verify the real CFR portal end-to-end from a debug build
///    without a deployed webhook. It is deliberately gated behind
///    `kDebugMode` so a release build never hits the portal directly.
///
/// The HTTP client is injectable so tests exercise the real code path with a
/// mocked transport (no live network).
class SapsCfrScraperClient {
  /// The official SAPS firearm status enquiry form.
  static const String enquiryUrl =
      'https://www.saps.gov.za/services/firearm_status_enquiry.php';

  /// Desktop browser User-Agent — the portal rejects some non-browser agents.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  final http.Client _http;
  final String _webhookUrl;

  /// Creates the client. [webhookUrl] may be empty when the webhook is not
  /// configured; [isConfigured] then reports false and, in a release build,
  /// [fetchStatus] refuses (returns null). In a debug build with no webhook,
  /// [fetchStatus] uses the direct portal path instead.
  SapsCfrScraperClient({String webhookUrl = '', http.Client? httpClient})
      : _webhookUrl = webhookUrl,
        _http = httpClient ?? http.Client();

  bool get isConfigured => _webhookUrl.trim().isNotEmpty;

  Uri get webhookUri => Uri.parse(_webhookUrl);

  /// Whether [fetchStatus] will use the direct (device → portal) path: a
  /// debug build with no configured webhook.
  bool get isDirectDebugEnabled => kDebugMode && !isConfigured;

  /// Fetches the current status for an application.
  ///
  /// Branches:
  ///   * webhook configured -> [fetchFromWebhook];
  ///   * `kDebugMode` + no webhook -> direct portal scrape;
  ///   * otherwise (release + no webhook) -> null.
  ///
  /// Returns null on transport / HTTP / parse errors (never throws — callers
  /// treat null as "status unavailable").
  Future<SapsCfrStatus?> fetchStatus({
    required String referenceNumber,
    required String idNumber,
    String? serialNumber,
  }) async {
    if (isConfigured) {
      return _fetchFromWebhook(
        referenceNumber: referenceNumber,
        idNumber: idNumber,
      );
    }
    if (kDebugMode) {
      return _fetchDirectFromSaps(
        referenceNumber: referenceNumber,
        serialNumber: serialNumber ?? idNumber,
      );
    }
    debugPrint('SapsCfrScraperClient: webhook not configured (release build)');
    return null;
  }

  /// POSTs the enquiry to the configured webhook and parses the JSON payload.
  Future<SapsCfrStatus?> _fetchFromWebhook({
    required String referenceNumber,
    required String idNumber,
  }) async {
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
        stage: SapsStatusClassifier.classify(rawStatus),
        displayLabel: SapsStatusClassifier.displayLabel(rawStatus),
        sapsUpdatedAt: _dateTimeOrNull(payload['sapsUpdatedAt']),
        statusMessage: payload['message'].toString(),
        batchNumber: payload['batchNumber'].toString(),
        submittedAt: _dateTimeOrNull(payload['submittedAt']),
        statusUpdatedAt: _dateTimeOrNull(payload['statusUpdatedAt']),
        trackUrl: payload['trackUrl'].toString(),
        raw: payload,
      );
    } catch (e) {
      debugPrint('SapsCfrScraperClient: webhook fetch failed: $e');
      return null;
    }
  }

  /// DEBUG-ONLY: performs the real enquiry against the official SAPS portal.
  ///
  /// Flow (mirrors the portal's browser form):
  ///   1. GET the enquiry page to obtain the form + `csrf` token and the
  ///      `csrf_token` cookie.
  ///   2. POST `fsref` (reference) + `fserial` (serial) with the `csrf` token,
  ///      the `csrf_token` cookie and a same-origin `Referer` header.
  ///   3. Follow any 3xx redirect (the `http` client follows automatically)
  ///      and parse the results page.
  ///
  /// Parses the "data on this page were updated on <b>DATE</b>" notice into
  /// [SapsCfrStatus.sapsUpdatedAt] and detects the "No records to retrieve…"
  /// NOT_FOUND response.
  Future<SapsCfrStatus?> _fetchDirectFromSaps({
    required String referenceNumber,
    required String serialNumber,
  }) async {
    try {
      // 1. GET the form page (captures the csrf token + cookie).
      final formResponse = await _http.get(
        Uri.parse(enquiryUrl),
        headers: {
          'User-Agent': userAgent,
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'en-ZA,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 30));

      if (formResponse.statusCode != 200) {
        debugPrint(
          'SapsCfrScraperClient: form GET returned HTTP '
          '${formResponse.statusCode}',
        );
        return null;
      }

      final csrf = _extractCsrfField(formResponse.body);
      final cookie = _extractCsrfCookie(formResponse.headers);

      // 2. POST the enquiry. The `http` client follows a 3xx redirect (the
      // portal answers 303 on some paths, 200 with the results page on
      // others) so `response.body` is the results page either way.
      final response = await _http
          .post(
            Uri.parse(enquiryUrl),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'User-Agent': userAgent,
              'Accept': 'text/html,application/xhtml+xml',
              'Accept-Language': 'en-ZA,en;q=0.9',
              'Referer': enquiryUrl,
              if (cookie != null) 'Cookie': 'csrf_token=$cookie',
            },
            body: {
              'csrf': csrf ?? '',
              'csrf_token': '',
              'fsref': referenceNumber,
              'fserial': serialNumber,
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint(
          'SapsCfrScraperClient: enquiry POST returned HTTP '
          '${response.statusCode}',
        );
        return null;
      }

      // 3. Parse the results page.
      return _parseEnquiryPage(response.body);
    } catch (e) {
      debugPrint('SapsCfrScraperClient: direct enquiry failed: $e');
      return null;
    }
  }

  /// Parses the SAPS results page into a [SapsCfrStatus].
  ///
  /// Returns null when the page carries neither a results row nor the
  /// not-found notice.
  @visibleForTesting
  static SapsCfrStatus? parseEnquiryPage(String html) =>
      _parseEnquiryPage(html);

  static SapsCfrStatus? _parseEnquiryPage(String html) {
    if (html.trim().isEmpty) return null;

    final sapsUpdatedAt = _parseUpdatedDate(html);
    final notFound = _isNotFound(html);

    if (notFound) {
      final message = _firstMatch(
            html,
            RegExp(r'No records to retrieve[^<]*', caseSensitive: false),
          ) ??
          'No records to retrieve for the selected reference / serial number';
      return SapsCfrStatus(
        rawStatus: message.trim(),
        stage: kSapsStageNotFound,
        displayLabel: 'Status Unavailable',
        sapsUpdatedAt: sapsUpdatedAt,
        notFound: true,
        raw: {'notFound': true, 'message': message.trim()},
      );
    }

    final row = _parseResultRow(html);
    if (row == null) return null;

    final rawStatus = row.status.trim().isEmpty
        ? row.statusDescription.trim()
        : row.status.trim();

    return SapsCfrStatus(
      rawStatus: rawStatus,
      stage: SapsStatusClassifier.classify(rawStatus),
      displayLabel: SapsStatusClassifier.displayLabel(rawStatus),
      sapsUpdatedAt: sapsUpdatedAt,
      applicationType: row.applicationType,
      applicationNumber: row.applicationNumber,
      calibre: row.calibre,
      make: row.make,
      serialNumber: row.serialNumber,
      statusDate: row.statusDate,
      statusDescription: row.statusDescription,
      nextStep: row.nextStep,
      raw: {
        'applicationType': row.applicationType,
        'applicationNumber': row.applicationNumber,
        'calibre': row.calibre,
        'make': row.make,
        'serialNumber': row.serialNumber,
        'statusDate': row.statusDate,
        'status': row.status,
        'statusDescription': row.statusDescription,
        'nextStep': row.nextStep,
      },
    );
  }

  /// Extracts the hidden `csrf` token from the enquiry form.
  @visibleForTesting
  static String? extractCsrfField(String html) => _extractCsrfField(html);

  static String? _extractCsrfField(String html) {
    final match = RegExp(
      '''name=["']csrf["']\\s+value=["']([^"']*)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    final value = match?.group(1)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Extracts the `csrf_token` cookie value from the response headers.
  @visibleForTesting
  static String? extractCsrfCookie(Map<String, String> headers) =>
      _extractCsrfCookie(headers);

  static String? _extractCsrfCookie(Map<String, String> headers) {
    final raw = headers['set-cookie'] ?? headers['Set-Cookie'] ?? '';
    if (raw.isEmpty) return null;
    final match = RegExp(
      r'csrf_token=([^;,\s]+)',
      caseSensitive: false,
    ).firstMatch(raw);
    final value = match?.group(1)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Parses the "data on this page were updated on <b>DATE</b>" notice.
  @visibleForTesting
  static DateTime? parseUpdatedDate(String html) => _parseUpdatedDate(html);

  static DateTime? _parseUpdatedDate(String html) {
    final match = RegExp(
      r'were updated on\s*<b>\s*([^<]+?)\s*</b>',
      caseSensitive: false,
    ).firstMatch(html);
    final raw = match?.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static bool _isNotFound(String html) {
    final lower = html.toLowerCase();
    return lower.contains('no records to retrieve') ||
        lower.contains('no records found') ||
        lower.contains('no record found');
  }

  /// Extracts the first data row from the results table (the portal emits a
  /// `<thead>` header followed by `<tr>` rows of `<td>` cells).
  static _SapsResultRow? _parseResultRow(String html) {
    final searchIdx = html.indexOf('Search Results');
    final scope = searchIdx >= 0 ? html.substring(searchIdx) : html;

    final rowRegex =
        RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true, caseSensitive: false);
    final cellRegex =
        RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', dotAll: true, caseSensitive: false);

    for (final rowMatch in rowRegex.allMatches(scope)) {
      final rowHtml = rowMatch.group(1) ?? '';
      final cells = cellRegex
          .allMatches(rowHtml)
          .map((m) => _stripHtml(m.group(1) ?? ''))
          .toList();
      // The header row uses <th>; a data row carries >= 8 <td> cells.
      if (cells.length >= 8 && !rowHtml.toLowerCase().contains('<th')) {
        return _SapsResultRow(
          applicationType: cells[0],
          applicationNumber: cells[1],
          calibre: cells[2],
          make: cells[3],
          serialNumber: cells[4],
          statusDate: cells[5],
          status: cells[6],
          statusDescription: cells[7],
          nextStep: cells.length > 8 ? cells[8] : '',
        );
      }
    }
    return null;
  }

  static String _stripHtml(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? _firstMatch(String input, RegExp pattern) {
    final match = pattern.firstMatch(input);
    return match?.group(0);
  }

  static DateTime? _dateTimeOrNull(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value.trim());
    return null;
  }
}

/// A parsed results-table row from the SAPS enquiry page.
class _SapsResultRow {
  final String applicationType;
  final String applicationNumber;
  final String calibre;
  final String make;
  final String serialNumber;
  final String statusDate;
  final String status;
  final String statusDescription;
  final String nextStep;

  const _SapsResultRow({
    required this.applicationType,
    required this.applicationNumber,
    required this.calibre,
    required this.make,
    required this.serialNumber,
    required this.statusDate,
    required this.status,
    required this.statusDescription,
    required this.nextStep,
  });
}

/// Parsed CFR enquiry result carrying the RAW portal status phrase plus the
/// classified stage / label and any optional enrichment the portal (or the
/// webhook) surfaced.
class SapsCfrStatus {
  final String rawStatus;

  /// Classified stage index (0 DFO / 1 Provincial / 2 CFR / 3 Printed /
  /// -1 Not Found) via [SapsStatusClassifier].
  final int stage;

  /// Human-friendly display label for [stage] via [SapsStatusClassifier].
  final String displayLabel;

  /// The date the SAPS portal reports its data was last updated
  /// ("data on this page were updated on <b>DATE</b>"). Null when unavailable.
  final DateTime? sapsUpdatedAt;

  /// True when the portal answered "No records to retrieve…" (NOT_FOUND).
  final bool notFound;

  /// Optional API-level message / notice returned alongside the status.
  final String statusMessage;

  /// Optional batch identifier grouping this application.
  final String batchNumber;

  final DateTime? submittedAt;
  final DateTime? statusUpdatedAt;
  final String trackUrl;

  // Portal results-table columns (present on the direct path, blank on the
  // webhook path unless the payload surfaces them).
  final String applicationType;
  final String applicationNumber;
  final String calibre;
  final String make;
  final String serialNumber;
  final String statusDate;
  final String statusDescription;
  final String nextStep;

  /// The full unparsed payload (for diagnostics / future fields).
  final Map<String, dynamic>? raw;

  const SapsCfrStatus({
    required this.rawStatus,
    this.stage = kSapsStageDfo,
    this.displayLabel = '',
    this.sapsUpdatedAt,
    this.notFound = false,
    this.statusMessage = '',
    this.batchNumber = '',
    this.submittedAt,
    this.statusUpdatedAt,
    this.trackUrl = '',
    this.applicationType = '',
    this.applicationNumber = '',
    this.calibre = '',
    this.make = '',
    this.serialNumber = '',
    this.statusDate = '',
    this.statusDescription = '',
    this.nextStep = '',
    this.raw,
  });
}
