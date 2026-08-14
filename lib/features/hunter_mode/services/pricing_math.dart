/// Pure, dependency-free pricing arithmetic for the JagSpoor marketplace.
///
/// Single source of truth for the **absorbed** 7.5% platform markup and the
/// 25% non-refundable deposit. Every hunter-facing surface (package cards,
/// booking sheets, custom-package builder, PayFast checkout) and every
/// outfitter financial surface (revenue summary, payout reports) routes
/// through these functions so the markup, deposit, and net-earnings math can
/// never drift between screens.
///
/// Semantics (the canonical data model written to every `bookings` document
/// by `PackageBookingManager`):
/// - `basePriceRands`      — the outfitter's listed base price, **net of
///   fees** (this is what the outfitter receives).
/// - `platformCommissionRands` = `basePriceRands × 0.075` — the JagSpoor
///   administration commission.
/// - `totalHunterPriceRands` = `basePriceRands × 1.075` — the **marked-up**
///   hunter-facing total (the markup is fully absorbed; no explicit
///   "Platform Fee" line is ever shown to the hunter).
/// - `depositAmountRands` = `totalHunterPriceRands × 0.25` — the 25%
///   non-refundable deposit, computed **off the marked-up total**.
/// - `balanceAmountRands` = `totalHunterPriceRands − depositAmountRands`.
///
/// For an outfitter financial dashboard the outfitter's **net earnings** are
/// the base price (`basePriceRands`), and the "gross revenue" figure is the
/// total collected from hunters (`totalHunterPriceRands`); the difference is
/// the platform fee. So: `netEarnings = grossRevenue − platformFee` and also
/// `netEarnings == basePriceRands`.
class PricingMath {
  PricingMath._();

  /// The flat JagSpoor platform administration commission rate (7.5%).
  static const double platformCommissionRate = 0.075;

  /// The non-refundable deposit fraction charged on approval (25%).
  static const double depositFraction = 0.25;

  /// The hunter-facing markup multiplier (base × 1.075).
  static const double markupMultiplier = 1.0 + platformCommissionRate;

  /// The hunter-facing marked-up total for a given [basePrice]
  /// (`basePrice × 1.075`). Absorbs the 7.5% platform fee — no separate fee
  /// line is shown to the hunter.
  static double markedUpTotal(double basePrice) =>
      basePrice * markupMultiplier;

  /// The 7.5% platform commission for a given [basePrice]
  /// (`basePrice × 0.075`).
  static double commissionFromBase(double basePrice) =>
      basePrice * platformCommissionRate;

  /// The 25% non-refundable deposit computed off the **marked-up** total
  /// (`markedUpTotal × 0.25`). Use this when you only have the base price.
  static double depositFromBase(double basePrice) =>
      markedUpTotal(basePrice) * depositFraction;

  /// The 25% non-refundable deposit computed off an already-marked-up
  /// [markedUpTotal] (`markedUpTotal × 0.25`). Use this when the marked-up
  /// total is already known (e.g. read from a booking document's
  /// `totalHunterPriceRands`).
  static double depositFromMarkedUpTotal(double markedUpTotal) =>
      markedUpTotal * depositFraction;

  /// The balance remaining after the deposit, off the marked-up total.
  static double balanceFromMarkedUpTotal(double markedUpTotal) =>
      markedUpTotal * (1.0 - depositFraction);

  /// The outfitter's net earnings given the gross revenue collected from
  /// hunters and the platform fee (`grossRevenue − platformFee`). This equals
  /// the outfitter's base price.
  static double netEarnings({
    required double grossRevenue,
    required double platformFee,
  }) =>
      grossRevenue - platformFee;

  /// Formats a ZAR money amount for hunter-facing display, e.g.
  /// `formatCurrency(1234.5)` → `'R 1 234.50'`, `formatCurrency(0)` →
  /// `'R 0.00'`. Locale-independent (no external intl dep): groups
  /// thousands with a thin space and always emits two decimals so prices
  /// line up. Single source of truth for the marketplace / booking-card
  /// deposit labels. (v4.5 to-do Item #7.)
  static String formatCurrency(double amount) {
    final neg = amount < 0;
    final abs = amount.abs();
    // Two-decimal rounded base, then group the integer part with thin spaces.
    final rounded = abs.toStringAsFixed(2);
    final dot = rounded.indexOf('.');
    final intPart = dot == -1 ? rounded : rounded.substring(0, dot);
    final decPart = dot == -1 ? '00' : rounded.substring(dot + 1);
    final grouped = _groupThousands(intPart);
    final body = decPart.isEmpty ? grouped : '$grouped.$decPart';
    return '${neg ? '-' : ''}R $body';
  }

  /// Groups an integer string with thin-space thousands separators
  /// (`'1234567'` → `'1\u202F234\u202F567'`). Pure string arithmetic.
  static String _groupThousands(String intPart) {
    if (intPart.length <= 3) return intPart;
    final buf = StringBuffer();
    var count = 0;
    for (var i = intPart.length - 1; i >= 0; i--) {
      if (count == 3) {
        buf.write('\u202F'); // thin space (matches the app's ZAR formatting)
        count = 0;
      }
      buf.write(intPart[i]);
      count++;
    }
    // Reverse the buffer.
    final s = buf.toString();
    return String.fromCharCodes(s.runes.toList().reversed);
  }

  /// Resolves a stored booking/package document's hunter-facing total,
  /// applying the 7.5% markup to the base price when the precomputed
  /// `totalHunterPriceRands` / `totalPriceZAR` field is absent (legacy docs).
  ///
  /// [totalHunterPrice] is the stored marked-up total (may be `null`/`0` for
  /// legacy documents); [basePrice] is the stored base price (always present).
  /// Returns the marked-up total, computing it from the base when the stored
  /// marked-up value is missing.
  static double resolveHunterTotal({
    required double? totalHunterPrice,
    required double basePrice,
  }) {
    if (totalHunterPrice != null && totalHunterPrice > 0) {
      return totalHunterPrice;
    }
    return markedUpTotal(basePrice);
  }

  /// Resolves a stored booking document's 25% deposit, computing it off the
  /// marked-up total when the precomputed `depositAmountRands` field is
  /// absent (legacy docs). Always derived from the marked-up total.
  static double resolveDeposit({
    required double? storedDeposit,
    required double markedUpTotalValue,
  }) {
    if (storedDeposit != null && storedDeposit > 0) {
      return storedDeposit;
    }
    return depositFromMarkedUpTotal(markedUpTotalValue);
  }

  /// Aggregates a list of booking records into the outfitter financial
  /// summary used by the revenue dashboard, applying the net-revenue
  /// protection rules:
  /// - `grossRevenue` = sum of the hunter-facing marked-up totals (total
  ///   collected from hunters, incl. the 7.5% fee).
  /// - `platformFees` = sum of the 7.5% commissions (derived from the base
  ///   when the stored commission is missing).
  /// - `netEarnings` = `grossRevenue − platformFees` = the outfitter's base
  ///   earnings, net of fees (e.g. R10 000 for a R10 000 base listing — NOT
  ///   R10 750 and NOT R9 250).
  ///
  /// Each record is a map with optional `basePriceRands`,
  /// `totalHunterPriceRands`, and `platformCommissionRands` fields (the
  /// shape written to `bookings` documents). Pure / dependency-free so the
  /// aggregation can be unit-tested without the Firestore emulator.
  static ({
    double grossRevenue,
    double platformFees,
    double netEarnings,
    int totalBookings,
  }) aggregateRevenueSummary(Iterable<Map<String, dynamic>> bookings) {
    double grossRevenue = 0.0;
    double platformFees = 0.0;
    var totalBookings = 0;

    for (final data in bookings) {
      final basePrice = (data['basePriceRands'] as num?)?.toDouble() ?? 0.0;
      final storedTotal =
          (data['totalHunterPriceRands'] as num?)?.toDouble();
      final storedCommission =
          (data['platformCommissionRands'] as num?)?.toDouble();

      grossRevenue += resolveHunterTotal(
        totalHunterPrice: storedTotal,
        basePrice: basePrice,
      );
      platformFees +=
          (storedCommission != null && storedCommission > 0)
              ? storedCommission
              : commissionFromBase(basePrice);
      totalBookings++;
    }

    final net = netEarnings(
      grossRevenue: grossRevenue,
      platformFee: platformFees,
    );

    return (
      grossRevenue: grossRevenue,
      platformFees: platformFees,
      netEarnings: net,
      totalBookings: totalBookings,
    );
  }
}
