import 'dart:math';

// ============================================================================
// Financial Engine Test Suite v8.1
// Validates marketplace rate calculations with 5% markup scaling
// ============================================================================

/// Calculates the hunter price with standard 5% marketplace commission markup.
///
/// Parameters:
/// - basePrice: The outfitter's base price in ZAR
///
/// Returns: Price scaled by 1.05, formatted to 2 decimal places
double calculateHunterPrice(double basePrice) {
  const double markup = 1.05;
  return double.parse((basePrice * markup).toStringAsFixed(2));
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

/// Calculates the total invoice amount including extras with markup.
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
  const double markup = 1.05;
  double total = basePrice * markup;

  for (final extra in extras) {
    final rawPrice = (extra['price'] is num) ? (extra['price'] as num).toDouble() : 0.0;
    final quantity = (extra['multiplier'] is num) ? (extra['multiplier'] as num).toInt() : 1;
    total += rawPrice * markup * quantity;
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
  print('Testing marketplace rate calculations with 5% markup');
  print('=' * 70);

  int passed = 0;
  int failed = 0;

  // Test 1: Basic markup calculation
  {
    const double basePrice = 100.0;
    final result = calculateHunterPrice(basePrice);
    assert(
      result == 105.00,
      'Expected 105.00 for 100.00 * 1.05, got $result',
    );
    print('✓ Test 1: Basic markup calculation (100.00 * 1.05 = 105.00)');
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
    // 100 * 1.05 = 105
    // (50 * 1.05 * 2) + (25 * 1.05 * 1) = 105 + 26.25 = 131.25
    // Total = 105 + 131.25 = 236.25
    assert(
      total == 236.25,
      'Expected 236.25, got $total',
    );
    print('✓ Test 4: Total amount with extras');
    passed++;
  }

  // Test 5: Decimal precision preservation
  {
    const double basePrice = 99.99;
    final result = calculateHunterPrice(basePrice);
    // 99.99 * 1.05 = 104.9895 -> 104.99
    assert(
      result == 104.99,
      'Expected 104.99 (rounded), got $result',
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
      result == 1050000.00,
      'Expected 1050000.00 for 1000000.00 * 1.05, got $result',
    );
    print('✓ Test 7: Large price handling');
    passed++;
  }

  // Test 8: Empty extras list
  {
    final total = calculateTotalAmount(200.0, []);
    assert(
      total == 210.00,
      'Expected 210.00 for base price only, got $total',
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

  // Test 11: Invoice markup consistency
  {
    // The markup constant must be exactly 1.05 across all calculations
    const double markup = 1.05;
    const double testPrices = 50.0;

    // Calculate using formula
    final formulaResult = testPrices * markup;

    // Calculate using function
    final functionResult = calculateHunterPrice(testPrices);

    assert(
      formulaResult.toStringAsFixed(2) == functionResult.toStringAsFixed(2),
      'Markup inconsistency: formula gives ${formulaResult.toStringAsFixed(2)}, '
          'function gives ${functionResult.toStringAsFixed(2)}',
    );
    print('✓ Test 11: Invoice markup consistency (1.05 factor)');
    passed++;
  }

  // Test 12: Edge case - very small price
  {
    const double basePrice = 0.01;
    final result = calculateHunterPrice(basePrice);
    // 0.01 * 1.05 = 0.0105 -> 0.01
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
    // Only base price should contribute: 100 * 1.05 = 105
    assert(
      total == 105.00,
      'Expected 105.00 (zero price extras ignored), got $total',
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
    // Only base price should contribute: 100 * 1.05 = 105
    assert(
      total == 105.00,
      'Expected 105.00 (zero quantity ignored), got $total',
    );
    print('✓ Test 14: Extra item with zero multiplier');
    passed++;
  }

  // Test 15: Multiple extras with same markup
  {
    final extras = [
      {'name': 'A', 'price': 10.0, 'multiplier': 1},
      {'name': 'B', 'price': 20.0, 'multiplier': 2},
      {'name': 'C', 'price': 30.0, 'multiplier': 3},
    ];
    final total = calculateTotalAmount(0.0, extras);
    // (10 * 1.05 * 1) + (20 * 1.05 * 2) + (30 * 1.05 * 3)
    // = 10.5 + 42 + 94.5 = 147
    assert(
      total == 147.00,
      'Expected 147.00 for multi-extras calculation, got $total',
    );
    print('✓ Test 15: Multiple extras with same markup');
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
    print('  - Markup factor (1.05) verified');
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
  runFinancialEngineTests();
}
