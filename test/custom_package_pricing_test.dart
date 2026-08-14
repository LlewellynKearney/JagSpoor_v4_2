import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the Custom Package Builder pricing model.
///
/// The builder's grand total is the sum of (quantity × `hunterDisplayPriceZAR`)
/// across all selected species + lodging/catering lines. `hunterDisplayPriceZAR`
/// already carries the **absorbed** 7.5% platform markup (base × 1.075), so the
/// hunter-facing total never surfaces an explicit "Platform Fee" row. The 25%
/// non-refundable deposit is `total × 0.25`. These tests encode that contract.
void main() {
  const double markup = 1.075; // base × 1.075 (absorbed 7.5% platform fee)
  const double depositFraction = 0.25;

  double hunterPrice(double base) => base * markup;

  double grandTotal(List<({double base, int qty})> lines) =>
      lines.fold(0.0, (sum, l) => sum + hunterPrice(l.base) * l.qty);

  test('grand total absorbs the 7.5% markup with no explicit fee line', () {
    final total = grandTotal([
      (base: 10000, qty: 2), // 2 × R10 000 × 1.075 = R21 500
      (base: 2500, qty: 1), // R2 500 × 1.075 = R2 687.50
    ]);
    // 21500 + 2687.50
    expect(total, closeTo(24187.5, 0.001));
    // Verify the absorbed markup: base sum × 1.075 == total.
    final baseSum = 10000 * 2 + 2500;
    expect(total, closeTo(baseSum * markup, 0.001));
  });

  test('deposit is exactly 25% of the marked-up grand total', () {
    final total = grandTotal([(base: 8000, qty: 1)]);
    final deposit = total * depositFraction;
    expect(deposit, closeTo(8000 * markup * 0.25, 0.001));
    expect(deposit, closeTo(2150.0, 0.001));
  });

  test('a single species line prices correctly with quantity', () {
    final total = grandTotal([(base: 18500, qty: 3)]); // Kudu bull × 3
    expect(total, closeTo(18500 * 1.075 * 3, 0.001));
    expect(total, closeTo(59662.5, 0.001));
  });

  test('lodging/catering fee lines use the same absorbed-markup model', () {
    final total = grandTotal([
      (base: 1500, qty: 4), // accommodation 4 nights
      (base: 800, qty: 4), // catering 4 days
    ]);
    expect(total, closeTo((1500 + 800) * 4 * markup, 0.001));
  });

  test('empty selection yields a zero total (no booking allowed)', () {
    expect(grandTotal([]), 0);
  });

  test('the outfitter-facing base is recoverable from the marked-up total', () {
    // submitCustomPackageBooking recovers base = total / 1.075 for the
    // commission breakdown stored on the booking doc (outfitter financials).
    final total = grandTotal([(base: 10000, qty: 1)]);
    final recoveredBase = total / markup;
    expect(recoveredBase, closeTo(10000, 0.001));
    final commission = total - recoveredBase;
    expect(commission, closeTo(750, 0.001)); // 7.5% of 10 000
  });
}
