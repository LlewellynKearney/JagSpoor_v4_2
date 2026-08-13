/// Standardized dropdown options for the Digital Firearm Safe, aligned with the
/// South African Firearms Control Act (Act 60 of 2000).
///
/// These constants back the dropdowns in the manual firearm entry form so that
/// licence sections, licence types, firearm types, and barrel lengths are
/// captured consistently. Stored values remain free-text strings (backward
/// compatible with scanned cards and existing records); values that fall
/// outside these lists are preserved via the form's "Custom..." entry.
class FcaFirearmOptions {
  FcaFirearmOptions._();

  /// FCA licence sections under which a firearm may be possessed. Each entry
  /// is "Section N - purpose" so the stored string is self-describing in the
  /// detail screen.
  static const List<String> licenceSections = [
    'Section 13 - Self-defence',
    'Section 14 - Collector (rare/collectable)',
    'Section 15 - Occasional sports-shooting / hunting',
    'Section 16 - Dedicated sports-shooting / hunting',
    'Section 17 - Business / Outfitter / Security',
    'Section 20 - Business / Outfitter / Security',
    'Section 21 - Temporary permit',
    'Section 22 - Inherited / Specific',
  ];

  /// FCA licence instruments / certificate types.
  static const List<String> licenceTypes = [
    'Competency Certificate',
    'Permanent Licence',
    'Temporary Permit',
    "Collector's Licence",
    'Business Licence',
    'Official Institution Licence',
  ];

  /// Standard firearm type categories used across the app.
  static const List<String> firearmTypes = [
    'Rifle',
    'Shotgun',
    'Handgun / Pistol',
    'Revolver',
    'Combination',
    'Air Rifle',
    'Muzzleloader',
  ];

  /// Standard firearm action types.
  static const List<String> actionTypes = [
    'Bolt-action',
    'Semi-automatic',
    'Lever-action',
    'Pump-action',
    'Break-action',
    'Single-shot',
    'Revolver',
  ];

  /// Standard barrel lengths, in whole inches from 2" to 38". Fractional or
  /// millimetre values can be entered via the form's custom-entry fallback.
  static final List<String> barrelLengths = [
    for (var i = 2; i <= 38; i++) '$i"',
  ];
}
