import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Admin-configured subscription amounts (ZAR per user per month), stored on
/// `admin_config/pricing`. Distinct hunter + outfitter rates are set
/// manually in the Admin portal; the revenue figures are derived from the
/// configured rates × the current subscriber counts.
///
/// **VAT model (Option A)**: the amounts are the **VAT-inclusive** final
/// charge the customer pays (R34.99 / R299.99). 15% SA VAT is *absorbed* out
/// of that amount, not added on top — the exclusive component is
/// `incl / 1.15`. The document therefore also carries the derived
/// `price_excl` / `price_incl` / `vat` / `display_price` fields so the
/// control plane and the Play Console base plan can be reconciled at a
/// glance.
///
/// `admin_config/*` documents are admin-write / signed-in-read per
/// `firestore.rules`, so the values are a server-owned control-plane input
/// that every client reads but only an admin can change.
class SubscriptionConfig {
  final double hunterSubscriptionZAR;
  final double outfitterSubscriptionZAR;

  const SubscriptionConfig({
    this.hunterSubscriptionZAR = 0.0,
    this.outfitterSubscriptionZAR = 0.0,
  });

  SubscriptionConfig copyWith({
    double? hunterSubscriptionZAR,
    double? outfitterSubscriptionZAR,
  }) =>
      SubscriptionConfig(
        hunterSubscriptionZAR:
            hunterSubscriptionZAR ?? this.hunterSubscriptionZAR,
        outfitterSubscriptionZAR:
            outfitterSubscriptionZAR ?? this.outfitterSubscriptionZAR,
      );

  /// South African VAT rate applied to subscriptions (percent).
  static const double vatRatePercent = 15.0;

  /// The VAT-exclusive component of a VAT-inclusive [amount]
  /// (`amount / 1.15`, rounded to whole cents).
  static double exclusiveOf(double amount) =>
      double.parse((amount / (1 + vatRatePercent / 100)).toStringAsFixed(2));

  /// The VAT component of a VAT-inclusive [amount] (`amount − excl`).
  static double vatOf(double amount) =>
      double.parse((amount - exclusiveOf(amount)).toStringAsFixed(2));

  /// Human-readable display label, e.g. `"R34.99/month incl. VAT"`.
  static String displayPriceFor(double amount) =>
      'R${amount.toStringAsFixed(2)}/month incl. VAT';

  /// Firestore / model hydration. Numeric strings are tolerated.
  ///
  /// Canonical field names are `hunter_monthly` / `outfitter_monthly` (the
  /// `admin_config/pricing` schema); the legacy camelCase keys are accepted
  /// as read aliases so a doc written by an older build still resolves. The
  /// `<tier>_monthly` amount is the VAT-INCLUSIVE charge; a doc holding only
  /// the exclusive `price_excl` reconciles to the inclusive amount.
  static SubscriptionConfig fromMap(Map<String, dynamic>? data) {
    if (data == null) return const SubscriptionConfig();
    return SubscriptionConfig(
      hunterSubscriptionZAR: _resolveInclusive(
        exclusive: _firstPositive(data['hunter_price_excl']),
        inclusive: _firstPositive(
            data['hunter_monthly'] ?? data['hunterSubscriptionZAR']),
      ),
      outfitterSubscriptionZAR: _resolveInclusive(
        exclusive: _firstPositive(data['outfitter_price_excl']),
        inclusive: _firstPositive(
            data['outfitter_monthly'] ?? data['outfitterSubscriptionZAR']),
      ),
    );
  }

  /// The admin-config payload. Writes the canonical snake_case keys the
  /// control plane uses, the legacy camelCase aliases, AND the derived
  /// VAT-inclusive/exclusive breakdown for both tiers so any reader (old or
  /// new) resolves the same amount.
  Map<String, dynamic> toMap() => {
        'hunter_monthly': hunterSubscriptionZAR,
        'outfitter_monthly': outfitterSubscriptionZAR,
        'hunterSubscriptionZAR': hunterSubscriptionZAR,
        'outfitterSubscriptionZAR': outfitterSubscriptionZAR,
        'vat': vatRatePercent,
        'hunter_price_excl': exclusiveOf(hunterSubscriptionZAR),
        'hunter_price_incl': hunterSubscriptionZAR,
        'outfitter_price_excl': exclusiveOf(outfitterSubscriptionZAR),
        'outfitter_price_incl': outfitterSubscriptionZAR,
        'hunter_display_price': displayPriceFor(hunterSubscriptionZAR),
        'outfitter_display_price': displayPriceFor(outfitterSubscriptionZAR),
      };

  /// Resolves the VAT-inclusive amount: the stored inclusive value when
  /// positive, else the exclusive value grossed up by VAT, else 0.
  static double _resolveInclusive({
    required double? exclusive,
    required double? inclusive,
  }) {
    if (inclusive != null && inclusive > 0) return inclusive;
    if (exclusive != null && exclusive > 0) {
      return double.parse(
          (exclusive * (1 + vatRatePercent / 100)).toStringAsFixed(2));
    }
    return 0.0;
  }

  static double? _firstPositive(dynamic v) {
    final d = _asDouble(v);
    return d > 0 ? d : null;
  }

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}

/// Derived subscription-driven revenue totals for the dashboard.
class SubscriptionRevenue {
  final int hunterCount;
  final int outfitterCount;
  final SubscriptionConfig config;

  const SubscriptionRevenue({
    required this.hunterCount,
    required this.outfitterCount,
    required this.config,
  });

  double get monthlyRecurringRevenue =>
      hunterCount * config.hunterSubscriptionZAR +
      outfitterCount * config.outfitterSubscriptionZAR;
  double get annualProjection => monthlyRecurringRevenue * 12;
  double get dailyEstimate => monthlyRecurringRevenue / 30;
  double get weeklyEstimate => monthlyRecurringRevenue * 7 / 30;
}

/// Reads / writes the Admin-configured subscription amounts and computes the
/// derived revenue figures for the Admin portal.
class SubscriptionConfigService {
  SubscriptionConfigService._();
  static final SubscriptionConfigService instance = SubscriptionConfigService._();

  /// Config document path. `admin_config/*` docs are admin-write /
  /// signed-in-read per `firestore.rules`.
  static const String configPath = 'admin_config';
  static const String configDocId = 'pricing';

  /// Admin control-plane defaults (ZAR / month, **VAT inclusive**). Used ONLY
  /// as the last-resort fallback when neither the live Play catalog NOR the
  /// `admin_config/pricing` document resolves an amount (e.g. first launch
  /// offline, billing unsupported, Firestore unreadable). The Admin Portal is
  /// the control plane; the Play Console is the charge truth.
  ///
  /// Option A: R34.99 / R299.99 is the FINAL charge — 15% VAT is absorbed out
  /// of it (R30.43 / R260.86 excl).
  static const double defaultHunterMonthlyZAR = 34.99;
  static const double defaultOutfitterMonthlyZAR = 299.99;

  /// Test seam: inject `FakeFirebaseFirestore` (same pattern as the other
  /// admin services) so the config round-trip is unit-testable.
  @visibleForTesting
  static FirebaseFirestore? firestoreForTesting;

  /// Test seam: resolve the admin uid stamped as `updatedBy`.
  @visibleForTesting
  static String? Function()? currentUserIdResolverForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    firestoreForTesting = null;
    currentUserIdResolverForTesting = null;
    _cached = null;
  }

  FirebaseFirestore get _db => firestoreForTesting ?? FirebaseFirestore.instance;

  /// Last successfully loaded config, cached in-memory so synchronous UI
  /// consumers (dashboard cards, checkout copy) can render the live admin
  /// amount without awaiting a Firestore round-trip. Populated by
  /// [loadConfig] / [getFallbackPrice]; `null` until the first load.
  static SubscriptionConfig? _cached;
  static SubscriptionConfig? get cachedPricing => _cached;

  String? get _uid {
    final resolver = currentUserIdResolverForTesting;
    if (resolver != null) return resolver();
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null; // [core/no-app] during cold-launch / widget tests
    }
  }

  /// Loads the current config (zero amounts when absent/unreadable). The
  /// successful result is cached for synchronous consumers.
  Future<SubscriptionConfig> loadConfig() async {
    try {
      final snap = await _db.collection(configPath).doc(configDocId).get();
      final config = SubscriptionConfig.fromMap(snap.data());
      _cached = config;
      return config;
    } catch (_) {
      return const SubscriptionConfig();
    }
  }

  /// Loads the config, falling back to the documented
  /// [defaultHunterMonthlyZAR] / [defaultOutfitterMonthlyZAR] for any amount
  /// that is absent / zero on the stored document. Used by the Admin Portal so
  /// the MRR box + the SAVE inputs are pre-seeded with a real price rather
  /// than R0.00 on a first run before an admin has saved anything.
  Future<SubscriptionConfig> loadConfigOrDefaults() async {
    final stored = await loadConfig();
    return SubscriptionConfig(
      hunterSubscriptionZAR: stored.hunterSubscriptionZAR > 0
          ? stored.hunterSubscriptionZAR
          : defaultHunterMonthlyZAR,
      outfitterSubscriptionZAR: stored.outfitterSubscriptionZAR > 0
          ? stored.outfitterSubscriptionZAR
          : defaultOutfitterMonthlyZAR,
    );
  }

  /// The live admin-configured monthly price (ZAR) for [tierKey]
  /// (`'hunter'` / `'outfitter'`).
  ///
  /// Reads `admin_config/pricing` and falls back to the documented
  /// [defaultHunterMonthlyZAR] / [defaultOutfitterMonthlyZAR] only when the
  /// document is absent / unreadable / carries no positive amount. Never
  /// throws — a caller always receives a usable amount.
  Future<double> getFallbackPrice(String tierKey) async {
    final config = await loadConfig();
    final isOutfitter = tierKey.toLowerCase() == 'outfitter';
    final configured =
        isOutfitter ? config.outfitterSubscriptionZAR : config.hunterSubscriptionZAR;
    if (configured > 0) return configured;
    return isOutfitter ? defaultOutfitterMonthlyZAR : defaultHunterMonthlyZAR;
  }

  /// Saves the admin-configured amounts (merge so other `admin_config` fields
  /// are preserved). Invalid (negative) amounts are clamped to zero. Stamps
  /// `updatedAt` (server timestamp) + `updatedBy` (admin uid) so the control
  /// plane is auditable.
  Future<void> saveConfig(SubscriptionConfig config) async {
    final sanitized = SubscriptionConfig(
      hunterSubscriptionZAR:
          config.hunterSubscriptionZAR < 0 ? 0.0 : config.hunterSubscriptionZAR,
      outfitterSubscriptionZAR: config.outfitterSubscriptionZAR < 0
          ? 0.0
          : config.outfitterSubscriptionZAR,
    );
    final payload = <String, dynamic>{
      ...sanitized.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (_uid != null) 'updatedBy': _uid,
    };
    await _db
        .collection(configPath)
        .doc(configDocId)
        .set(payload, SetOptions(merge: true));
    _cached = sanitized;
  }

  /// Pure revenue derivation: configured amounts × the respective subscriber
  /// counts. Unit-testable without a Firestore emulator.
  static SubscriptionRevenue computeRevenue(
    SubscriptionConfig config, {
    required int hunterCount,
    required int outfitterCount,
  }) =>
      SubscriptionRevenue(
        hunterCount: hunterCount,
        outfitterCount: outfitterCount,
        config: config,
      );
}
