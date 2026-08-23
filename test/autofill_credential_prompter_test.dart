import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/auth/services/autofill_credential_prompter.dart';

/// Unit tests for [AutofillCredentialPrompter] — verifies the helper invokes
/// the platform `TextInput.finishAutofillContext` method (which triggers the
/// native credential manager's save prompt) and never throws when the
/// platform channel is unavailable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, null);
  });

  test('finishMethod constant matches the platform channel method', () {
    expect(
      AutofillCredentialPrompter.finishMethod,
      'TextInput.finishAutofillContext',
    );
  });

  test('promptSaveCredentials invokes TextInput.finishAutofillContext', () {
    AutofillCredentialPrompter.promptSaveCredentials();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'TextInput.finishAutofillContext');
  });

  test('promptSaveCredentials can be called repeatedly without throwing', () {
    AutofillCredentialPrompter.promptSaveCredentials();
    AutofillCredentialPrompter.promptSaveCredentials();
    expect(calls, hasLength(2));
  });

  test('does not throw when no platform handler is registered', () {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, null);
    expect(
      () => AutofillCredentialPrompter.promptSaveCredentials(),
      returnsNormally,
    );
  });
}
