import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resolution result for [GeminiConfigService.resolveKey].
class GeminiKeyResolution {
  const GeminiKeyResolution({
    required this.apiKey,
    required this.source,
  });

  /// The resolved API key (empty string when nothing is configured).
  final String apiKey;

  /// Where the key was resolved from.
  final GeminiKeySource source;

  /// Whether a non-empty key was resolved.
  bool get isConfigured => apiKey.isNotEmpty;

  @override
  String toString() =>
      'GeminiKeyResolution(apiKey: ${isConfigured ? '<redacted>' : '<empty>'}, '
      'source: $source)';
}

/// The source a Gemini API key was resolved from.
enum GeminiKeySource {
  /// `--dart-define=GEMINI_API_KEY=...` baked in at compile time via
  /// `String.fromEnvironment('GEMINI_API_KEY')`. Highest priority.
  dartDefine,

  /// `Platform.environment['GEMINI_API_KEY']` — the runtime process env
  /// (desktop / CI runners). Second priority.
  processEnv,

  /// A key persisted in local storage (SharedPreferences) via
  /// [GeminiConfigService.setApiKey] — the runtime fallback when the key was
  /// not supplied at compile time (e.g. a release build that omits
  /// `--dart-define`, or an admin-set key). Lowest priority.
  localStorage,

  /// No key resolved from any source.
  none,
}

/// Signature for the platform-environment accessor (overridable in tests).
typedef EnvAccessor = String? Function(String key);

/// Signature for the compile-time `String.fromEnvironment` accessor.
///
/// `String.fromEnvironment` is a `const` that is resolved at *compile* time,
/// so it cannot be read through a normal indirection at runtime. The default
/// implementation reads the compile-time value once; tests inject a fixed
/// value to exercise each branch of [resolveKey].
typedef DartDefineAccessor = String Function(String key, String defaultValue);

/// Central, hardened Gemini API-key resolver with a three-tier fallback
/// chain and a reactive configuration state.
///
/// Resolution priority (per the v4.5 to-do Item #2):
///  1. `const String.fromEnvironment('GEMINI_API_KEY')` — the `--dart-define`
///     value baked in at compile time. This is the canonical way to ship a key
///     in a release build.
///  2. `Platform.environment['GEMINI_API_KEY']` — the runtime process env,
///     used by desktop / CI runners (`flutter test`, `flutter run -d
///     linux/windows`) and by `flutter run --dart-define=...` on mobile.
///  3. Local secure storage (SharedPreferences key `jagspoor_gemini_api_key`)
///     — a runtime fallback for when `--dart-define` was omitted at compile
///     time. An admin / the user can set it at runtime via [setApiKey]; it
///     persists across launches.
///
/// Exposes [isGeminiApiKeyConfigured] to drive the scanner's "AI extraction
/// unavailable" banner state **reactively** (the service is a
/// [ChangeNotifier]; the banner listens and rebuilds when a key is set or
/// cleared at runtime).
class GeminiConfigService extends ChangeNotifier {
  static const String _prefsKey = 'jagspoor_gemini_api_key';

  /// Process-wide singleton. Constructed lazily on first access.
  static GeminiConfigService get instance =>
      _instance ??= GeminiConfigService._();
  static GeminiConfigService? _instance;

  GeminiConfigService._();

  /// The compile-time `--dart-define` value. Read once at construction (the
  /// value is a `const` and cannot change after compile). Empty string when
  /// `--dart-define=GEMINI_API_KEY=...` was not supplied at build time.
  static const String _compiledKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  /// The cached local-storage key (loaded by [init]). Empty until [init]
  /// completes (or when no key was ever stored).
  String _storedKey = '';

  /// Whether [init] has loaded the persisted local-storage key.
  bool _initialized = false;

  /// Platform environment accessor (overridable for tests via
  /// [injectForTesting]).
  EnvAccessor _envAccessor = _defaultEnvAccessor;

  /// Test override for the compile-time key (the `const
  /// String.fromEnvironment` cannot be toggled per-test, so tests inject a
  /// fixed value to exercise the dartDefine branch of [resolveKey]). `null`
  /// in production → the real compile-time const is used.
  String? _compiledKeyOverride;

  /// The last-resolved key + source (computed lazily and re-cached on
  /// [setApiKey] / [clearApiKey]). `null` means "not yet resolved".
  GeminiKeyResolution? _cached;

  static String? _defaultEnvAccessor(String key) {
    // `Platform.environment` throws on web; guard so the resolver is safe to
    // call on every platform.
    try {
      return Platform.environment[key];
    } catch (_) {
      return null;
    }
  }

  /// Loads the persisted local-storage key (SharedPreferences). Call once at
  /// startup (mirrors `ThemeController.init` / `MeasurementFormatter.init`)
  /// before any consumer reads [isGeminiApiKeyConfigured] / [resolveKey].
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _storedKey = prefs.getString(_prefsKey) ?? '';
    } catch (_) {
      // SharedPreferences unavailable (e.g. web before storage init) — leave
      // the stored key empty; the dart-define / env sources still apply.
      _storedKey = '';
    }
    _initialized = true;
    _cached = null; // force re-resolve
  }

  /// Injects test overrides for the env accessor, the local-storage key, and
  /// the compile-time key, then marks the service initialized so [resolveKey]
  /// does not require a live SharedPreferences instance. Only for unit tests.
  @visibleForTesting
  void injectForTesting({
    required EnvAccessor envAccessor,
    String storedKey = '',
    String? compiledKey,
  }) {
    _envAccessor = envAccessor;
    _storedKey = storedKey;
    _compiledKeyOverride = compiledKey;
    _initialized = true;
    _cached = null;
  }

  /// Resolves the Gemini API key through the three-tier fallback chain.
  ///
  /// Pure given the injected env accessor + the cached stored key (no I/O),
  /// so it is fully unit-testable without a live SharedPreferences / platform
  /// environment. Returns a [GeminiKeyResolution] describing the key + source.
  GeminiKeyResolution resolveKey() {
    if (_cached != null) return _cached!;

    // Use the test override when set; otherwise the compile-time const.
    final compiledKey =
        _compiledKeyOverride ?? _compiledKey;

    // 1. Compile-time --dart-define (highest priority).
    if (compiledKey.isNotEmpty) {
      _cached = GeminiKeyResolution(
        apiKey: compiledKey,
        source: GeminiKeySource.dartDefine,
      );
      return _cached!;
    }

    // 2. Runtime process environment (desktop / CI).
    final envKey = _envAccessor('GEMINI_API_KEY');
    if (envKey != null && envKey.isNotEmpty) {
      _cached = GeminiKeyResolution(
        apiKey: envKey,
        source: GeminiKeySource.processEnv,
      );
      return _cached!;
    }

    // 3. Local storage fallback (runtime-set key, persists across launches).
    if (_storedKey.isNotEmpty) {
      _cached = GeminiKeyResolution(
        apiKey: _storedKey,
        source: GeminiKeySource.localStorage,
      );
      return _cached!;
    }

    _cached = const GeminiKeyResolution(
      apiKey: '',
      source: GeminiKeySource.none,
    );
    return _cached!;
  }

  /// Whether a non-empty Gemini API key is currently configured (from any
  /// source). The reactive banner state — listen to [GeminiConfigService]
  /// (a [ChangeNotifier]) and read this getter to drive the banner.
  bool get isGeminiApiKeyConfigured => resolveKey().isConfigured;

  /// The resolved API key (empty string when unconfigured). Convenience for
  /// callers that only need the key string.
  String get apiKey => resolveKey().apiKey;

  /// The source the key was resolved from (for diagnostics / the banner).
  GeminiKeySource get keySource => resolveKey().source;

  /// Persists a runtime-set key to local storage (SharedPreferences) so it is
  /// available on the next launch even when `--dart-define` was omitted at
  /// compile time. Notifies listeners so the reactive banner updates.
  ///
  /// Setting an empty / whitespace-only key is treated as a clear.
  Future<void> setApiKey(String key) async {
    final trimmed = key.trim();
    _storedKey = trimmed;
    _cached = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (trimmed.isEmpty) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, trimmed);
      }
    } catch (_) {
      // Best-effort persist; the in-memory copy still drives the current
      // session even if SharedPreferences is unavailable.
    }
    notifyListeners();
  }

  /// Clears the runtime-set local-storage key. Notifies listeners.
  Future<void> clearApiKey() async {
    await setApiKey('');
  }

  /// Clears all cached state (for sign-out / test teardown). Notifies
  /// listeners so the banner reverts to "unconfigured" if the only source
  /// was the in-memory local-storage key.
  @visibleForTesting
  void reset() {
    _storedKey = '';
    _cached = null;
    _envAccessor = _defaultEnvAccessor;
    _compiledKeyOverride = null;
    _initialized = false;
    notifyListeners();
  }
}
