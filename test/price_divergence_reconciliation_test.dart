import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';

/// Regression guard for the Admin Portal PRICE DIVERGENCE check under the
/// Option A model.
///
/// Under Option A the Play Console base plan is configured with the FINAL
/// VAT-INCLUSIVE charge (R34.99 / R299.99) — the same figure the Admin control
/// plane stores — so the two are compared directly. (The previous model grossed
/// the catalog amount up by 15% first, which is what produced the incorrect
/// R40.24 display and a false divergence signal.)
void main() {
  group('PlayPriceReconciliation.matches', () {
    test('Play R34.99 matches Admin R34.99 incl (hunter)', () {
      final r = PlayPriceReconciliation.compare(
        playExVat: 34.99,
        adminInclVat: 34.99,
      );
      expect(r.playInclVat, 34.99);
      expect(r.matches, isTrue);
    });

    test('Play R299.99 matches Admin R299.99 incl (outfitter)', () {
      final r = PlayPriceReconciliation.compare(
        playExVat: 299.99,
        adminInclVat: 299.99,
      );
      expect(r.playInclVat, 299.99);
      expect(r.matches, isTrue);
    });

    test('tolerance absorbs sub-2-cent rounding drift', () {
      // A 1-cent difference still counts as a match.
      expect(
        PlayPriceReconciliation.compare(playExVat: 34.99, adminInclVat: 35.00)
            .matches,
        isTrue,
      );
    });

    test('a genuine mismatch warns', () {
      final r = PlayPriceReconciliation.compare(
        playExVat: 34.99,
        adminInclVat: 39.99,
      );
      expect(r.matches, isFalse);
    });

    test('non-positive / non-finite inputs collapse to zero (no NaN)', () {
      final r = PlayPriceReconciliation.compare(
        playExVat: double.nan,
        adminInclVat: -5,
      );
      expect(r.playInclVat, 0);
      expect(r.adminInclVat, 0);
    });
  });

  group('PlayPriceReconciliation copy', () {
    test('matchMessage shows both amounts', () {
      final r = PlayPriceReconciliation.compare(
        playExVat: 34.99,
        adminInclVat: 34.99,
      );
      expect(
        r.matchMessage,
        'Play Console R34.99 matches Admin R34.99',
      );
    });

    test('mismatchMessage points the operator at the Play base plan', () {
      final r = PlayPriceReconciliation.compare(
        playExVat: 34.99,
        adminInclVat: 39.99,
      );
      expect(r.mismatchMessage, contains('R34.99'));
      expect(r.mismatchMessage, contains('Admin R39.99'));
      expect(r.mismatchMessage, contains('update Play Console base plan'));
    });

    test('honours the store currency symbol', () {
      final r = PlayPriceReconciliation.compare(
        playExVat: 34.99,
        adminInclVat: 34.99,
        currencySymbol: r'$',
      );
      expect(r.matchMessage, contains(r'$34.99'));
    });
  });

  group('SubscriptionConfig VAT source of truth', () {
    test('the documented constants are the Option A inclusive amounts', () {
      expect(hunterMonthlyPriceZAR, 34.99);
      expect(outfitterMonthlyPriceZAR, 299.99);
      expect(saVatRate, 0.15);
      expect(priceDivergenceToleranceZAR, 0.02);
    });

    test('SubscriptionVatPrice.fromInclusive shows the listed price verbatim',
        () {
      final p = SubscriptionVatPrice.fromInclusive(34.99);
      expect(p.inclVat, 34.99);
      expect(p.primaryLabel, 'R 34.99/month');
      expect(p.vatNote, 'Incl. 15% VAT');
    });
  });
}
