import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http;
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

  /// The raw-status phrase attached to a portal response that demands BOTH a
  /// serial number AND a reference number. Classified to
  /// [kSapsStageNeedSerialAndRef] (-2) and displayed with an actionable hint.
  static const String kNeedSerialAndRefStatus = 'NEED_SERIAL_AND_REF';

  /// How many characters of the raw portal HTML are retained on the parsed
  /// result for on-screen diagnostics.
  static const int kHtmlSnippetMaxChars = 500;

  final http.Client _http;
  final String _webhookUrl;

  /// True when [httpClient] was supplied (the test seam). When set, the direct
  /// portal path reuses [_http] instead of building the cert-bypass client, so
  /// a mocked transport can drive the enquiry with no live network.
  final bool _httpInjected;

  /// Creates the client. [webhookUrl] may be empty when the webhook is not
  /// configured; [isConfigured] then reports false and, in a release build,
  /// [fetchStatus] refuses (returns null). In a debug build with no webhook,
  /// [fetchStatus] uses the direct portal path instead.
  SapsCfrScraperClient({String webhookUrl = '', http.Client? httpClient})
      : _webhookUrl = webhookUrl,
        _http = httpClient ?? http.Client(),
        _httpInjected = httpClient != null;

  /// The HTTP client used for the DIRECT (device → saps.gov.za) path.
  ///
  /// The injected test client wins when supplied (unit tests). Otherwise a
  /// dedicated [io.HttpClient] is created whose certificate validation is
  /// bypassed for `saps.gov.za` in debug builds only — saps.gov.za presents a
  /// chain the Android trust store rejects on some devices/emulators, which
  /// otherwise fails the handshake. In a release build the callback always
  /// returns false, so the default verified transport is used.
  http.Client _buildDirectClient() {
    if (_httpInjected) return _http;
    final io.HttpClient ioClient = io.HttpClient()
      ..badCertificateCallback = (io.X509Certificate cert, String host, int port) {
        final bypass = certBypassForHost(host);
        if (bypass) {
          debugPrint(
            'SapsCfrScraperClient: cert verify BYPASSED for $host '
            '(kDebugMode + saps.gov.za)',
          );
        }
        return bypass;
      };
    return http.IOClient(ioClient);
  }

  /// Whether certificate verification should be bypassed for [host].
  ///
  /// Only `saps.gov.za` (and its subdomains) in a debug build — every other
  /// host keeps full verification, and a release build always verifies.
  @visibleForTesting
  static bool certBypassForHost(String host) =>
      host.contains('saps.gov.za') && kDebugMode;

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

  /// Builds the enquiry URL with the direct query-parameter form the portal
  /// ALSO accepts: `?fsref=REF&fserial=SERIAL&fid=&fref=&frid=&fiserial=`.
  ///
  /// Values are percent-encoded via [Uri]'s query encoding, so a reference or
  /// serial containing reserved characters cannot corrupt the request.
  @visibleForTesting
  static Uri buildQueryEnquiryUri({
    required String referenceNumber,
    required String serialNumber,
  }) {
    return Uri.parse(enquiryUrl).replace(queryParameters: {
      'fsref': referenceNumber,
      'fserial': serialNumber,
      'fid': '',
      'fref': '',
      'frid': '',
      'fiserial': '',
    });
  }

  /// Whether a portal body is empty / meaningless (no usable HTML), used to
  /// decide whether the GET attempt should fall through to the POST path.
  static bool _isEmptyBody(String html) {
    final stripped = html
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return stripped.isEmpty;
  }

  /// DEBUG-ONLY: performs the real enquiry against the official SAPS portal.
  ///
  /// Flow (mirrors the portal's browser form):
  ///   1. GET the enquiry page with the direct query parameters
  ///      (`?fsref=…&fserial=…&fid=&fref=&frid=&fiserial=`). When the portal
  ///      answers with a usable results page (or an explicit NOT_FOUND /
  ///      "Please supply…" notice) the enquiry is complete.
  ///   2. Otherwise GET the bare form page to obtain the form + `csrf` token
  ///      and the `csrf_token` cookie, then POST `fsref` + `fserial` with the
  ///      `csrf` token, the `csrf_token` cookie and a same-origin `Referer`.
  ///   3. Follow any 3xx redirect (the `http` client follows automatically)
  ///      and parse the results page.
  ///
  /// Parses the "data on this page were updated on <b>DATE</b>" notice into
  /// [SapsCfrStatus.sapsUpdatedAt] and detects the "No records to retrieve…"
  /// NOT_FOUND response and the "Please supply a Serial Number AND Reference
  /// Number" validation notice.
  Future<SapsCfrStatus?> _fetchDirectFromSaps({
    required String referenceNumber,
    required String serialNumber,
  }) async {
    // saps.gov.za presents a certificate chain the Android system trust store
    // (and some emulators / older devices) rejects, which surfaced as a
    // handshake failure. In a DEBUG build we bypass certificate validation for
    // saps.gov.za ONLY (the host check keeps every other host verified); a
    // release build always uses the default, verified transport. The webhook
    // path continues to use the injected _http client, so its cert handling is
    // untouched. [client] is our own socket pool and is closed below; the
    // injected test client is left open.
    final http.Client client = _buildDirectClient();

    try {
      // 1. GET-first with the query parameters the portal also accepts. This is
      //    the cheapest path — some portal builds answer the enquiry straight
      //    from a GET without the csrf handshake.
      try {
        final getResponse = await client
            .get(
              buildQueryEnquiryUri(
                referenceNumber: referenceNumber,
                serialNumber: serialNumber,
              ),
              headers: {
                'User-Agent': userAgent,
                'Accept': 'text/html,application/xhtml+xml',
                'Accept-Language': 'en-ZA,en;q=0.9',
              },
            )
            .timeout(const Duration(seconds: 30));

        if (getResponse.statusCode == 200 &&
            !_isEmptyBody(getResponse.body)) {
          final parsed = _parseEnquiryPage(getResponse.body);
          // Only accept the GET result when it carries something meaningful —
          // a results row, a NOT_FOUND notice, or the "Please supply…" prompt.
          // The bare form page parses to null and falls through to the POST.
          if (parsed != null) return parsed;
        }
      } catch (e) {
        debugPrint('SapsCfrScraperClient: query GET failed, trying POST: $e');
      }

      try {
        // 2. POST fallback. First GET the bare form page (captures the csrf
        //    token + cookie).
        final formResponse = await client.get(
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

        // POST the enquiry. The `http` client follows a 3xx redirect (the
        // portal answers 303 on some paths, 200 with the results page on
        // others) so `response.body` is the results page either way.
        final response = await client
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
    } finally {
      // Release the socket pool for this enquiry — but only when we created it.
      // The injected test client is shared across calls, so leave it open.
      if (!_httpInjected) client.close();
    }
  }

  /// The first [kHtmlSnippetMaxChars] characters of the portal HTML, for
  /// on-screen diagnostics. Collapses whitespace so the fragment stays compact.
  @visibleForTesting
  static String htmlSnippetOf(String html) {
    final normalized = html.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= kHtmlSnippetMaxChars) return normalized;
    return normalized.substring(0, kHtmlSnippetMaxChars);
  }

  /// Parses the SAPS results page into a [SapsCfrStatus].
  ///
  /// Order of detection:
  ///   1. "Please supply a Serial Number AND Reference Number" -> the
  ///      NEED_SERIAL_AND_REF prompt ([kSapsStageNeedSerialAndRef]).
  ///   2. "No records to retrieve" -> NOT_FOUND ([kSapsStageNotFound]).
  ///   3. The "Search Results" table -> the first data row.
  ///
  /// Returns null when the page carries none of the above (e.g. the bare form
  /// page).
  @visibleForTesting
  static SapsCfrStatus? parseEnquiryPage(String html) =>
      _parseEnquiryPage(html);

  static SapsCfrStatus? _parseEnquiryPage(String html) {
    if (html.trim().isEmpty) return null;

    final htmlSnippet = htmlSnippetOf(html);
    final sapsUpdatedAt = _parseUpdatedDate(html);

    // 1. Validation prompt: a firearm enquiry needs BOTH a serial number AND
    //    a reference number (a competency-only application needs the ref).
    if (_needsSerialAndRef(html)) {
      return SapsCfrStatus(
        rawStatus: kNeedSerialAndRefStatus,
        stage: kSapsStageNeedSerialAndRef,
        displayLabel: SapsStatusClassifier.displayLabel(kNeedSerialAndRefStatus),
        sapsUpdatedAt: sapsUpdatedAt,
        statusMessage:
            'The portal requires BOTH a serial number and a reference number '
            'for firearm applications (reference only for competency).',
        htmlSnippet: htmlSnippet,
        raw: {'needsSerialAndRef': true, 'htmlSnippet': htmlSnippet},
      );
    }

    // 2. No records.
    if (_isNotFound(html)) {
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
        htmlSnippet: htmlSnippet,
        raw: {
          'notFound': true,
          'message': message.trim(),
          'htmlSnippet': htmlSnippet,
        },
      );
    }

    // 3. The Search Results table.
    final row = _parseResultRow(html);
    if (row == null) return null;

    // Concatenate the Status + Status description columns so the classifier
    // sees the full phrase the portal renders across both cells.
    final rawStatus = <String>[
      row.status.trim(),
      row.statusDescription.trim(),
    ].where((part) => part.isNotEmpty).join(' — ');

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
      htmlSnippet: htmlSnippet,
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
        'htmlSnippet': htmlSnippet,
      },
    );
  }

  /// True when the portal refused the enquiry because a firearm application
  /// needs BOTH a serial number AND a reference number.
  static bool _needsSerialAndRef(String html) {
    final lower = html.toLowerCase();
    return lower.contains('please supply a serial number and reference number') ||
        lower.contains('please supply a serial') ||
        (lower.contains('supply a serial number') &&
            lower.contains('reference number')) ||
        lower.contains('need_serial_and_ref');
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

  /// Extracts the first data row from the results table.
  ///
  /// The portal emits a "Search Results:" heading followed by a table whose
  /// header is a `<th>` row and whose first data row is a `<td>` row. The scope
  /// is bounded to the results table (from "Search Results" to the next
  /// `</table>`) so unrelated page tables are never parsed.
  ///
  /// Two column layouts are supported:
  ///   * **10 columns** (the current portal): Type, App No, ID, Caliber, Make,
  ///     Serial, Date, Status, Status description, Next step.
  ///   * **8-9 columns** (legacy / compact): Type, App No, Caliber, Make,
  ///     Serial, Date, Status, Status description [, Next step].
  static _SapsResultRow? _parseResultRow(String html) {
    final searchIdx = html.indexOf('Search Results');
    final scope = searchIdx >= 0 ? _resultsTableScope(html, searchIdx) : html;

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
      if (rowHtml.toLowerCase().contains('<th')) continue;

      if (cells.length >= 10) {
        // Current portal layout (ID column present at index 2; index 9 = next).
        return _SapsResultRow(
          applicationType: cells[0],
          applicationNumber: cells[1],
          calibre: cells[3],
          make: cells[4],
          serialNumber: cells[5],
          statusDate: cells[6],
          status: cells[7],
          statusDescription: cells[8],
          nextStep: cells[9],
        );
      }
      if (cells.length >= 8) {
        // Legacy / compact layout (no ID column).
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

  /// Bounds the results scope from the "Search Results" marker to the end of
  /// that table (`</table>`), so the row scan never wanders past the section.
  static String _resultsTableScope(String html, int searchIdx) {
    final endIdx = html.indexOf('</table>', searchIdx);
    return endIdx > searchIdx
        ? html.substring(searchIdx, endIdx)
        : html.substring(searchIdx);
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

  /// The first [SapsCfrScraperClient.kHtmlSnippetMaxChars] characters of the
  /// portal HTML (whitespace-collapsed), for on-screen diagnostics in the
  /// debug screen. Empty on the webhook path.
  final String htmlSnippet;

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
    this.htmlSnippet = '',
  });
}
