import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_gate.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_feature_flag.dart';

/// Proves the "flag OFF ⇒ no UI anywhere" contract for the Veld feature.
void main() {
  Widget wrap(VeldCarryGate gate) => MaterialApp(home: Scaffold(body: gate));

  test('the default build has the compile-time switch OFF', () {
    expect(VeldCarryFeatureFlag.compileTimeEnabled, isFalse);
    expect(
      VeldCarryFeatureFlag.shouldEnable(
        compileTime: VeldCarryFeatureFlag.compileTimeEnabled,
        adminConfig: true,
      ),
      isFalse,
    );
  });

  testWidgets('renders nothing when both switches are off (default)',
      (tester) async {
    var built = false;
    await tester.pumpWidget(
      wrap(
        VeldCarryGate(
          flag: VeldCarryFeatureFlag.forTesting(
            compileTimeEnabled: false,
            adminConfigEnabled: false,
          ),
          builder: (_) {
            built = true;
            return const Text('VELD UI');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('VELD UI'), findsNothing);
    expect(built, isFalse);
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('renders nothing when only the control-plane switch is on',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        VeldCarryGate(
          flag: VeldCarryFeatureFlag.forTesting(
            compileTimeEnabled: false,
            adminConfigEnabled: true,
          ),
          builder: (_) => const Text('VELD UI'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('VELD UI'), findsNothing);
  });

  testWidgets('renders the child when both switches are on', (tester) async {
    await tester.pumpWidget(
      wrap(
        VeldCarryGate(
          flag: VeldCarryFeatureFlag.forTesting(
            compileTimeEnabled: true,
            adminConfigEnabled: true,
          ),
          builder: (_) => const Text('VELD UI'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('VELD UI'), findsOneWidget);
  });

  testWidgets('fails closed when the control-plane read cannot resolve',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        VeldCarryGate(
          flag: VeldCarryFeatureFlag.forTesting(
            compileTimeEnabled: true,
            adminConfigEnabled: false,
          ),
          builder: (_) => const Text('VELD UI'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('VELD UI'), findsNothing);
  });
}
