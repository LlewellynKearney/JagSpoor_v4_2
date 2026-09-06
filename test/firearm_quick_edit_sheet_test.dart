import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/widgets/firearm_quick_edit_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Opens the sheet and returns a completer that resolves with the result the
  // launcher receives (null when dismissed). Callers await [openSheet] before
  // interacting with the widget tree, then await [result.future] after
  // triggering save / dismiss.
  Future<Future<FirearmQuickEditResult?>> openSheet(
    WidgetTester tester, {
    Map<String, String> firearm = const {},
    String title = 'Edit Firearm Details',
  }) async {
    final theme = ThemeController();
    final completer = Completer<FirearmQuickEditResult?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () {
                  completer.complete(
                    FirearmQuickEditSheet.show(
                      context,
                      theme: theme,
                      firearm: firearm,
                      title: title,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return completer.future;
  }

  testWidgets('renders all four detail fields pre-filled + save button',
      (tester) async {
    await openSheet(
      tester,
      firearm: const {
        'make': 'TIKKA',
        'model': 'T3x',
        'caliber': '.308 Win',
        'serial': 'OB14468',
      },
    );

    expect(find.text('Edit Firearm Details'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('quickEditMakeField')),
          )
          .controller
          ?.text,
      'TIKKA',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('quickEditModelField')),
          )
          .controller
          ?.text,
      'T3x',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('quickEditCaliberField')),
          )
          .controller
          ?.text,
      // Tolerates the legacy 'calibre' alias for pre-fill.
      '.308 Win',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('quickEditSerialField')),
          )
          .controller
          ?.text,
      'OB14468',
    );
    expect(find.text('SAVE CHANGES'), findsOneWidget);
  });

  testWidgets('editing + saving returns the new values via Navigator.pop',
      (tester) async {
    final resultFuture = await openSheet(
      tester,
      firearm: const {'make': 'CZ', 'model': '457', 'caliber': '.22 LR'},
    );

    await tester.enterText(
      find.byKey(const ValueKey('quickEditMakeField')),
      'HOWA 1500',
    );
    await tester.enterText(
      find.byKey(const ValueKey('quickEditModelField')),
      'Varmint',
    );
    await tester.enterText(
      find.byKey(const ValueKey('quickEditCaliberField')),
      '.223 Rem',
    );
    await tester.enterText(
      find.byKey(const ValueKey('quickEditSerialField')),
      'XY753',
    );
    await tester.tap(find.byKey(const ValueKey('quickEditSaveButton')));
    await tester.pumpAndSettle();

    final result = await resultFuture;
    expect(result, isNotNull);
    expect(result!.make, 'HOWA 1500');
    expect(result.model, 'Varmint');
    expect(result.caliber, '.223 Rem');
    expect(result.serial, 'XY753');
  });

  testWidgets('dismissing (close) returns null', (tester) async {
    final resultFuture = await openSheet(tester);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(await resultFuture, isNull);
  });

  testWidgets('empty Make is rejected by the validator (no pop)', (tester) async {
    await openSheet(tester);
    // Clear the make field, then tap save.
    await tester.enterText(
      find.byKey(const ValueKey('quickEditMakeField')),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('quickEditSaveButton')));
    await tester.pumpAndSettle();

    // Sheet stays open and a validation message shows.
    expect(find.text('Edit Firearm Details'), findsOneWidget);
    expect(find.text('Make is required'), findsOneWidget);
  });
}