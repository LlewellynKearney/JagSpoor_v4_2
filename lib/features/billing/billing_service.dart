import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../subscription/services/play_billing_service.dart';
import '../subscription/services/subscription_pricing.dart';
import 'billing_plans.dart';
import 'payfast_form.dart';

/// Result of a billing attempt, so the UI can branch on the outcome without
/// throwing.
class BillingResult {
  /// Whether the checkout was launched (the user is now on PayFast / the
  /// native store sheet).
  final bool launched;

  /// True when the user abandoned / cancelled.
  final bool cancelled;

  /// A user-facing message when something went wrong.
  final String? message;

  const BillingResult({
    required this.launched,
    this.cancelled = false,
    this.message,
  });

  static const BillingResult ok = BillingResult(launched: true);
  static const BillingResult cancelledResult =
      BillingResult(launched: false, cancelled: true);

  BillingResult failure(String message) =>
      BillingResult(launched: false, message: message);
}

/// The signed PayFast payment form returned by the `createPayFastPayment`
/// callable.
class PayFastPayment {
  final String processUrl;
  final Map<String, String> fields;
  final String merchantPaymentId;
  final String planId;
  final double amount;

  const PayFastPayment({
    required this.processUrl,
    required this.fields,
    required this.merchantPaymentId,
    required this.planId,
    required this.amount,
  });

  static PayFastPayment fromJson(Map<String, dynamic> json) {
    final rawFields = (json['fields'] as Map?) ?? const {};
    return PayFastPayment(
      processUrl: (json['processUrl'] ?? '').toString(),
      fields: rawFields.map(
        (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
      ),
      merchantPaymentId: (json['merchantPaymentId'] ?? '').toString(),
      planId: (json['planId'] ?? '').toString(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Platform-agnostic billing facade.
///
/// * **Web** -> PayFast. Calls the `createPayFastPayment` callable, then posts
///   the signed form to PayFast's hosted checkout (auto-submit via an injected
///   `<form>`; falls back to `url_launcher` if the DOM submit is unavailable).
/// * **Android / iOS** -> the existing Google Play Billing flow
///   ([PlayBillingService]) — Play policy requires Play Billing for in-app
///   digital goods, so PayFast is deliberately NOT used on native.
///
/// The merchant key is NEVER present in this client: it is used server-side to
/// sign the form. The client only ever sees the public `merchant_id` + the MD5
/// signature inside [PayFastPayment.fields].
class BillingService {
  BillingService._();
  static final BillingService instance = BillingService._();

  /// Firebase project id (used to build the callable endpoint). Mirrors
  /// `EntitlementService.projectIdForTesting`.
  @visibleForTesting
  static String projectIdForTesting = 'jagspoor';

  static const String _functionsRegion = 'us-central1';
  static const String _createPaymentCallable = 'createPayFastPayment';

  /// Test seam: replaces the HTTP POST to the callable.
  @visibleForTesting
  static Future<http.Response> Function(Uri uri, Map<String, String> headers,
      Object body)? httpPostForTesting;

  /// Test seam: replaces the current user id resolution.
  @visibleForTesting
  static String? Function()? currentUserIdResolverForTesting;

  /// Test seam: replaces the ID token resolution.
  @visibleForTesting
  static Future<String?> Function()? idTokenResolverForTesting;

  /// Test seam: replaces the browser form submit. Returns true when the form
  /// was submitted.
  @visibleForTesting
  static bool Function(String url, Map<String, String> fields)?
      formSubmitterForTesting;

  /// Test seam: replaces the native `url_launcher` hand-off used when no DOM
  /// form can be submitted (Android / iOS).
  @visibleForTesting
  static Future<bool> Function(Uri url)? urlLauncherForTesting;

  /// Test seam: forces the platform routing (`true` = PayFast web path,
  /// `false` = native Play Billing path). Null uses the real platform.
  @visibleForTesting
  static bool? usesPayFastForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    projectIdForTesting = 'jagspoor';
    httpPostForTesting = null;
    currentUserIdResolverForTesting = null;
    idTokenResolverForTesting = null;
    formSubmitterForTesting = null;
    urlLauncherForTesting = null;
    usesPayFastForTesting = null;
  }

  /// Whether the current build is the web build (PayFast path).
  bool get isWeb => usesPayFast;

  /// Whether this platform uses PayFast (web) rather than Play Billing.
  bool get usesPayFast => usesPayFastForTesting ?? kIsWeb;

  /// The PayFast site a web subscriber uses to manage their recurring billing.
  ///
  /// PayFast has no per-subscription deep link comparable to Google Play's
  /// subscriptions centre, so the web build links to the PayFast dashboard
  /// root. Only ever shown to a PayFast-billed (web) subscriber.
  static const String payfastDashboardUrl = 'https://www.payfast.co.za/';

  String? get _uid {
    final resolver = currentUserIdResolverForTesting;
    if (resolver != null) return resolver();
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

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

  /// The plans offered for [tier] (client mirror of the server catalog).
  List<BillingPlan> plansForTier(SubscriptionTier tier) =>
      BillingPlans.forTier(tier);

  /// The plans offered for the given role (`hunter` / `outfitter`).
  List<BillingPlan> plansForRole(String role) =>
      BillingPlans.forTier(SubscriptionTier.fromString(role));

  /// Starts a checkout for [plan] using the platform-appropriate flow.
  ///
  /// Web -> PayFast hosted checkout. Native -> Google Play Billing (the Play
  /// purchase stream then drives the entitlement; see
  /// `SubscriptionScreen._listenForPurchases`).
  ///
  /// Set [alternativeBilling] when the user has chosen PayFast through Google
  /// Play's **User Choice Billing** flow on Android. The flag is forwarded to
  /// the server so the ITN stamps the entitlement `payfast_alternative`, and
  /// it selects the native browser launch (there is no DOM form off the web).
  Future<BillingResult> pay({
    required String role,
    required BillingPlan plan,
    bool alternativeBilling = false,
  }) async {
    if (usesPayFast || alternativeBilling) {
      return _payWithPayFast(
        role: role,
        plan: plan,
        alternativeBilling: alternativeBilling,
      );
    }
    return _payWithPlayBilling(plan);
  }

  /// Convenience: start a PayFast checkout by plan id.
  Future<BillingResult> payWithPlanId({
    required String role,
    required String planId,
    bool alternativeBilling = false,
  }) async {
    final plan = BillingPlans.byId(planId);
    if (plan == null) {
      return const BillingResult(
        launched: false,
        message: 'Unknown plan.',
      );
    }
    return pay(
      role: role,
      plan: plan,
      alternativeBilling: alternativeBilling,
    );
  }

  /// Requests the signed PayFast form from the callable and returns it.
  ///
  /// Returns null (with a message) when the user is not signed in, the
  /// callable is unreachable, or PayFast is not configured server-side.
  Future<({PayFastPayment? payment, String? error})> requestPayFastPayment({
    required String role,
    required String planId,
    String? billingCycle,
    bool alternativeBilling = false,
  }) async {
    final uid = _uid;
    if (uid == null) {
      return (payment: null, error: 'Sign in to start a checkout.');
    }
    final idToken = await _idToken();
    if (idToken == null) {
      return (payment: null, error: 'Sign in to start a checkout.');
    }
    final endpoint = 'https://$_functionsRegion-$projectIdForTesting'
        '.cloudfunctions.net/$_createPaymentCallable';
    try {
      final body = jsonEncode({
        'data': {
          'role': role,
          'planId': planId,
          if (billingCycle != null) 'billingCycle': billingCycle,
          // Tells the server this checkout came from Google Play's User Choice
          // Billing flow, so the ITN stamps `payfast_alternative` and the
          // service fee stays reconcilable against the Play invoice.
          if (alternativeBilling) 'alternativeBilling': true,
        },
      });
      final res = await (httpPostForTesting ?? _defaultPost)(
        Uri.parse(endpoint),
        {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body,
      );
      if (res.statusCode != 200) {
        return (
          payment: null,
          error: _extractError(res.body) ??
              'Could not start the PayFast checkout (${res.statusCode}).',
        );
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      // Callable responses are wrapped in {"result": {...}}.
      final result = (decoded['result'] ?? decoded) as Map<String, dynamic>;
      return (payment: PayFastPayment.fromJson(result), error: null);
    } catch (e) {
      debugPrint('BillingService.requestPayFastPayment error: $e');
      return (
        payment: null,
        error: 'Could not reach the payment service. Please try again.',
      );
    }
  }

  Future<http.Response> _defaultPost(
    Uri uri,
    Map<String, String> headers,
    Object body,
  ) =>
      http.post(uri, headers: headers, body: body);

  /// Extracts the callable error message from a response body, if present.
  String? _extractError(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final err = decoded['error'];
      if (err is Map && err['message'] != null) {
        return err['message'].toString();
      }
    } catch (_) {}
    return null;
  }

  /// Web checkout: request the signed form, then post it to PayFast.
  ///
  /// Two launch paths, because only a browser can submit an HTML form:
  ///  * **Web** — inject a hidden form and submit it in the current tab.
  ///  * **Native** (Android User Choice Billing, or an iOS PayFast
  ///    subscriber) — build a signed GET URL from the same form fields and
  ///    hand it to `url_launcher` so the hosted checkout opens in the device
  ///    browser. PayFast accepts a signed query string on `/eng/process`
  ///    (verified: the endpoint processes GET and validates the signature
  ///    identically), and the ITN still arrives server-to-server.
  Future<BillingResult> _payWithPayFast({
    required String role,
    required BillingPlan plan,
    bool alternativeBilling = false,
  }) async {
    final (:payment, :error) = await requestPayFastPayment(
      role: role,
      planId: plan.planId,
      billingCycle: plan.cycle.key,
      alternativeBilling: alternativeBilling,
    );
    if (payment == null) {
      return BillingResult(launched: false, message: error);
    }

    // Native: no DOM, so open the signed checkout URL in the device browser.
    //
    // This branch must NOT run when the web-billing seam is forced: the
    // existing web tests drive the DOM submitter directly (without setting
    // `usesPayFastForTesting`), so a raw `kIsWeb` check would misroute them
    // into the browser-launch path on the test VM.
    final nativeLaunch = !kIsWeb && usesPayFastForTesting != true;
    if (nativeLaunch) {
      final uri = Uri.parse(buildSignedGetUrl(payment));
      final launched = await (urlLauncherForTesting ?? _defaultUrlLauncher)(uri);
      if (!launched) {
        return const BillingResult(
          launched: false,
          message: 'Could not open the PayFast checkout in your browser.',
        );
      }
      return BillingResult.ok;
    }

    final submitted = (formSubmitterForTesting ?? submitPayFastForm)(
      payment.processUrl,
      payment.fields,
    );
    if (!submitted) {
      return const BillingResult(
        launched: false,
        message: 'Could not open the PayFast checkout in this browser.',
      );
    }
    return BillingResult.ok;
  }

  /// Builds the signed GET URL for a hosted PayFast checkout.
  ///
  /// The `processUrl` + every signed field (including `signature`) are
  /// appended as a query string, so the device browser can open the checkout
  /// without an HTML form. Pure, so it is unit-testable.
  static String buildSignedGetUrl(PayFastPayment payment) {
    final params = <String, String>{
      ...payment.fields,
    };
    // Uri.replace percent-encodes the values and preserves the signature,
    // which was computed over the UNENCODED field values.
    return Uri.parse(payment.processUrl).replace(queryParameters: params).toString();
  }

  Future<bool> _defaultUrlLauncher(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('BillingService._defaultUrlLauncher error: $e');
      return false;
    }
  }

  /// Native checkout: hand off to Google Play Billing.
  Future<BillingResult> _payWithPlayBilling(BillingPlan plan) async {
    try {
      final supported = await PlayBillingService.instance.isBillingSupported();
      if (!supported) {
        return const BillingResult(
          launched: false,
          message: 'Google Play Billing is not available on this device.',
        );
      }
      final launched =
          await PlayBillingService.instance.purchaseProduct(plan.tier);
      return launched
          ? BillingResult.ok
          : const BillingResult(
              launched: false,
              message: 'Could not start the Google Play purchase.',
            );
    } catch (e) {
      debugPrint('BillingService._payWithPlayBilling error: $e');
      return const BillingResult(
        launched: false,
        message: 'Could not start the Google Play purchase.',
      );
    }
  }
}
