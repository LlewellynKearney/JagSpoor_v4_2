import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/services/incoming_referral_handler.dart';
import 'package:jagspoor/services/install_referrer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Task 2B — Play Install Referrer service contracts.
///
/// Exercises the Dart `InstallReferrerService` via its seams (raw referrer +
/// validator) AND via the real method channel (mocked), so both the parsing /
/// validation / caching path and the platform bridge contract are covered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    InstallReferrerService.instance.resetForTesting();
    ReferralLinkHandler.instance.resetForTesting();
  });

  tearDown(() {
    InstallReferrerService.instance.resetForTesting();
    ReferralLinkHandler.instance.resetForTesting();
  });

  group('InstallReferrerService (seams)', () {
    test('is a no-op on non-Android platforms', () async {
      final svc = InstallReferrerService.instance;
      svc.isAndroidForTesting = false;
      final result = await svc.initialize();
      expect(result.hasCode, isFalse);
      expect(result.error, isNotNull);
    });

    test('parses referral_<CODE> and validates it, caching the code',
        () async {
      final svc = InstallReferrerService.instance;
      svc.isAndroidForTesting = true;
      svc.rawReferrerForTesting = 'referral_JAGSPOOR7Q3X';
      svc.validateCodeForTesting = (code) async => code == 'JAGSPOOR7Q3X';

      final result = await svc.initialize();
      expect(result.referralCode, 'JAGSPOOR7Q3X');
      expect(result.validated, isTrue);
      expect(ReferralLinkHandler.instance.pendingCode, 'JAGSPOOR7Q3X');
    });

    test('invalid code is rejected (not validated) but still cached for retry',
        () async {
      final svc = InstallReferrerService.instance;
      svc.isAndroidForTesting = true;
      svc.rawReferrerForTesting = 'referral_NOPE1234';
      svc.validateCodeForTesting = (_) async => false;

      final result = await svc.initialize();
      expect(result.referralCode, 'NOPE1234');
      expect(result.validated, isFalse);
    });

    test('a referrer with no parsable code yields no code', () async {
      final svc = InstallReferrerService.instance;
      svc.isAndroidForTesting = true;
      svc.rawReferrerForTesting = 'referral_';
      final result = await svc.initialize();
      expect(result.hasCode, isFalse);
    });

    test('a blank referrer yields no code (not an error)', () async {
      final svc = InstallReferrerService.instance;
      svc.isAndroidForTesting = true;
      svc.rawReferrerForTesting = '';
      final result = await svc.initialize();
      expect(result.hasCode, isFalse);
      expect(result.error, isNull);
    });

    test('reads the referrer only ONCE (already-checked short-circuits)',
        () async {
      final svc = InstallReferrerService.instance;
      svc.isAndroidForTesting = true;
      svc.rawReferrerForTesting = 'referral_JAGSPOOR7Q3X';
      svc.validateCodeForTesting = (_) async => true;
      await svc.initialize();
      // Second call with a DIFFERENT referrer still short-circuits.
      svc.rawReferrerForTesting = 'referral_OTHER2345';
      svc.alreadyCheckedForTesting = true;
      final second = await svc.initialize();
      expect(second.hasCode, isFalse);
      expect(second.error, contains('already read'));
    });

    test('a throwing validator never crashes (code cached unvalidated)',
        () async {
      final svc = InstallReferrerService.instance;
      svc.isAndroidForTesting = true;
      svc.rawReferrerForTesting = 'referral_JAGSPOOR7Q3X';
      svc.validateCodeForTesting = (_) async => throw Exception('boom');
      final result = await svc.initialize();
      expect(result.referralCode, 'JAGSPOOR7Q3X');
      expect(result.validated, isFalse);
    });
  });

  group('InstallReferrerService (method channel)', () {
    const channel = MethodChannel(InstallReferrerService.channelName);

    test('reads + parses the installReferrer map from the native bridge',
        () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return <String, dynamic>{
          'installReferrer': 'referral_JAGSPOOR7Q3X',
          'installBeginTimestampSeconds': 1700000000,
        };
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final svc = InstallReferrerService.instance;
      svc.isAndroidForTesting = true;
      svc.validateCodeForTesting = (_) async => true;

      final result = await svc.initialize();
      expect(calls.single.method, 'getInstallReferrer');
      expect(result.referralCode, 'JAGSPOOR7Q3X');
      expect(result.validated, isTrue);
    });

    test('a channel PlatformException degrades to no code (no crash)',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'SERVICE_UNAVAILABLE');
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final svc = InstallReferrerService.instance;
      svc.isAndroidForTesting = true;
      final result = await svc.initialize();
      expect(result.hasCode, isFalse);
    });
  });
}
