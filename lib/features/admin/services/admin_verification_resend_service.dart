import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Client for the admin-only email-verification resend Cloud Functions.
///
/// Email-verification mails are sent by Firebase Auth itself, so the app can
/// only resend for the signed-in user. Re-sending on behalf of an arbitrary
/// account needs the Admin SDK (`generateEmailVerificationLink`), which lives
/// in the `resendVerificationEmail` / `resendVerificationEmailsBulk` callables.
///
/// The callables are invoked over HTTPS with the caller's Firebase ID token
/// (Bearer) — the SAME dependency-free pattern `EntitlementService` and
/// `AdminKpiService` use, so no `cloud_functions` plugin is required and the
/// native builds are untouched. The server re-checks admin privileges; the
/// client-side `isAdmin` gate is defense-in-depth only.
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

  @visibleForTesting
  static void resetTestSeams() {
    resendOneForTesting = null;
    resendBulkForTesting = null;
    idTokenResolverForTesting = null;
    projectIdForTesting = 'jagspoor';
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
      final res = await http.post(
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
        final delivered =
            result is Map && result['delivered'] == true;
        return ResendOutcome(
          delivered: delivered,
          message: delivered
              ? 'Verification email sent.'
              : 'Link generated but the email could not be delivered.',
        );
      }
      return ResendOutcome(
        delivered: false,
        message: _errorMessage(res, 'Resend failed (${res.statusCode}).'),
      );
    } catch (e) {
      debugPrint('AdminVerificationResendService.resendOne error: $e');
      return const ResendOutcome(
        delivered: false,
        message: 'Resend failed — check your connection and try again.',
      );
    }
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
      final res = await http.post(
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
          final delivered = results
              .whereType<Map>()
              .where((r) => r['delivered'] == true)
              .length;
          return BulkResendOutcome(
            delivered: delivered,
            processed: (result['processed'] as num?)?.toInt() ?? results.length,
            skipped: (result['skipped'] as num?)?.toInt() ?? 0,
            message: 'Resent to $delivered of ${results.length}.',
          );
        }
      }
      return BulkResendOutcome(
        delivered: 0,
        processed: 0,
        skipped: 0,
        message: _errorMessage(res, 'Bulk resend failed (${res.statusCode}).'),
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
  String _errorMessage(http.Response res, String fallback) {
    try {
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final err = decoded['error'];
      if (err is Map && err['message'] != null) {
        return err['message'].toString();
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

  const ResendOutcome({required this.delivered, required this.message});
}

/// Outcome of a bulk resend.
class BulkResendOutcome {
  final int delivered;
  final int processed;
  final int skipped;
  final String message;

  const BulkResendOutcome({
    required this.delivered,
    required this.processed,
    required this.skipped,
    required this.message,
  });
}
