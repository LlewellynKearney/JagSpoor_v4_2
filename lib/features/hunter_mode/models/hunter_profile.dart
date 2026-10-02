import 'package:cloud_firestore/cloud_firestore.dart';

/// Safely converts a raw Firestore date value to a [DateTime].
///
/// Handles every shape these fields can arrive in:
/// - `cloud_firestore` [Timestamp] (the canonical serialized form written by
///   `toFirestore`).
/// - A [DateTime] (e.g. an in-memory map or a `FakeFirebaseFirestore`
///   round-trip).
/// - An ISO-8601 [String] (the shape `toJson` writes for the
///   `SharedPreferences` cache, or a legacy / external doc).
/// - A `num` (milliseconds-since-epoch, a legacy int representation).
///
/// Returns `null` for `null` / an unparseable string / an unsupported type so
/// a `fromMap` / `fromJson` never throws on a missing or malformed date.
DateTime? parseTimestamp(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  return null;
}

/// Returns a copy of [data] in which every Firestore-only value is replaced by
/// a `jsonEncode`-safe equivalent.
///
/// The profile cache writes the raw `users/{uid}` document map (which may
/// carry [Timestamp] values such as `createdAt` / `updatedAt`) to
/// `SharedPreferences` via `jsonEncode`. `jsonEncode` cannot encode a
/// [Timestamp] — the exact cause of the
/// "Converting object to an encodable object failed: Instance of 'Timestamp'"
/// crash. This helper:
/// - converts any [Timestamp] to its ISO-8601 string,
/// - converts any [DateTime] to its ISO-8601 string,
/// - drops any [FieldValue] sentinel (e.g. the `updatedAt`
///   `FieldValue.serverTimestamp()` the save path builds) — the authoritative
///   value is re-read from Firestore, and `jsonEncode` cannot encode a
///   sentinel either,
/// - recursively maps nested [Map]s,
/// - passes every other JSON-native value through unchanged.
///
/// This is the safety net for the cache path; a caller that goes through
/// [HunterProfile.toJson] is already safe.
Map<String, dynamic> encodeProfileCache(Map<String, dynamic> data) {
  dynamic encodeValue(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is FieldValue) return null;
    if (value is Map) {
      return {
        for (final entry in value.entries) entry.key.toString(): encodeValue(entry.value),
      };
    }
    if (value is Iterable) return value.map(encodeValue).toList();
    return value;
  }

  return {
    for (final entry in data.entries) entry.key: encodeValue(entry.value),
  };
}

/// Typed model for the hunter profile held under `users/{uid}` (+ the
/// owner-only `users/{uid}/private/profile` POPIA document).
///
/// The model exists to give the profile a single, well-defined serialization
/// contract:
///
/// - [toFirestore] is the **Firebase write** shape. Date fields are encoded
///   as [Timestamp] / `FieldValue.serverTimestamp()` so Firestore stores
///   native timestamps.
/// - [toJson] is the **`jsonEncode` / `SharedPreferences` cache** shape. Date
///   fields are encoded as ISO-8601 strings only — it MUST never contain a
///   [Timestamp], because `jsonEncode` cannot encode one ("Converting object
///   to an encodable object failed: Instance of 'Timestamp'").
/// - [fromMap] / [fromJson] decode any date shape via [parseTimestamp].
class HunterProfile {
  final String firstName;
  final String lastName;
  final String fullName;
  final String phoneNumber;
  final String altContact;
  final String email;
  final String address;
  final String farmName;
  final String latitude;
  final String longitude;
  final String profileImageUrl;
  final String unitPreference;
  final bool darkModeAmbient;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const HunterProfile({
    this.firstName = '',
    this.lastName = '',
    this.fullName = '',
    this.phoneNumber = '',
    this.altContact = '',
    this.email = '',
    this.address = '',
    this.farmName = '',
    this.latitude = '',
    this.longitude = '',
    this.profileImageUrl = '',
    this.unitPreference = 'metric',
    this.darkModeAmbient = false,
    this.createdAt,
    this.updatedAt,
  });

  /// Builds a profile from a Firestore / cache map, tolerating the field
  /// aliases the app has used over time (`phone` / `phoneNumber`,
  /// `surname` / `lastName`, `measurementUnit` / `unitPreference`, ...).
  factory HunterProfile.fromMap(Map<String, dynamic> map) {
    String str(List<String> keys) {
      for (final k in keys) {
        final v = map[k];
        if (v != null && v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
      return '';
    }

    final legacyFull = str(['fullName', 'full_name']);
    var first = str(['firstName', 'first_name', 'name']);
    var last = str(['lastName', 'last_name', 'surname']);
    // Legacy single `fullName` ("Jane Doe") is split on the first space so a
    // returning hunter who completed the pre-split form is not bounced back
    // to onboarding.
    if (first.isEmpty && legacyFull.contains(' ')) {
      first = legacyFull.substring(0, legacyFull.indexOf(' '));
    }
    if (last.isEmpty && legacyFull.contains(' ')) {
      last = legacyFull.substring(legacyFull.indexOf(' ') + 1);
    }
    final full = legacyFull != ''
        ? legacyFull
        : [first, last].where((p) => p.isNotEmpty).join(' ');

    return HunterProfile(
      firstName: first,
      lastName: last,
      fullName: full,
      phoneNumber: str(['phoneNumber', 'phone', 'cellNumber', 'cell']),
      altContact: str(['altContact', 'alt_contact']),
      email: str(['email']),
      address: str(['address']),
      farmName: str(['farmName', 'farm_name']),
      latitude: str(['latitude']),
      longitude: str(['longitude']),
      profileImageUrl: str(['profileImageUrl', 'profile_image_url']),
      unitPreference: str(['unitPreference', 'measurementUnit']) != ''
          ? str(['unitPreference', 'measurementUnit'])
          : 'metric',
      darkModeAmbient: map['darkModeAmbient'] == true,
      createdAt: parseTimestamp(map['createdAt'] ?? map['created_at']),
      updatedAt: parseTimestamp(map['updatedAt'] ?? map['updated_at']),
    );
  }

  /// Decodes the `SharedPreferences` cache. Identical to [fromMap] but kept as
  /// a named entry point so a caller cannot accidentally read a Timestamp.
  factory HunterProfile.fromJson(Map<String, dynamic> json) =>
      HunterProfile.fromMap(json);

  /// **Firebase write** shape. Date fields are native Firestore types.
  ///
  /// Pass `serverTimestamp: true` to let Firestore stamp `updatedAt` on the
  /// server (the normal profile save). When it is false the local [updatedAt]
  /// is written as a [Timestamp], and a null value is omitted entirely.
  Map<String, dynamic> toFirestore({bool serverTimestamp = false}) {
    final out = <String, dynamic>{
      'firstName': firstName,
      'lastName': lastName,
      'fullName': fullName,
      'phone': phoneNumber,
      'altContact': altContact,
      'email': email,
      'address': address,
      'farmName': farmName,
      'latitude': latitude,
      'longitude': longitude,
      'profileImageUrl': profileImageUrl,
      'unitPreference': unitPreference,
      'darkModeAmbient': darkModeAmbient,
    };
    if (createdAt != null) out['createdAt'] = Timestamp.fromDate(createdAt!);
    if (serverTimestamp) {
      out['updatedAt'] = FieldValue.serverTimestamp();
    } else if (updatedAt != null) {
      out['updatedAt'] = Timestamp.fromDate(updatedAt!);
    }
    return out;
  }

  /// **`jsonEncode` / `SharedPreferences` cache** shape. Date fields are
  /// ISO-8601 strings only — this map can never contain a [Timestamp].
  Map<String, dynamic> toJson() => <String, dynamic>{
        'firstName': firstName,
        'lastName': lastName,
        'fullName': fullName,
        'phoneNumber': phoneNumber,
        'altContact': altContact,
        'email': email,
        'address': address,
        'farmName': farmName,
        'latitude': latitude,
        'longitude': longitude,
        'profileImageUrl': profileImageUrl,
        'unitPreference': unitPreference,
        'darkModeAmbient': darkModeAmbient,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  HunterProfile copyWith({
    String? firstName,
    String? lastName,
    String? fullName,
    String? phoneNumber,
    String? altContact,
    String? email,
    String? address,
    String? farmName,
    String? latitude,
    String? longitude,
    String? profileImageUrl,
    String? unitPreference,
    bool? darkModeAmbient,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HunterProfile(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      altContact: altContact ?? this.altContact,
      email: email ?? this.email,
      address: address ?? this.address,
      farmName: farmName ?? this.farmName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      unitPreference: unitPreference ?? this.unitPreference,
      darkModeAmbient: darkModeAmbient ?? this.darkModeAmbient,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
