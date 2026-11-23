import 'package:flutter/material.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_feature_flag.dart';

/// Renders [builder] only while the Veld & Carrying Capacity feature is ON.
///
/// This is the **only** way the feature's UI is reached. With the default
/// OFF build the gate renders `SizedBox.shrink()` — no button, no tile, no
/// empty space — and performs **no Firestore read at all**, because the
/// compile-time switch alone can never enable the feature.
///
/// When the build was compiled with `--dart-define=VELD_CARRY_ENABLED=true`,
/// the gate resolves `admin_config/feature_flags.veldCarryEnabled` once and
/// rebuilds. Any failure fails closed (nothing renders), matching
/// [VeldCarryFeatureFlag]'s documented failure policy.
class VeldCarryGate extends StatefulWidget {
  const VeldCarryGate({
    super.key,
    required this.builder,
    this.flag,
  });

  /// Built only when the feature is enabled.
  final WidgetBuilder builder;

  /// Test seam: inject a flag instance (e.g.
  /// `VeldCarryFeatureFlag.forTesting(compileTimeEnabled: true,
  /// adminConfigEnabled: true)`).
  @visibleForTesting
  final VeldCarryFeatureFlag? flag;

  @override
  State<VeldCarryGate> createState() => _VeldCarryGateState();
}

class _VeldCarryGateState extends State<VeldCarryGate> {
  late final VeldCarryFeatureFlag _flag =
      widget.flag ?? VeldCarryFeatureFlag.instance;

  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _enabled = _flag.isVeldCarryEnabled;
    if (_enabled) return;
    // Default OFF build: never touch Firestore, never render anything.
    if (!_flag.compileTimeSwitchEnabled) return;
    _flag.ensureLoaded().then((_) {
      if (!mounted) return;
      final enabled = _flag.isVeldCarryEnabled;
      if (enabled == _enabled) return;
      setState(() => _enabled = enabled);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();
    return widget.builder(context);
  }
}
