/// Field-level classification of the data held under `users/{uid}`.
///
/// The parent `users/{uid}` document is the **account directory**: name,
/// phone, email, role and farm details, which other signed-in app users
/// legitimately need (marketplace listings, outfitter/hunter contact cards,
/// booking-availability configuration). It is readable by any signed-in user.
///
/// [specialPersonalInformation] holds information that POPIA classifies as
/// **special personal information** (s.26 — health) or that is otherwise
/// high-harm if disclosed (identity number, firearm-permit particulars).
/// Those fields are persisted in the owner-only
/// `users/{uid}/private/profile` subcollection so another signed-in user can
/// never read them. This is the data-handling contract the published privacy
/// policy commits to ("your health, ID and firearm data are readable only by
/// you").
class SensitivePersonalInformation {
  SensitivePersonalInformation._();

  /// Owner-only subcollection that carries [specialPersonalInformation].
  static const String privateCollection = 'private';

  /// Document id inside [privateCollection] holding the sensitive profile.
  static const String privateProfileDocId = 'profile';

  /// Full path segment helper: `users/{uid}/private/profile`.
  static String privateProfilePath(String uid) =>
      'users/$uid/$privateCollection/$privateProfileDocId';

  /// POPIA s.26 special personal information (health) plus the highest-harm
  /// identifiers. These MUST NOT appear on the cross-user-readable
  /// `users/{uid}` document.
  static const List<String> specialPersonalInformation = [
    'bloodType',
    'allergies',
    'medicalAid',
    'emergencyContact',
    'hasFirstAid',
    'idNumber',
    'provincialPermits',
    'hunterStatus',
  ];

  /// Legacy aliases of the above that may exist on older documents.
  static const List<String> sensitiveAliases = [
    'medicalAidNumber',
    'medicalConditions',
    'idPassportNumber',
  ];

  /// Everything in [specialPersonalInformation] + [sensitiveAliases].
  static List<String> get allSensitiveFields => [
    ...specialPersonalInformation,
    ...sensitiveAliases,
  ];

  /// True when [field] must be stored only in the owner-only subcollection.
  static bool isSensitive(String field) => allSensitiveFields.contains(field);

  /// Copies the sensitive subset of [source] into a new map (used to route
  /// profile writes to the private document and to strip sensitive fields
  /// from anything destined for the cross-user-readable parent document).
  static Map<String, dynamic> extract(Map<String, dynamic> source) => {
    for (final f in allSensitiveFields)
      if (source.containsKey(f)) f: source[f],
  };

  /// Returns [source] without any sensitive field (safe to write to the
  /// cross-user-readable `users/{uid}` document).
  static Map<String, dynamic> redact(Map<String, dynamic> source) => {
    for (final entry in source.entries)
      if (!isSensitive(entry.key)) entry.key: entry.value,
  };
}
