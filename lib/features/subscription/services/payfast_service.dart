import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/services/user_role_provider.dart';

/// The subscription tier a user is billed on. Mirrors the app's role model
/// (`UserRoleProvider.AppRole`) but lives here so the pricing engine has no
/// dependency on the role provider for pure payload construction.
enum SubscriptionTier {
  hunter,
  outfitter;

  /// Resolves the billing tier from the app's operational role. Admins are
  /// not billed; an unknown / admin role maps to [SubscriptionTier.hunter]
  /// (the cheaper tier) so a caller never over-charges by default.
  static SubscriptionTier fromAppRole(AppRole role) =>
      role == AppRole.outfitter ? SubscriptionTier.outfitter : SubscriptionTier.hunter;

  static SubscriptionTier fromString(String? value) =>
      value == 'outfitter' ? SubscriptionTier.outfitter : SubscriptionTier.hunter;

  String get key => name;
}

/// Lifecycle state of a user's subscription, as written by the PayFast ITN
/// webhook onto `users/{uid}.subscriptionStatus`.
enum SubscriptionStatus {
  /// No subscription on record.
  none,

  /// Inside the initial 30-day free trial (set client-side at checkout).
  trial,

  /// Actively billed (set by the ITN handler on a COMPLETE subscription
  /// payment).
  active,

  /// Billing cancelled / lapsed (set by the ITN handler on a FAILED /
  /// CANCELLED notification).
  cancelled;

  static SubscriptionStatus fromString(String? value) {
    switch (value) {
      case 'trial':
        return SubscriptionStatus.trial;
      case 'active':
        return SubscriptionStatus.active;
      case 'cancelled':
        return SubscriptionStatus.cancelled;
      default:
        return SubscriptionStatus.none;
    }
  }

  String get key => name;
}

/// A resolved promo / discount code adjustment applied to the checkout total
/// before the payment payload is generated.
class PromoCodeAdjustment {
  /// The normalized (upper-cased, trimmed) code that was applied.
  final String code;

  /// Percentage discount (0-100) applied to the recurring amount.
  final double percentOff;

  /// Absolute ZAR discount applied to the recurring amount.
  final double amountOffZAR;

  const PromoCodeAdjustment({
    required this.code,
    this.percentOff = 0.0,
    this.amountOffZAR = 0.0,
  });

  /// Applies the adjustment to [baseAmount] and clamps to >= 0.
  double apply(double baseAmount) {
    var adjusted = baseAmount;
    if (percentOff > 0) adjusted -= baseAmount * (percentOff / 100.0);
    if (amountOffZAR > 0) adjusted -= amountOffZAR;
    return adjusted < 0 ? 0.0 : adjusted;
  }
}

/// Pure promo-code engine. Codes are validated against a lookup map so the
/// hook is live today and can be wired to a remote promo catalog later
/// without touching the checkout flow.
class PromoCodeEngine {
  PromoCodeEngine._();

  /// Built-in promo catalog (upper-cased code -> adjustment). Intended as the
  /// "future use" hook: additional codes can be added here or resolved from a
  /// remote source and merged in via [validate] callers.
  static const Map<String, PromoCodeAdjustment> _catalog = {
    'JAGSPOOR10': PromoCodeAdjustment(code: 'JAGSPOOR10', percentOff: 10),
    'LAUNCH25': PromoCodeAdjustment(code: 'LAUNCH25', percentOff: 25),
    'SAHUNTER50': PromoCodeAdjustment(code: 'SAHUNTER50', percentOff: 50),
  };

  /// Normalizes a raw user-entered code (trim + upper-case).
  static String normalize(String? raw) => (raw ?? '').trim().toUpperCase();

  /// Validates [raw] against the catalog. Returns the adjustment for a known
  /// code, `null` for an unknown / blank code (treated as "no promo").
  static PromoCodeAdjustment? validate(String? raw) {
    final code = normalize(raw);
    if (code.isEmpty) return null;
    return _catalog[code];
  }

  /// Whether [raw] is a syntactically valid, known promo code.
  static bool isValid(String? raw) => validate(raw) != null;
}

/// Immutable PayFast environment configuration (sandbox vs production).
class PayFastConfig {
  final String merchantId;
  final String merchantKey;
  final String passphrase;
  final String processUrl;
  final bool isSandbox;

  const PayFastConfig({
    required this.merchantId,
    required this.merchantKey,
    required this.passphrase,
    required this.processUrl,
    required this.isSandbox,
  });
}

/// The fully-constructed PayFast subscription checkout payload, ready to be
/// URL-encoded and launched.
class PayFastCheckoutPayload {
  /// Ordered field map (insertion order == PayFast signature order).
  final Map<String, String> fields;

  /// The PayFast endpoint the form should POST to.
  final String processUrl;

  const PayFastCheckoutPayload({required this.fields, required this.processUrl});

  /// The MD5 signature carried on the payload (`fields['signature']`).
  String get signature => fields['signature'] ?? '';

  /// URL-encoded query string of every field (signature included).
  String toQueryString() => fields.entries
      .map((e) => '${e.key}=${PayFastService.encodeValue(e.value)}')
      .join('&');

  /// The full GET-style checkout URL (PayFast accepts a form GET/POST).
  Uri toUri() => Uri.parse('$processUrl?${toQueryString()}');
}

/// PayFast subscription billing service.
///
/// Implements the subscription checkout flow:
///  - Sandbox / production endpoint toggling via environment flags.
///  - Role-based pricing: Hunter R19.99/month, Outfitter R199.99/month.
///  - An initial 30-day free trial before recurring billing starts.
///  - MD5 signature generation with the merchant passphrase for data
///    integrity validation.
///
/// The pure payload / signature methods are static + dependency-free so they
/// are fully unit-testable; [launchCheckout] is the thin platform wrapper.
class PayFastService {
  PayFastService._();
  static final PayFastService instance = PayFastService._();

  // --- Pricing (ZAR per month) ---
  static const double hunterMonthlyZAR = 19.99;
  static const double outfitterMonthlyZAR = 199.99;

  // --- Trial ---
  /// Length of the initial free trial before the first recurring charge.
  static const int trialDays = 30;

  // --- Endpoints ---
  static const String sandboxProcessUrl =
      'https://sandbox.payfast.co.za/eng/process';
  static const String productionProcessUrl =
      'https://www.payfast.co.za/eng/process';

  // --- Sandbox credentials (per integration spec) ---
  static const String sandboxMerchantId = '10053397';
  static const String sandboxMerchantKey = 'svmau2781rcn';
  static const String sandboxPassphrase = 'jagspoor_sandbox_2026';

  // --- Environment flag ---
  /// Whether the sandbox environment is active. Overridable at compile time
  /// via `--dart-define=PAYFAST_SANDBOX=false` for a production build; the
  /// default (and debug builds) stay on the sandbox so a release candidate
  /// never accidentally bills a live card during testing.
  static const bool _compiledSandbox = bool.fromEnvironment(
    'PAYFAST_SANDBOX',
    defaultValue: true,
  );

  /// Whether the sandbox endpoints are in use. Debug/profile builds always
  /// use the sandbox; release builds honor the compiled flag.
  static bool get isSandbox => kDebugMode ? true : _compiledSandbox;

  /// The active PayFast configuration for the current environment.
  static PayFastConfig get activeConfig => isSandbox
      ? const PayFastConfig(
          merchantId: sandboxMerchantId,
          merchantKey: sandboxMerchantKey,
          passphrase: sandboxPassphrase,
          processUrl: sandboxProcessUrl,
          isSandbox: true,
        )
      : const PayFastConfig(
          // Production credentials are injected at release time; the sandbox
          // pair is the only credential set bundled with the app.
          merchantId: sandboxMerchantId,
          merchantKey: sandboxMerchantKey,
          passphrase: sandboxPassphrase,
          processUrl: productionProcessUrl,
          isSandbox: false,
        );

  /// The base monthly amount for [tier] before any promo adjustment.
  static double baseAmountFor(SubscriptionTier tier) =>
      tier == SubscriptionTier.outfitter ? outfitterMonthlyZAR : hunterMonthlyZAR;

  /// The final recurring amount after applying [promo] (null = no promo).
  static double resolveAmount(SubscriptionTier tier, PromoCodeAdjustment? promo) {
    final base = baseAmountFor(tier);
    return promo == null ? base : promo.apply(base);
  }

  /// The date the first recurring charge falls due (now + [trialDays]).
  static DateTime trialEndDate(DateTime from) => from.add(const Duration(days: trialDays));

  /// PayFast percent-encoding: RFC 3986 with spaces as `+` (NOT `%20`).
  static String encodeValue(String value) =>
      Uri.encodeComponent(value).replaceAll('%20', '+');

  /// Builds the signature source string: the ordered `key=value` pairs joined
  /// with `&`, each value percent-encoded, with the passphrase appended as
  /// `&passphrase=<encoded>` when present.
  static String buildSignatureSource(
    Map<String, String> fields, {
    String? passphrase,
  }) {
    final buffer = StringBuffer();
    fields.forEach((key, value) {
      if (key == 'signature') return;
      if (value.isEmpty) return;
      if (buffer.isNotEmpty) buffer.write('&');
      buffer.write('$key=${encodeValue(value)}');
    });
    if (passphrase != null && passphrase.isNotEmpty) {
      buffer.write('&passphrase=${encodeValue(passphrase)}');
    }
    return buffer.toString();
  }

  /// Generates the MD5 signature over [fields] using the merchant
  /// [passphrase]. This is the data-integrity validation PayFast performs on
  /// every checkout + ITN payload.
  static String generateSignature(
    Map<String, String> fields, {
    String? passphrase,
  }) {
    final source = buildSignatureSource(fields, passphrase: passphrase);
    return md5.convert(utf8.encode(source)).toString();
  }

  /// Verifies a received signature (e.g. from an ITN payload) against the
  /// expected MD5.
  static bool verifySignature(
    Map<String, String> fields,
    String receivedSignature, {
    String? passphrase,
  }) =>
      generateSignature(fields, passphrase: passphrase) ==
      receivedSignature.toLowerCase();

  /// Builds the ordered subscription checkout payload for [tier].
  ///
  /// [userId] / [emailAddress] identify the subscriber; [promo] (optional)
  /// adjusts the recurring amount before the payload is generated; [now]
  /// fixes the trial window for deterministic tests.
  ///
  /// PayFast subscription fields used:
  ///  - `subscription_type=1` -> recurring subscription.
  ///  - `billing_date` -> first recurring charge date (start of paid billing,
  ///    i.e. after the 30-day free trial).
  ///  - `recurring_amount` -> the monthly charge (promo-adjusted).
  ///  - `frequency=3` -> monthly billing.
  ///  - `cycles=0` -> bill until cancelled.
  ///  - `custom_str1` -> carries the trial marker (`trial_30d`) so the ITN
  ///    handler can distinguish trial-start from recurring billing events.
  ///  - `custom_str2` -> the billing tier (`hunter` / `outfitter`).
  ///  - `custom_str3` -> the applied promo code (empty when none).
  static PayFastCheckoutPayload buildCheckoutPayload({
    required SubscriptionTier tier,
    required String userId,
    required String emailAddress,
    String? userName,
    PromoCodeAdjustment? promo,
    DateTime? now,
    PayFastConfig? config,
  }) {
    final cfg = config ?? activeConfig;
    final amount = resolveAmount(tier, promo);
    final billingDate = trialEndDate(now ?? DateTime.now());
    final billingDateStr =
        '${billingDate.year.toString().padLeft(4, '0')}-'
        '${billingDate.month.toString().padLeft(2, '0')}-'
        '${billingDate.day.toString().padLeft(2, '0')}';

    // Insertion order matters: PayFast signs fields in payload order.
    final fields = <String, String>{
      'merchant_id': cfg.merchantId,
      'merchant_key': cfg.merchantKey,
      'return_url': 'https://jagspoor.page.link/subscription-return',
      'cancel_url': 'https://jagspoor.page.link/subscription-cancel',
      'notify_url':
          'https://us-central1-jagspoor.cloudfunctions.net/payfastSubscriptionITN',
      'name_first': userName ?? '',
      'email_address': emailAddress,
      'm_payment_id': 'sub_${userId}_${tier.key}',
      'amount': amount.toStringAsFixed(2),
      'item_name': 'JagSpoor ${tier == SubscriptionTier.outfitter ? 'Outfitter' : 'Hunter'} Subscription',
      'item_description':
          'Monthly ${tier.key} subscription ($trialDays-day free trial, then R${amount.toStringAsFixed(2)}/month)',
      'custom_str1': 'trial_${trialDays}d',
      'custom_str2': tier.key,
      'custom_str3': promo?.code ?? '',
      'subscription_type': '1',
      'billing_date': billingDateStr,
      'recurring_amount': amount.toStringAsFixed(2),
      'frequency': '3', // monthly
      'cycles': '0', // until cancelled
    };

    fields['signature'] =
        generateSignature(fields, passphrase: cfg.passphrase);
    return PayFastCheckoutPayload(fields: fields, processUrl: cfg.processUrl);
  }

  /// Launches the PayFast subscription checkout in the external browser.
  /// Returns whether a browser accepted the hand-off.
  Future<bool> launchCheckout(PayFastCheckoutPayload payload) async {
    try {
      return await launchUrl(
        payload.toUri(),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('PayFastService.launchCheckout failed: $e');
      return false;
    }
  }
}
