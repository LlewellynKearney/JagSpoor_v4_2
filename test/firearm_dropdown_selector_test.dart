import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/ballistics/data/models/rifle_profile.dart';
import 'package:jagspoor/widgets/firearm_dropdown_selector.dart';

RifleProfile _rifle(String id, {String make = '', String model = ''}) {
  return RifleProfile(
    id: id,
    name: '$make $model',
    caliber: '.308 Win',
    make: make,
    model: model,
  );
}

Widget _boilerplate(FirearmDropdownSelector selector) {
  // Disable the InkSparkle ripple (its `ink_sparkle.frag` shader asset is
  // unavailable in the headless desktop test runner) so tap interactions in
  // the test do not throw "Asset not found".
  return MaterialApp(
    theme: ThemeData(
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    ),
    home: Scaffold(
      body: Material(child: selector),
    ),
  );
}

void main() {
  group('FirearmDropdownSelector', () {
    testWidgets('renders the live dropdown with firearm display names',
        (tester) async {
      final rifles = [_rifle('a', make: 'Tikka', model: 'T3x')];
      String? picked;
      await tester.pumpWidget(_boilerplate(FirearmDropdownSelector(
        selectedFirearmId: null,
        firearms: rifles,
        onChanged: (id) => picked = id,
      )));

      // Hint text is shown when nothing is selected.
      expect(find.text('Choose Firearm'), findsOneWidget);
      // Tapping the dropdown opens the menu with the display name.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('Tikka T3x (.308 Win)'), findsOneWidget);
      await tester.tap(find.text('Tikka T3x (.308 Win)').last);
      await tester.pumpAndSettle();
      expect(picked, 'a');
    });

    testWidgets(
        'coerces a stale selectedFirearmId (no longer in the list) to null '
        'instead of throwing a "value not in items" assertion', (tester) async {
      // The firearm 'gone' was selected then deleted from the safe; the
      // remaining list only has 'a'. A raw DropdownButtonFormField would
      // assert here; the selector must silently coerce to null.
      await tester.pumpWidget(_boilerplate(FirearmDropdownSelector(
        selectedFirearmId: 'gone',
        firearms: [_rifle('a', make: 'Tikka', model: 'T3x')],
        onChanged: (_) {},
      )));
      await tester.pumpAndSettle();

      // No assertion thrown (test would fail otherwise); hint shows because
      // the effective value is null.
      expect(find.text('Choose Firearm'), findsOneWidget);
      // The dropdown widget itself rendered (not the empty-state field).
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('renders a disabled "No firearms found in Safe" field '
        'when the list is empty', (tester) async {
      await tester.pumpWidget(_boilerplate(FirearmDropdownSelector(
        selectedFirearmId: null,
        firearms: const [],
        onChanged: (_) {},
      )));
      await tester.pumpAndSettle();

      expect(find.text('No firearms found in Safe'), findsOneWidget);
      // No interactive dropdown offered when there is nothing to select.
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      // The disabled TextFormField is the rendered control.
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('renders a LinearProgressIndicator while loading',
        (tester) async {
      await tester.pumpWidget(_boilerplate(FirearmDropdownSelector(
        selectedFirearmId: null,
        firearms: const [],
        isLoading: true,
        onChanged: (_) {},
      )));
      // Use `pump` (not `pumpAndSettle`): the LinearProgressIndicator's
      // indeterminate animation never settles, so pumpAndSettle would time
      // out. A single frame is enough to assert the control rendered.
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // No dropdown / no empty-state hint while loading.
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('No firearms found in Safe'), findsNothing);
    });

    testWidgets('hides the trailing widget while loading and when empty',
        (tester) async {
      const badge = Key('turret-badge');
      // Loading -> no trailing. (`pump`, not `pumpAndSettle`, because the
      // LinearProgressIndicator animates indefinitely.)
      await tester.pumpWidget(_boilerplate(FirearmDropdownSelector(
        selectedFirearmId: null,
        firearms: const [],
        isLoading: true,
        onChanged: (_) {},
        trailing: const SizedBox(key: badge),
      )));
      await tester.pump();
      expect(find.byKey(badge), findsNothing);

      // Empty -> no trailing.
      await tester.pumpWidget(_boilerplate(FirearmDropdownSelector(
        selectedFirearmId: null,
        firearms: const [],
        onChanged: (_) {},
        trailing: const SizedBox(key: badge),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(badge), findsNothing);

      // Populated -> trailing renders.
      await tester.pumpWidget(_boilerplate(FirearmDropdownSelector(
        selectedFirearmId: null,
        firearms: [_rifle('a', make: 'Tikka', model: 'T3x')],
        onChanged: (_) {},
        trailing: const SizedBox(key: badge),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(badge), findsOneWidget);
    });

    testWidgets('reports the selected id via onChanged', (tester) async {
      final rifles = [
        _rifle('a', make: 'Tikka', model: 'T3x'),
        _rifle('b', make: 'Sako', model: 'S20'),
      ];
      String? picked;
      await tester.pumpWidget(_boilerplate(FirearmDropdownSelector(
        selectedFirearmId: null,
        firearms: rifles,
        onChanged: (id) => picked = id,
      )));

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sako S20 (.308 Win)').last);
      await tester.pumpAndSettle();
      expect(picked, 'b');
    });
  });
}
