import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../subscription/services/subscription_pricing.dart';
import 'billing_plans.dart';

/// Google Play's service fee for a transaction taken through the alternative
/// billing programme, in basis points (2600 = 26%).
///
/// This is the reduced rate Google charges when the user actively chooses the
/// alternative system instead of Google Play Billing. It is recorded on every
/// `alternative_billing_reports` document so the Play Console "Alternative
/// billing" invoice can be reconciled without recomputing the rate.
///
/// **Operator action:** confirm the exact rate in Play Console → Monetization →
/// Alternative billing before relying on this figure for accounting. It is
/// declared here as a single named constant precisely so it can be corrected
/// in one place.
const int alternativeBillingServiceFeeBasisPoints = 2600;

/// Google Play **User Choice Billing** (alternative billing) support.
///
/// South Africa is enrolled in Play's alternative billing programme, so an
/// Android subscriber may pay JagSpoor either through Google Play Billing or
/// through PayFast. Play requires the app to:
///
///  1. show BOTH options and let the user actively choose (never auto-default
///     to the alternative, never hide Google Play on Android),
///  2. obtain an **external transaction token** from the Play Billing Library
///     before handing the user to the alternative payment flow, and
///  3. report the resulting transaction (the token + the amount charged) to
///     Google so the service fee can be invoiced.
///
/// This service owns steps 2 and 3 on the Dart side.
///
/// ## The token, and why the prompt's method name is not used
///
/// There is no `BillingClient.createAlternativeBillingReportingToken()` in the
/// Play Billing Library — that method does not exist. The real API (verified
/// against `com.android.billingclient:billing:8.0.0`) is:
///
///  * `createAlternativeBillingOnlyReportingDetailsAsync(listener)` — the
///    *alternative-billing-only* programme (no Play option offered at all).
///    The token arrives as
///    `AlternativeBillingOnlyReportingDetails.getExternalTransactionToken()`.
///  * `Builder.enableUserChoiceBilling(listener)` +
///    `UserChoiceBillingListener.userSelectedAlternativeBilling(details)` —
///    **User Choice Billing**, where Play presents the choice UI and the token
///    arrives as `UserChoiceDetails.getExternalTransactionToken()`.
///
/// JagSpoor needs **User Choice Billing** (both options are shown), so the
/// native side enables `enableUserChoiceBilling` and surfaces
/// `UserChoiceDetails.getExternalTransactionToken()` through this channel.
/// `createAlternativeBillingOnlyReportingDetailsAsync` is additionally exposed
/// on the native side so the app can still obtain a token when the Play-side
/// choice sheet is unavailable (e.g. an emulator without the updated Play
/// Store) — the Dart side treats both paths identically.
///
/// ## Failure posture
///
/// Every method degrades gracefully. The alternative (PayFast) checkout must
/// remain usable when Play reports that User Choice Billing is unavailable, is
/// not yet provisioned for the account, or the platform channel is missing
/// (widget tests, desktop). A missing token is recorded as
/// `status: 'token_unavailable'` so the transaction is visible for manual
/// reporting rather than silently dropped.
class AlternativeBillingService {
  AlternativeBillingService._();

  static final AlternativeBillingService instance = AlternativeBillingService._();

  /// The Dart↔native channel implemented by `MainActivity` (Android only).
  static const MethodChannel channel =
      MethodChannel('com.jagspoor/alternative_billing');

  /// The Firestore collection every alternative-billing transaction is logged
  /// to. An operator (or the Cloud Function below) reconciles these against
  /// the Play Console's "Alternative billing" invoice report.
  static const String reportsCollection = 'alternative_billing_reports';

  /// The programme identifier stored on every report.
  static const String userChoiceProgram = 'user_choice_billing';

  /// Canonical report statuses.
  static const String statusReported = 'reported';
  static const String statusPending = 'pending';
  static const String statusTokenUnavailable = 'token_unavailable';
  static const String statusFailed = 'failed';

  // ── Test seams ─────────────────────────────────────────────────────────

  /// Overrides the platform call. Return the token, or throw to simulate an
  /// unavailable Play service.
  @visibleForTesting
  static Future<String?> Function()? createTokenForTesting;

  /// Overrides the report write.
  @visibleForTesting
  static Future<void> Function(Map<String, dynamic> report)? reportWriterForTesting;

  /// Overrides the current user id resolution.
  @visibleForTesting
  static String? Function()? currentUserIdResolverForTesting;

  /// Overrides the Firestore instance.
  @visibleForTesting
  static FirebaseFirestore? firestoreForTesting;

  /// Overrides the platform capability check. Null uses the real platform.
  @visibleForTesting
  static bool? isSupportedForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    createTokenForTesting = null;
    reportWriterForTesting = null;
    currentUserIdResolverForTesting = null;
    firestoreForTesting = null;
    isSupportedForTesting = null;
  }

  // ── Platform / capability ──────────────────────────────────────────────

  /// Whether User Choice Billing can be offered on this build.
  ///
  /// Android only: Play Billing has no web or iOS implementation, and the
  /// browser build is outside Google Play billing entirely (it charges through
  /// PayFast and shows no Play affordance at all).
  ///
  /// This is a *synchronous* hint derived from the platform, used for cheap
  /// early-outs. It is deliberately NOT what the UI branches on: the test VM
  /// reports [TargetPlatform.android] while having no billing plugin at all,
  /// so branching on the platform enum would surface the choice UI in every
  /// widget test. Call [probeSupport] (an actual native round-trip) to decide
  /// whether to render the choice surface.
  bool get isSupported =>
      isSupportedForTesting ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  /// Asks the native host whether User Choice Billing is actually available.
  ///
  /// Returns false on any host without the bridge — a test VM, iOS, desktop,
  /// or an Android build whose Play Store predates the programme. This is the
  /// value the subscription UI must branch on, so the choice surface only ever
  /// appears where a real token can be obtained.
  Future<bool> probeSupport() async {
    final override = isSupportedForTesting;
    if (override != null) return override;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final available = await channel.invokeMethod<bool>(
        'isAlternativeBillingSupported',
      );
      return available ?? false;
    } on MissingPluginException {
      // No native bridge on this host (tests / desktop). Not an error.
      return false;
    } on PlatformException catch (e) {
      debugPrint('AlternativeBillingService: support probe failed '
          '(${e.code}): ${e.message}');
      return false;
    } catch (e) {
      debugPrint('AlternativeBillingService: support probe error: $e');
      return false;
    }
  }

  String? get _uid {
    final resolver = currentUserIdResolverForTesting;
    if (resolver != null) return resolver();
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  FirebaseFirestore get _firestore =>
      firestoreForTesting ?? FirebaseFirestore.instance;

  // ── Token creation ─────────────────────────────────────────────────────

  /// Asks Play for an external transaction token for the alternative flow.
  ///
  /// Call this **before** handing the user to PayFast so the token can be
  /// reported with the resulting transaction. Returns null (never throws) when
  /// Play cannot supply one — the caller proceeds with the PayFast checkout and
  /// records the transaction as `token_unavailable`.
  Future<String?> createAlternativeBillingToken() async {
    final override = createTokenForTesting;
    if (override != null) {
      try {
        return _normalize(await override());
      } catch (e) {
        debugPrint('AlternativeBillingService: token override failed: $e');
        return null;
      }
    }
    if (!isSupported) return null;
    try {
      final token = await channel.invokeMethod<String>('createAlternativeBillingToken');
      return _normalize(token);
    } on MissingPluginException {
      // No native implementation on this host (tests / desktop). Not an error
      // the user should ever see.
      return null;
    } on PlatformException catch (e) {
      debugPrint('AlternativeBillingService: createAlternativeBillingToken '
          'failed (${e.code}): ${e.message}');
      return null;
    } catch (e) {
      debugPrint('AlternativeBillingService: createAlternativeBillingToken '
          'unexpected error: $e');
      return null;
    }
  }

  /// Tells the native layer that the user chose the alternative flow.
  ///
  /// On a User-Choice-Billing-enabled client Play itself invokes the native
  /// `UserChoiceBillingListener`, which pushes the token up this channel. This
  /// method is the explicit handshake for the alternative-billing-only path.
  /// Best-effort: a failure is logged and never blocks the checkout.
  Future<bool> reportAlternativeBillingToken(String token) async {
    if (!isSupported) return false;
    final trimmed = token.trim();
    if (trimmed.isEmpty) return false;
    try {
      final ok = await channel.invokeMethod<bool>(
        'reportAlternativeBillingToken',
        <String, dynamic>{'token': trimmed},
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('AlternativeBillingService: reportAlternativeBillingToken '
          'failed (${e.code}): ${e.message}');
      return false;
    } catch (e) {
      debugPrint('AlternativeBillingService: reportAlternativeBillingToken '
          'unexpected error: $e');
      return false;
    }
  }

  // ── Transaction logging ────────────────────────────────────────────────

  /// Builds the Firestore report document for an alternative-billing
  /// transaction. Pure (no I/O) so the shape is unit-testable.
  ///
  /// [planId] is the Play-side plan id (`hunter_monthly` …); [alternativeSku]
  /// is the alternative catalogue id (`jagspoor_hunter_monthly_payfast` …).
  /// The service fee is recorded as basis points so the arithmetic is exact.
  static Map<String, dynamic> buildReport({
    required String userId,
    required SubscriptionTier tier,
    required BillingCycle cycle,
    required double amountZar,
    required String planId,
    required String alternativeSku,
    String? payfastTransactionId,
    String? reportingToken,
    String status = statusPending,
    String program = userChoiceProgram,
  }) {
    final feeBps = alternativeBillingServiceFeeBasisPoints;
    final fee = (amountZar * feeBps) / 10000.0;
    return <String, dynamic>{
      'userId': userId,
      'tier': tier.key,
      'billingCycle': cycle.key,
      'planId': planId,
      'alternativeSku': alternativeSku,
      'amountZar': amountZar,
      // Play's alternative billing service fee. Recorded alongside the amount
      // so the invoice reconciliation never has to recompute the rate.
      // Written under BOTH spellings: `feeBps` is the operator-facing name
      // used in the Play Console reconciliation notes, `serviceFeeBasisPoints`
      // is what the server-side reporter reads.
      'serviceFeeBasisPoints': feeBps,
      'feeBps': feeBps,
      'serviceFeeZar': double.parse(fee.toStringAsFixed(2)),
      'payfastTransactionId': payfastTransactionId,
      'reportingToken': reportingToken,
      'status': status,
      'program': program,
      'reportedAt': FieldValue.serverTimestamp(),
    };
  }

  /// The alternative-billing SKU for a Play plan id, e.g.
  /// `hunter_monthly` -> `jagspoor_hunter_monthly_payfast`.
  static String alternativeSkuFor(String planId) {
    final trimmed = planId.trim();
    if (trimmed.isEmpty) return '';
    return 'jagspoor_${trimmed}_payfast';
  }

  /// The Play-side subscription product id for a tier (the id the token is
  /// associated with in the Play Console).
  static String playProductIdFor(SubscriptionTier tier) => tier.playProductId;

  /// Writes an alternative-billing transaction report.
  ///
  /// Owner-scoped (`users/{uid}` writes are frozen, so this uses its own
  /// collection). Returns the document id, or null when the write could not be
  /// made (no session / offline / rules). A failure never blocks the PayFast
  /// checkout — the caller has already launched it by this point.
  Future<String?> recordAlternativeBillingTransaction({
    required SubscriptionTier tier,
    required BillingCycle cycle,
    required double amountZar,
    String? payfastTransactionId,
    String? reportingToken,
    String? status,
  }) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      debugPrint('AlternativeBillingService: no signed-in user; report skipped');
      return null;
    }
    final planId = '${tier.key}_${cycle.key}';
    // The client NEVER claims `reported`: that status means the Play Developer
    // API actually accepted the transaction, which only the server-side
    // reporter (`functions/src/alternative_billing.ts`) can establish. A
    // token in hand means the row is ready to be reported — hence `pending`.
    final resolvedStatus = status ??
        (reportingToken == null || reportingToken.isEmpty
            ? statusTokenUnavailable
            : statusPending);
    final report = buildReport(
      userId: uid,
      tier: tier,
      cycle: cycle,
      amountZar: amountZar,
      planId: planId,
      alternativeSku: alternativeSkuFor(planId),
      payfastTransactionId: payfastTransactionId,
      reportingToken: reportingToken,
      status: resolvedStatus,
    );
    final override = reportWriterForTesting;
    if (override != null) {
      try {
        await override(report);
      } catch (e) {
        debugPrint('AlternativeBillingService: report writer failed: $e');
      }
      return null;
    }
    try {
      final ref = await _firestore.collection(reportsCollection).add(report);
      return ref.id;
    } catch (e) {
      debugPrint('AlternativeBillingService: report write failed: $e');
      return null;
    }
  }

  static String? _normalize(String? token) {
    final trimmed = (token ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
