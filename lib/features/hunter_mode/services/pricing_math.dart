/// Pure, dependency-free pricing arithmetic for the JagSpoor marketplace.
///
/// Single source of truth for the hunter-facing total price. Every
/// hunter-facing surface (package cards, booking sheets, custom-package
/// builder) and every outfitter financial surface (revenue summary, payout
/// reports) routes through these functions so the totals math can never drift
/// between screens.
///
/// Semantics (the canonical data model written to every `bookings` document
/// by `PackageBookingManager`):
/// - `basePriceRands` — the outfitter's listed base price. This IS the
///   total the hunter pays; there is no platform commission / markup.
/// - `totalHunterPriceRands` = `basePriceRands` — the hunter-facing total
///   (kept as a separate field for read compatibility with legacy docs).
///
/// There is no platform fee / commission and no deposit split: the total
/// amount simply reflects the base package/booking cost. The outfitter's net
/// earnings equal the gross revenue collected from hunters.
class PricingMath {
  PricingMath._();

  /// Formats a ZAR money amount for hunter-facing display, e.g.
  /// `formatCurrency(1234.5)` → `'R 1 234.50'`, `formatCurrency(0)` →
  /// `'R 0.00'`. Locale-independent (no external intl dep): groups
  /// thousands with a thin space and always emits two decimals so prices
  /// line up. Single source of truth for the marketplace / booking-card
  /// price labels.
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

  /// Resolves a stored booking/package document's hunter-facing total.
  ///
  /// There is no platform markup: the total equals the base price. For
  /// legacy documents that carry a marked-up `totalHunterPriceRands` /
  /// `totalPriceZAR` (written by a prior version that applied a 7.5%
  /// commission), the base price is preferred so the displayed total
  /// reflects the base booking cost with no platform cut. When the base
  /// price is absent, the stored total is used as a non-zero fallback.
  ///
  /// [totalHunterPrice] is the stored total (may be `null`/`0` for legacy
  /// documents); [basePrice] is the stored base price.
  static double resolveHunterTotal({
    required double? totalHunterPrice,
    required double basePrice,
  }) {
    if (basePrice > 0) return basePrice;
    if (totalHunterPrice != null && totalHunterPrice > 0) {
      return totalHunterPrice;
    }
    return 0.0;
  }

  /// Aggregates a list of booking records into the outfitter financial
  /// summary used by the revenue dashboard.
  ///
  /// - `grossRevenue` = sum of the booking totals (total collected from
  ///   hunters = the base price; there is no platform commission).
  /// - `netEarnings` = `grossRevenue` (the outfitter receives the full
  ///   booking amount; no platform cut is deducted).
  ///
  /// Each record is a map with optional `basePriceRands` and
  /// `totalHunterPriceRands` fields (the shape written to `bookings`
  /// documents). Pure / dependency-free so the aggregation can be
  /// unit-tested without the Firestore emulator.
  static ({
    double grossRevenue,
    double netEarnings,
    int totalBookings,
  }) aggregateRevenueSummary(Iterable<Map<String, dynamic>> bookings) {
    double grossRevenue = 0.0;
    var totalBookings = 0;

    for (final data in bookings) {
      final basePrice = (data['basePriceRands'] as num?)?.toDouble() ?? 0.0;
      final storedTotal =
          (data['totalHunterPriceRands'] as num?)?.toDouble();
      grossRevenue += resolveHunterTotal(
        totalHunterPrice: storedTotal,
        basePrice: basePrice,
      );
      totalBookings++;
    }

    return (
      grossRevenue: grossRevenue,
      netEarnings: grossRevenue,
      totalBookings: totalBookings,
    );
  }
}
