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

  /// Marks the start of the free trial on the user's profile.
  ///
  /// With Google Play Billing the free-trial offer itself is configured in
  /// the Play Console (a per-product promo/offer linked to the subscription);
  /// this write records the trial window + tier on `users/{uid}` so the UI
  /// reflects the trial immediately after a successful Play purchase. The
  /// `users/{uid}` rules already allow owner writes.
  ///
  /// **Schema unification (TODO #5)**: two signup paths previously wrote
  /// DIFFERENT field layouts — the backend `initializeNewUserTrial` trigger
  /// writes `trialEndsAt` / `trialStart` / `subscriptionSource: 'trial'` /
  /// `requiresPayment`, while this client write historically wrote only
  /// `subscriptionTrialEndsAt` / `subscriptionProvider`. A doc from either
  /// path alone could therefore fail the entitlement read. This method now
  /// writes BOTH timestamp schemas (`trialStart`/`trialEnd`/`trialStartedAt`/
  /// `trialEndsAt` AND `subscriptionTrialEndsAt`/`subscriptionTrialStart`)
  /// plus the canonical `subscriptionStatus`, so every reader — the
  /// entitlement gate, the dashboards, and any legacy consumer — resolves the
  /// trial regardless of which spelling it checks.
  ///
  /// NOTE: the server-owned fields (`isPremium`, `subscriptionSource`,
  /// `premiumExpiry`, `entitlementUpdatedAt`) are deliberately NOT written
  /// here. `firestore.rules` uses field-level CHANGE DETECTION to keep them
  /// backend-only, so a client write would be rejected; the
  /// `initializeNewUserTrial` trigger owns them (Admin SDK, bypasses rules).
  Future<void> markTrialStarted({
    required SubscriptionTier tier,
    String promoCode = '',
    DateTime? now,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('No signed-in user');
    final start = now ?? DateTime.now();
    final end = start.add(trialDuration);
    await _db.collection('users').doc(uid).set({
      // --- Backend-trigger schema (trialEndsAt / trialStart) ---
      'trialStartedAt': Timestamp.fromDate(start),
      'trialStart': Timestamp.fromDate(start),
      'trialEndsAt': Timestamp.fromDate(end),
      'trialEnd': Timestamp.fromDate(end),
      // --- Client markTrialStarted schema (subscriptionTrialEndsAt) ---
      'subscriptionTrialEndsAt': Timestamp.fromDate(end),
      'subscriptionTrialStart': Timestamp.fromDate(start),
      // --- Shared status / tier / provider ---
      'subscriptionStatus': subscriptionStatusTrial,
      'subscriptionTier': tier.key,
      'subscriptionPromoCode': promoCode,
      'subscriptionProvider': 'google_play_billing',
      'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Migration helper (TODO #5): backfills the MISSING trial-schema aliases on
  /// an existing `users/{uid}` document so a doc created by the OTHER signup
  /// path resolves under every reader.
  ///
  /// Called on login / boot. Only the trial-timestamp aliases + the canonical
  /// `subscriptionStatus` are written — the server-owned fields
  /// (`isPremium`, `subscriptionSource`, `premiumExpiry`,
  /// `entitlementUpdatedAt`) are NEVER touched (they are frozen by
  /// `firestore.rules` change-detection and owned by Cloud Functions).
  ///
  /// Best-effort and idempotent: when no trial timestamps are present at all
  /// nothing is written; when the alias fields already exist nothing changes.
  /// Returns `true` when a backfill write was performed.
  Future<bool> backfillTrialSchemaAliases() async {
    final uid = _uid;
    if (uid == null) return false;
    final ref = _db.collection('users').doc(uid);
    final Map<String, dynamic> data;
    try {
      final snap = await ref.get();
      data = snap.data() ?? const <String, dynamic>{};
    } catch (e) {
      debugPrint('SubscriptionStatusService.backfillTrialSchemaAliases read failed: $e');
      return false;
    }
    if (data.isEmpty) return false;

    // Resolve the existing trial window from either schema.
    DateTime? start;
    DateTime? end;
    for (final key in trialStartFieldAliases) {
      start ??= _toDate(data[key]);
    }
    for (final key in trialEndFieldAliases) {
      end ??= _toDate(data[key]);
    }
    if (start == null && end == null) return false; // no trial on file

    final status =
        (data['subscriptionStatus'] ?? '').toString().trim().toLowerCase();
    final trialStatus = const {'trial', 'trialing', 'trialling', 'trial_active'}
        .contains(status);

    final patch = <String, dynamic>{};
    if (start != null) {
      final ts = Timestamp.fromDate(start);
      for (final key in trialStartFieldAliases) {
        if (data[key] == null) patch[key] = ts;
      }
    }
    if (end != null) {
      final ts = Timestamp.fromDate(end);
      for (final key in trialEndFieldAliases) {
        if (data[key] == null) patch[key] = ts;
      }
    }
    // Normalize a known trial status to the canonical `'trialing'` value, and
    // stamp that status onto a doc that carries a STILL-VALID trial window but
    // no status at all (the backend-trigger schema). An expired window is left
    // alone rather than mislabelled `'trialing'` — the timestamp already
    // governs access.
    if (trialStatus && status != subscriptionStatusTrial) {
      patch['subscriptionStatus'] = subscriptionStatusTrial;
    } else if (status.isEmpty &&
        end != null &&
        end.isAfter(DateTime.now())) {
      patch['subscriptionStatus'] = subscriptionStatusTrial;
    }
    if (patch.isEmpty) return false;

    try {
      await ref.set(patch, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('SubscriptionStatusService.backfillTrialSchemaAliases write failed: $e');
      return false;
    }
  }

  static DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
    return null;
  }
}
