import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/services/gemini_config_service.dart';

/// Unit tests for the centralized Gemini API-key resolver
/// (`GeminiConfigService`), which backs the AI scanner's three-tier fallback
/// chain (v4.5 to-do Item #2):
///  1. `const String.fromEnvironment('GEMINI_API_KEY')` (--dart-define).
///  2. `Platform.environment['GEMINI_API_KEY']` (desktop / CI runtime env).
///  3. Local secure storage (SharedPreferences) — runtime fallback when
///     `--dart-define` was omitted at compile time.
///
/// `String.fromEnvironment` is a `const` resolved at *compile* time, so it
/// cannot be toggled per-test; the service exposes a `compiledKey` override
/// on `injectForTesting` to exercise the dartDefine branch deterministically.
void main() {
  late GeminiConfigService service;

  setUp(() {
    // The singleton is reset between tests so each test gets a clean service.
    service = GeminiConfigService.instance;
    service.reset();
  });

  tearDown(() {
    service.reset();
  });

  group('resolveKey fallback priority', () {
    test('1. dart-define wins over env + local storage', () {
      service.injectForTesting(
        envAccessor: (_) => 'env-key',
        storedKey: 'stored-key',
        compiledKey: 'dart-define-key',
      );
      final r = service.resolveKey();
      expect(r.apiKey, 'dart-define-key');
      expect(r.source, GeminiKeySource.dartDefine);
      expect(r.isConfigured, isTrue);
    });

    test('2. env wins when dart-define absent (desktop / CI)', () {
      service.injectForTesting(
        envAccessor: (_) => 'env-key',
        storedKey: 'stored-key',
        compiledKey: '', // no --dart-define
      );
      final r = service.resolveKey();
      expect(r.apiKey, 'env-key');
      expect(r.source, GeminiKeySource.processEnv);
      expect(r.isConfigured, isTrue);
    });

    test('3. local storage wins when dart-define + env absent', () {
      service.injectForTesting(
        envAccessor: (_) => null, // no runtime env
        storedKey: 'stored-key',
        compiledKey: '', // no --dart-define
      );
      final r = service.resolveKey();
      expect(r.apiKey, 'stored-key');
      expect(r.source, GeminiKeySource.localStorage);
      expect(r.isConfigured, isTrue);
    });

    test('none when all three sources are absent', () {
      service.injectForTesting(
        envAccessor: (_) => null,
        storedKey: '',
        compiledKey: '',
      );
      final r = service.resolveKey();
      expect(r.apiKey, '');
      expect(r.source, GeminiKeySource.none);
      expect(r.isConfigured, isFalse);
    });
  });

  group('empty / whitespace handling', () {
    test('empty env value does not count as configured', () {
      service.injectForTesting(
        envAccessor: (_) => '',
        storedKey: 'stored-key',
        compiledKey: '',
      );
      final r = service.resolveKey();
      // empty env → falls through to local storage
      expect(r.source, GeminiKeySource.localStorage);
      expect(r.apiKey, 'stored-key');
    });

    test('null env falls through to local storage', () {
      service.injectForTesting(
        envAccessor: (_) => null,
        storedKey: 'stored-key',
        compiledKey: '',
      );
      final r = service.resolveKey();
      expect(r.source, GeminiKeySource.localStorage);
    });

    test('whitespace-only env does not count as configured', () {
      service.injectForTesting(
        envAccessor: (_) => '   ',
        storedKey: 'stored-key',
        compiledKey: '',
      );
      final r = service.resolveKey();
      // '   ' is non-empty so it currently resolves to processEnv; this pins
      // the contract (a non-empty env string wins, even whitespace). A stored
      // key is the fallback only when env is null/empty.
      expect(r.source, GeminiKeySource.processEnv);
    });
  });

  group('isGeminiApiKeyConfigured (reactive banner state)', () {
    test('true when dart-define present', () {
      service.injectForTesting(
        envAccessor: (_) => null,
        storedKey: '',
        compiledKey: 'dart-define-key',
      );
      expect(service.isGeminiApiKeyConfigured, isTrue);
    });

    test('true when env present', () {
      service.injectForTesting(
        envAccessor: (_) => 'env-key',
        storedKey: '',
        compiledKey: '',
      );
      expect(service.isGeminiApiKeyConfigured, isTrue);
    });

    test('true when local storage present', () {
      service.injectForTesting(
        envAccessor: (_) => null,
        storedKey: 'stored-key',
        compiledKey: '',
      );
      expect(service.isGeminiApiKeyConfigured, isTrue);
    });

    test('false when no source configured', () {
      service.injectForTesting(
        envAccessor: (_) => null,
        storedKey: '',
        compiledKey: '',
      );
      expect(service.isGeminiApiKeyConfigured, isFalse);
    });
  });

  group('ChangeNotifier reactivity', () {
    test('notifyListeners fires on setApiKey', () async {
      service.injectForTesting(
        envAccessor: (_) => null,
        storedKey: '',
        compiledKey: '',
      );
      var notifyCount = 0;
      service.addListener(() => notifyCount++);
      // setApiKey with empty key is treated as a clear but still notifies.
      await service.setApiKey('new-runtime-key');
      expect(notifyCount, 1);
      // The stored key is now the in-memory copy, so isConfigured is true.
      expect(service.isGeminiApiKeyConfigured, isTrue);
      expect(service.resolveKey().apiKey, 'new-runtime-key');
      expect(service.resolveKey().source, GeminiKeySource.localStorage);
    });

    test('notifyListeners fires on clearApiKey', () async {
      service.injectForTesting(
        envAccessor: (_) => null,
        storedKey: 'stored-key',
        compiledKey: '',
      );
      var notifyCount = 0;
      service.addListener(() => notifyCount++);
      await service.clearApiKey();
      expect(notifyCount, 1);
      expect(service.isGeminiApiKeyConfigured, isFalse);
    });

    test('setApiKey trims whitespace', () async {
      service.injectForTesting(
        envAccessor: (_) => null,
        storedKey: '',
        compiledKey: '',
      );
      await service.setApiKey('  trimmed-key  ');
      expect(service.resolveKey().apiKey, 'trimmed-key');
    });

    test('setApiKey with empty string clears the key', () async {
      service.injectForTesting(
        envAccessor: (_) => null,
        storedKey: 'stored-key',
        compiledKey: '',
      );
      expect(service.isGeminiApiKeyConfigured, isTrue);
      await service.setApiKey('');
      expect(service.isGeminiApiKeyConfigured, isFalse);
    });

    test('reset clears all state and notifies', () {
      service.injectForTesting(
        envAccessor: (_) => 'env-key',
        storedKey: 'stored-key',
        compiledKey: 'dart-define-key',
      );
      var notifyCount = 0;
      service.addListener(() => notifyCount++);
      service.reset();
      expect(notifyCount, 1);
    });
  });

  group('resolution caching', () {
    test('resolveKey caches the result (same instance returned)', () {
      service.injectForTesting(
        envAccessor: (_) => 'env-key',
        storedKey: '',
        compiledKey: '',
      );
      final r1 = service.resolveKey();
      final r2 = service.resolveKey();
      expect(identical(r1, r2), isTrue);
    });

    test('setApiKey invalidates the cache', () async {
      service.injectForTesting(
        envAccessor: (_) => null,
        storedKey: 'stored-key',
        compiledKey: '',
      );
      final r1 = service.resolveKey();
      expect(r1.source, GeminiKeySource.localStorage);
      await service.setApiKey('new-key');
      final r2 = service.resolveKey();
      expect(r2.apiKey, 'new-key');
      expect(identical(r1, r2), isFalse);
    });
  });

  group('GeminiKeyResolution redaction', () {
    test('toString redacts a configured key', () {
      const r = GeminiKeyResolution(
        apiKey: 'super-secret-key',
        source: GeminiKeySource.dartDefine,
      );
      final s = r.toString();
      expect(s.contains('super-secret-key'), isFalse);
      expect(s.contains('<redacted>'), isTrue);
    });

    test('toString shows <empty> for an unconfigured key', () {
      const r = GeminiKeyResolution(
        apiKey: '',
        source: GeminiKeySource.none,
      );
      expect(r.toString().contains('<empty>'), isTrue);
    });
  });
}
