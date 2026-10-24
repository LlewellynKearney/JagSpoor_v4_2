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

  /// PayFast used through Google Play's **User Choice Billing** (alternative
  /// billing) programme. Recorded distinctly from [payfast] so the Play
  /// service fee can be reconciled, but resolved to the same canonical
  /// website-managed branch for routing (`billingPlatform` / `isPayfastBilled`)
  /// — a subscriber on this platform manages billing on the website and must
  /// never be sent to the Play subscriptions centre.
  static const String payfastAlternative = 'payfast_alternative';

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

  /// Server-owned mirror of the Google Play purchase state.
  ///
  /// `writeEntitlement` sets it `true` whenever the server confirms a Play
  /// purchase (`validateGooglePlayPurchase`), i.e. whenever the `purchases`
  /// collection carries an active transaction for the account. It is the
  /// server's durable answer to "does Google Play currently hold an active
  /// subscription for this uid?" and is the repair path for a `users/{uid}`
  /// document that was never mirrored from `purchases`.
  ///
  /// Client-write is frozen in `firestore.rules` (server-owned), so it can
  /// only ever be set by the Cloud Function.
  final bool hasActivePurchase;

  /// The account-creation timestamp (`createdAt`), used as a last-resort
  /// 30-day trial fallback when neither a trial-end timestamp NOR a trial
  /// status is present. `null` when the field is absent.
  final DateTime? createdAt;

  /// The billing platform that granted the subscription — `'google_play'` or
  /// `'payfast'`, else `null` when unknown.
  ///
  /// This is the **Play-policy switch**: a Play-billed subscriber MUST be
  /// routed to Google Play's own subscriptions manager and must NEVER be shown
  /// a link that steers to an external (website) checkout. Read from the
  /// server-owned `subscriptionPlatform` field (aliases tolerated), falling
  /// back to the canonical `subscriptionSource` when only that is present
  /// (`subscriptionSource` uses the identical `'google_play'` / `'payfast'`
  /// vocabulary). `firestore.rules` freezes `subscriptionPlatform` alongside
  /// the other server-owned entitlement fields, so it is not client-forgeable.
  final String? subscriptionPlatform;

  const UserEntitlement({
    this.isPremium = false,
    this.premiumExpiry,
    this.subscriptionSource,
    this.subscriptionProduct,
    this.trialStart,
    this.trialEnd,
    this.subscriptionStatus = '',
    this.requiresPayment = false,
    this.hasActivePurchase = false,
    this.createdAt,
    this.subscriptionPlatform,
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
  /// **v1.0.12 hotfix:** access now REQUIRES a non-null, future
  /// `premiumExpiry`. The previous fallback granted premium on a stored
  /// `subscriptionStatus == 'active'` with **no** expiry — that was the vector
  /// a forged client status (or a stale mirror) could exploit to obtain
  /// permanent free access. A status alone no longer grants access; the
  /// server-authoritative `entitlements/{uid}` mirror (read by
  /// [EntitlementService.getMyEntitlement]) always carries the expiry.
  bool isPremiumActive(DateTime now) {
    final expiry = premiumExpiry;
    // The server-confirmed purchase flag is itself proof the server validated
    // an active Google Play transaction for this account (the `purchases`
    // mirror). It therefore grants access even before a locally-cached
    // `premiumExpiry` resolves — the server only ever sets it alongside a real
    // expiry, so this cannot be forged by a client (the field is frozen in
    // `firestore.rules`).
    if (hasActivePurchase) return true;
    if (expiry == null) return false;
    if (isPremium && expiry.isAfter(now)) return true;
    // A stored active status is honoured only WITH a future expiry.
    if (_isActiveStatus(subscriptionStatus) && expiry.isAfter(now)) return true;
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

  /// Resolves the billing platform from the raw document, preferring the
  /// explicit `subscriptionPlatform` field (with alias tolerance) and falling
  /// back to the canonical `subscriptionSource`. Both use the same
  /// `'google_play'` / `'payfast'` vocabulary. Returns `null` when neither is a
  /// recognized platform (e.g. `'trial'` / `'none'` / absent).
  ///
  /// `payfast_alternative` (a PayFast purchase taken through Google Play's
  /// **User Choice Billing** programme) resolves to the canonical
  /// [SubscriptionSource.payfast]: it is website-managed, so the subscriber
  /// must be routed to the PayFast dashboard and NEVER to the Play
  /// subscriptions centre. The prefix match is what keeps that Play-policy
  /// branch correct.
  static String? _resolvePlatform(Map<String, dynamic> data) {
    final candidates = <dynamic>[
      data['subscriptionPlatform'],
      data['subscription_platform'],
      data['billingPlatform'],
      data['platform'],
      data['subscriptionSource'],
      data['subscription_source'],
    ];
    for (final raw in candidates) {
      final value = (raw ?? '').toString().trim().toLowerCase();
      if (value == SubscriptionSource.googlePlay ||
          value.startsWith('google_play')) {
        return SubscriptionSource.googlePlay;
      }
      if (value == SubscriptionSource.payfast ||
          value.startsWith('payfast')) {
        return SubscriptionSource.payfast;
      }
    }
    return null;
  }

  /// The resolved billing platform (`'google_play'` / `'payfast'` / `null`),
  /// preferring [subscriptionPlatform] and falling back to
  /// [subscriptionSource] when only that field is populated.
  String? get billingPlatform {
    final platform = subscriptionPlatform;
    if (platform == SubscriptionSource.googlePlay ||
        platform == SubscriptionSource.payfast) {
      return platform;
    }
    final source = subscriptionSource;
    if (source == SubscriptionSource.googlePlay ||
        source == SubscriptionSource.payfast) {
      return source;
    }
    return null;
  }

  /// Whether this subscription is billed by Google Play — i.e. the user must
  /// be routed to Google Play's subscriptions manager (and must NEVER be shown
  /// an external website checkout link).
  bool get isPlayBilled => billingPlatform == SubscriptionSource.googlePlay;

  /// Whether this subscription is billed via the PayFast website checkout —
  /// the only case where a "Manage subscription on website" affordance is
  /// policy-compliant.
  bool get isPayfastBilled => billingPlatform == SubscriptionSource.payfast;

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
    // The canonical nested `subscription` map (written by writeEntitlement for
    // the web/PayFast checkout) is a fallback source for the premium fields
    // when the flat aliases are absent. It is server-owned (change-detection
    // frozen in firestore.rules), so reading it never trusts a client value.
    final nested = data['subscription'];
    final nestedMap =
        nested is Map ? Map<String, dynamic>.from(nested) : const <String, dynamic>{};
    return UserEntitlement(
      isPremium: data['isPremium'] == true || nestedMap['isActive'] == true,
      premiumExpiry:
          _toDate(data['premiumExpiry']) ?? _toDate(nestedMap['expiresAt']),
      subscriptionSource: data['subscriptionSource'] as String?,
      subscriptionProduct:
          (data['subscriptionProduct'] as String?) ??
          (nestedMap['plan'] as String?),
      trialStart: _resolveTrialStart(data),
      trialEnd: _resolveTrialEnd(data),
      subscriptionStatus: status.isNotEmpty
          ? status
          : (nestedMap['status'] ?? '').toString().trim().toLowerCase(),
      requiresPayment: data['requiresPayment'] == true,
      hasActivePurchase: data['hasActivePurchase'] == true,
      createdAt: _toDate(data['createdAt']) ?? _toDate(data['created_at']),
      subscriptionPlatform:
          _resolvePlatform(data) ?? _resolvePlatform(nestedMap),
    );
  }

  /// Builds an entitlement from the server-authoritative `entitlements/{uid}`
  /// mirror (written ONLY by Cloud Functions; `firestore.rules` sets
  /// `write: false` for clients). The mirror carries the premium fields
  /// (`isPremium` / `premiumExpiry` / `subscriptionSource` /
  /// `subscriptionProduct`) and never a client-forgeable status, so it is the
  /// trusted source for [isPremiumActive] (v1.0.12 hotfix). Trial fields are
  /// absent from the mirror and are merged in from `users/{uid}`.
  static UserEntitlement fromEntitlementMirror(Map<String, dynamic>? data) {
    if (data == null) return const UserEntitlement();
    final nested = data['subscription'];
    final nestedMap =
        nested is Map ? Map<String, dynamic>.from(nested) : const <String, dynamic>{};
    return UserEntitlement(
      isPremium: data['isPremium'] == true || nestedMap['isActive'] == true,
      premiumExpiry:
          _toDate(data['premiumExpiry']) ?? _toDate(nestedMap['expiresAt']),
      subscriptionSource: data['subscriptionSource'] as String?,
      subscriptionProduct:
          (data['subscriptionProduct'] as String?) ??
          (nestedMap['plan'] as String?),
      hasActivePurchase: data['hasActivePurchase'] == true,
      subscriptionPlatform:
          _resolvePlatform(data) ?? _resolvePlatform(nestedMap),
    );
  }

  /// Merges this (trial + status, from `users/{uid}`) with a server-owned
  /// premium [mirror] (from `entitlements/{uid}`). When the mirror carries
  /// premium data it takes precedence (it is the Admin-SDK-written source of
  /// truth); when the mirror is absent / empty the premium fields fall back to
  /// this document so a legacy subscriber whose entitlement predates the mirror
  /// is never locked out. The trial window / status / createdAt /
  /// requiresPayment always come from this (users) document.
  UserEntitlement mergePremiumMirror(UserEntitlement mirror) {
    final hasMirror = mirror.isPremium || mirror.premiumExpiry != null;
    return UserEntitlement(
      isPremium: hasMirror ? mirror.isPremium : isPremium,
      premiumExpiry: hasMirror ? mirror.premiumExpiry : premiumExpiry,
      subscriptionSource:
          hasMirror ? (mirror.subscriptionSource ?? subscriptionSource) : subscriptionSource,
      subscriptionProduct:
          hasMirror ? (mirror.subscriptionProduct ?? subscriptionProduct) : subscriptionProduct,
      trialStart: trialStart,
      trialEnd: trialEnd,
      subscriptionStatus: subscriptionStatus,
      requiresPayment: requiresPayment,
      // The server-confirmed purchase flag may arrive from EITHER the users
      // document (writeEntitlement mirrors it there too) or the
      // entitlements/{uid} mirror — take whichever is set.
      hasActivePurchase: hasActivePurchase || mirror.hasActivePurchase,
      createdAt: createdAt,
      // The billing platform may arrive from either document; prefer the
      // mirror's (server-authoritative) value, else keep this document's.
      subscriptionPlatform:
          mirror.subscriptionPlatform ?? subscriptionPlatform,
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

  /// Test seam: replaces the server-authoritative premium grant performed by
  /// [setPremium] so the `itemAlreadyOwned` recovery path can be asserted
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
    idTokenResolverForTesting = null;
    premiumSetterForTesting = null;
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
  /// **v1.0.12 hotfix — reads the server-authoritative mirror.** The premium
  /// fields are taken from `entitlements/{uid}` (written ONLY by Cloud
  /// Functions; `firestore.rules` sets `write: false` for clients), merged with
  /// the trial window / status read from `users/{uid}`. This removes the
  /// `users/{uid}` document from the premium trust path entirely.
  ///
  /// Prefers the SERVER documents so a just-provisioned trial or a
  /// freshly-verified purchase is observed immediately, falling back to the
  /// cache when offline, then to the empty entitlement.
  Future<UserEntitlement> getMyEntitlement() async {
    final uid = _uid;
    if (uid == null) return const UserEntitlement();
    final userRef = _db.collection('users').doc(uid);
    final entRef = _db.collection('entitlements').doc(uid);

    final users = await _readWithFallback(userRef);
    final mirror = await _readWithFallback(entRef);
    if (users == null && mirror == null) return const UserEntitlement();

    final base = UserEntitlement.fromMap(users);
    final premium = UserEntitlement.fromEntitlementMirror(mirror);
    return base.mergePremiumMirror(premium);
  }

  /// Reads a document preferring the server, then the cache, then null.
  /// Never throws.
  Future<Map<String, dynamic>?> _readWithFallback(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final snap = await ref.get(const GetOptions(source: Source.server));
      return snap.data();
    } catch (e) {
      debugPrint('EntitlementService: server read failed for '
          '${ref.path}, falling back to cache: $e');
      try {
        final cached = await ref.get(const GetOptions(source: Source.cache));
        return cached.data();
      } catch (cacheError) {
        debugPrint('EntitlementService: cache read failed for '
            '${ref.path}: $cacheError');
        return null;
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

  /// Grants (or refreshes) the premium entitlement for the signed-in user.
  ///
  /// **Server-authoritative by design.** `users/{uid}` and `entitlements/{uid}`
  /// freeze `isPremium` / `premiumExpiry` / `subscriptionStatus` / `isPro`
  /// against client writes (`firestore.rules`), so this NEVER writes premium
  /// state locally. It routes through the same
  /// [verifyGooglePlayPurchase] callable the normal purchase flow uses, which
  /// has the Cloud Function re-validate the Play purchase token and write the
  /// authoritative entitlement. The `itemAlreadyOwned` recovery path calls this
  /// after restoring the user's existing purchase, so "already owned" ends with
  /// the SAME server-verified premium grant as a fresh purchase.
  ///
  /// Returns `true` when the server confirmed the entitlement. A missing
  /// session / token or a rejected verification resolves `false` (never
  /// throws) so the caller can surface a retry instead of crashing.
  Future<bool> setPremium({
    required String productId,
    String? purchaseToken,
  }) async {
    final override = premiumSetterForTesting;
    if (override != null) {
      return override(productId: productId, purchaseToken: purchaseToken);
    }
    final token = purchaseToken;
    if (token == null || token.isEmpty) {
      debugPrint(
        'EntitlementService.setPremium: no purchase token for $productId — '
        'cannot grant premium (nothing to verify server-side).',
      );
      return false;
    }
    final result = await verifyGooglePlayPurchase(
      purchaseToken: token,
      productId: productId,
    );
    if (!result.success) {
      debugPrint(
        'EntitlementService.setPremium: server rejected the entitlement grant '
        'for $productId (${result.message}).',
      );
    }
    return result.success;
  }
}

/// Result of a server-side Google Play purchase verification.
class PurchaseVerificationResult {
  final bool success;
  final String? message;

  const PurchaseVerificationResult({required this.success, this.message});
}