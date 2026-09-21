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

/// The free-trial length mirrored from `subscription_pricing.dart`
/// ([trialDuration]) — 30 days. Used as a last-resort trial window when a
/// `users/{uid}` document carries neither a trial-end timestamp nor a trial
/// status but does carry a `createdAt`.
const Duration trialWindow = Duration(days: 30);

/// Every `users/{uid}` field name under which a trial-end timestamp may be
/// stored, in priority order. The two signup paths write different spellings:
/// the backend `initializeNewUserTrial` trigger writes `trialEndsAt` /
/// `trialEnd`, while the client `SubscriptionStatusService.markTrialStarted`
/// writes `subscriptionTrialEndsAt`. Both are accepted so a valid trial is
/// never paywalled on a schema mismatch.
const List<String> trialEndFieldAliases = <String>[
  'subscriptionTrialEndsAt',
  'trialEndsAt',
  'trialEnd',
  'subscriptionTrialEnd',
  'subscription_trial_ends_at',
  'trial_ends_at',
  'trial_end',
];

/// Every `users/{uid}` field name under which a trial-start timestamp may be
/// stored, in priority order (backend trigger + client markTrialStarted
/// schemas, plus snake_case legacy variants).
const List<String> trialStartFieldAliases = <String>[
  'trialStartedAt',
  'trialStart',
  'subscriptionTrialStartedAt',
  'subscriptionTrialStart',
  'trial_started_at',
  'trial_start',
];

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

  /// The canonical `users/{uid}.subscriptionStatus` string, stored
  /// lower-cased + trimmed (e.g. `'trialing'`, `'active'`, `'cancelled'`).
  ///
  /// The status is the primary signal for access: the backend Auth `onCreate`
  /// trigger + the client `markTrialStarted` both write `'trialing'`, and a
  /// Play purchase writes `'active'`. It is read here so an account with a
  /// valid trial is never paywalled purely because the trial-end field is
  /// spelled differently (see [isTrialActive]).
  final String subscriptionStatus;

  /// The server-owned `requiresPayment` flag. When `true` the account has been
  /// flagged as requiring payment (e.g. a pre-provisioned / abuse-blocked
  /// account) and must NOT be granted trial access. Written by the backend
  /// `initializeNewUserTrial` trigger (which sets it `false` for a granted
  /// trial).
  final bool requiresPayment;

  /// The account-creation timestamp (`createdAt`), used as a last-resort
  /// 30-day trial fallback when neither a trial-end timestamp NOR a trial
  /// status is present. `null` when the field is absent.
  final DateTime? createdAt;

  const UserEntitlement({
    this.isPremium = false,
    this.premiumExpiry,
    this.subscriptionSource,
    this.subscriptionProduct,
    this.trialStart,
    this.trialEnd,
    this.subscriptionStatus = '',
    this.requiresPayment = false,
    this.createdAt,
  });

  /// Trial / grace status strings that indicate an in-progress free trial.
  /// Both `'trial'` and `'trialing'` are accepted (the backend + client write
  /// `'trialing'`; legacy docs may carry `'trial'`; `'trial_active'` is the
  /// remaining documented alias).
  static bool _isTrialStatus(String status) =>
      status == 'trial' ||
      status == 'trialing' ||
      status == 'trialling' ||
      status == 'trial_active';

  /// Status strings that indicate an actively-billed subscription.
  static bool _isActiveStatus(String status) =>
      status == 'active' || status == 'subscribed' || status == 'premium';

  /// Whether the user has an active premium entitlement.
  ///
  /// Primary: the server-authoritative `isPremium` flag + a future
  /// `premiumExpiry`. Fallback: `subscriptionStatus == 'active'` (a Play
  /// purchase whose expiry mirror has not landed yet) — treated as active
  /// when the expiry is absent or still in the future.
  bool isPremiumActive(DateTime now) {
    if (isPremium && premiumExpiry != null && premiumExpiry!.isAfter(now)) {
      return true;
    }
    if (_isActiveStatus(subscriptionStatus)) {
      final expiry = premiumExpiry;
      return expiry == null || expiry.isAfter(now);
    }
    return false;
  }

  /// Whether the user is inside their free trial window.
  ///
  /// Schema-tolerant by design — the two signup paths write DIFFERENT field
  /// layouts, so access must be granted from either:
  ///  - **Backend trigger schema** (`trialEndsAt`, `trialStart`,
  ///    `subscriptionSource: 'trial'`, `requiresPayment: false`), and
  ///  - **Client `markTrialStarted` schema** (`subscriptionTrialEndsAt`,
  ///    `subscriptionProvider`).
  ///
  /// Resolution order:
  ///  1. A trial-end timestamp under ANY spelling
  ///     ([_resolveTrialEnd]) — future = active, past = ended (an explicit
  ///     past expiry always wins over a stale `'trialing'` status).
  ///  2. A trial status (`'trial'`/`'trialing'`/`'trial_active'`) with no
  ///     timestamp — active unless [requiresPayment] is set.
  ///  3. Last resort: no timestamp AND no trial status, but the account was
  ///     created within the 30-day trial window ([isWithinCreationTrialWindow])
  ///     — active unless [requiresPayment] is set.
  ///
  /// `requiresPayment == true` blocks trial access at every step (the account
  /// was explicitly flagged as not trial-eligible). Unknown / non-trial
  /// statuses with no dates fail closed.
  bool isTrialActive(DateTime now) {
    if (requiresPayment) return false;
    final end = trialEnd;
    if (end != null) return end.isAfter(now);
    if (_isTrialStatus(subscriptionStatus)) return true;
    return isWithinCreationTrialWindow(now);
  }

  /// Whether the account was created within the 30-day trial window, used as a
  /// last-resort fallback when a doc carries neither a trial-end timestamp nor
  /// a recognized trial status (e.g. a partially-written legacy document).
  /// Returns `false` when [createdAt] is absent or in the future.
  bool isWithinCreationTrialWindow(DateTime now) {
    final created = createdAt;
    if (created == null) return false;
    final age = now.difference(created);
    return age >= Duration.zero && age < trialWindow;
  }

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

  /// Resolves the first present trial-end timestamp across
  /// [trialEndFieldAliases] (both signup schemas + snake_case legacy
  /// variants).
  static DateTime? _resolveTrialEnd(Map<String, dynamic> data) {
    for (final key in trialEndFieldAliases) {
      final value = _toDate(data[key]);
      if (value != null) return value;
    }
    return null;
  }

  /// Resolves the first present trial-start timestamp across
  /// [trialStartFieldAliases].
  static DateTime? _resolveTrialStart(Map<String, dynamic> data) {
    for (final key in trialStartFieldAliases) {
      final value = _toDate(data[key]);
      if (value != null) return value;
    }
    return null;
  }

  static UserEntitlement fromMap(Map<String, dynamic>? data) {
    if (data == null) return const UserEntitlement();
    final status = (data['subscriptionStatus'] ?? '').toString().trim().toLowerCase();
    return UserEntitlement(
      isPremium: data['isPremium'] == true,
      premiumExpiry: _toDate(data['premiumExpiry']),
      subscriptionSource: data['subscriptionSource'] as String?,
      subscriptionProduct: data['subscriptionProduct'] as String?,
      trialStart: _resolveTrialStart(data),
      trialEnd: _resolveTrialEnd(data),
      subscriptionStatus: status,
      requiresPayment: data['requiresPayment'] == true,
      createdAt: _toDate(data['createdAt']) ?? _toDate(data['created_at']),
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
  ///
  /// Prefers the SERVER document (`Source.server`) so a just-provisioned
  /// trial written by the backend trigger (or the client registration write)
  /// is observed immediately rather than a stale cache hit on the very first
  /// login. Falls back to the cache when offline / on a server error so an
  /// off-grid user is not locked out — and finally to the empty entitlement
  /// when neither is retrievable.
  Future<UserEntitlement> getMyEntitlement() async {
    final uid = _uid;
    if (uid == null) return const UserEntitlement();
    final ref = _db.collection('users').doc(uid);
    try {
      final snap = await ref.get(const GetOptions(source: Source.server));
      return UserEntitlement.fromMap(snap.data());
    } catch (e) {
      debugPrint('EntitlementService.getMyEntitlement server read failed, '
          'falling back to cache: $e');
      try {
        final cached = await ref.get(const GetOptions(source: Source.cache));
        return UserEntitlement.fromMap(cached.data());
      } catch (cacheError) {
        debugPrint('EntitlementService.getMyEntitlement cache read failed: '
            '$cacheError');
        return const UserEntitlement();
      }
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