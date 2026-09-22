import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../services/entitlement_service.dart' show trialEndFieldAliases, trialStartFieldAliases;
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
      // Schema-tolerant: accept EITHER signup path's trial-end spelling
      // (`subscriptionTrialEndsAt` from the client write, `trialEndsAt` from
      // the backend trigger). See `trialEndFieldAliases`.
      trialEndsAt: _resolveTrialEnd(data),
      renewalDate: _toDate(data['subscriptionRenewalDate']),
      promoCode: (data['subscriptionPromoCode'] as String?) ?? '',
    );
  }

  /// First present trial-end timestamp across every documented alias.
  static DateTime? _resolveTrialEnd(Map<String, dynamic> data) {
    for (final key in trialEndFieldAliases) {
      final value = _toDate(data[key]);
      if (value != null) return value;
    }
    return null;
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

  /// Records the trial TIER / promo metadata on the user's profile.
  ///
  /// **Server-owned trial window (v9)**: the trial timestamps
  /// (`trialEndsAt` / `trialStart` / `trialStartedAt` / `trialEnd` /
  /// `subscriptionTrialEndsAt` / `subscriptionTrialStart`) and the
  /// `subscriptionStatus` are FROZEN in `firestore.rules` — they may only be
  /// written by Cloud Functions (Admin SDK) to prevent trial abuse via
  /// client-writable timestamps. The authoritative trial provisioner is the
  /// backend `initializeNewUserTrial` Auth `onCreate` trigger, which stamps
  /// the full trial window on account creation.
  ///
  /// This method therefore writes ONLY the fields the client still owns:
  /// the tier (`subscriptionTier`), the promo code (`subscriptionPromoCode`)
  /// and the provider (`subscriptionProvider`). It deliberately does NOT
  /// write any trial timestamp or the status — a client write of a frozen
  /// field is rejected by the rules. Callers should treat the trial window as
  /// server-provisioned (read back from `users/{uid}`).
  Future<void> markTrialStarted({
    required SubscriptionTier tier,
    String promoCode = '',
    DateTime? now,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('No signed-in user');
    await _db.collection('users').doc(uid).set({
      // Client-owned metadata only — the trial window + status are frozen
      // and provisioned by the backend trigger.
      'subscriptionTier': tier.key,
      'subscriptionPromoCode': promoCode,
      'subscriptionProvider': 'google_play_billing',
      'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Trial-schema migration (TODO #5).
  ///
  /// **Disabled client-side in v9.** The trial-window aliases
  /// (`trialEndsAt` / `trialStart` / `subscriptionTrialEndsAt` / …) and
  /// `subscriptionStatus` are FROZEN in `firestore.rules` (only the Admin SDK
  /// may write them — trial-abuse prevention). A client backfill of those
  /// aliases would therefore be rejected with PERMISSION_DENIED. The schema
  /// unification it performed is now the responsibility of the backend:
  /// `initializeNewUserTrial` stamps the full trial window on every new
  /// account, and a one-off Admin-SDK migration can heal legacy docs.
  ///
  /// Retained as a no-op so existing call sites (login / boot) keep
  /// compiling; it performs no write and always returns `false`. Use
  /// [readTrialState] to inspect a doc's trial window.
  Future<bool> backfillTrialSchemaAliases() async => false;

  /// Reads the current trial window (`start`/`end`) from `users/{uid}`,
  /// tolerating every documented alias. Best-effort — returns `(null, null)`
  /// on a missing doc / read error. Read-only (no frozen-field write).
  Future<({DateTime? start, DateTime? end})> readTrialState() async {
    final uid = _uid;
    if (uid == null) return (start: null, end: null);
    final Map<String, dynamic> data;
    try {
      final snap = await _db.collection('users').doc(uid).get();
      data = snap.data() ?? const <String, dynamic>{};
    } catch (e) {
      debugPrint('SubscriptionStatusService.readTrialState failed: $e');
      return (start: null, end: null);
    }
    DateTime? start;
    DateTime? end;
    for (final key in trialStartFieldAliases) {
      start ??= _toDate(data[key]);
    }
    for (final key in trialEndFieldAliases) {
      end ??= _toDate(data[key]);
    }
    return (start: start, end: end);
  }

  static DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
    return null;
  }
}
