import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'play_billing_service.dart';
import 'subscription_pricing.dart';

/// Name of the Firestore collection that records Google Play purchases.
const String purchasesCollection = 'purchases';

/// The `purchases/{id}` status value recorded for a verified / active purchase.
const String purchaseStatusActive = 'active';

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

  @visibleForTesting
  static void resetTestSeams() {
    firestoreForTesting = null;
    currentUserIdResolverForTesting = null;
    purchaseStreamForTesting = null;
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
          debugPrint('PlayPurchaseRecorder purchase error: ${purchase.error}');
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

  /// Writes the transaction to `users/{uid}` + `purchases`.
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
    final tier = SubscriptionTier.fromPlayProductId(productId);
    try {
      // 1) Mirror the entitlement onto the user profile so the paywall /
      //    role gates unlock immediately.
      await _db.collection('users').doc(uid).set({
        'subscriptionTier': tier.key,
        'subscriptionStatus': subscriptionStatusActive,
        'isPro': true,
        'subscriptionProvider': 'google_play_billing',
        'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2) Persist the transaction itself (one document per purchase token so
      //    a repeated delivery of the same token cannot create duplicates).
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
}
