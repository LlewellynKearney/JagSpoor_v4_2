// ============================================================================
// Financial Engine Test Suite v8.1
// Validates marketplace rate calculations (no platform commission / markup).
// ============================================================================
import 'package:flutter_test/flutter_test.dart';

/// Calculates the hunter price. There is no platform commission / markup, so
/// the hunter price equals the outfitter's base price.
///
/// Parameters:
/// - basePrice: The outfitter's base price in ZAR
///
/// Returns: The base price, formatted to 2 decimal places
double calculateHunterPrice(double basePrice) {
  return double.parse(basePrice.toStringAsFixed(2));
}

/// Formats a price with currency prefix for display.
///
/// Parameters:
/// - price: The numeric price value
///
/// Returns: Formatted string "R XX.XX"
String formatPrice(double price) {
  return 'R ${price.toStringAsFixed(2)}';
}

/// Validates that a price string matches the expected format.
bool isValidPriceFormat(String priceString) {
  // Valid format: "R XX.XX" or "R X.XX"
  final regex = RegExp(r'^R\s*\d+\.\d{2}$');
  return regex.hasMatch(priceString);
}

/// Calculates the total invoice amount including extras. There is no platform
/// commission / markup: the total is the sum of the base package price plus
/// each extra's (price × quantity).
///
/// Parameters:
/// - basePrice: The base package price
/// - extras: List of extra items with 'price' and 'multiplier' fields
///
/// Returns: Total amount formatted to 2 decimal places
double calculateTotalAmount(
  double basePrice,
  List<Map<String, dynamic>> extras,
) {
  double total = basePrice;

  for (final extra in extras) {
    final rawPrice = (extra['price'] is num) ? (extra['price'] as num).toDouble() : 0.0;
    final quantity = (extra['multiplier'] is num) ? (extra['multiplier'] as num).toInt() : 1;
    total += rawPrice * quantity;
  }

  return double.parse(total.toStringAsFixed(2));
}

/// Parses included animals JSON string and extracts pricing data.
Map<String, dynamic> parseIncludedAnimalsJson(String jsonString) {
  if (jsonString.isEmpty) {
    return {
      'animals': <String>[],
      'slaughterFee': 0.0,
      'coldroomFee': 0.0,
      'bakkieFee': 0.0,
      'phFee': 0.0,
    };
  }

  try {
    // Simple JSON parsing without external dependencies
    final result = <String, dynamic>{
      'animals': <String>[],
      'slaughterFee': 0.0,
      'coldroomFee': 0.0,
      'bakkieFee': 0.0,
      'phFee': 0.0,
    };

    // Extract animals array
    final animalsMatch = RegExp(r'"animals"\s*:\s*\[(.*?)\]').firstMatch(jsonString);
    if (animalsMatch != null) {
      final animalsStr = animalsMatch.group(1) ?? '';
      final animalMatches = RegExp(r'"([^"]+)"').allMatches(animalsStr);
      result['animals'] = animalMatches.map((m) => m.group(1)!).toList();
    }

    // Extract numeric fields
    final fields = ['slaughterFee', 'coldroomFee', 'bakkieFee', 'phFee'];
    for (final field in fields) {
      final match = RegExp('"$field"\\s*:\\s*([\\d.]+)').firstMatch(jsonString);
      if (match != null) {
        result[field] = double.parse(match.group(1)!);
      }
    }

    return result;
  } catch (_) {
    return {
      'animals': <String>[],
      'slaughterFee': 0.0,
      'coldroomFee': 0.0,
      'bakkieFee': 0.0,
      'phFee': 0.0,
    };
  }
}

// ============================================================================
// Test Suite - Pure Dart Assertions
// ============================================================================

void runFinancialEngineTests() {
  print('=' * 70);
  print('FINANCIAL ENGINE TEST SUITE v8.1');
  print('Testing rate calculations (no platform commission / markup)');
  print('=' * 70);

  int passed = 0;
  int failed = 0;

  // Test 1: Basic price calculation (no markup)
  {
    const double basePrice = 100.0;
    final result = calculateHunterPrice(basePrice);
    assert(
      result == 100.00,
      'Expected 100.00 (no markup), got $result',
    );
    print('✓ Test 1: Basic price calculation (100.00, no markup)');
    passed++;
  }

  // Test 2: Price formatting
  {
    final priceString = formatPrice(105.00);
    assert(
      priceString == 'R 105.00',
      'Expected "R 105.00", got "$priceString"',
    );
    print('✓ Test 2: Price formatting (105.00 -> "R 105.00")');
    passed++;
  }

  // Test 3: Valid price format validation
  {
    assert(
      isValidPriceFormat('R 105.00'),
      'Expected "R 105.00" to be valid',
    );
    assert(
      isValidPriceFormat('R 1234.56'),
      'Expected "R 1234.56" to be valid',
    );
    assert(
      !isValidPriceFormat('105.00'),
      'Expected "105.00" to be invalid',
    );
    assert(
      !isValidPriceFormat('R 105'),
      'Expected "R 105" to be invalid (missing decimals)',
    );
    print('✓ Test 3: Price format validation');
    passed++;
  }

  // Test 4: Total amount calculation with extras
  {
    final extras = [
      {'name': 'Extra 1', 'price': 50.0, 'multiplier': 2},
      {'name': 'Extra 2', 'price': 25.0, 'multiplier': 1},
    ];
    final total = calculateTotalAmount(100.0, extras);
    // 100 + (50 * 2) + (25 * 1) = 100 + 100 + 25 = 225
    assert(
      total == 225.00,
      'Expected 225.00, got $total',
    );
    print('✓ Test 4: Total amount with extras');
    passed++;
  }

  // Test 5: Decimal precision preservation
  {
    const double basePrice = 99.99;
    final result = calculateHunterPrice(basePrice);
    assert(
      result == 99.99,
      'Expected 99.99, got $result',
    );
    print('✓ Test 5: Decimal precision preservation');
    passed++;
  }

  // Test 6: Zero price handling
  {
    const double basePrice = 0.0;
    final result = calculateHunterPrice(basePrice);
    assert(
      result == 0.00,
      'Expected 0.00 for zero input, got $result',
    );
    print('✓ Test 6: Zero price handling');
    passed++;
  }

  // Test 7: Large price handling
  {
    const double basePrice = 1000000.0;
    final result = calculateHunterPrice(basePrice);
    assert(
      result == 1000000.00,
      'Expected 1000000.00 (no markup), got $result',
    );
    print('✓ Test 7: Large price handling');
    passed++;
  }

  // Test 8: Empty extras list
  {
    final total = calculateTotalAmount(200.0, []);
    assert(
      total == 200.00,
      'Expected 200.00 for base price only, got $total',
    );
    print('✓ Test 8: Empty extras list');
    passed++;
  }

  // Test 9: JSON parsing - valid input
  {
    const String json =
        '{"animals":["Impala","Kudu"],"slaughterFee":150.50,"coldroomFee":75.25}';
    final result = parseIncludedAnimalsJson(json);
    assert(
      result['animals'].length == 2,
      'Expected 2 animals, got ${result['animals'].length}',
    );
    assert(
      result['slaughterFee'] == 150.50,
      'Expected 150.50 slaughter fee, got ${result['slaughterFee']}',
    );
    assert(
      result['coldroomFee'] == 75.25,
      'Expected 75.25 coldroom fee, got ${result['coldroomFee']}',
    );
    print('✓ Test 9: JSON parsing - valid input');
    passed++;
  }

  // Test 10: JSON parsing - empty input
  {
    final result = parseIncludedAnimalsJson('');
    assert(
      result['animals'].isEmpty,
      'Expected empty animals list for empty input',
    );
    assert(
      result['slaughterFee'] == 0.0,
      'Expected 0.0 slaughter fee for empty input',
    );
    print('✓ Test 10: JSON parsing - empty input');
    passed++;
  }

  // Test 11: Invoice price consistency (no markup factor)
  {
    const double testPrices = 50.0;

    // Calculate using formula (identity — no markup)
    final formulaResult = testPrices;

    // Calculate using function
    final functionResult = calculateHunterPrice(testPrices);

    assert(
      formulaResult.toStringAsFixed(2) == functionResult.toStringAsFixed(2),
      'Price inconsistency: formula gives ${formulaResult.toStringAsFixed(2)}, '
          'function gives ${functionResult.toStringAsFixed(2)}',
    );
    print('✓ Test 11: Invoice price consistency (no markup factor)');
    passed++;
  }

  // Test 12: Edge case - very small price
  {
    const double basePrice = 0.01;
    final result = calculateHunterPrice(basePrice);
    assert(
      result == 0.01,
      'Expected 0.01 for tiny price, got $result',
    );
    print('✓ Test 12: Edge case - very small price');
    passed++;
  }

  // Test 13: Extra item with zero price
  {
    final extras = [
      {'name': 'Free Extra', 'price': 0.0, 'multiplier': 5},
    ];
    final total = calculateTotalAmount(100.0, extras);
    // Only base price should contribute: 100
    assert(
      total == 100.00,
      'Expected 100.00 (zero price extras ignored), got $total',
    );
    print('✓ Test 13: Extra item with zero price');
    passed++;
  }

  // Test 14: Extra item with zero multiplier
  {
    final extras = [
      {'name': 'Skipped Extra', 'price': 50.0, 'multiplier': 0},
    ];
    final total = calculateTotalAmount(100.0, extras);
    // Only base price should contribute: 100
    assert(
      total == 100.00,
      'Expected 100.00 (zero quantity ignored), got $total',
    );
    print('✓ Test 14: Extra item with zero multiplier');
    passed++;
  }

  // Test 15: Multiple extras with no markup
  {
    final extras = [
      {'name': 'A', 'price': 10.0, 'multiplier': 1},
      {'name': 'B', 'price': 20.0, 'multiplier': 2},
      {'name': 'C', 'price': 30.0, 'multiplier': 3},
    ];
    final total = calculateTotalAmount(0.0, extras);
    // (10 * 1) + (20 * 2) + (30 * 3) = 10 + 40 + 90 = 140
    assert(
      total == 140.00,
      'Expected 140.00 for multi-extras calculation, got $total',
    );
    print('✓ Test 15: Multiple extras with no markup');
    passed++;
  }

  // Summary
  print('=' * 70);
  print('FINANCIAL ENGINE TEST SUMMARY');
  print('=' * 70);
  print('Total Tests: ${passed + failed}');
  print('Passed: $passed');
  print('Failed: $failed');
  print('=' * 70);

  if (failed == 0) {
    print('✓ ALL FINANCIAL ENGINE TESTS PASSED');
    print('  - No platform commission / markup verified');
    print('  - Price formatting (2 decimals) verified');
    print('  - Currency prefix ("R ") verified');
    print('  - Edge cases handled correctly');
  } else {
    print('✗ SOME TESTS FAILED - Review output above');
  }
}

// ============================================================================
// Entry Point
// ============================================================================
void main() {
  // The suite uses raw `assert` + `print` internally; wrap in a single
  // framework test so the runner reports a pass/fail.
  test('Financial Engine Test Suite v8.1', () {
    runFinancialEngineTests();
  });
}
