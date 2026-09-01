import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'subscription_pricing.dart';

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
/// With Google Play Billing the *authoritative* subscription status lives in
/// the Google Play store; this service mirrors it onto `users/{uid}` so the
/// app's own UI, role gating, and dashboards can read it reactively:
///  - activation / renewal is written from the Play Billing purchase stream
///    (see [recordPlayPurchase] / [recordTrialStarted]);
///  - `subscriptionStatus: 'active'` + `subscriptionRenewalDate` are derived
///    from the Play receipt / renewal date;
///  - cancellation / pausing happens inside Google Play — the Play purchase
///    stream reflects the new state and this service records it.
class SubscriptionStatusService {
  SubscriptionStatusService._();
  static final SubscriptionStatusService instance = SubscriptionStatusService._();

  /// Test seams (same pattern as the other services).
  @visibleForTesting
  static FirebaseFirestore? firestoreForTesting;

  @visibleForTesting
  static String? Function()? currentUserIdResolverForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    firestoreForTesting = null;
    currentUserIdResolverForTesting = null;
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

  /// Marks the start of the free trial on the user's profile.
  ///
  /// With Google Play Billing the free-trial offer itself is configured in
  /// the Play Console (a per-product promo/offer linked to the subscription);
  /// this write records the trial window + tier on `users/{uid}` so the UI
  /// reflects the trial immediately after a successful Play purchase. The
  /// `users/{uid}` rules already allow owner writes.
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
      'subscriptionTrialEndsAt': Timestamp.fromDate(
        start.add(const Duration(days: SubscriptionTrial.trialDays)),
      ),
      'subscriptionPromoCode': promoCode,
      'subscriptionProvider': 'google_play_billing',
      'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Records an active Play Billing purchase on `users/{uid}`.
  ///
  /// Writes the mirrored entitlement (live google_play_billing provider) so
  /// the app's SSR stream + dashboards read it consistently.
  Future<void> recordPlayPurchase({
    required SubscriptionTier tier,
    String purchaseToken = '',
    DateTime? renewalDate,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('No signed-in user');
    await _db.collection('users').doc(uid).set({
      'subscriptionStatus': SubscriptionStatus.active.key,
      'subscriptionTier': tier.key,
      'subscriptionProvider': 'google_play_billing',
      'subscriptionPlayPurchaseToken': purchaseToken,
      if (renewalDate != null)
        'subscriptionRenewalDate': Timestamp.fromDate(renewalDate),
      'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Records a cancellation after the Play store reports the subscription was
  /// cancelled / paused (reflected by the Play purchase stream).
  Future<void> recordPlayCancellation() async {
    final uid = _uid;
    if (uid == null) throw StateError('No signed-in user');
    await _db.collection('users').doc(uid).set({
      'subscriptionStatus': SubscriptionStatus.cancelled.key,
      'subscriptionCancelledAt': Timestamp.now(),
      'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
