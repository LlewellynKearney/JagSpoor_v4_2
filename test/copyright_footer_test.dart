// Tests for the CopyrightFooter widget, including a regression guard for the
// "invisible full-screen footer absorbs body taps" defect: when the footer
// was implemented with `Center`, placing it in a Scaffold's
// `bottomNavigationBar` slot made the Center expand to the full screen
// height. The bottomNavigationBar slot is hit-tested BEFORE the body slot,
// so the footer's (invisible, mid-screen) text swallowed every tap in its
// band and body buttons under it never fired. The footer must shrink-wrap
// its caption instead of expanding.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';

void main() {
  testWidgets('renders the caption', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CopyrightFooter()),
    ));
    expect(find.text(CopyrightFooter.caption), findsOneWidget);
  });

  testWidgets(
      'REGRESSION: as a bottomNavigationBar the footer must not cover the '
      'screen or swallow body taps', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('T')),
        body: Center(
          child: FilledButton.icon(
            onPressed: () => tapped = true,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('ACTION'),
          ),
        ),
        bottomNavigationBar: const SafeArea(
          top: false,
          child: CopyrightFooter.tight(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The footer caption must be a short strip at the BOTTOM of the screen,
    // not a full-height overlay in the middle.
    final footerRect =
        tester.getRect(find.text(CopyrightFooter.caption));
    expect(footerRect.height, lessThan(100),
        reason: 'The footer caption must shrink-wrap, not expand to fill '
            'the screen height.');
    expect(footerRect.top, greaterThan(500),
        reason: 'The footer must sit at the bottom of the screen (600px '
            'surface), not in the middle where it overlaps body content.');

    // A body button (rendered mid-screen, in the band the broken footer
    // used to cover) must receive taps.
    await tester.tap(find.text('ACTION'));
    await tester.pump();
    expect(tapped, isTrue,
        reason: 'Body buttons must receive taps when a CopyrightFooter is '
            'used as the bottomNavigationBar.');
  });
}
