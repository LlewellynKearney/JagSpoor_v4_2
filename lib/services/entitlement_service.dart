import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Canonical subscription source values mirroring the Cloud Functions
/// entitlement module (`functions/src/entitlement.ts`).
class SubscriptionSource {
  SubscriptionSource._();

  static const String googlePlay = 'google_play';
  static const String payfast = 'payfast';
  static const String trial = 'trial';
  static const String none = 'none';
}

/// Pure snapshot of a user's entitlement state derived from the
/// `users/{uid}` document. The premium fields (`isPremium`, `premiumExpiry`,
/// `subscriptionSource`) are server-authoritative — written ONLY by Cloud
/// Functions and never mutated by the app.
class UserEntitlement {
  final bool isPremium;
  final DateTime? premiumExpiry;
  final String? subscriptionSource;
  final String? subscriptionProduct;
  final DateTime? trialStart;
  final DateTime? trialEnd;

  const UserEntitlement({
    this.isPremium = false,
    this.premiumExpiry,
    this.subscriptionSource,
    this.subscriptionProduct,
    this.trialStart,
    this.trialEnd,
  });

  /// Whether the user has an active premium entitlement (verified server-side).
  bool isPremiumActive(DateTime now) =>
      isPremium && premiumExpiry != null && premiumExpiry!.isAfter(now);

  /// Whether the user is inside their 30-day free trial window.
  bool isTrialActive(DateTime now) =>
      trialEnd != null && trialEnd!.isAfter(now);

  /// Combined access gate: trial OR premium.
  bool canAccessPremium(DateTime now) =>
      isPremiumActive(now) || isTrialActive(now);

  /// Whole days remaining in the trial window (0 when ended/absent).
  int trialDaysRemaining(DateTime now) {
    final end = trialEnd;
    if (end == null) return 0;
    final days = end.difference(now).inDays;
    return days < 0 ? 0 : days;
  }

  /// Whether the entitlement was granted via Google Play.
  bool get isGooglePlay => subscriptionSource == SubscriptionSource.googlePlay;

  /// Whether the entitlement was granted via the PayFast website checkout.
  bool get isPayfast => subscriptionSource == SubscriptionSource.payfast;

  static UserEntitlement fromMap(Map<String, dynamic>? data) {
    if (data == null) return const UserEntitlement();
    return UserEntitlement(
      isPremium: data['isPremium'] == true,
      premiumExpiry: _toDate(data['premiumExpiry']),
      subscriptionSource: data['subscriptionSource'] as String?,
      subscriptionProduct: data['subscriptionProduct'] as String?,
      trialStart: _toDate(data['trialStart']) ?? _toDate(data['trialStartedAt']),
      trialEnd: _toDate(data['trialEnd']) ?? _toDate(data['trialEndsAt']),
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

/// Reactive entitlement source backed by the `users/{uid}` document.
///
/// The premium fields on that document are written exclusively by Cloud
/// Functions (`validateGooglePlayPurchase`, `payfastITN`, the trial trigger),
/// NOT by the app — so the client can only ever READ entitlement state.
class EntitlementService {
  EntitlementService._();
  static final EntitlementService instance = EntitlementService._();

  /// The Cloud Functions callable that verifies a Google Play purchase
  /// server-side and writes the entitlement. The app never writes
  /// `isPremium` locally.
  static const String _validatePlayCallable = 'validateGooglePlayPurchase';

  /// Firebase project id (used to build the callable HTTP endpoint). Must
  /// match `firebase_options.dart` / the deployed functions region.
  @visibleForTesting
  static String projectIdForTesting = 'jagspoor';

  /// Functions region (defaults to the us-central1 deploy region).
  static const String _functionsRegion = 'us-central1';

  @visibleForTesting
  static FirebaseFirestore? firestoreForTesting;

  @visibleForTesting
  static String? Function()? currentUserIdResolverForTesting;

  @visibleForTesting
  static Future<String?> Function()? idTokenResolverForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    firestoreForTesting = null;
    currentUserIdResolverForTesting = null;
    idTokenResolverForTesting = null;
    projectIdForTesting = 'jagspoor';
  }

  FirebaseFirestore get _db {
    final override = firestoreForTesting;
    if (override != null) return override;
    return FirebaseFirestore.instance;
  }

  /// Resolves the Firebase Auth ID token used to authenticate the callable
  /// invocation. Overridable in tests; fails soft to null for cold-launch /
  /// widget-test environments.
  Future<String?> _idToken() async {
    final override = idTokenResolverForTesting;
    if (override != null) return override();
    try {
      final user = FirebaseAuth.instance.currentUser;
      return await user?.getIdToken();
    } catch (_) {
      return null;
    }
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

  /// Reactive stream of the current user's entitlement. Emits the empty
  /// entitlement for unauthenticated callers or on a hard stream error.
  Stream<UserEntitlement> watchMyEntitlement() {
    final uid = _uid;
    if (uid == null) return Stream.value(const UserEntitlement());
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snap) => UserEntitlement.fromMap(snap.data()))
        .handleError((Object e) {
      debugPrint('EntitlementService.watchMyEntitlement error: $e');
    });
  }

  /// One-shot read of the current user's entitlement state.
  Future<UserEntitlement> getMyEntitlement() async {
    final uid = _uid;
    if (uid == null) return const UserEntitlement();
    try {
      final snap = await _db.collection('users').doc(uid).get();
      return UserEntitlement.fromMap(snap.data());
    } catch (e) {
      debugPrint('EntitlementService.getMyEntitlement error: $e');
      return const UserEntitlement();
    }
  }

  /// Calls the `validateGooglePlayPurchase` Cloud Function with the Play
  /// purchase token. On success the Cloud Function writes `isPremium` /
  /// `premiumExpiry` onto `users/{uid}` + `entitlements/{uid}` — the app
  /// does NOT set premium state locally.
  ///
  /// The callable is invoked via the HTTPS trigger endpoint
  ///
  ///   https://us-central1-<project>.cloudfunctions.net/validateGooglePlayPurchase
  ///
  /// authenticated with the caller's Firebase ID token (Bearer). No extra
  /// platform plugin is required.
  Future<PurchaseVerificationResult> verifyGooglePlayPurchase({
    required String purchaseToken,
    required String productId,
    String? packageName,
  }) async {
    final uid = _uid;
    if (uid == null) {
      return const PurchaseVerificationResult(
        success: false,
        message: 'You must be signed in to verify a purchase.',
      );
    }
    final idToken = await _idToken();
    if (idToken == null) {
      return const PurchaseVerificationResult(
        success: false,
        message: 'You must be signed in to verify a purchase.',
      );
    }
    final endpoint = 'https://$_functionsRegion-${projectIdForTesting}'
        '.cloudfunctions.net/$_validatePlayCallable';
    try {
      final res = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'data': {
            'purchaseToken': purchaseToken,
            'productId': productId,
            'packageName': packageName ?? 'za.co.jagspoor.app',
          },
        }),
      );
      if (res.statusCode == 200) {
        return const PurchaseVerificationResult(success: true);
      }
      String message = 'Purchase verification failed (${res.statusCode}).';
      try {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final callableError = decoded['error'] ?? {};
        if (callableError is Map && callableError['message'] != null) {
          message = callableError['message'] as String;
        }
      } catch (_) {}
      return PurchaseVerificationResult(success: false, message: message);
    } catch (e) {
      debugPrint('EntitlementService.verifyGooglePlayPurchase error: $e');
      return PurchaseVerificationResult(
        success: false,
        message: 'Purchase verification failed.',
      );
    }
  }
}

/// Result of a server-side Google Play purchase verification.
class PurchaseVerificationResult {
  final bool success;
  final String? message;

  const PurchaseVerificationResult({required this.success, this.message});
}