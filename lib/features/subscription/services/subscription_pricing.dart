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
  /// the same application id (`com.example.jagspoor`), configured as
  /// *Subscriptions* with the sale price below (R 19.99 / R 199.99 per month).
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

/// The canonical `users/{uid}.subscriptionStatus` string representing an
/// active free trial. This is the value the automatic trial assignment writes
/// (and the value the backend `initializeNewUserTrial` Auth trigger writes),
/// so the client and the Cloud Function agree on a single trial status.
const String subscriptionStatusTrial = 'trialing';

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