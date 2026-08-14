import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/pricing_math.dart';

/// Unit tests for the single-source pricing arithmetic (`PricingMath`) that
/// backs the hunter-facing markup presentation, the outfitter net-revenue
/// protection, and the PayFast deposit amount.
///
/// The spec (Item #9):
/// - Hunter-facing prices dynamically include the 7.5% platform markup
///   (`price × 1.075`); the 25% deposit is computed off the marked-up total
///   (`markedUpTotal × 0.25`); no explicit "Platform Fee" line is shown.
/// - Outfitter revenue figures reflect base amounts net of fees
///   (e.g. R10,000, not R10,750 and not R9,250).
/// - The PayFast amount matches the 25% marked-up deposit.
void main() {
  group('PricingMath constants', () {
    test('platform commission rate is 7.5%', () {
      expect(PricingMath.platformCommissionRate, 0.075);
    });

    test('deposit fraction is 25%', () {
      expect(PricingMath.depositFraction, 0.25);
    });

    test('markup multiplier is 1.075', () {
      expect(PricingMath.markupMultiplier, 1.075);
    });
  });

  group('PricingMath.markedUpTotal', () {
    test('base × 1.075 — absorbs the 7.5% fee', () {
      expect(PricingMath.markedUpTotal(10000), closeTo(10750, 0.001));
      expect(PricingMath.markedUpTotal(2500), closeTo(2687.5, 0.001));
    });

    test('zero base yields zero total', () {
      expect(PricingMath.markedUpTotal(0), 0);
    });
  });

  group('PricingMath.commissionFromBase', () {
    test('base × 0.075', () {
      expect(PricingMath.commissionFromBase(10000), closeTo(750, 0.001));
    });
  });

  group('PricingMath.depositFromBase', () {
    test('25% of the MARKED-UP total (not the base)', () {
      // R10 000 base → R10 750 marked-up total → R2 687.50 deposit.
      expect(PricingMath.depositFromBase(10000), closeTo(2687.5, 0.001));
      // Confirm it is NOT 25% of the base (R2 500).
      expect(PricingMath.depositFromBase(10000), isNot(closeTo(2500, 0.001)));
    });
  });

  group('PricingMath.depositFromMarkedUpTotal', () {
    test('25% of the supplied marked-up total', () {
      expect(
        PricingMath.depositFromMarkedUpTotal(10750),
        closeTo(2687.5, 0.001),
      );
    });
  });

  group('PricingMath.balanceFromMarkedUpTotal', () {
    test('marked-up total minus the 25% deposit (75%)', () {
      expect(
        PricingMath.balanceFromMarkedUpTotal(10750),
        closeTo(8062.5, 0.001),
      );
      // deposit + balance == marked-up total
      expect(
        PricingMath.depositFromMarkedUpTotal(10750) +
            PricingMath.balanceFromMarkedUpTotal(10750),
        closeTo(10750, 0.001),
      );
    });
  });

  group('PricingMath.netEarnings (outfitter revenue protection)', () {
    test('gross − fee = outfitter base earnings (R10 000, not R9 250)', () {
      // R10 000 base listing: gross collected from hunter = R10 750, fee = R750.
      final gross = PricingMath.markedUpTotal(10000); // 10750
      final fee = PricingMath.commissionFromBase(10000); // 750
      final net = PricingMath.netEarnings(
        grossRevenue: gross,
        platformFee: fee,
      );
      // The outfitter's net earnings equal the base price (R10 000) — the
      // protected net-revenue figure. It must NOT be R10 750 (gross) and
      // must NOT be R9 250 (base − fee, the prior double-counted bug).
      expect(net, closeTo(10000, 0.001));
      expect(net, isNot(closeTo(10750, 0.001)));
      expect(net, isNot(closeTo(9250, 0.001)));
    });

    test('net earnings equal the base price across a range of base prices', () {
      for (final base in [0, 500, 1000, 5000, 10000, 25000, 100000]) {
        final gross = PricingMath.markedUpTotal(base.toDouble());
        final fee = PricingMath.commissionFromBase(base.toDouble());
        final net = PricingMath.netEarnings(
          grossRevenue: gross,
          platformFee: fee,
        );
        expect(net, closeTo(base.toDouble(), 0.001),
            reason: 'net should equal base for base=$base');
      }
    });
  });

  group('PricingMath.resolveHunterTotal (legacy fallback)', () {
    test('uses the stored marked-up total when present', () {
      expect(
        PricingMath.resolveHunterTotal(
          totalHunterPrice: 10750,
          basePrice: 10000,
        ),
        closeTo(10750, 0.001),
      );
    });

    test('derives base × 1.075 when the stored total is null (legacy doc)', () {
      expect(
        PricingMath.resolveHunterTotal(
          totalHunterPrice: null,
          basePrice: 10000,
        ),
        closeTo(10750, 0.001),
      );
    });

    test('derives base × 1.075 when the stored total is 0 (legacy doc)', () {
      expect(
        PricingMath.resolveHunterTotal(
          totalHunterPrice: 0,
          basePrice: 10000,
        ),
        closeTo(10750, 0.001),
      );
    });

    test('never returns the unmarked-up base price to a hunter', () {
      // For every legacy input shape, the resolved total must be the marked-up
      // value, never the bare base.
      for (final stored in [null, 0.0, -1.0]) {
        final resolved = PricingMath.resolveHunterTotal(
          totalHunterPrice: stored,
          basePrice: 10000,
        );
        expect(resolved, closeTo(10750, 0.001));
        expect(resolved, isNot(closeTo(10000, 0.001)));
      }
    });
  });

  group('PricingMath.resolveDeposit (legacy fallback)', () {
    test('uses the stored deposit when present', () {
      expect(
        PricingMath.resolveDeposit(
          storedDeposit: 2687.5,
          markedUpTotalValue: 10750,
        ),
        closeTo(2687.5, 0.001),
      );
    });

    test('derives 25% of the marked-up total when stored deposit is missing', () {
      expect(
        PricingMath.resolveDeposit(
          storedDeposit: null,
          markedUpTotalValue: 10750,
        ),
        closeTo(2687.5, 0.001),
      );
      expect(
        PricingMath.resolveDeposit(
          storedDeposit: 0,
          markedUpTotalValue: 10750,
        ),
        closeTo(2687.5, 0.001),
      );
    });
  });

  group('PayFast deposit alignment (Item #9 part 3)', () {
    test('the PayFast charge amount equals the 25% marked-up deposit', () {
      // The amount submitted to PayFast must be the 25% deposit off the
      // marked-up total — the same value rendered on the hunter-facing
      // "25% Deposit" row. This guards against the deposit and the PayFast
      // charge drifting apart.
      const base = 10000.0;
      final markedUpTotal = PricingMath.markedUpTotal(base); // 10750
      final displayedDeposit =
          PricingMath.depositFromMarkedUpTotal(markedUpTotal); // 2687.5
      final payFastAmount = PricingMath.resolveDeposit(
        storedDeposit: null, // legacy booking → derived
        markedUpTotalValue: markedUpTotal,
      );
      expect(payFastAmount, equals(displayedDeposit));
      expect(payFastAmount, closeTo(2687.5, 0.001));
    });

    test('the deposit is never computed off the unmarked-up base', () {
      const base = 10000.0;
      final deposit = PricingMath.depositFromBase(base);
      // R2 687.50 (off R10 750), NOT R2 500 (off R10 000).
      expect(deposit, closeTo(2687.5, 0.001));
      expect(deposit, isNot(closeTo(2500, 0.001)));
    });
  });

  group('End-to-end booking pricing contract (Item #9 parts 1 & 2)', () {
    test('a R10 000 base listing produces the exact spec figures', () {
      const base = 10000.0;
      final hunterTotal = PricingMath.markedUpTotal(base);
      final fee = PricingMath.commissionFromBase(base);
      final deposit = PricingMath.depositFromMarkedUpTotal(hunterTotal);
      final balance = PricingMath.balanceFromMarkedUpTotal(hunterTotal);
      final net = PricingMath.netEarnings(
        grossRevenue: hunterTotal,
        platformFee: fee,
      );

      // Hunter sees: R10 750 total, R2 687.50 deposit (no Platform Fee line).
      expect(hunterTotal, closeTo(10750, 0.001));
      expect(deposit, closeTo(2687.5, 0.001));
      expect(balance, closeTo(8062.5, 0.001));
      // Outfitter sees: R10 000 net earnings (base, net of fees).
      expect(net, closeTo(10000, 0.001));
      // The fee the platform retains.
      expect(fee, closeTo(750, 0.001));
      // gross − fee − net == 0 (the split is exact).
      expect(hunterTotal - fee - net, closeTo(0, 0.001));
    });
  });

  group('PricingMath.aggregateRevenueSummary (outfitter revenue protection)', () {
    test('aggregates stored marked-up totals + commissions into net earnings', () {
      final summary = PricingMath.aggregateRevenueSummary([
        // R10 000 base booking — fully populated doc.
        {
          'basePriceRands': 10000,
          'totalHunterPriceRands': 10750,
          'platformCommissionRands': 750,
        },
        // R5 000 base booking — fully populated doc.
        {
          'basePriceRands': 5000,
          'totalHunterPriceRands': 5375,
          'platformCommissionRands': 375,
        },
      ]);
      // gross = 10750 + 5375 = 16125; fees = 750 + 375 = 1125;
      // net = 16125 − 1125 = 15000 (= 10000 + 5000, the two base prices).
      expect(summary.totalBookings, 2);
      expect(summary.grossRevenue, closeTo(16125, 0.001));
      expect(summary.platformFees, closeTo(1125, 0.001));
      expect(summary.netEarnings, closeTo(15000, 0.001));
    });

    test('derives the marked-up total + commission for legacy docs', () {
      final summary = PricingMath.aggregateRevenueSummary([
        // Legacy doc — only basePriceRands present.
        {'basePriceRands': 10000},
      ]);
      // gross derived = 10750; fee derived = 750; net = 10000.
      expect(summary.totalBookings, 1);
      expect(summary.grossRevenue, closeTo(10750, 0.001));
      expect(summary.platformFees, closeTo(750, 0.001));
      expect(summary.netEarnings, closeTo(10000, 0.001));
    });

    test('net earnings never include the 7.5% fee (R10 000, not R10 750)', () {
      final summary = PricingMath.aggregateRevenueSummary([
        {'basePriceRands': 10000, 'totalHunterPriceRands': 10750,
         'platformCommissionRands': 750},
      ]);
      expect(summary.netEarnings, closeTo(10000, 0.001));
      expect(summary.netEarnings, isNot(closeTo(10750, 0.001)));
      expect(summary.netEarnings, isNot(closeTo(9250, 0.001)));
    });

    test('empty bookings yield zero summary', () {
      final summary = PricingMath.aggregateRevenueSummary([]);
      expect(summary.totalBookings, 0);
      expect(summary.grossRevenue, 0);
      expect(summary.platformFees, 0);
      expect(summary.netEarnings, 0);
    });
  });
}
