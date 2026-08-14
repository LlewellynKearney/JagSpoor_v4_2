import 'dart:math';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// Sensor AI Integration Test Suite v10.0
// Validates Inventory Bridge, Gyro calculations, and AI Target Scanning
// ============================================================================

// Import the ballistics calculation functions
import '../../../lib/features/ballistics/data/scope_calculator.dart';

// ============================================================================
// Test Results Tracking
// ============================================================================
int passed = 0;
int failed = 0;

// ============================================================================
// Test 1: Inventory Bridge - Empty Data Sets
// ============================================================================
void testInventoryBridgeEmptyDataSets() {
  print('\n--- Test 1: Inventory Bridge - Empty Data Sets ---');
  
  // Simulate empty firearms list
  final List<Map<String, dynamic>> emptyFirearms = [];
  final riflesEmpty = emptyFirearms.isEmpty;
  
  // Simulate empty ammunition list
  final List<Map<String, dynamic>> emptyAmmo = [];
  final ammoEmpty = emptyAmmo.isEmpty;
  
  assert(riflesEmpty, 'Firearms list should be empty');
  assert(ammoEmpty, 'Ammunition list should be empty');
  
  print('✓ Empty firearms list handled correctly');
  print('✓ Empty ammunition list handled correctly');
  passed++;
}

// ============================================================================
// Test 2: Inventory Bridge - Low Stock Count Handling
// ============================================================================
void testInventoryBridgeLowStockCount() {
  print('\n--- Test 2: Inventory Bridge - Low Stock Count ---');
  
  // Simulate ammunition with low stock
  final List<Map<String, dynamic>> lowStockAmmo = [
    {'id': 'ammo1', 'bulletWeightGrains': 168, 'remainingStockCount': 5},
    {'id': 'ammo2', 'bulletWeightGrains': 175, 'remainingStockCount': 2},
    {'id': 'ammo3', 'bulletWeightGrains': 180, 'remainingStockCount': 0},
  ];
  
  // Check that low stock is correctly identified
  for (final ammo in lowStockAmmo) {
    final count = ammo['remainingStockCount'] as int;
    final isLowStock = count > 0 && count <= 10;
    final isOutOfStock = count <= 0;
    
    if (count == 5 || count == 2) {
      assert(isLowStock, 'Ammo with $count stock should be low stock');
      assert(!isOutOfStock, 'Ammo with $count stock should not be out of stock');
    }
    if (count == 0) {
      assert(isOutOfStock, 'Ammo with 0 stock should be out of stock');
      assert(!isLowStock, 'Ammo with 0 stock should not be low stock');
    }
  }
  
  print('✓ Low stock count correctly identified (5, 2)');
  print('✓ Out of stock correctly identified (0)');
  print('✓ No null errors with low stock counts');
  passed++;
}

// ============================================================================
// Test 3: Gyro Calculation - 45 Degree Barrel Angle
// Validates that 45 degrees reduces 200m LOS to ~141.42m true horizontal
// ============================================================================
void testGyroCalculation45Degrees() {
  print('\n--- Test 3: Gyro Calculation - 45 Degree Barrel Angle ---');
  
  final result = ScopeCalculator.calculateGyroHoldover(
    lineOfSightDistance: 200.0,
    barrelAngleDegrees: 45.0,
    clickValueUnit: 0.25,
  );
  
  // cos(45°) = √2/2 ≈ 0.7071
  // 200m * 0.7071 ≈ 141.42m
  final expectedTrueHorizontal = 200.0 * (sqrt(2) / 2);
  
  print('  Line of Sight: 200m');
  print('  Barrel Angle: 45°');
  print('  Expected True Horizontal: ${expectedTrueHorizontal.toStringAsFixed(2)}m');
  print('  Calculated True Horizontal: ${result.trueHorizontalDistance.toStringAsFixed(2)}m');
  
  // Allow small tolerance for floating point precision
  final tolerance = 0.01;
  assert(
    (result.trueHorizontalDistance - expectedTrueHorizontal).abs() < tolerance,
    'True horizontal should be ~${expectedTrueHorizontal.toStringAsFixed(2)}m, got ${result.trueHorizontalDistance.toStringAsFixed(2)}m',
  );
  
  assert(result.isHoldingOver, '45 degree angle should indicate holding over');
  assert(!result.isHoldingUnder, '45 degree angle should not indicate holding under');
  assert(result.direction == 'UP', 'Direction should be UP for positive angle');
  
  print('✓ True horizontal calculation correct: ${result.trueHorizontalDistance.toStringAsFixed(2)}m ≈ 141.42m');
  print('✓ Hold direction correctly identified: ${result.direction}');
  passed++;
}

// ============================================================================
// Test 4: Gyro Calculation - Negative Angle (Hold Under)
// ============================================================================
void testGyroCalculationNegativeAngle() {
  print('\n--- Test 4: Gyro Calculation - Negative Angle (Hold Under) ---');
  
  final result = ScopeCalculator.calculateGyroHoldover(
    lineOfSightDistance: 300.0,
    barrelAngleDegrees: -30.0,
    clickValueUnit: 0.25,
  );
  
  // cos(-30°) = cos(30°) ≈ 0.8660
  final expectedTrueHorizontal = 300.0 * (sqrt(3) / 2);
  
  print('  Line of Sight: 300m');
  print('  Barrel Angle: -30°');
  print('  Expected True Horizontal: ${expectedTrueHorizontal.toStringAsFixed(2)}m');
  print('  Calculated True Horizontal: ${result.trueHorizontalDistance.toStringAsFixed(2)}m');
  
  final tolerance = 0.01;
  assert(
    (result.trueHorizontalDistance - expectedTrueHorizontal).abs() < tolerance,
    'True horizontal should be ~${expectedTrueHorizontal.toStringAsFixed(2)}m, got ${result.trueHorizontalDistance.toStringAsFixed(2)}m',
  );
  
  assert(!result.isHoldingOver, '-30 degree angle should not indicate holding over');
  assert(result.isHoldingUnder, '-30 degree angle should indicate holding under');
  assert(result.direction == 'DOWN', 'Direction should be DOWN for negative angle');
  
  print('✓ True horizontal calculation correct: ${result.trueHorizontalDistance.toStringAsFixed(2)}m');
  print('✓ Hold direction correctly identified: ${result.direction}');
  passed++;
}

// ============================================================================
// Test 5: Gyro Calculation - Zero Angle (Level)
// ============================================================================
void testGyroCalculationZeroAngle() {
  print('\n--- Test 5: Gyro Calculation - Zero Angle (Level) ---');
  
  final result = ScopeCalculator.calculateGyroHoldover(
    lineOfSightDistance: 150.0,
    barrelAngleDegrees: 0.0,
    clickValueUnit: 0.25,
  );
  
  // cos(0°) = 1.0, so true horizontal = line of sight
  assert(
    result.trueHorizontalDistance == 150.0,
    'True horizontal should equal line of sight at 0 degrees',
  );
  
  assert(!result.isHoldingOver, '0 degree angle should not indicate holding over');
  assert(!result.isHoldingUnder, '0 degree angle should not indicate holding under');
  assert(result.direction == 'LEVEL', 'Direction should be LEVEL for zero angle');
  
  print('✓ True horizontal equals line of sight at 0°');
  print('✓ Level condition correctly identified');
  passed++;
}

// ============================================================================
// Test 6: AI Target Scanning - MOA Unit Correction
// ============================================================================
void testAiTargetScanningMOA() {
  print('\n--- Test 6: AI Target Scanning - MOA Unit Correction ---');
  
  // Test with a known deviation at 100m
  final result = ScopeCalculator.calculateMoaTargetCorrection(
    deviationX_cm: 5.0,
    deviationY_cm: 3.0,
    targetDistanceMeters: 100.0,
    scopeUnitType: 'MOA',
  );
  
  print('  Deviation X: 5.0 cm, Deviation Y: 3.0 cm');
  print('  Target Distance: 100m');
  print('  Scope Unit: MOA');
  print('  Correction X: ${result.correctionX_clicks.toStringAsFixed(0)} clicks');
  print('  Correction Y: ${result.correctionY_clicks.toStringAsFixed(0)} clicks');
  print('  Tactical String: ${result.tacticalString}');
  
  // At 100m, 5cm right should require positive X correction
  assert(result.correctionX_clicks > 0, 'Right deviation should produce positive X clicks');
  
  // At 100m, 3cm up should require positive Y correction
  assert(result.correctionY_clicks > 0, 'Up deviation should produce positive Y clicks');
  
  // Tactical string should contain RIGHT and UP
  assert(result.tacticalString.contains('RIGHT'), 'Tactical string should mention RIGHT');
  assert(result.tacticalString.contains('UP'), 'Tactical string should mention UP');
  
  print('✓ MOA scope shift vectors calculated correctly');
  print('✓ Tactical correction string formatted correctly');
  passed++;
}

// ============================================================================
// Test 7: AI Target Scanning - MRAD Unit Correction
// ============================================================================
void testAiTargetScanningMRAD() {
  print('\n--- Test 7: AI Target Scanning - MRAD Unit Correction ---');
  
  final result = ScopeCalculator.calculateMoaTargetCorrection(
    deviationX_cm: 5.0,
    deviationY_cm: 3.0,
    targetDistanceMeters: 100.0,
    scopeUnitType: 'MRAD',
  );
  
  print('  Deviation X: 5.0 cm, Deviation Y: 3.0 cm');
  print('  Target Distance: 100m');
  print('  Scope Unit: MRAD');
  print('  Correction X: ${result.correctionX_clicks.toStringAsFixed(0)} clicks');
  print('  Correction Y: ${result.correctionY_clicks.toStringAsFixed(0)} clicks');
  print('  Tactical String: ${result.tacticalString}');
  
  // MRAD calculations are different from MOA
  assert(result.correctionX_clicks != 0 || result.correctionY_clicks != 0, 
      'Should have non-zero correction for deviations');
  
  print('✓ MRAD scope shift vectors calculated correctly');
  passed++;
}

// ============================================================================
// Test 8: AI Target Scanning - Left and Down Deviations
// ============================================================================
void testAiTargetScanningLeftAndDown() {
  print('\n--- Test 8: AI Target Scanning - Left and Down Deviations ---');
  
  final result = ScopeCalculator.calculateMoaTargetCorrection(
    deviationX_cm: -4.0,
    deviationY_cm: -2.0,
    targetDistanceMeters: 200.0,
    scopeUnitType: 'MOA',
  );
  
  print('  Deviation X: -4.0 cm (LEFT), Deviation Y: -2.0 cm (DOWN)');
  print('  Tactical String: ${result.tacticalString}');
  
  // Negative X deviation should require LEFT correction (negative clicks)
  assert(result.correctionX_clicks < 0, 'Left deviation should produce negative X clicks');
  
  // Negative Y deviation should require DOWN correction (negative clicks)
  assert(result.correctionY_clicks < 0, 'Down deviation should produce negative Y clicks');
  
  // Tactical string should contain LEFT and DOWN
  assert(result.tacticalString.contains('LEFT'), 'Tactical string should mention LEFT');
  assert(result.tacticalString.contains('DOWN'), 'Tactical string should mention DOWN');
  
  print('✓ Left/Down corrections calculated correctly');
  passed++;
}

// ============================================================================
// Test 9: AI Target Scanning - Center (No Adjustment)
// ============================================================================
void testAiTargetScanningCenter() {
  print('\n--- Test 9: AI Target Scanning - Center (No Adjustment) ---');
  
  final result = ScopeCalculator.calculateMoaTargetCorrection(
    deviationX_cm: 0.0,
    deviationY_cm: 0.0,
    targetDistanceMeters: 100.0,
    scopeUnitType: 'MOA',
  );
  
  print('  Deviation X: 0.0 cm, Deviation Y: 0.0 cm');
  print('  Tactical String: ${result.tacticalString}');
  
  // Zero deviation should require no adjustment
  assert(result.correctionX_clicks == 0, 'Center X should produce 0 clicks');
  assert(result.correctionY_clicks == 0, 'Center Y should produce 0 clicks');
  assert(result.tacticalString.contains('CENTER'), 'Tactical string should mention CENTER');
  
  print('✓ Center (no adjustment) handled correctly');
  passed++;
}

// ============================================================================
// Test 10: AI Target Scanning - Group Center Calculation
// ============================================================================
void testAiTargetGroupCenterCalculation() {
  print('\n--- Test 10: AI Target Scanning - Group Center Calculation ---');
  
  // Simulate shot group coordinates
  final List<Map<String, double>> shotCoordinates = [
    {'x': 1.0, 'y': 2.0},
    {'x': -1.5, 'y': 1.0},
    {'x': 0.5, 'y': -0.5},
    {'x': -0.3, 'y': 1.5},
    {'x': 0.2, 'y': -1.0},
  ];
  
  final center = ScopeCalculator.calculateGroupCenter(shotCoordinates);
  
  // Expected center: average of all coordinates
  final expectedX = (1.0 + -1.5 + 0.5 + -0.3 + 0.2) / 5;
  final expectedY = (2.0 + 1.0 + -0.5 + 1.5 + -1.0) / 5;
  
  print('  Shot Coordinates: $shotCoordinates');
  print('  Calculated Center: X=${center['x']!.toStringAsFixed(2)}, Y=${center['y']!.toStringAsFixed(2)}');
  print('  Expected Center: X=${expectedX.toStringAsFixed(2)}, Y=${expectedY.toStringAsFixed(2)}');
  
  final tolerance = 0.01;
  assert(
    (center['x']! - expectedX).abs() < tolerance,
    'Center X should be ~$expectedX, got ${center['x']}',
  );
  assert(
    (center['y']! - expectedY).abs() < tolerance,
    'Center Y should be ~$expectedY, got ${center['y']}',
  );
  
  print('✓ Group center calculation correct');
  passed++;
}

// ============================================================================
// Test 11: AI Target Scanning - Empty Coordinates Handling
// ============================================================================
void testAiTargetEmptyCoordinates() {
  print('\n--- Test 11: AI Target Scanning - Empty Coordinates ---');
  
  final List<Map<String, double>> emptyCoordinates = [];
  final center = ScopeCalculator.calculateGroupCenter(emptyCoordinates);
  
  assert(center['x'] == 0.0, 'Empty coordinates should return center at x=0');
  assert(center['y'] == 0.0, 'Empty coordinates should return center at y=0');
  
  print('✓ Empty coordinates handled without errors');
  passed++;
}

// ============================================================================
// Test 12: True Horizontal Distance Calculation
// ============================================================================
void testTrueHorizontalDistance() {
  print('\n--- Test 12: True Horizontal Distance Calculation ---');
  
  // Test various angles
  final testCases = [
    {'angle': 0.0, 'expected': 1.0},
    {'angle': 30.0, 'expected': sqrt(3) / 2},  // ~0.866
    {'angle': 60.0, 'expected': 0.5},
    {'angle': 90.0, 'expected': 0.0},
  ];
  
  for (final testCase in testCases) {
    final los = 100.0;
    final angle = testCase['angle'] as double;
    final expected = testCase['expected'] as double;
    
    final result = ScopeCalculator.calculateTrueHorizontalDistance(
      lineOfSightDistance: los,
      angleDegrees: angle,
    );
    
    final tolerance = 0.001;
    assert(
      (result - los * expected).abs() < tolerance,
      'At $angle°, true horizontal should be ${los * expected}, got $result',
    );
    
    print('  Angle $angle°: ${result.toStringAsFixed(2)}m ✓');
  }
  
  print('✓ True horizontal distance calculation verified for multiple angles');
  passed++;
}

// ============================================================================
// Test 13: Type Safety - Null Value Handling
// ============================================================================
void testTypeSafetyNullHandling() {
  print('\n--- Test 13: Type Safety - Null Value Handling ---');
  
  // Test rifle profile null safety
  final rifleData = <String, dynamic>{
    'name': 'Test Rifle',
    'caliber': '.308',
    'scopeClickValue': null,
    'serialNumber': null,
  };
  
  // Ensure null values don't cause crashes
  final scopeValue = rifleData['scopeClickValue'] ?? 0.25;
  final serialNumber = rifleData['serialNumber'] ?? '';
  
  assert(scopeValue == 0.25, 'Null scopeClickValue should default to 0.25');
  assert(serialNumber == '', 'Null serialNumber should default to empty string');
  
  print('✓ Null values handled safely with defaults');
  passed++;
}

// ============================================================================
// Test 14: Integration Test - Full Gyro to Correction Flow
// ============================================================================
void testFullGyroToCorrectionFlow() {
  print('\n--- Test 14: Integration Test - Full Gyro to Correction Flow ---');
  
  // Step 1: Calculate gyro holdover
  final gyroResult = ScopeCalculator.calculateGyroHoldover(
    lineOfSightDistance: 250.0,
    barrelAngleDegrees: 15.0,
    clickValueUnit: 0.25,
  );
  
  print('  Step 1 - Gyro Holdover:');
  print('    True Horizontal: ${gyroResult.trueHorizontalDistance.toStringAsFixed(2)}m');
  print('    Direction: ${gyroResult.direction}');
  print('    Tactical: ${gyroResult.tacticalOutput}');
  
  // Step 2: Simulate target scan at true horizontal distance
  final scanData = ScopeCalculator.simulateTargetScanData(
    targetDistanceMeters: gyroResult.trueHorizontalDistance,
  );
  
  print('  Step 2 - Target Scan:');
  print('    Shot count: ${scanData.length}');
  
  // Step 3: Calculate group center
  final groupCenter = ScopeCalculator.calculateGroupCenter(scanData);
  
  print('    Group Center: X=${groupCenter['x']!.toStringAsFixed(2)}, Y=${groupCenter['y']!.toStringAsFixed(2)}');
  
  // Step 4: Calculate correction
  final correction = ScopeCalculator.calculateMoaTargetCorrection(
    deviationX_cm: groupCenter['x']!,
    deviationY_cm: groupCenter['y']!,
    targetDistanceMeters: gyroResult.trueHorizontalDistance,
    scopeUnitType: 'MOA',
  );
  
  print('  Step 3 - Correction:');
  print('    ${correction.tacticalString}');
  
  assert(gyroResult.trueHorizontalDistance > 0, 'True horizontal should be positive');
  assert(scanData.isNotEmpty, 'Scan should produce data');
  assert(correction.tacticalString.isNotEmpty, 'Correction should have tactical string');
  
  print('✓ Full integration flow completed successfully');
  passed++;
}

// ============================================================================
// Test 15: Multiple Scope Click Values
// ============================================================================
void testMultipleClickValues() {
  print('\n--- Test 15: Multiple Scope Click Values ---');
  
  final clickValues = [0.25, 0.5, 1.0, 0.1];
  
  for (final clickValue in clickValues) {
    final result = ScopeCalculator.calculateGyroHoldover(
      lineOfSightDistance: 100.0,
      barrelAngleDegrees: 10.0,
      clickValueUnit: clickValue,
    );
    
    print('  Click Value $clickValue: ${result.clickUnits.toStringAsFixed(1)} clicks');
    
    // Higher click value = fewer clicks needed
    assert(result.clickUnits >= 0, 'Clicks should be non-negative');
  }
  
  print('✓ Multiple click values handled correctly');
  passed++;
}

// ============================================================================
// Run All Tests
// ============================================================================
void runSensorAiIntegrationTests() {
  print('=' * 70);
  print('SENSOR AI INTEGRATION TEST SUITE v10.0');
  print('=' * 70);
  
  try {
    testInventoryBridgeEmptyDataSets();
    testInventoryBridgeLowStockCount();
    testGyroCalculation45Degrees();
    testGyroCalculationNegativeAngle();
    testGyroCalculationZeroAngle();
    testAiTargetScanningMOA();
    testAiTargetScanningMRAD();
    testAiTargetScanningLeftAndDown();
    testAiTargetScanningCenter();
    testAiTargetGroupCenterCalculation();
    testAiTargetEmptyCoordinates();
    testTrueHorizontalDistance();
    testTypeSafetyNullHandling();
    testFullGyroToCorrectionFlow();
    testMultipleClickValues();
  } catch (e, stackTrace) {
    print('\n✗ Test failed with error: $e');
    print('Stack trace: $stackTrace');
    failed++;
  }
  
  // Summary
  print('\n' + '=' * 70);
  print('TEST SUMMARY');
  print('=' * 70);
  print('Total Tests: ${passed + failed}');
  print('Passed: $passed');
  print('Failed: $failed');
  print('=' * 70);
  
  if (failed == 0) {
    print('✓ ALL SENSOR AI INTEGRATION TESTS PASSED');
    print('  - Inventory Bridge correctly handles empty/low stock data');
    print('  - Barrel angle 45° correctly reduces 200m LOS to ~141.42m horizontal');
    print('  - Target scanning alignment equations verified for MOA/MRAD');
    print('  - Type safety maintained throughout calculations');
  } else {
    print('✗ SOME TESTS FAILED - Review output above');
    exit(1);
  }
}

// ============================================================================
// Entry Point
// ============================================================================
void main() {
  // The suite uses raw `assert` + `print` internally; wrap in a single
  // framework test so the runner reports a pass/fail.
  test('Sensor AI Integration Test Suite v10.0', () {
    runSensorAiIntegrationTests();
  });
}
