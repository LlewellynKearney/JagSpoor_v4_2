import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/widgets/booking_chat_thread.dart';

/// Locks in the public [BookingChatThreadState] contract the outfitter
/// booking card depends on: a parent can drive the thread's expand/collapse
/// state from external affordances (the unread-mail indicator + the
/// "IN-APP CHAT" button) via a [GlobalKey<BookingChatThreadState>] without
/// the parent owning any chat-layout / scroll / composer state of its own.
void main() {
  late ThemeController theme;

  setUp(() {
    theme = ThemeController();
  });

  testWidgets(
      'the thread starts collapsed (initiallyExpanded defaults to false)',
      (tester) async {
    final key = GlobalKey<BookingChatThreadState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BookingChatThread(
          key: key,
          bookingId: 'b1',
          theme: theme,
          senderName: 'User',
        ),
      ),
    ));

    expect(key.currentState, isNotNull);
    expect(key.currentState!.isExpanded, isFalse,
        reason: 'thread starts collapsed by default');
    // Collapsed -> the Firebase-dependent message list is NOT built (the
    // `if (_isExpanded)` guard skips it), so no Firebase app is touched.
  });

  testWidgets(
      'toggleExpanded() flips the expand state (GlobalKey contract the '
      'outfitter card depends on)', (tester) async {
    final key = GlobalKey<BookingChatThreadState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BookingChatThread(
          key: key,
          bookingId: 'b1',
          theme: theme,
          senderName: 'User',
        ),
      ),
    ));

    // Drive the state via the GlobalKey -- mirrors how the outfitter card's
    // _toggleChatDrawer calls _chatThreadKey.currentState?.toggleExpanded().
    // We do NOT pump the expanded build here because the expanded content
    // touches FirebaseFirestore.instance (no Firebase app in the test
    // harness); the contract under test is the state flag, not the render.
    key.currentState!.toggleExpanded();
    expect(key.currentState!.isExpanded, isTrue,
        reason: 'toggleExpanded opens the thread');

    key.currentState!.toggleExpanded();
    expect(key.currentState!.isExpanded, isFalse,
        reason: 'second toggle collapses the thread again');
  });

  testWidgets('initiallyExpanded: true sets the state flag on mount '
      '(build error tolerated; contract is the flag)', (tester) async {
    final key = GlobalKey<BookingChatThreadState>();
    // The expanded content touches FirebaseFirestore.instance, which throws
    // [core/no-app] in the headless test harness. We tolerate the build
    // exception (caught by the framework) and assert only the state flag
    // the outfitter card reads through the GlobalKey.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BookingChatThread(
          key: key,
          bookingId: 'b1',
          theme: theme,
          senderName: 'User',
          initiallyExpanded: true,
        ),
      ),
    ));
    // Drain the build error without failing the test.
    final dynamic exception = tester.takeException();
    expect(exception, isNotNull,
        reason: 'expected Firebase [core/no-app] build error');
    expect(key.currentState!.isExpanded, isTrue,
        reason: 'initiallyExpanded seeds the state open on mount');
  });

  testWidgets('tapping the built-in header flips the state flag',
      (tester) async {
    final key = GlobalKey<BookingChatThreadState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BookingChatThread(
          key: key,
          bookingId: 'b1',
          theme: theme,
          senderName: 'User',
        ),
      ),
    ));

    expect(key.currentState!.isExpanded, isFalse);
    // Tap the expandable header InkWell. The header tap flips the flag
    // synchronously inside setState; the subsequent expanded build touches
    // FirebaseFirestore.instance (no Firebase app in the harness), whose
    // exception we tolerate below.
    await tester.tap(find.byIcon(Icons.chat_rounded));
    await tester.pump(const Duration(milliseconds: 50));
    final dynamic exception = tester.takeException();
    expect(exception, isNotNull,
        reason: 'expected Firebase [core/no-app] build error after expand');
    expect(key.currentState!.isExpanded, isTrue,
        reason: 'built-in header tap opens the thread');
  });
}
