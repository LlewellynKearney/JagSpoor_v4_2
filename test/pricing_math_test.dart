import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/pricing_math.dart';

/// Unit tests for the single-source pricing arithmetic (`PricingMath`).
///
/// Contract (post platform-commission removal):
/// - There is no platform commission / markup. The hunter-facing total equals
///   the base package/booking cost.
/// - The 25% non-refundable deposit is computed off the total
///   (`total × 0.25`).
/// - The outfitter's net earnings equal the gross revenue collected from
///   hunters (no platform cut is deducted).
void main() {
  group('PricingMath constants', () {
    test('deposit fraction is 25%', () {
      expect(PricingMath.depositFraction, 0.25);
    });
  });

  group('PricingMath.depositFromTotal', () {
    test('25% of the supplied total', () {
      expect(PricingMath.depositFromTotal(10000), closeTo(2500, 0.001));
      expect(PricingMath.depositFromTotal(2500), closeTo(625, 0.001));
    });

    test('zero total yields zero deposit', () {
      expect(PricingMath.depositFromTotal(0), 0);
    });
  });

  group('PricingMath.balanceFromTotal', () {
    test('total minus the 25% deposit (75%)', () {
      expect(PricingMath.balanceFromTotal(10000), closeTo(7500, 0.001));
      // deposit + balance == total
      expect(
        PricingMath.depositFromTotal(10000) +
            PricingMath.balanceFromTotal(10000),
        closeTo(10000, 0.001),
      );
    });
  });

  group('PricingMath.resolveHunterTotal (no commission)', () {
    test('uses the base price when present (total = base)', () {
      expect(
        PricingMath.resolveHunterTotal(
          totalHunterPrice: 10000,
          basePrice: 10000,
        ),
        closeTo(10000, 0.001),
      );
    });

    test('uses the base price when the stored total is null (legacy doc)', () {
      expect(
        PricingMath.resolveHunterTotal(
          totalHunterPrice: null,
          basePrice: 10000,
        ),
        closeTo(10000, 0.001),
      );
    });

    test('uses the base price when the stored total is 0 (legacy doc)', () {
      expect(
        PricingMath.resolveHunterTotal(
          totalHunterPrice: 0,
          basePrice: 10000,
        ),
        closeTo(10000, 0.001),
      );
    });

    test('falls back to the stored total when the base price is absent', () {
      expect(
        PricingMath.resolveHunterTotal(
          totalHunterPrice: 10000,
          basePrice: 0,
        ),
        closeTo(10000, 0.001),
      );
    });

    test('returns 0 when both base and stored total are absent', () {
      expect(
        PricingMath.resolveHunterTotal(
          totalHunterPrice: null,
          basePrice: 0,
        ),
        0,
      );
    });

    test('prefers the base price over a legacy marked-up total', () {
      // A legacy doc may carry a marked-up total (written by a prior version
      // that applied a 7.5% commission). The base price is preferred so the
      // displayed total reflects the base booking cost with no platform cut.
      expect(
        PricingMath.resolveHunterTotal(
          totalHunterPrice: 10750,
          basePrice: 10000,
        ),
        closeTo(10000, 0.001),
        reason: 'base price should win over the legacy marked-up total',
      );
    });
  });

  group('PricingMath.resolveDeposit (legacy fallback)', () {
    test('uses the stored deposit when present', () {
      expect(
        PricingMath.resolveDeposit(
          storedDeposit: 2500,
          total: 10000,
        ),
        closeTo(2500, 0.001),
      );
    });

    test('derives 25% of the total when stored deposit is missing', () {
      expect(
        PricingMath.resolveDeposit(
          storedDeposit: null,
          total: 10000,
        ),
        closeTo(2500, 0.001),
      );
      expect(
        PricingMath.resolveDeposit(
          storedDeposit: 0,
          total: 10000,
        ),
        closeTo(2500, 0.001),
      );
    });
  });

  group('PayFast deposit alignment', () {
    test('the PayFast charge amount equals the 25% deposit off the total', () {
      // The amount submitted to PayFast must be the 25% deposit off the total
      // — the same value rendered on the hunter-facing "25% Deposit" row.
      const base = 10000.0;
      final total = PricingMath.resolveHunterTotal(
        totalHunterPrice: base,
        basePrice: base,
      );
      final displayedDeposit = PricingMath.depositFromTotal(total); // 2500
      final payFastAmount = PricingMath.resolveDeposit(
        storedDeposit: null, // legacy booking → derived
        total: total,
      );
      expect(payFastAmount, equals(displayedDeposit));
      expect(payFastAmount, closeTo(2500, 0.001));
    });
  });

  group('End-to-end booking pricing contract', () {
    test('a R10 000 base listing produces a R10 000 total + R2 500 deposit', () {
      const base = 10000.0;
      final hunterTotal = PricingMath.resolveHunterTotal(
        totalHunterPrice: base,
        basePrice: base,
      );
      final deposit = PricingMath.depositFromTotal(hunterTotal);
      final balance = PricingMath.balanceFromTotal(hunterTotal);

      // Hunter sees: R10 000 total, R2 500 deposit (no Platform Fee line).
      expect(hunterTotal, closeTo(10000, 0.001));
      expect(deposit, closeTo(2500, 0.001));
      expect(balance, closeTo(7500, 0.001));
    });
  });

  group('PricingMath.aggregateRevenueSummary (net = gross)', () {
    test('aggregates booking totals; net equals gross', () {
      final summary = PricingMath.aggregateRevenueSummary([
        {'basePriceRands': 10000, 'totalHunterPriceRands': 10000},
        {'basePriceRands': 5000, 'totalHunterPriceRands': 5000},
      ]);
      // gross = 10000 + 5000 = 15000; net = gross (no platform cut).
      expect(summary.totalBookings, 2);
      expect(summary.grossRevenue, closeTo(15000, 0.001));
      expect(summary.netEarnings, closeTo(15000, 0.001));
    });

    test('uses the base price for legacy docs', () {
      final summary = PricingMath.aggregateRevenueSummary([
        {'basePriceRands': 10000},
      ]);
      expect(summary.totalBookings, 1);
      expect(summary.grossRevenue, closeTo(10000, 0.001));
      expect(summary.netEarnings, closeTo(10000, 0.001));
    });

    test('net earnings equal gross (R10 000, not R9 250 or R10 750)', () {
      final summary = PricingMath.aggregateRevenueSummary([
        {'basePriceRands': 10000, 'totalHunterPriceRands': 10000},
      ]);
      expect(summary.netEarnings, closeTo(10000, 0.001));
      expect(summary.netEarnings, isNot(closeTo(10750, 0.001)));
      expect(summary.netEarnings, isNot(closeTo(9250, 0.001)));
    });

    test('empty bookings yield zero summary', () {
      final summary = PricingMath.aggregateRevenueSummary([]);
      expect(summary.totalBookings, 0);
      expect(summary.grossRevenue, 0);
      expect(summary.netEarnings, 0);
    });
  });

  group('PricingMath.formatCurrency', () {
    test('formats a positive amount with thin-space thousands grouping', () {
      expect(PricingMath.formatCurrency(1234.5), 'R 1\u202F234.50');
    });

    test('formats zero', () {
      expect(PricingMath.formatCurrency(0), 'R 0.00');
    });

    test('formats a negative amount', () {
      expect(PricingMath.formatCurrency(-1000), '-R 1\u202F000.00');
    });
  });
}
