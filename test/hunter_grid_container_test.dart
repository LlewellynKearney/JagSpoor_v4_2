import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/shared/widgets/hunter_grid_container.dart';

void main() {
  group('HunterGridContainer', () {
    testWidgets('renders a GridView with every child', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HunterGridContainer(
              children: [
                Text('card-1'),
                Text('card-2'),
                Text('card-3'),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('card-1'), findsOneWidget);
      expect(find.text('card-2'), findsOneWidget);
      expect(find.text('card-3'), findsOneWidget);
    });

    testWidgets('uses the standardized max-extent grid delegate', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HunterGridContainer(
              maxCrossAxisExtent: 300,
              childAspectRatio: 0.9,
              spacing: 12,
              children: [Text('card-1')],
            ),
          ),
        ),
      );
      await tester.pump();

      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;
      expect(delegate.maxCrossAxisExtent, 300);
      expect(delegate.childAspectRatio, 0.9);
      expect(delegate.mainAxisSpacing, 12);
      expect(delegate.crossAxisSpacing, 12);
    });

    testWidgets('the static gridDelegate matches the Game Guide defaults', (
      tester,
    ) async {
      final delegate = HunterGridContainer.gridDelegate();
      expect(delegate.maxCrossAxisExtent, 280);
      expect(delegate.childAspectRatio, 0.72);
      expect(delegate.mainAxisSpacing, 16);
      expect(delegate.crossAxisSpacing, 16);
    });

    testWidgets('renders the optional footer after the last child', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HunterGridContainer(
              footer: Text('FOOTER'),
              children: [Text('card-1'), Text('card-2')],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('FOOTER'), findsOneWidget);
      expect(find.text('card-1'), findsOneWidget);
      expect(find.text('card-2'), findsOneWidget);
    });

    testWidgets('honours an explicit padding override', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HunterGridContainer(
              padding: EdgeInsets.zero,
              children: [Text('card-1')],
            ),
          ),
        ),
      );
      await tester.pump();
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(grid.padding, EdgeInsets.zero);
    });
  });
}
