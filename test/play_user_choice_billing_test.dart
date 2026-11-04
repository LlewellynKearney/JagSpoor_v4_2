import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/subscription/services/play_billing_service.dart';

/// Google Play **User Choice Billing** service contract.
///
/// Play only renders its own choice dialog when the native `BillingClient`
/// was built with `enableUserChoiceBilling(listener)`. The plugin exposes that
/// as `setBillingChoice(BillingChoiceMode.userChoiceBilling)`, and surfaces
/// the user's alternative selection on `userChoiceDetailsStream` with the
/// external transaction token the app must report back to Google.
void main() {
  tearDown(PlayBillingService.resetTestSeams);

  group('PlayUserChoiceDetails', () {
    test('carries the external transaction token + product ids', () {
      const details = PlayUserChoiceDetails(
        externalTransactionToken: 'uct-token',
        productIds: ['jagspoor_hunter_monthly'],
      );

      expect(details.externalTransactionToken, 'uct-token');
      expect(details.productIds, ['jagspoor_hunter_monthly']);
      expect(details.hasToken, isTrue);
    });

    test('hasToken is false for a blank token', () {
      const blank = PlayUserChoiceDetails(externalTransactionToken: '   ');
      expect(blank.hasToken, isFalse);
      const empty = PlayUserChoiceDetails(externalTransactionToken: '');
      expect(empty.hasToken, isFalse);
    });

    test('product ids default to an empty list', () {
      const details = PlayUserChoiceDetails(externalTransactionToken: 'x');
      expect(details.productIds, isEmpty);
    });
  });

  group('PlayBillingService.enableUserChoiceBilling', () {
    test('returns the seam result and records the call', () async {
      PlayBillingService.enableUserChoiceBillingForTesting = () async => true;

      final enabled = await PlayBillingService.instance
          .enableUserChoiceBilling();

      expect(enabled, isTrue);
      expect(PlayBillingService.enableUserChoiceBillingCalls, 1);
    });

    test('a seam that reports the dialog is unavailable returns false',
        () async {
      PlayBillingService.enableUserChoiceBillingForTesting = () async => false;

      final enabled = await PlayBillingService.instance
          .enableUserChoiceBilling();

      expect(enabled, isFalse);
      // The call still happened (the screen does not distinguish a refusal
      // from a missing programme — both fall back to the in-app surface).
      expect(PlayBillingService.enableUserChoiceBillingCalls, 1);
    });

    test('a throwing seam is swallowed and reports false', () async {
      PlayBillingService.enableUserChoiceBillingForTesting =
          () async => throw StateError('no billing bridge');

      final enabled = await PlayBillingService.instance
          .enableUserChoiceBilling();

      expect(enabled, isFalse);
    });
  });

  group('PlayBillingService.userChoiceDetailsStream', () {
    test('forwards the seam stream', () async {
      final controller = StreamController<PlayUserChoiceDetails>();
      PlayBillingService.userChoiceDetailsStreamForTesting = controller.stream;

      final received = <PlayUserChoiceDetails>[];
      final sub =
          PlayBillingService.instance.userChoiceDetailsStream.listen(received.add);

      controller.add(const PlayUserChoiceDetails(
        externalTransactionToken: 'play-uct-token',
        productIds: ['jagspoor_outfitter_monthly'],
      ));
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.externalTransactionToken, 'play-uct-token');
      expect(received.single.productIds, ['jagspoor_outfitter_monthly']);

      await sub.cancel();
      await controller.close();
    });

    test('returns an empty stream on a host without the platform addition',
        () async {
      // A host without the Android addition degrades to an empty stream so
      // callers can always subscribe without a null check.
      PlayBillingService.userChoiceDetailsStreamForTesting =
          const Stream<PlayUserChoiceDetails>.empty();

      final stream = PlayBillingService.instance.userChoiceDetailsStream;
      expect(stream, isA<Stream<PlayUserChoiceDetails>>());
      expect(await stream.isEmpty, isTrue);
    });
  });

  group('resetTestSeams', () {
    test('clears the UCB seams + call counter', () {
      PlayBillingService.enableUserChoiceBillingForTesting = () async => true;
      PlayBillingService.userChoiceDetailsStreamForTesting =
          const Stream<PlayUserChoiceDetails>.empty();
      PlayBillingService.enableUserChoiceBillingCalls = 5;

      PlayBillingService.resetTestSeams();

      expect(PlayBillingService.enableUserChoiceBillingForTesting, isNull);
      expect(PlayBillingService.userChoiceDetailsStreamForTesting, isNull);
      expect(PlayBillingService.enableUserChoiceBillingCalls, 0);
    });
  });
}
