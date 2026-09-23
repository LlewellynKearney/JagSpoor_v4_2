import '../../admin/services/subscription_config_service.dart';
import '../../auth/services/user_role_provider.dart';

/// The billing tier a user is subscribed to. Mirrors the app's role model
/// ([UserRoleProvider.AppRole]) but lives here so the pricing engine has no
/// dependency on the role provider for pure billing logic.
enum SubscriptionTier {
  hunter,
  outfitter;

  /// Resolves the billing tier from the app's operational role. Admins are
  /// not billed; an unknown / admin role maps to [SubscriptionTier.hunter]
  /// (the cheaper tier) so a caller never over-charges by default.
  static SubscriptionTier fromAppRole(AppRole role) =>
      role == AppRole.outfitter
          ? SubscriptionTier.outfitter
          : SubscriptionTier.hunter;

  static SubscriptionTier fromString(String? value) =>
      value == 'outfitter' ? SubscriptionTier.outfitter : SubscriptionTier.hunter;

  String get key => name;

  /// The Google Play Billing product id backing this tier.
  ///
  /// These SkuDetails ids must be created in the Google Play Console under
  /// the same application id (`za.co.jagspoor.app`), configured as
  /// *Subscriptions*. The sale price lives in the Play Console base plan
  /// (the charge truth) and must match the Admin Portal
  /// `admin_config/pricing` amounts — the VAT-inclusive control-plane
  /// defaults are R 34.99 / R 299.99 per month (Option A: the listed price is
  /// the final charge; 15% VAT is absorbed out of it).
  String get playProductId => switch (this) {
        SubscriptionTier.hunter => 'jagspoor_hunter_monthly',
        SubscriptionTier.outfitter => 'jagspoor_outfitter_monthly',
      };

  /// Resolves the billing tier from a Play Billing product id.
  static SubscriptionTier fromPlayProductId(String? productId) =>
      productId == SubscriptionTier.outfitter.playProductId
          ? SubscriptionTier.outfitter
          : SubscriptionTier.hunter;
}

/// How long the free trial granted to newly registered standard accounts
/// lasts (30 days).
const Duration trialDuration = Duration(days: 30);

/// Last-resort fallback monthly prices (ZAR) for the two billing tiers.
///
/// These are **VAT-inclusive** end-user amounts (Option A: the customer pays
/// R34.99 / R299.99 and that is the final charge — VAT is absorbed out of it,
/// not added on top). At the 15% SA VAT rate that is R30.43 excl / R34.99
/// incl and R260.86 excl / R299.99 incl.
///
/// They mirror the Admin Portal defaults
/// ([SubscriptionConfigService.defaultHunterMonthlyZAR] /
/// [SubscriptionConfigService.defaultOutfitterMonthlyZAR]) and are used ONLY
/// when NEITHER the live Play Billing catalog
/// ([PlayBillingService.loadProducts] → `PlayProduct.rawPrice`, the
/// authoritative charge) NOR the admin-controlled `admin_config/pricing`
/// document resolves an amount. The Admin Portal is the control plane; the
/// Play Console is the charge truth — see [resolveMonthlyPrice].
///
/// The Play Console base plan MUST be configured as R34.99 / R299.99
/// **including VAT** so `ProductDetails.price` (the value the paywall shows)
/// matches these fallbacks.
const double hunterMonthlyPriceZAR = 34.99;
const double outfitterMonthlyPriceZAR = 299.99;

/// South African Value-Added Tax rate (15%) applied to Google Play catalog
/// prices, which are quoted **excluding VAT** in South Africa.
const double saVatRate = 0.15;

/// Tolerance (ZAR) within which two reconciled price figures count as equal.
///
/// The Play Console catalog amount is quoted **excluding VAT** while the Admin
/// control plane stores the **VAT-inclusive** amount, so a reconciliation must
/// gross the catalog figure up by 15% before comparing. Rounding across the two
/// representations (and the store's own cent rounding) can drift by a fraction
/// of a cent, so a 2-cent tolerance avoids a false PRICE DIVERGENCE warning
/// (e.g. Play R30.43 excl -> R34.9945 incl vs Admin R34.99).
const double priceDivergenceToleranceZAR = 0.02;

/// Reconciles a Google Play catalog amount against an Admin-configured amount
/// under the Option A (VAT-inclusive listed price) model.
///
/// Google Play quotes the catalog amount EXCLUDING VAT in South Africa; the
/// Admin control plane (`admin_config/pricing`) stores the FINAL VAT-INCLUSIVE
/// charge the customer pays. A naive comparison of the two figures is therefore
/// always wrong (R30.43 vs R34.99). This helper performs the correct
/// reconciliation — `playExVat * 1.15` vs `adminInclVat`, within
/// [priceDivergenceToleranceZAR] — and produces the operator-facing copy.
///
/// Single source of truth used by the Admin Portal divergence banner and the
/// subscriber-facing checkout notice so both agree on when (and how) to warn.
class PlayPriceReconciliation {
  /// Catalog amount **excluding** VAT, as returned by Play (`rawPrice`).
  final double playExVat;

  /// Catalog amount **including** VAT (`playExVat * (1 + vatRate)`).
  final double playInclVat;

  /// Admin-configured amount (already VAT inclusive).
  final double adminInclVat;

  /// Currency symbol used in the generated [matchMessage] / [mismatchMessage].
  final String currencySymbol;

  /// Tolerance within which the inclusive amounts count as equal.
  final double tolerance;

  const PlayPriceReconciliation({
    required this.playExVat,
    required this.playInclVat,
    required this.adminInclVat,
    this.currencySymbol = 'R',
    this.tolerance = priceDivergenceToleranceZAR,
  });

  /// Builds the reconciliation: grosses [playExVat] up to the VAT-inclusive
  /// payable amount and compares it against the Admin-inclusive
  /// [adminInclVat]. Non-finite inputs collapse to zero so the UI can never
  /// render `NaN`.
  factory PlayPriceReconciliation.compare({
    required double playExVat,
    required double adminInclVat,
    double vatRate = saVatRate,
    String currencySymbol = 'R',
    double tolerance = priceDivergenceToleranceZAR,
  }) {
    final exVat = playExVat.isFinite && playExVat > 0 ? playExVat : 0.0;
    final admin =
        adminInclVat.isFinite && adminInclVat > 0 ? adminInclVat : 0.0;
    return PlayPriceReconciliation(
      playExVat: exVat,
      playInclVat: exVat * (1 + vatRate),
      adminInclVat: admin,
      currencySymbol: currencySymbol.isEmpty ? 'R' : currencySymbol,
      tolerance: tolerance,
    );
  }

  String _fmt(double v) => '$currencySymbol${v.toStringAsFixed(2)}';

  /// Whether the Play (grossed-up) and Admin amounts agree within [tolerance].
  /// When this is true the operator banner must stay hidden.
  bool get matches => (playInclVat - adminInclVat).abs() < tolerance;

  /// Confirmation copy, e.g.
  /// `Play Console R30.43 excl (R34.99 incl) matches Admin R34.99`.
  String get matchMessage => 'Play Console ${_fmt(playExVat)} excl '
      '(${_fmt(playInclVat)} incl) matches Admin ${_fmt(adminInclVat)}';

  /// Warning copy, e.g.
  /// `Play Console R30.43 excl (R34.99 incl) != Admin R35.99 — update Play
  /// Console base plan to match.`
  String get mismatchMessage => 'Play Console ${_fmt(playExVat)} excl '
      '(${_fmt(playInclVat)} incl) != Admin ${_fmt(adminInclVat)} — '
      'update Play Console base plan to match.';
}

/// Resolved VAT breakdown for a catalog amount quoted **excluding VAT**.
///
/// Google Play returns the localized, formatted catalog price
/// (`ProductDetails.price` / `rawPrice`) which — in South Africa — is the
/// EX-VAT amount. The app must display the amount the customer actually pays,
/// so the VAT-inclusive amount is derived here (`exVat * 1.15`) and shown as
/// the primary price, with the ex-VAT figure as the explanatory subtext.
///
/// Single source of truth so the paywall / subscription screen and their tests
/// agree on one VAT calculation (`hunter_monthly` + `outfitter_monthly`).
class SubscriptionVatPrice {
  /// Catalog amount excluding VAT.
  final double exVat;

  /// Amount the customer pays, including VAT.
  final double inclVat;

  /// Currency symbol reported by the store (e.g. `R`). Falls back to `R`.
  final String currencySymbol;

  /// The VAT rate applied (defaults to the SA 15%).
  final double vatRate;

  const SubscriptionVatPrice({
    required this.exVat,
    required this.inclVat,
    this.currencySymbol = 'R',
    this.vatRate = saVatRate,
  });

  /// Builds the breakdown for an ex-VAT [exVat] amount, adding VAT at
  /// [vatRate] (default 15%). Non-positive amounts resolve to zero so the UI
  /// can never render a negative price.
  factory SubscriptionVatPrice.fromExVat(
    double exVat, {
    String currencySymbol = 'R',
    double vatRate = saVatRate,
  }) {
    final base = exVat.isFinite && exVat > 0 ? exVat : 0.0;
    return SubscriptionVatPrice(
      exVat: base,
      inclVat: base * (1 + vatRate),
      currencySymbol: currencySymbol.isEmpty ? 'R' : currencySymbol,
      vatRate: vatRate,
    );
  }

  /// The VAT portion of [inclVat].
  double get vatAmount => inclVat - exVat;

  /// Primary price label, e.g. `R228.85/month`.
  String get primaryLabel => '${formatZar(inclVat)}/month';

  /// Explanatory subtext, e.g. `Incl. 15% VAT (R199.00 excl. VAT)`.
  String get vatNote {
    final percent = (vatRate * 100).round();
    return 'Incl. $percent% VAT (${formatZar(exVat)} excl. VAT)';
  }

  /// Formats a ZAR amount with the resolved currency symbol + two decimals
  /// (`199` -> `R199.00`). Locale-independent.
  String formatZar(double amount) =>
      '$currencySymbol${amount.toStringAsFixed(2)}';
}

/// Resolves the monthly display price (ZAR) for [tier] using the documented
/// precedence:
///   1. the LIVE Play catalog `rawPrice` (the authoritative charge), when a
///      product has loaded;
///   2. the admin-controlled `admin_config/pricing` amount (via
///      [SubscriptionConfigService.getFallbackPrice]);
///   3. the hard-coded [hunterMonthlyPriceZAR] / [outfitterMonthlyPriceZAR]
///      last resort.
///
/// Kept on the pricing module so the dashboard cards, the checkout screen and
/// any other price consumer agree on one resolution order.
Future<double> resolveMonthlyPrice(
  SubscriptionTier tier, {
  double? playRawPrice,
}) async {
  if (playRawPrice != null && playRawPrice > 0) return playRawPrice;
  try {
    return await SubscriptionConfigService.instance
        .getFallbackPrice(tier.key);
  } catch (_) {
    return tier == SubscriptionTier.outfitter
        ? outfitterMonthlyPriceZAR
        : hunterMonthlyPriceZAR;
  }
}

/// The canonical `users/{uid}.subscriptionStatus` string representing an
/// active free trial. This is the value the automatic trial assignment writes
/// (and the value the backend `initializeNewUserTrial` Auth trigger writes),
/// so the client and the Cloud Function agree on a single trial status.
const String subscriptionStatusTrial = 'trialing';

/// The canonical `users/{uid}.subscriptionStatus` string representing an
/// actively-billed Google Play subscription. Written by the purchase recorder
/// (`PlayPurchaseRecorder`) once Billing confirms the transaction — the
/// `firestore.rules` guard permits this transition from a trial state.
const String subscriptionStatusActive = 'active';

/// Defines which newly registered accounts automatically receive a free
/// trial. The admin account is excluded so that it keeps its fixed billing
/// tiers rather than being rolled into the standard trial flow.
class TrialAssignmentPolicy {
  /// The platform admin email. Mirrors the allow-list used by
  /// [UserRoleProvider] / [AdminAuthGuard] so the trial bypass agrees with
  /// the rest of the app's admin detection.
  static const String adminEmail = 'admin@jag-spoor.co.za';

  /// The platform admin UID, when known. Left null by default; a deployment
  /// that wants UID-based admin detection sets this to the admin account's
  /// Firebase Auth uid. `null`/empty disables the UID check (email remains
  /// authoritative).
  static String? adminUid;

  /// Whether [userId]/[email] belongs to the JagSpoor admin account.
  ///
  /// The email comparison is case-insensitive + trimmed. The UID check only
  /// applies when [adminUid] has been configured.
  static bool isAdmin(String? userId, String? email) {
    final normalizedEmail = email?.toLowerCase().trim();
    if (normalizedEmail == adminEmail) return true;
    final uid = adminUid;
    if (uid != null && uid.isNotEmpty && userId == uid) return true;
    return false;
  }
}

/// Lifecycle state of a user's subscription, as stored on `users/{uid}`.
enum SubscriptionStatus {
  /// No subscription on record.
  none,

  /// Inside the initial free trial (provisioned by the Play Console trial
  /// offer and/or marked client-side at checkout).
  trial,

  /// Actively billed through Google Play Billing.
  active,

  /// Billing cancelled / lapsed.
  cancelled;

  static SubscriptionStatus fromString(String? value) {
    switch (value) {
      case 'trial':
      case 'trialing':
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

/// A resolved promo / discount code adjustment applied to the checkout total.
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
/// without touching the billing flow.
class PromoCodeEngine {
  PromoCodeEngine._();

  /// Built-in promo catalog (upper-cased code -> adjustment).
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

/// Shared trial-window constant.
///
/// The free-trial period is applied through Google Play Billing (a Play
/// Console offer on the subscription products); this mirrors the window the
/// UI advertises so the trial banner + expiry date stay consistent.
class SubscriptionTrial {
  SubscriptionTrial._();

  /// Length of the initial free trial before the first recurring charge.
  static const int trialDays = 30;
}