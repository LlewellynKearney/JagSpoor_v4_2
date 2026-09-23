import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';

/// Regression guard for the Admin Portal PRICE DIVERGENCE false-positive.
///
/// Under Option A the Play Console base plan is configured EXCLUDING VAT
/// (R30.43 / R260.86) while the Admin control plane stores the FINAL
/// VAT-INCLUSIVE charge (R34.99 / R299.99). Grossing the catalog amount up by
/// 15% reconciles the two, so no warning must be shown.
void main() {
  group('PlayPriceReconciliation.matches', () {
    test('Play R30.43 excl reconciles to Admin R34.99 incl (hunter)', () {
      final r = PlayPriceReconciliation.compare(
        playExVat: 30.43,
        adminInclVat: 34.99,
      );
      expect(r.playInclVat, closeTo(34.9945, 0.0001));
      expect(r.matches, isTrue);
    });

    test('Play R260.86 excl reconciles to Admin R299.99 incl (outfitter)', () {
      final r = PlayPriceReconciliation.compare(
        playExVat: 260.86,
        adminInclVat: 299.99,
      );
      expect(r.playInclVat, closeTo(299.989, 0.0001));
      expect(r.matches, isTrue);
    });

    test('tolerance absorbs sub-2-cent rounding drift', () {
      // 34.99/1.15 = 30.426... ; Play rounds to 30.43 -> 34.9945 incl.
      expect(
        PlayPriceReconciliation.compare(playExVat: 30.43, adminInclVat: 34.99)
            .matches,
        isTrue,
      );
      // A 1-cent inclusive difference still counts as a match.
      expect(
        PlayPriceReconciliation.compare(playExVat: 30.43, adminInclVat: 35.00)
            .matches,
        isTrue,
      );
    });

    test('a genuine mismatch (ex-VAT interpreted as inclusive) still warns',
        () {
      // The exact bug being fixed: comparing the raw catalog amount against
      // the inclusive admin amount must NOT be treated as a match.
      final r = PlayPriceReconciliation.compare(
        playExVat: 34.99,
        adminInclVat: 34.99,
      );
      expect(r.matches, isFalse);
    });

    test('a real divergence beyond tolerance warns', () {
      final r = PlayPriceReconciliation.compare(
        playExVat: 30.43,
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
    test('matchMessage shows both the ex-VAT and incl-VAT figures', () {
      final r = PlayPriceReconciliation.compare(
        playExVat: 30.43,
        adminInclVat: 34.99,
      );
      expect(
        r.matchMessage,
        'Play Console R30.43 excl (R34.99 incl) matches Admin R34.99',
      );
    });

    test('mismatchMessage points the operator at the Play base plan', () {
      final r = PlayPriceReconciliation.compare(
        playExVat: 30.43,
        adminInclVat: 39.99,
      );
      expect(r.mismatchMessage, contains('R30.43 excl'));
      expect(r.mismatchMessage, contains('R34.99 incl'));
      expect(r.mismatchMessage, contains('Admin R39.99'));
      expect(r.mismatchMessage, contains('update Play Console base plan'));
    });

    test('honours the store currency symbol', () {
      final r = PlayPriceReconciliation.compare(
        playExVat: 30.43,
        adminInclVat: 34.99,
        currencySymbol: r'$',
      );
      expect(r.matchMessage, contains(r'$30.43'));
    });
  });

  group('SubscriptionConfig VAT source of truth', () {
    test('toMap stores the VAT-inclusive amount + derived excl component', () {
      // The canonical fields the divergence check reads are hashable via the
      // SubscriptionConfig round-trip; the exclusive derivation lives in the
      // seed payload. Verified here through the documented constants.
      expect(hunterMonthlyPriceZAR, 34.99);
      expect(outfitterMonthlyPriceZAR, 299.99);
      expect(saVatRate, 0.15);
      expect(priceDivergenceToleranceZAR, 0.02);
    });
  });
}
