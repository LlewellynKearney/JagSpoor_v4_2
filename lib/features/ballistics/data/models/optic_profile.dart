/// Turret adjustment unit system used by a scope.
enum TurretUnit {
  /// Minutes of angle (imperial). Common clicks: 1/4 MOA, 1/8 MOA, 1/2 MOA.
  moa,
  /// Milliradians (metric). Common click: 0.1 MRAD (rarely 0.05 MRAD).
  mrad,
}

/// Reticle focal plane — determines whether reticle markings scale with zoom.
enum FocalPlane {
  /// First focal plane: reticle subtensions are true at every magnification.
  ffp,
  /// Second focal plane: reticle subtensions are only true at the native
  /// (calibration) magnification and must be scaled at other powers.
  sfp,
}

/// Physical + optical specification of a scope, linked to a user firearm.
///
/// All fields are persisted as a nested `optic` map on the firearm document so
/// the optic "travels" with its host rifle. Legacy firearm docs that pre-date
/// this feature hydrate to sensible defaults via [OpticProfile.defaults].
class OpticProfile {
  final String opticName;
  final double tubeDiameterMm;
  final double heightOverBoreInches;
  final TurretUnit turretUnit;
  final double clickValue;
  final FocalPlane focalPlane;
  final String reticleType;
  final double nativeMagnification;
  final double currentMagnification;

  const OpticProfile({
    this.opticName = '',
    this.tubeDiameterMm = 30.0,
    this.heightOverBoreInches = 1.75,
    this.turretUnit = TurretUnit.moa,
    this.clickValue = 0.25,
    this.focalPlane = FocalPlane.sfp,
    this.reticleType = 'Mil-Dot',
    this.nativeMagnification = 10.0,
    this.currentMagnification = 10.0,
  });

  /// Defaults used when a firearm has no persisted optic spec.
  static const OpticProfile defaults = OpticProfile();

  factory OpticProfile.fromJson(Map<String, dynamic> json) {
    TurretUnit unitFor(dynamic v) {
      final s = (v?.toString() ?? 'moa').toLowerCase();
      return s.startsWith('mrad') || s.startsWith('mil')
          ? TurretUnit.mrad
          : TurretUnit.moa;
    }

    FocalPlane planeFor(dynamic v) {
      final s = (v?.toString() ?? 'sfp').toLowerCase();
      return s.startsWith('ffp') || s.startsWith('first')
          ? FocalPlane.ffp
          : FocalPlane.sfp;
    }

    return OpticProfile(
      opticName: (json['opticName'] as String?) ?? '',
      tubeDiameterMm: _toDouble(json['tubeDiameterMm'], 30.0),
      heightOverBoreInches: _toDouble(json['heightOverBoreInches'], 1.75),
      turretUnit: unitFor(json['turretUnit']),
      clickValue: _toDouble(json['clickValue'], 0.25),
      focalPlane: planeFor(json['focalPlane']),
      reticleType: (json['reticleType'] as String?) ?? 'Mil-Dot',
      nativeMagnification: _toDouble(json['nativeMagnification'], 10.0),
      currentMagnification: _toDouble(json['currentMagnification'], 10.0),
    );
  }

  Map<String, dynamic> toJson() => {
        'opticName': opticName,
        'tubeDiameterMm': tubeDiameterMm,
        'heightOverBoreInches': heightOverBoreInches,
        'turretUnit': turretUnit == TurretUnit.moa ? 'MOA' : 'MRAD',
        'clickValue': clickValue,
        'focalPlane': focalPlane == FocalPlane.ffp ? 'FFP' : 'SFP',
        'reticleType': reticleType,
        'nativeMagnification': nativeMagnification,
        'currentMagnification': currentMagnification,
      };

  OpticProfile copyWith({
    String? opticName,
    double? tubeDiameterMm,
    double? heightOverBoreInches,
    TurretUnit? turretUnit,
    double? clickValue,
    FocalPlane? focalPlane,
    String? reticleType,
    double? nativeMagnification,
    double? currentMagnification,
  }) {
    return OpticProfile(
      opticName: opticName ?? this.opticName,
      tubeDiameterMm: tubeDiameterMm ?? this.tubeDiameterMm,
      heightOverBoreInches: heightOverBoreInches ?? this.heightOverBoreInches,
      turretUnit: turretUnit ?? this.turretUnit,
      clickValue: clickValue ?? this.clickValue,
      focalPlane: focalPlane ?? this.focalPlane,
      reticleType: reticleType ?? this.reticleType,
      nativeMagnification: nativeMagnification ?? this.nativeMagnification,
      currentMagnification: currentMagnification ?? this.currentMagnification,
    );
  }

  /// Human-readable label for the turret unit system.
  String get turretUnitLabel =>
      turretUnit == TurretUnit.moa ? 'MOA' : 'MRAD';

  /// Human-readable label for the focal plane.
  String get focalPlaneLabel =>
      focalPlane == FocalPlane.ffp ? 'FFP' : 'SFP';

  /// Per-click label, e.g. "1/4 MOA" or "0.1 MRAD".
  String get clickValueLabel {
    if (turretUnit == TurretUnit.moa) {
      // Express common MOA clicks as fractions.
      if (clickValue == 0.25) return '1/4 MOA';
      if (clickValue == 0.125) return '1/8 MOA';
      if (clickValue == 0.5) return '1/2 MOA';
      if (clickValue == 1.0) return '1 MOA';
      return '${clickValue.toStringAsFixed(3)} MOA';
    }
    return '$clickValue MRAD';
  }

  static double _toDouble(dynamic value, double fallback) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  @override
  String toString() =>
      'OpticProfile($opticName, ${tubeDiameterMm}mm, HOB ${heightOverBoreInches}", '
      '$turretUnitLabel $clickValueLabel, $focalPlaneLabel, $reticleType)';
}

/// Common reticle types offered in the optic picker.
class ReticleTypes {
  static const List<String> standard = [
    'Mil-Dot',
    'MOA-2',
    'BDC (Bullet Drop Compensator)',
    'German #4',
    'Ballistic Plex',
    'Tactical Milling',
    'Christmas Tree (Horus)',
    'Duplex',
  ];

  static const List<String> turretUnits = ['MOA', 'MRAD'];
  static const List<String> focalPlanes = ['FFP', 'SFP'];

  /// Standard click-value presets per turret unit.
  static const Map<String, List<double>> clickPresets = {
    'MOA': [0.25, 0.125, 0.5, 1.0],
    'MRAD': [0.1, 0.05],
  };
}
