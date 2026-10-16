import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../services/entitlement_service.dart';
import 'play_billing_service.dart';
import 'subscription_pricing.dart';

/// Name of the Firestore collection that records Google Play purchases.
const String purchasesCollection = 'purchases';

/// The `purchases/{id}` status value recorded for a verified / active purchase.
const String purchaseStatusActive = 'active';

/// Outcome of reconciling the `purchases` collection into the entitlement.
///
/// See [PlayPurchaseRecorder.reconcileEntitlementFromPurchases]. The flag the
/// UI actually gates on is the SERVER-written `users/{uid}` mirror — this
/// result only reports what the local sync observed.
class PurchaseReconciliation {
  /// True when at least one `purchases` document owned by the caller carries
  /// [purchaseStatusActive].
  final bool hasActivePurchase;

  /// The product id of the active purchase used for the grant (`null` when no
  /// row existed or every row carried a blank product id — junk rows).
  final String? productId;

  /// True when the server confirmed the purchase and therefore wrote the
  /// authoritative entitlement (`subscriptionStatus: 'active'`,
  /// `isPremium`, `premiumExpiry`, `hasActivePurchase`).
  final bool premiumGranted;

  const PurchaseReconciliation({
    this.hasActivePurchase = false,
    this.productId,
    this.premiumGranted = false,
  });

  /// No active purchase / no signed-in user.
  static const PurchaseReconciliation none = PurchaseReconciliation();

  @override
  String toString() => 'PurchaseReconciliation(hasActivePurchase: '
      '$hasActivePurchase, productId: $productId, '
      'premiumGranted: $premiumGranted)';
}

/// Records completed Google Play subscription purchases onto Firestore.
///
/// Google Play Billing is the charge truth, but the app's own screens need a
/// durable, queryable record of the transaction — and `users/{uid}` must
/// reflect the new entitlement so the paywall / role gates unlock without a
/// cold restart. This service is that single write path:
///
///  * `users/{uid}` is merge-updated with `subscriptionTier`,
///    `subscriptionStatus: 'active'` and `isPro: true`;
///  * one `purchases/{id}` document is created per transaction carrying
///    `uid`, `productId`, `purchaseToken` and `status`.
///
/// It listens to [PlayBillingService.purchaseStream] — which also delivers
/// **restored** purchases — so a subscriber on a new device re-syncs
/// automatically. Listening is idempotent: [startListening] attaches at most
/// one subscription per process, so it is safe to call from every
/// subscription surface (paywall, subscription screen, dashboards).
///
/// **`itemAlreadyOwned` recovery.** When Google Play reports
/// `BillingResponse.itemAlreadyOwned` (the user already holds the
/// subscription — e.g. re-subscribing on a device where the entitlement was
/// never linked), that is NOT a purchase failure. The recorder restores the
/// existing purchase, acknowledges it, and grants the premium entitlement
/// server-side (see [_recoverAlreadyOwned]) instead of logging a purchase
/// error.
class PlayPurchaseRecorder {
  PlayPurchaseRecorder._();
  static final PlayPurchaseRecorder instance = PlayPurchaseRecorder._();

  /// Test seams (mirrors the other billing / Firestore services).
  @visibleForTesting
  static FirebaseFirestore? firestoreForTesting;

  @visibleForTesting
  static String? Function()? currentUserIdResolverForTesting;

  /// Test seam: replaces the Play purchase stream so the recording path can be
  /// exercised without the `in_app_purchase` platform plugin.
  @visibleForTesting
  static Stream<List<PurchaseDetails>>? purchaseStreamForTesting;

  /// Test seam: replaces the premium grant performed after an
  /// `itemAlreadyOwned` recovery so the entitlement outcome is assertable
  /// without a live Cloud Function.
  @visibleForTesting
  static Future<bool> Function({
    required String productId,
    String? purchaseToken,
  })? premiumSetterForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    firestoreForTesting = null;
    currentUserIdResolverForTesting = null;
    purchaseStreamForTesting = null;
    premiumSetterForTesting = null;
    instance._subscription?.cancel();
    instance._subscription = null;
    instance._started = false;
  }

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _started = false;

  FirebaseFirestore get _db {
    final override = firestoreForTesting;
    if (override != null) return override;
    return FirebaseFirestore.instance;
  }

  /// The signed-in uid, or null when there is no Firebase app / session
  /// (cold-launch race, widget-test host). Never throws.
  String? get _uid {
    final resolver = currentUserIdResolverForTesting;
    if (resolver != null) return resolver();
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Whether a purchase listener is currently attached.
  @visibleForTesting
  bool get isListening => _started;

  /// Attaches the purchase listener (at most once per process). A missing
  /// billing plugin — e.g. a widget-test host — degrades silently so callers
  /// can wire this from `initState` unconditionally.
  void startListening() {
    if (_started) return;
    _started = true;
    try {
      final stream =
          purchaseStreamForTesting ?? PlayBillingService.instance.purchaseStream;
      _subscription = stream.listen(
        _onPurchases,
        onError: (Object e) =>
            debugPrint('PlayPurchaseRecorder purchase stream error: $e'),
      );
    } catch (e) {
      debugPrint('PlayPurchaseRecorder.startListening failed: $e');
    }
  }

  /// Detaches the listener (used by tests / sign-out flows).
  Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final active = purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored;
      if (!active) {
        if (purchase.status == PurchaseStatus.error) {
          // `itemAlreadyOwned` is NOT an error — the store is telling us the
          // subscription is already held. Recover it (restore + acknowledge +
          // grant premium) instead of logging a purchase error.
          if (PlayBillingErrors.isItemAlreadyOwned(purchase.error)) {
            await _recoverAlreadyOwned(purchase.productID);
          } else {
            debugPrint('PlayPurchaseRecorder purchase error: ${purchase.error}');
          }
        }
        continue;
      }
      await recordPurchase(
        productId: purchase.productID,
        purchaseToken: purchase.verificationData.serverVerificationData,
      );
      // NOTE: completing the Play transaction is deliberately left to the
      // caller (the subscription screen finishes it after the server-side
      // verification round-trip). The recorder only persists the record.
    }
  }

  /// Recovers a subscription the store reports as already owned.
  ///
  /// Sequence (mirrors the requested fix):
  ///  1. Ask Google Play to replay prior purchases
  ///     ([PlayBillingService.restorePurchases]).
  ///  2. Query the store for the live purchase
  ///     ([PlayBillingService.queryPastPurchases] / [findExistingPurchase]).
  ///  3. Acknowledge it ([PlayBillingService.completePurchase]) so the store
  ///     stops holding the transaction.
  ///  4. Grant the premium entitlement
  ///     ([EntitlementService.setPremium]) — server-authoritative, so the
  ///     entitlement is written by the Cloud Function exactly as it is for a
  ///     fresh purchase.
  ///
  /// Every step is best-effort: a missing session / token or a store error
  /// leaves the existing (cached) entitlement in place rather than throwing.
  Future<void> _recoverAlreadyOwned(String productId) async {
    debugPrint(
      'PlayPurchaseRecorder: subscription already owned, restoring '
      '(product $productId).',
    );
    // 1) Ask the store to replay prior purchases.
    await PlayBillingService.instance.restorePurchases();
    // 2) Find the existing purchase for this product.
    final existing =
        await PlayBillingService.instance.findExistingPurchase(productId);
    if (existing == null) {
      debugPrint(
        'PlayPurchaseRecorder: itemAlreadyOwned for $productId but the store '
        'returned no live purchase — nothing to acknowledge.',
      );
      return;
    }
    // 3) Acknowledge the existing transaction so it is not held open.
    await PlayBillingService.instance.completePurchase(existing);
    // 4) Grant the premium entitlement server-side.
    final token = existing.verificationData.serverVerificationData;
    final granted = await _setPremium(productId: productId, token: token);
    // 5) Record the transaction so the purchase history is complete.
    if (token.isNotEmpty) {
      await recordPurchase(productId: productId, purchaseToken: token);
    }
    debugPrint(
      'PlayPurchaseRecorder: restored already-owned $productId — premium '
      '${granted ? 'granted' : 'pending server confirmation'}.',
    );
  }

  /// Delegates the premium grant to [EntitlementService.setPremium] (or the
  /// recorder-level test seam when one is installed).
  Future<bool> _setPremium({
    required String productId,
    required String token,
  }) async {
    final override = premiumSetterForTesting;
    if (override != null) {
      return override(productId: productId, purchaseToken: token);
    }
    return EntitlementService.instance.setPremium(
      productId: productId,
      purchaseToken: token,
    );
  }

  /// Writes the transaction record to `purchases/{uid}_{productId}`.
  ///
  /// **v1.0.12 hotfix:** the recorder no longer mirrors the entitlement onto
  /// `users/{uid}` (`subscriptionStatus` / `isPro` / `subscriptionTier`). Those
  /// fields are server-owned (see `firestore.rules`), and the authoritative
  /// entitlement is written by the `validateGooglePlayPurchase` Cloud Function.
  /// A client write of those fields is now rejected with PERMISSION_DENIED, so
  /// the recorder's only job is the durable, owner-scoped transaction record.
  ///
  /// Returns `true` when the `purchases` document was written. A missing
  /// session (or an offline / rules-denied Firestore) resolves `false` and is
  /// logged — the Play transaction is still acknowledged by the caller so the
  /// store never keeps re-delivering it indefinitely.
  Future<bool> recordPurchase({
    required String productId,
    required String purchaseToken,
    String status = purchaseStatusActive,
  }) async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('PlayPurchaseRecorder: no signed-in user — purchase not '
          'recorded (product $productId).');
      return false;
    }
    // A blank product id can never be verified server-side (the Play Developer
    // API rejects it) and it is exactly the junk-row shape observed in the
    // live `purchases` collection. Refuse it here so no new junk row is
    // written; `reconcileEntitlementFromPurchases` skips legacy ones.
    if (productId.trim().isEmpty) {
      debugPrint('PlayPurchaseRecorder: refusing to record a purchase with a '
          'blank productId (uid $uid).');
      return false;
    }
    final tier = SubscriptionTier.fromPlayProductId(productId);
    try {
      // Persist the transaction itself (one document per uid + product id so a
      // repeated delivery of the same token cannot create duplicates). The
      // entitlement is written server-side by `validateGooglePlayPurchase`.
      await _db
          .collection(purchasesCollection)
          .doc('${uid}_$productId')
          .set({
        'uid': uid,
        'productId': productId,
        'purchaseToken': purchaseToken,
        'status': status,
        'tier': tier.key,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('PlayPurchaseRecorder.recordPurchase failed: $e');
      return false;
    }
  }

  /// Reconciles the `purchases` collection into the entitlement — the
  /// "users collection not synced from purchases collection" fix.
  ///
  /// Called on app start and on every auth-state change (see
  /// [syncEntitlementFromPurchases] / `main.dart`). The `purchases`
  /// collection is the durable, owner-scoped record of what Google Play
  /// actually charged for, so it is the source of truth used to repair a
  /// `users/{uid}` document that was never mirrored (a dropped purchase
  /// stream delivery, an install that predates the recorder, or a Cloud
  /// Function round-trip that failed).
  ///
  /// Steps:
  ///  1. Read `purchases` where `uid == currentUid` and `status == 'active'`
  ///     (ordered client-side so no composite index is required).
  ///  2. Ignore junk rows (blank `productId` / `purchaseToken`) — a row that
  ///     cannot be verified server-side must never grant entitlement.
  ///  3. If a usable active purchase exists, ask the server to (re-)validate
  ///     it via [EntitlementService.setPremium] / the
  ///     `validateGooglePlayPurchase` callable. The Cloud Function re-checks
  ///     the Play token and writes the authoritative `users/{uid}` mirror
  ///     (`subscriptionStatus: 'active'`, `isPremium`, `premiumExpiry`,
  ///     `hasActivePurchase`) + the `entitlements/{uid}` mirror.
  ///
  /// **The entitlement write stays server-authoritative.** The client never
  /// sets `subscriptionStatus` / `isPremium` itself (those fields are frozen
  /// in `firestore.rules` — a client write is PERMISSION_DENIED); the sync
  /// simply drives the same server path a fresh purchase uses, so a repaired
  /// account ends with an identical, server-verified grant.
  ///
  /// Never throws. Returns [PurchaseReconciliation.none] for an unauthenticated
  /// caller / read error, and a result carrying [hasActivePurchase] with
  /// `premiumGranted: false` when the store lookup failed (the caller can then
  /// retry on the next launch).
  Future<PurchaseReconciliation> reconcileEntitlementFromPurchases() async {
    final uid = _uid;
    if (uid == null) return PurchaseReconciliation.none;

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> rows;
    try {
      final snap = await _db
          .collection(purchasesCollection)
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: purchaseStatusActive)
          .get();
      rows = snap.docs;
    } catch (e) {
      debugPrint('PlayPurchaseRecorder.reconcileEntitlementFromPurchases read '
          'failed: $e');
      return PurchaseReconciliation.none;
    }

    // Newest first so the most recent active purchase wins. `updatedAt` may
    // be a server timestamp that has not resolved locally yet — a missing
    // value sorts last, which is the safe default.
    final sorted = [...rows];
    sorted.sort((a, b) {
      final at = _asDate(a.data()['updatedAt'] ?? a.data()['createdAt']);
      final bt = _asDate(b.data()['updatedAt'] ?? b.data()['createdAt']);
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

    // Junk-row guard: a row with no product id / token cannot be verified
    // (see the empty-productId document in the live collection) and must not
    // be used to unlock premium.
    for (final row in sorted) {
      final data = row.data();
      final productId = (data['productId'] ?? '').toString().trim();
      final token = (data['purchaseToken'] ?? '').toString().trim();
      if (productId.isEmpty || token.isEmpty) {
        debugPrint('PlayPurchaseRecorder: skipping junk purchase row '
            '${row.id} (blank productId/token) — it cannot be verified.');
        continue;
      }
      final granted = await _setPremium(productId: productId, token: token);
      debugPrint('PlayPurchaseRecorder: reconciled active purchase $productId '
          'for $uid — premium ${granted ? 'granted' : 'pending server '
          'confirmation'}.');
      return PurchaseReconciliation(
        hasActivePurchase: true,
        productId: productId,
        premiumGranted: granted,
      );
    }

    return PurchaseReconciliation.none;
  }

  /// Fire-and-forget entry point for app start / auth-state changes.
  ///
  /// Runs [reconcileEntitlementFromPurchases] and swallows every failure so a
  /// caller can invoke it unconditionally (e.g. from a Firebase Auth state
  /// listener) without guarding it. Attaches the purchase listener first so a
  /// purchase delivered while the sync is in flight is still recorded.
  Future<void> syncEntitlementFromPurchases() async {
    startListening();
    try {
      await reconcileEntitlementFromPurchases();
    } catch (e) {
      debugPrint('PlayPurchaseRecorder.syncEntitlementFromPurchases failed: $e');
    }
  }

  static DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    return null;
  }
}
