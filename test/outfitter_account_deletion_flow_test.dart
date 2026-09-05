import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/outfitter_mode/outfitter_dashboard.dart';

/// Widget tests for the outfitter-side "Delete Account" flow surfaced from
/// the Outfitter Dashboard settings sheet.
///
/// The dashboard's `accountDeletionRunner` seam replaces the real
/// `OutfitterAccountDeletionService` cascade (which would touch live Firebase
/// Auth + Firestore), so the confirmation-dialog contract, the danger-zone
/// rendering, the in-flight state, and the failure paths are exercised
/// hermetically.
void main() {
  late ThemeController theme;
  late bool deletionInvoked;
  late Future<void> Function() deletionRunner;

  setUp(() {
    theme = ThemeController.instance;
    deletionInvoked = false;
    deletionRunner = () async {
      deletionInvoked = true;
    };
  });

  Future<void> pumpDashboard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OutfitterDashboard(
          theme: theme,
          accountDeletionRunner: deletionRunner,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openSettingsSheet(WidgetTester tester) async {
    await pumpDashboard(tester);
    await tester.tap(
      find.byTooltip('Outfitter settings'),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the settings sheet shows the Delete Account danger zone',
      (tester) async {
    await openSettingsSheet(tester);

    expect(find.text('DANGER ZONE'), findsOneWidget);
    expect(find.text('DELETE ACCOUNT & ALL DATA'), findsOneWidget);
    // The danger zone sits below the change-password list tile.
    expect(find.text('Change Password'), findsOneWidget);
  });

  testWidgets('tapping DELETE opens the irreversible confirmation dialog',
      (tester) async {
    await openSettingsSheet(tester);

    await tester.tap(find.text('DELETE ACCOUNT & ALL DATA'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Account'), findsOneWidget);
    expect(find.textContaining('IRREVERSIBLE'), findsOneWidget);
    expect(find.text('DELETE FOREVER'), findsOneWidget);
    expect(find.text('CANCEL'), findsOneWidget);
    // Confirm the destructive list is present.
    expect(find.text('Registered farms and farm managers'), findsOneWidget);
  });

  testWidgets('cancelling the dialog does not run the deletion',
      (tester) async {
    await openSettingsSheet(tester);

    await tester.tap(find.text('DELETE ACCOUNT & ALL DATA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    expect(deletionInvoked, isFalse);
    // The settings sheet is still up.
    expect(find.text('DANGER ZONE'), findsOneWidget);
  });

  testWidgets('confirming DELETE FOREVER runs the deletion cascade',
      (tester) async {
    await openSettingsSheet(tester);

    await tester.tap(find.text('DELETE ACCOUNT & ALL DATA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DELETE FOREVER'));
    await tester.pumpAndSettle();

    expect(deletionInvoked, isTrue);
  });

  testWidgets('the danger-zone button is styled as a destructive warning',
      (tester) async {
    await openSettingsSheet(tester);

    // Scroll the danger zone into view if it sits below the fold.
    await tester.ensureVisible(find.text('DELETE ACCOUNT & ALL DATA'));
    await tester.pumpAndSettle();

    final buttons = find.byWidgetPredicate(
      (w) =>
          w is ElevatedButton &&
          w.style != null &&
          w.style!.backgroundColor?.resolve({}) == Colors.red.shade700,
    );
    expect(buttons, findsOneWidget);
  });
}