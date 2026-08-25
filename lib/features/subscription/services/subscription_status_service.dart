import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'payfast_service.dart';

/// Immutable snapshot of a user's subscription state as stored on
/// `users/{uid}`.
class UserSubscription {
  final SubscriptionStatus status;
  final SubscriptionTier? tier;

  /// End of the current trial / start of paid billing.
  final DateTime? trialEndsAt;

  /// Next recurring billing date (set by the ITN handler on activation).
  final DateTime? renewalDate;

  /// The promo code applied at checkout (empty when none).
  final String promoCode;

  const UserSubscription({
    this.status = SubscriptionStatus.none,
    this.tier,
    this.trialEndsAt,
    this.renewalDate,
    this.promoCode = '',
  });

  bool get isActive => status == SubscriptionStatus.active;
  bool get isInTrial => status == SubscriptionStatus.trial;
  bool get hasSubscription => isActive || isInTrial;

  /// Days remaining in the trial (0 when not in trial / expired).
  int trialDaysRemaining(DateTime now) {
    if (!isInTrial || trialEndsAt == null) return 0;
    final remaining = trialEndsAt!.difference(now).inDays;
    return remaining < 0 ? 0 : remaining;
  }

  static UserSubscription fromMap(Map<String, dynamic>? data) {
    if (data == null) return const UserSubscription();
    return UserSubscription(
      status: SubscriptionStatus.fromString(data['subscriptionStatus'] as String?),
      tier: data['subscriptionTier'] == null
          ? null
          : SubscriptionTier.fromString(data['subscriptionTier'] as String?),
      trialEndsAt: _toDate(data['subscriptionTrialEndsAt']),
      renewalDate: _toDate(data['subscriptionRenewalDate']),
      promoCode: (data['subscriptionPromoCode'] as String?) ?? '',
    );
  }

  static DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
    return null;
  }
}

/// Reads / writes the user's subscription state on `users/{uid}`.
///
/// The authoritative activation write (`subscriptionStatus: 'active'` +
/// renewal date) is performed server-side by the `payfastSubscriptionITN`
/// Cloud Function; this service owns the client-side trial marker write (so
/// the UI reflects the trial immediately after checkout) and the reactive
/// status stream the subscription screen listens to.
class SubscriptionStatusService {
  SubscriptionStatusService._();
  static final SubscriptionStatusService instance = SubscriptionStatusService._();

  /// Test seams (same pattern as the other services).
  @visibleForTesting
  static FirebaseFirestore? firestoreForTesting;

  @visibleForTesting
  static String? Function()? currentUserIdResolverForTesting;

  /// Seam for the cancellation HTTP call so widget/unit tests can substitute
  /// a fake without a live network. Returns the raw response when the
  /// endpoint answered, `null` when it is unreachable (transport error / no
  /// Firebase app / no ID token).
  @visibleForTesting
  static Future<http.Response?> Function(String userId, String idToken)?
      cancellationInvokerForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    firestoreForTesting = null;
    currentUserIdResolverForTesting = null;
    cancellationInvokerForTesting = null;
  }

  FirebaseFirestore get _db {
    final override = firestoreForTesting;
    if (override != null) return override;
    return FirebaseFirestore.instance;
  }

  String? get _uid {
    final resolver = currentUserIdResolverForTesting;
    if (resolver != null) return resolver();
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null; // [core/no-app] during cold-launch / widget tests
    }
  }

  /// Reactive stream of the current user's subscription state. Emits the
  /// empty state for an unauthenticated caller or on a hard stream error.
  Stream<UserSubscription> watchMySubscription() {
    final uid = _uid;
    if (uid == null) return Stream.value(const UserSubscription());
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snap) => UserSubscription.fromMap(snap.data()))
        .handleError((Object e) {
      debugPrint('SubscriptionStatusService.watchMySubscription error: $e');
    });
  }

  /// One-shot read of the current user's subscription state.
  Future<UserSubscription> getMySubscription() async {
    final uid = _uid;
    if (uid == null) return const UserSubscription();
    try {
      final snap = await _db.collection('users').doc(uid).get();
      return UserSubscription.fromMap(snap.data());
    } catch (e) {
      debugPrint('SubscriptionStatusService.getMySubscription error: $e');
      return const UserSubscription();
    }
  }

  /// Marks the start of the 30-day free trial on the user's profile after a
  /// successful checkout launch. The ITN handler later flips the status to
  /// `active` (or `cancelled`) — this write only records the trial window +
  /// the intended tier so the UI reflects the pending subscription
  /// immediately. The `users/{uid}` rules already allow owner writes.
  Future<void> markTrialStarted({
    required SubscriptionTier tier,
    String promoCode = '',
    DateTime? now,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('No signed-in user');
    final start = now ?? DateTime.now();
    await _db.collection('users').doc(uid).set({
      'subscriptionStatus': SubscriptionStatus.trial.key,
      'subscriptionTier': tier.key,
      'subscriptionTrialEndsAt':
          Timestamp.fromDate(PayFastService.trialEndDate(start)),
      'subscriptionPromoCode': promoCode,
      'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// The HTTPS cancellation endpoint deployed alongside the subscription
  /// ITN webhook (see `functions/src/index.ts` `cancelSubscription`).
  static String get cancelSubscriptionUrl =>
      'https://us-central1-jagspoor.cloudfunctions.net/cancelSubscription';

  /// Cancels the current user's subscription by invoking the deployed
  /// cancellation endpoint with the caller's Firebase ID token, which
  /// terminates the PayFast recurring billing token server-side
  /// (fail-closed) and flips `users/{uid}.subscriptionStatus` to
  /// `cancelled`.
  ///
  /// Falls back to a direct `users/{uid}` owner write ONLY when the endpoint
  /// is unreachable (e.g. not yet deployed in a dev environment) so the
  /// user's billing intent is still recorded; an endpoint that ANSWERS with
  /// an error (e.g. 502 when PayFast does not acknowledge the termination)
  /// throws instead, so billing is never silently marked cancelled without
  /// the token being terminated.
  ///
  /// Returns `true` on success; throws a `StateError` for an unauthenticated
  /// caller and a `CancellationException` when the endpoint rejects the
  /// request / cannot confirm PayFast termination.
  Future<bool> cancelSubscription() async {
    final uid = _uid;
    if (uid == null) throw StateError('No signed-in user');

    final response = await _invokeCancelEndpoint(uid);
    if (response != null) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      throw CancellationException(
        'The cancellation service rejected the request '
        '(HTTP ${response.statusCode}). Please try again.',
      );
    }

    // Endpoint unreachable / not deployed in the dev environment: record the
    // cancellation intent via the owner-write path (the token termination
    // itself still requires the deployed endpoint).
    await _db.collection('users').doc(uid).set({
      'subscriptionStatus': SubscriptionStatus.cancelled.key,
      'subscriptionCancelledAt': Timestamp.now(),
      'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  }

  /// Invokes the deployed cancellation endpoint. Returns the raw [http.Response]
  /// when the endpoint answered, `null` when it is unreachable (transport
  /// error / no Firebase app / no ID token available).
  Future<http.Response?> _invokeCancelEndpoint(String uid) async {
    final invoker = cancellationInvokerForTesting;
    if (invoker != null) {
      return invoker(uid, 'test-token');
    }
    String idToken;
    try {
      idToken = await FirebaseAuth.instance.currentUser?.getIdToken() ?? '';
    } catch (_) {
      return null; // [core/no-app] during cold-launch / widget tests.
    }
    if (idToken.isEmpty) return null;
    try {
      return await http.post(
        Uri.parse(cancelSubscriptionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'userId': uid}),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Signal raised by [SubscriptionStatusService.cancelSubscription] when the
/// backend cannot confirm the PayFast token termination (the subscription is
/// NOT marked cancelled — the user may safely retry).
class CancellationException implements Exception {
  final String message;
  const CancellationException(this.message);
  @override
  String toString() => 'CancellationException: $message';
}
