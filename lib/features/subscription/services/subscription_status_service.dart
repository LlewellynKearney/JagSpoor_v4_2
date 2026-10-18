import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/offline_stream_guard.dart';
import '../../../services/entitlement_service.dart'
    show trialEndFieldAliases, trialStartFieldAliases, SubscriptionSource;
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

  /// The billing platform that granted the subscription — `'google_play'` or
  /// `'payfast'`, else `null` when unknown. Read from the server-owned
  /// `subscriptionPlatform` field (alias-tolerant), falling back to the
  /// canonical `subscriptionSource`. This is the Play-policy switch: a
  /// Play-billed subscriber must be routed to Google Play's subscriptions
  /// manager, never to an external website checkout.
  final String? platform;

  /// The server-owned `subscriptionProduct` (the plan id, e.g.
  /// `hunter_monthly` / `outfitter_yearly`, or a Play product id). Used to
  /// mark the ACTIVE plan card ("YOUR TIER") so an existing subscriber sees
  /// which of the two plans they are on. Empty when the field is absent.
  final String planId;

  const UserSubscription({
    this.status = SubscriptionStatus.none,
    this.tier,
    this.trialEndsAt,
    this.renewalDate,
    this.promoCode = '',
    this.platform,
    this.planId = '',
  });

  bool get isActive => status == SubscriptionStatus.active;
  bool get isInTrial => status == SubscriptionStatus.trial;
  bool get hasSubscription => isActive || isInTrial;

  /// Whether this subscription is billed by Google Play (route to the Play
  /// subscriptions manager; never show an external website checkout link).
  bool get isPlayBilled =>
      platform == SubscriptionSource.googlePlay ||
      platform == 'google_play_billing';

  /// Whether this subscription is billed via the PayFast website checkout (the
  /// only case where a "Manage subscription on website" affordance is
  /// policy-compliant).
  bool get isPayfastBilled => platform == SubscriptionSource.payfast;

  /// The billing cycle the active subscription bills on, resolved from the
  /// server-owned plan id. `'yearly'` when the plan id names an annual plan
  /// (`hunter_yearly` / `outfitter_yearly` / any id containing `year`),
  /// otherwise `'monthly'`. Returns `null` when there is no plan id on file
  /// (legacy docs / a not-yet-mirrored purchase), so the UI can avoid
  /// mis-claiming which card is the subscriber's.
  String? get activeCycle {
    final id = planId.trim().toLowerCase();
    if (id.isEmpty) return null;
    return id.contains('year') ? 'yearly' : 'monthly';
  }

  /// Whether the given [cycle] (`'monthly'` / `'yearly'`) is the plan the
  /// active subscription is on. False when no plan id is on file, so no card
  /// is wrongly badged.
  bool isActiveCycle(String cycle) {
    final active = activeCycle;
    if (active == null) return false;
    return active == cycle.trim().toLowerCase();
  }

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
      platform: _resolvePlatform(data),
      planId: _resolvePlanId(data),
    );
  }

  /// Resolves the server-owned plan id, tolerating the documented aliases.
  /// The canonical `subscriptionProduct` (written by `writeEntitlement` on a
  /// Play or PayFast grant) wins; the snake_case / `plan` / `billingCycle`
  /// spellings are accepted for legacy / third-party-written docs.
  static String _resolvePlanId(Map<String, dynamic> data) {
    for (final raw in <dynamic>[
      data['subscriptionProduct'],
      data['subscription_product'],
      data['planId'],
      data['plan'],
      data['billingCycle'],
    ]) {
      final value = (raw ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// Resolves the billing platform from the raw document, preferring the
  /// explicit `subscriptionPlatform` field (alias-tolerant) and falling back
  /// to `subscriptionSource` / `subscriptionProvider`. Returns `null` when none
  /// of them names a recognized platform.
  static String? _resolvePlatform(Map<String, dynamic> data) {
    for (final raw in <dynamic>[
      data['subscriptionPlatform'],
      data['subscription_platform'],
      data['billingPlatform'],
      data['subscriptionSource'],
      data['subscription_source'],
      data['subscriptionProvider'],
      data['subscription_provider'],
    ]) {
      final value = (raw ?? '').toString().trim().toLowerCase();
      if (value == SubscriptionSource.googlePlay ||
          value == 'google_play_billing' ||
          value.startsWith('google_play')) {
        return SubscriptionSource.googlePlay;
      }
      if (value == SubscriptionSource.payfast || value.startsWith('payfast')) {
        return SubscriptionSource.payfast;
      }
    }
    return null;
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

  /// Counts how many times [watchMySubscription] has built a Firestore
  /// subscription. A screen must build this ONCE per State (caching the
  /// stream), never on every `build()`; a rising count across a rebuild is the
  /// exact regression that flickered the subscription screen back to the empty
  /// selector state. Test-only.
  @visibleForTesting
  static int watchMySubscriptionCalls = 0;

  /// Optional override for [watchMySubscription] (tests only). Lets a test
  /// supply a *delayed* stream so the screen's first frame is provably driven
  /// by the one-shot seed rather than the stream's initial snapshot.
  @visibleForTesting
  static Stream<UserSubscription> Function()? streamForTesting;

  /// Optional override for [getMySubscription] (tests only).
  @visibleForTesting
  static Future<UserSubscription> Function()? oneShotForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    firestoreForTesting = null;
    currentUserIdResolverForTesting = null;
    watchMySubscriptionCalls = 0;
    streamForTesting = null;
    oneShotForTesting = null;
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
  ///
  /// The Firestore `snapshots()` subscription is wrapped in
  /// [OfflineStreamGuard.offlineResilient] so a hard error (a missing
  /// composite index, a permissions change, or an unrecoverable network
  /// error with nothing in cache) serves a defined empty emission and
  /// **completes** instead of hanging. The previous `.handleError` form was a
  /// silent trap: `Stream.handleError` ignores the callback's return value, so
  /// the error was discarded and the stream never emitted — leaving the
  /// consuming `StreamBuilder` stuck in `ConnectionState.waiting` and the
  /// subscription screen rendering its empty "NO ACTIVE SUBSCRIPTION" state
  /// forever (the "stays on the selector" symptom).
  Stream<UserSubscription> watchMySubscription() {
    watchMySubscriptionCalls++;
    final override = streamForTesting;
    if (override != null) return override();
    final uid = _uid;
    if (uid == null) return Stream.value(const UserSubscription());
    return OfflineStreamGuard.offlineResilient(
      _db
          .collection('users')
          .doc(uid)
          .snapshots()
          .map((snap) => UserSubscription.fromMap(snap.data())),
      fallback: const UserSubscription(),
      debugLabel: 'watchMySubscription',
    );
  }

  /// One-shot read of the current user's subscription state.
  Future<UserSubscription> getMySubscription() async {
    final override = oneShotForTesting;
    if (override != null) return override();
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
  /// the promo code (`subscriptionPromoCode`) and the provider
  /// (`subscriptionProvider`). It deliberately does NOT write any trial
  /// timestamp, the status, OR the tier — all of those are frozen in
  /// `firestore.rules` (v1.0.12 hotfix froze `subscriptionTier`; a client write
  /// of it is rejected). Callers should treat the trial window + tier as
  /// server-provisioned (read back from `users/{uid}`).
  Future<void> markTrialStarted({
    required SubscriptionTier tier,
    String promoCode = '',
    DateTime? now,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('No signed-in user');
    await _db.collection('users').doc(uid).set({
      // Client-owned metadata only — the trial window, status and tier are
      // frozen and provisioned by the backend trigger / Cloud Functions.
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
