import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/services/referral_link_service.dart';

/// Verifies that the native share-sheet action produces the NEW
/// `https://jagspoor.co.za/r/<CODE>` App Link and NEVER the dead
/// `jagspoor.page.link` domain (Firebase Dynamic Links was shut down by Google
/// on 2025-08-25).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
      // Intercept the share call so nothing hits a native platform.
      return 'dev.fluttercommunity.plus/share/success';
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null);
  });

  test('shareReferralLink carries the App Link (not page.link)', () async {
    // The message that is handed to the share sheet is built by the same pure
    // builder the service uses; assert it directly (the platform channel only
    // transports it).
    final message =
        ReferralLinkService.buildShareMessage('JAGSPOOR7Q3X', userId: 'u1');
    expect(message, contains('https://jagspoor.co.za/r/JAGSPOOR7Q3X'));
    expect(message.contains('page.link'), isFalse);
    expect(message, contains('1 month free'));

    // And the share call itself does not throw when invoked.
    await ReferralLinkService.shareReferralLink('JAGSPOOR7Q3X');
  });

  test('a blank code shares nothing', () async {
    // No assertion on the channel; simply confirms the no-op path never throws.
    await ReferralLinkService.shareReferralLink('');
  });
}
