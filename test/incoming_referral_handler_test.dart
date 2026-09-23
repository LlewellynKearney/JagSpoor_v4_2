import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/services/incoming_referral_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unit tests for [ReferralLinkHandler] — the incoming App Links receiver that
/// replaced Firebase Dynamic Links (shut down 2025-08-25).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReferralLinkHandler.instance.resetForTesting();
  });

  tearDown(() {
    ReferralLinkHandler.instance.resetForTesting();
  });

  test('handleUri stores an HTTPS App Link code', () async {
    await ReferralLinkHandler.instance.handleUri(
      Uri.parse('https://jagspoor.co.za/r/JAGSPOOR7Q3X'),
      validateCode: (_) async => true,
    );
    expect(ReferralLinkHandler.instance.pendingCode, 'JAGSPOOR7Q3X');
    expect(ReferralLinkHandler.instance.hasPendingCode, isTrue);
  });

  test('handleUri stores a custom-scheme code', () async {
    await ReferralLinkHandler.instance.handleUri(
      Uri.parse('jagspoor://referral?code=SCHEME123'),
      validateCode: (_) async => true,
    );
    expect(ReferralLinkHandler.instance.pendingCode, 'SCHEME123');
  });

  test('upper-cases the stored code', () async {
    await ReferralLinkHandler.instance.handleUri(
      Uri.parse('https://jagspoor.co.za/r/abc123'),
      validateCode: (_) async => true,
    );
    expect(ReferralLinkHandler.instance.pendingCode, 'ABC123');
  });

  test('ignores a non-referral URI', () async {
    await ReferralLinkHandler.instance.handleUri(
      Uri.parse('https://jagspoor.co.za/about'),
      validateCode: (_) async => true,
    );
    expect(ReferralLinkHandler.instance.pendingCode, isNull);
  });

  test('a code that fails validation is stored but not signalled', () async {
    var resolved = false;
    await ReferralLinkHandler.instance.handleUri(
      Uri.parse('https://jagspoor.co.za/r/INVALID1'),
      validateCode: (_) async => false,
    );
    // registerCode still records it (so the signup screen can pre-fill), but
    // the onCodeResolved callback is only fired for a valid code.
    expect(ReferralLinkHandler.instance.pendingCode, 'INVALID1');
    expect(resolved, isFalse);
  });

  test('a validation failure (throwing validator) never crashes', () async {
    await ReferralLinkHandler.instance.handleUri(
      Uri.parse('https://jagspoor.co.za/r/BOOM1234'),
      validateCode: (_) async => throw StateError('no firebase'),
    );
    expect(ReferralLinkHandler.instance.pendingCode, 'BOOM1234');
  });

  test('registerCode persists to SharedPreferences', () async {
    await ReferralLinkHandler.instance.registerCode('PERSIST1');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(ReferralLinkHandler.pendingCodePrefsKey),
      'PERSIST1',
    );
  });

  test('clearPendingCode removes the in-memory + durable copy', () async {
    await ReferralLinkHandler.instance.registerCode('CLEARME');
    await ReferralLinkHandler.instance.clearPendingCode();
    expect(ReferralLinkHandler.instance.pendingCode, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ReferralLinkHandler.pendingCodePrefsKey), isNull);
  });

  test('registerCode rejects a blank code', () async {
    final ok = await ReferralLinkHandler.instance.registerCode('   ');
    expect(ok, isFalse);
    expect(ReferralLinkHandler.instance.pendingCode, isNull);
  });

  test('a stored code is restored into memory by initialize()', () async {
    // Simulate a previous session having persisted a code.
    SharedPreferences.setMockInitialValues({
      ReferralLinkHandler.pendingCodePrefsKey: 'RESTORED',
    });
    ReferralLinkHandler.instance.resetForTesting();
    // initialize() with a null initial link still restores the durable code.
    await ReferralLinkHandler.instance.initialize(
      appLinks: _NullAppLinks(),
      validateCode: (_) async => true,
    );
    expect(ReferralLinkHandler.instance.pendingCode, 'RESTORED');
  });

  test('initialize() honours an initial link + fires onCodeResolved',
      () async {
    var resolvedCode = '';
    await ReferralLinkHandler.instance.initialize(
      appLinks: _FixedAppLinks(
        Uri.parse('https://jagspoor.co.za/r/LAUNCH99'),
      ),
      validateCode: (_) async => true,
      onCodeResolved: (code) => resolvedCode = code,
    );
    expect(ReferralLinkHandler.instance.pendingCode, 'LAUNCH99');
    expect(resolvedCode, 'LAUNCH99');
  });
}

/// Minimal fake link source that yields a single fixed initial link and no
/// warm stream events (no native plugin involved).
class _FixedAppLinks implements AppLinkSource {
  _FixedAppLinks(this.uri);
  final Uri uri;

  @override
  Future<Uri?> getInitialLink() async => uri;

  @override
  Stream<Uri> get uriLinkStream => const Stream<Uri>.empty();
}

/// Fake that reports no initial link.
class _NullAppLinks implements AppLinkSource {
  @override
  Future<Uri?> getInitialLink() async => null;

  @override
  Stream<Uri> get uriLinkStream => const Stream<Uri>.empty();
}
