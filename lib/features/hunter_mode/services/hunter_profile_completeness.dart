import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// The mandatory hunter profile fields: a Name (first name), a Surname
/// (last name), and at least one contact detail (phone number OR email).
///
/// A hunter cannot access the main app features until these fields are
/// validly filled and saved to Firestore. The [HunterProfileCompleteness]
/// check runs on registration + login (see the auth routing in
/// `auth_screen.dart` + `splash_screen.dart`) and, when the profile is
/// incomplete, redirects the hunter to the Hunter Profile screen to
/// complete onboarding before any dashboard is shown.
class HunterProfileCompleteness {
  HunterProfileCompleteness._();
  static final HunterProfileCompleteness instance =
      HunterProfileCompleteness._();

  /// Injection seam so the check can be exercised against a
  /// `FakeFirebaseFirestore` without a live Firebase app.
  @visibleForTesting
  factory HunterProfileCompleteness.forTesting(FirebaseFirestore firestore) {
    final c = HunterProfileCompleteness._();
    c._firestoreOverride = firestore;
    return c;
  }

  FirebaseFirestore? _firestoreOverride;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  /// Resolves the mandatory-field completeness for the supplied Firebase
  /// Auth uid.
  ///
  /// Reads `users/{uid}` and returns a [HunterProfileStatus] describing
  /// which mandatory fields are present. Best-effort + tolerant: a missing
  /// user doc, a Firestore fetch error (offline / permissions /
  /// `[core/no-app]` during a cold-launch race), or any field-level absence
  /// resolves to an incomplete status so the auth gate redirects to the
  /// profile screen (never silently admits an incomplete hunter to the app).
  Future<HunterProfileStatus> statusFor(String uid) async {
    if (uid.isEmpty) return const HunterProfileStatus();
    try {
      final snap = await _firestore.collection('users').doc(uid).get();
      if (!snap.exists) return const HunterProfileStatus();
      final data = snap.data() ?? const <String, dynamic>{};
      return HunterProfileStatus.fromUserData(data);
    } catch (_) {
      // Offline / permissions / no-app -- treat as incomplete so the gate
      // redirects to the profile screen (the user can complete onboarding
      // once the fetch succeeds; never silently bypass).
      return const HunterProfileStatus();
    }
  }
}

/// Snapshot of a hunter's mandatory-profile completeness.
///
/// A field is "present" when it is a non-empty (trimmed) string. The
/// [isComplete] getter is the single gate the auth routing checks: the
/// hunter must have a Name, a Surname, AND at least one contact detail
/// (phone OR email).
class HunterProfileStatus {
  final bool hasFirstName;
  final bool hasLastName;
  final bool hasPhone;
  final bool hasEmail;

  const HunterProfileStatus({
    this.hasFirstName = false,
    this.hasLastName = false,
    this.hasPhone = false,
    this.hasEmail = false,
  });

  factory HunterProfileStatus.fromUserData(Map<String, dynamic> data) {
    String trim(dynamic v) => (v?.toString() ?? '').trim();
    final firstName = trim(data['firstName']).isNotEmpty ||
        trim(data['first_name']).isNotEmpty ||
        trim(data['name']).isNotEmpty;
    // A legacy single `fullName` ("Jane Doe") counts as both the first
    // and last name being present so a returning hunter who completed the
    // pre-split profile form is not bounced back to onboarding.
    final fullName = trim(data['fullName']);
    final fullNamePresent = fullName.isNotEmpty;
    final lastName = trim(data['lastName']).isNotEmpty ||
        trim(data['last_name']).isNotEmpty ||
        trim(data['surname']).isNotEmpty ||
        (fullNamePresent && fullName.contains(' '));
    final phone = trim(data['phone']).isNotEmpty ||
        trim(data['phoneNumber']).isNotEmpty ||
        trim(data['cellNumber']).isNotEmpty ||
        trim(data['cell']).isNotEmpty;
    final email = trim(data['email']).isNotEmpty;

    return HunterProfileStatus(
      hasFirstName: firstName || fullNamePresent,
      hasLastName: lastName,
      hasPhone: phone,
      hasEmail: email,
    );
  }

  bool get hasAnyContactDetail => hasPhone || hasEmail;

  /// Whether ALL mandatory profile fields are present. This is the gate the
  /// auth routing checks before admitting a hunter to the main app.
  bool get isComplete =>
      hasFirstName && hasLastName && hasAnyContactDetail;

  /// A short human-readable summary of the missing fields, used by the auth
  /// gate's "redirecting to complete your profile" snackbar.
  String get missingSummary {
    final missing = <String>[];
    if (!hasFirstName) missing.add('Name');
    if (!hasLastName) missing.add('Surname');
    if (!hasAnyContactDetail) missing.add('Contact details');
    return missing.isEmpty
        ? ''
        : 'Missing: ${missing.join(', ')}.';
  }
}
