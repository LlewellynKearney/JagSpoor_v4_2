import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Two-switch gate for the Veld & Carrying Capacity feature.
///
/// The feature is enabled ONLY when BOTH switches are ON:
///
///  1. **Compile-time** — the app was built with
///     `--dart-define=VELD_CARRY_ENABLED=true`. Defaults to `false`, so a
///     normal build never enables the feature.
///  2. **Control-plane** — `admin_config/feature_flags` carries
///     `veldCarryEnabled: true`. This is the same `admin_config/*` document
///     family used by `admin_config/app_version` and
///     `admin_config/review_config`; no separate config system is introduced.
///
/// Failure policy is **fail-closed**: a missing doc, a non-boolean value, a
/// Firestore error or an offline read all resolve to OFF. That deliberately
/// inverts `AppVersionCheck`'s fail-open stance — an unreleased feature must
/// never switch itself on.
///
/// There is no UI caller yet; this phase only establishes the gate.
class VeldCarryFeatureFlag {
  VeldCarryFeatureFlag._({
    required bool compileTimeEnabled,
    FirebaseFirestore? firestore,
    bool adminConfigEnabled = false,
  })  : _compileTimeEnabled = compileTimeEnabled,
        _firestore = firestore,
        _adminConfigEnabled = adminConfigEnabled;

  /// Control-plane collection (shared with the other `admin_config` docs).
  static const String configCollection = 'admin_config';

  /// Control-plane document holding feature switches.
  static const String configDocument = 'feature_flags';

  /// The field this gate reads.
  static const String adminConfigField = 'veldCarryEnabled';

  /// Compile-time switch — `--dart-define=VELD_CARRY_ENABLED=true`.
  static const bool compileTimeEnabled =
      bool.fromEnvironment('VELD_CARRY_ENABLED', defaultValue: false);

  static VeldCarryFeatureFlag? _instance;

  /// Process-wide instance (no UI caller yet).
  static VeldCarryFeatureFlag get instance => _instance ??=
      VeldCarryFeatureFlag._(compileTimeEnabled: compileTimeEnabled);

  final bool _compileTimeEnabled;
  final FirebaseFirestore? _firestore;
  bool _adminConfigEnabled;
  bool _loaded = false;

  /// Last control-plane value read; `false` before the first load.
  bool get adminConfigEnabled => _adminConfigEnabled;

  /// True only when the compile-time AND control-plane switches are both ON.
  bool get isVeldCarryEnabled => shouldEnable(
        compileTime: _compileTimeEnabled,
        adminConfig: _adminConfigEnabled,
      );

  /// The pure gating rule: both switches must be true.
  static bool shouldEnable({
    required bool compileTime,
    required bool adminConfig,
  }) =>
      compileTime && adminConfig;

  /// Injects a fake Firestore / compile-time value for tests.
  @visibleForTesting
  static VeldCarryFeatureFlag forTesting({
    bool compileTimeEnabled = false,
    FirebaseFirestore? firestore,
    bool adminConfigEnabled = false,
  }) =>
      VeldCarryFeatureFlag._(
        compileTimeEnabled: compileTimeEnabled,
        firestore: firestore,
        adminConfigEnabled: adminConfigEnabled,
      );

  @visibleForTesting
  static void resetForTesting() => _instance = null;

  /// Resolves the control-plane flag. Never throws; fails closed.
  ///
  /// Reads from the SERVER rather than the cache so an offline device cannot
  /// act on a stale `true`; the resulting error is caught and yields `false`.
  Future<bool> refresh() async {
    try {
      final db = _resolveFirestore();
      if (db == null) {
        _adminConfigEnabled = false;
        _loaded = true;
        return false;
      }
      final snapshot = await db
          .collection(configCollection)
          .doc(configDocument)
          .get(const GetOptions(source: Source.server));
      final data = snapshot.data();
      // Only a literal `true` enables the flag; anything else fails closed.
      _adminConfigEnabled = data != null && data[adminConfigField] == true;
      _loaded = true;
      return _adminConfigEnabled;
    } catch (e) {
      debugPrint('VeldCarryFeatureFlag.refresh failed, failing closed: $e');
      _adminConfigEnabled = false;
      _loaded = true;
      return false;
    }
  }

  /// Loads the control-plane flag once. Never throws.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      await refresh();
    } catch (e) {
      debugPrint('VeldCarryFeatureFlag.ensureLoaded failed: $e');
      _adminConfigEnabled = false;
      _loaded = true;
    }
  }

  FirebaseFirestore? _resolveFirestore() {
    if (_firestore != null) return _firestore;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }
}
