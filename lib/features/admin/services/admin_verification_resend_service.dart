import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Client for the admin-only email-verification resend Cloud Functions.
///
/// Email-verification mails are sent by Firebase Auth itself, so the app can
/// only resend for the signed-in user. Re-sending on behalf of an arbitrary
/// account needs the Admin SDK, which lives in the `resendVerificationEmail` /
/// `resendVerificationEmailsBulk` callables. The server mints a custom token
/// for the target account, exchanges it for that account's idToken, and calls
/// the Identity Toolkit `accounts:sendOobCode` endpoint with it (a
/// service-account token is rejected with `INVALID_ID_TOKEN`); with no API key
/// configured it returns a minted verification link instead.
///
/// The callables are invoked over HTTPS with the caller's Firebase ID token
/// (Bearer) — the SAME dependency-free pattern `EntitlementService` and
/// `AdminKpiService` use, so no `cloud_functions` plugin is required and the
/// native builds are untouched. The server re-checks admin privileges; the
/// client-side `isAdmin` gate is defense-in-depth only.
///
/// A per-account failure carries the `accounts:sendOobCode` HTTP status code
/// back to the portal ([ResendOutcome.statusCode]) so the admin sees
/// `sendOobCode 400: INVALID_ID_TOKEN` instead of a bare "could not be
/// delivered".
class AdminVerificationResendService {
  AdminVerificationResendService._();
  static final AdminVerificationResendService instance =
      AdminVerificationResendService._();

  /// The callable names (must match the `functions/src/email_verification.ts`
  /// exports).
  static const String resendOneCallable = 'resendVerificationEmail';
  static const String resendBulkCallable = 'resendVerificationEmailsBulk';

  /// Functions region (mirrors the deploy region used by every callable).
  static const String _functionsRegion = 'us-central1';

  @visibleForTesting
  static String projectIdForTesting = 'jagspoor';

  /// Test seam: replaces the one-account invocation.
  @visibleForTesting
  static Future<ResendOutcome> Function(String uid)? resendOneForTesting;

  /// Test seam: replaces the bulk invocation.
  @visibleForTesting
  static Future<BulkResendOutcome> Function(List<String> uids)? resendBulkForTesting;

  /// Test seam: overrides the ID-token resolver.
  @visibleForTesting
  static Future<String?> Function()? idTokenResolverForTesting;

  /// Test seam: overrides the HTTP client so the response-parsing path (the
  /// sendOobCode status code surfacing) is testable without a live function.
  @visibleForTesting
  static http.Client? httpClientForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    resendOneForTesting = null;
    resendBulkForTesting = null;
    idTokenResolverForTesting = null;
    httpClientForTesting = null;
    projectIdForTesting = 'jagspoor';
  }

  /// The POST used by both callables (overridable via [httpClientForTesting]).
  static Future<http.Response> _post(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
  }) {
    final client = httpClientForTesting;
    if (client != null) {
      return client.post(uri, headers: headers, body: body);
    }
    return http.post(uri, headers: headers, body: body);
  }

  Future<String?> _idToken() async {
    final override = idTokenResolverForTesting;
    if (override != null) return override();
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  String _endpoint(String callable) =>
      'https://$_functionsRegion-$projectIdForTesting'
      '.cloudfunctions.net/$callable';

  /// Resends the verification email to a single account.
  Future<ResendOutcome> resendOne(String uid) async {
    final override = resendOneForTesting;
    if (override != null) return override(uid);
    final idToken = await _idToken();
    if (idToken == null) {
      return const ResendOutcome(
        delivered: false,
        message: 'You must be signed in as an admin to resend.',
      );
    }
    try {
      final res = await _post(
        Uri.parse(_endpoint(resendOneCallable)),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'data': {'uid': uid},
        }),
      );
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final result = decoded['result'];
        final map = result is Map ? result : const {};
        final delivered = map['delivered'] == true;
        final statusCode = (map['statusCode'] as num?)?.toInt();
        final reason = (map['reason'] as String?)?.trim();
        final link = (map['verificationLink'] as String?)?.trim();
        return ResendOutcome(
          delivered: delivered,
          statusCode: statusCode,
          reason: (reason == null || reason.isEmpty) ? null : reason,
          verificationLink: (link == null || link.isEmpty) ? null : link,
          message: describeOne(delivered: delivered, statusCode: statusCode, reason: reason, link: link),
        );
      }
      return ResendOutcome(
        delivered: false,
        statusCode: res.statusCode,
        message: errorMessageFor(res, 'Resend failed (${res.statusCode}).'),
      );
    } catch (e) {
      debugPrint('AdminVerificationResendService.resendOne error: $e');
      return const ResendOutcome(
        delivered: false,
        message: 'Resend failed — check your connection and try again.',
      );
    }
  }

  /// Builds the row-level message from the server's per-account result.
  ///
  /// The `sendOobCode` HTTP STATUS CODE is included whenever the server
  /// reached the endpoint (e.g. `sendOobCode 400: INVALID_ID_TOKEN`) so a
  /// failure is diagnosable straight from the portal instead of a bare
  /// "could not be delivered".
  @visibleForTesting
  static String describeOne({
    required bool delivered,
    int? statusCode,
    String? reason,
    String? link,
  }) {
    if (delivered) return 'Verification email sent.';
    final code = statusCode == null ? '' : 'sendOobCode $statusCode: ';
    if (link != null && link.isNotEmpty) {
      return 'No API key configured — verification link generated. '
          'Deliver it manually.';
    }
    final detail = (reason == null || reason.isEmpty)
        ? 'the email could not be delivered'
        : reason;
    return '$code$detail';
  }

  /// Builds the bulk summary, appending the distinct failure status codes so
  /// "Resent to 0 of 12." becomes "Resent to 0 of 12 (sendOobCode 400)."
  @visibleForTesting
  static String describeBulk({
    required int delivered,
    required int total,
    required Set<int> statusCodes,
  }) {
    final base = 'Resent to $delivered of $total.';
    if (delivered == total || statusCodes.isEmpty) return base;
    final codes = (statusCodes.toList()..sort()).join(', ');
    return '$base (sendOobCode $codes)';
  }

  /// Resends to a capped batch of accounts. The server enforces the cap; the
  /// client also trims defensively so a caller can never exceed it.
  Future<BulkResendOutcome> resendBulk(
    List<String> uids, {
    int limit = 50,
  }) async {
    final batch = uids.length > limit ? uids.sublist(0, limit) : uids;
    final override = resendBulkForTesting;
    if (override != null) return override(batch);
    final idToken = await _idToken();
    if (idToken == null) {
      return const BulkResendOutcome(
        delivered: 0,
        processed: 0,
        skipped: 0,
        message: 'You must be signed in as an admin to resend.',
      );
    }
    try {
      final res = await _post(
        Uri.parse(_endpoint(resendBulkCallable)),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'data': {'uids': batch},
        }),
      );
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final result = decoded['result'];
        if (result is Map) {
          final results = (result['results'] as List?) ?? const [];
          final maps = results.whereType<Map>();
          final delivered = maps.where((r) => r['delivered'] == true).length;
          final statusCodes = <int>{};
          for (final r in maps) {
            final code = (r['statusCode'] as num?)?.toInt();
            if (code != null) statusCodes.add(code);
          }
          return BulkResendOutcome(
            delivered: delivered,
            processed: (result['processed'] as num?)?.toInt() ?? results.length,
            skipped: (result['skipped'] as num?)?.toInt() ?? 0,
            statusCodes: statusCodes.toList(growable: false),
            message: describeBulk(
              delivered: delivered,
              total: results.length,
              statusCodes: statusCodes,
            ),
          );
        }
      }
      return BulkResendOutcome(
        delivered: 0,
        processed: 0,
        skipped: 0,
        statusCodes: [res.statusCode],
        message: errorMessageFor(res, 'Bulk resend failed (${res.statusCode}).'),
      );
    } catch (e) {
      debugPrint('AdminVerificationResendService.resendBulk error: $e');
      return const BulkResendOutcome(
        delivered: 0,
        processed: 0,
        skipped: 0,
        message: 'Bulk resend failed — check your connection and try again.',
      );
    }
  }

  /// Extracts the callable error message (`error.message`) from a response.
  ///
  /// This is what surfaces a server-side `failed-precondition` diagnostic
  /// (e.g. the credential/IAM identity + missing role) to the admin UI, so the
  /// user sees WHY a resend failed instead of a bare "0 of N".
  @visibleForTesting
  static String errorMessageFor(http.Response res, String fallback) {
    try {
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final err = decoded['error'];
      if (err is Map && err['message'] != null) {
        final msg = err['message'].toString().trim();
        if (msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    return fallback;
  }

  /// Opens a `mailto:` URI in the platform's mail client (used by the
  /// "Remind Unverified With Role" action, which sends a gentle reminder —
  /// NOT a fresh verification link — to active users). Returns whether the
  /// hand-off succeeded; never throws.
  Future<bool> launchMailto(Uri mailto) async {
    try {
      return await launchUrl(mailto, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('AdminVerificationResendService.launchMailto error: $e');
      return false;
    }
  }
}

/// Outcome of a single-account resend.
class ResendOutcome {
  final bool delivered;
  final String message;

  /// The `accounts:sendOobCode` HTTP status code, when the server reached the
  /// endpoint. Surfaced in the row diagnostic (e.g. `400` for
  /// `INVALID_ID_TOKEN`) — never a token.
  final int? statusCode;

  /// The server's failure reason, verbatim (e.g.
  /// `send failed: 400: INVALID_ID_TOKEN`).
  final String? reason;

  /// The minted verification link, present ONLY on the no-API-key fallback
  /// path (the admin delivers it manually). Null on a normal send.
  final String? verificationLink;

  const ResendOutcome({
    required this.delivered,
    required this.message,
    this.statusCode,
    this.reason,
    this.verificationLink,
  });
}

/// Outcome of a bulk resend.
class BulkResendOutcome {
  final int delivered;
  final int processed;
  final int skipped;
  final String message;

  /// The distinct `accounts:sendOobCode` status codes seen across the batch's
  /// failures (empty when every attempt succeeded). Lets the portal show WHY
  /// a batch failed without a per-row drill-down.
  final List<int> statusCodes;

  const BulkResendOutcome({
    required this.delivered,
    required this.processed,
    required this.skipped,
    required this.message,
    this.statusCodes = const [],
  });
}
