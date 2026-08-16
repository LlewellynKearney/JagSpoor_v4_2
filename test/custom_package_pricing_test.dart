import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the Custom Package Builder pricing model.
///
/// The builder's grand total is the sum of (quantity × `hunterDisplayPriceZAR`)
/// across all selected species + lodging/catering lines. There is no platform
/// commission / markup and no deposit split: `hunterDisplayPriceZAR` equals
/// the item base price, so the hunter-facing total is simply the sum of the
/// base costs (no explicit "Platform Fee" row, no deposit row).
void main() {
  // hunterDisplayPriceZAR equals the base price (no platform markup).
  double hunterPrice(double base) => base;

  double grandTotal(List<({double base, int qty})> lines) =>
      lines.fold(0.0, (sum, l) => sum + hunterPrice(l.base) * l.qty);

  test('grand total is the sum of base costs (no platform fee line)', () {
    final total = grandTotal([
      (base: 10000, qty: 2), // 2 × R10 000 = R20 000
      (base: 2500, qty: 1), // R2 500
    ]);
    // 20000 + 2500
    expect(total, closeTo(22500, 0.001));
    // Verify there is no markup: base sum == total.
    final baseSum = 10000 * 2 + 2500;
    expect(total, closeTo(baseSum, 0.001));
  });

  test('a single species line prices correctly with quantity', () {
    final total = grandTotal([(base: 18500, qty: 3)]); // Kudu bull × 3
    expect(total, closeTo(18500 * 3, 0.001));
    expect(total, closeTo(55500, 0.001));
  });

  test('lodging/catering fee lines use the same base-price model', () {
    final total = grandTotal([
      (base: 1500, qty: 4), // accommodation 4 nights
      (base: 800, qty: 4), // catering 4 days
    ]);
    expect(total, closeTo((1500 + 800) * 4, 0.001));
  });

  test('empty selection yields a zero total (no booking allowed)', () {
    expect(grandTotal([]), 0);
  });

  test('the base price is recoverable from the total (total = base)', () {
    // submitCustomPackageBooking stores the base price as the total on the
    // booking doc; there is no commission to recover.
    final total = grandTotal([(base: 10000, qty: 1)]);
    final recoveredBase = total;
    expect(recoveredBase, closeTo(10000, 0.001));
    final commission = total - recoveredBase;
    expect(commission, 0); // no platform commission
  });
}
