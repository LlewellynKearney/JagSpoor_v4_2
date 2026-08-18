import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Resolves the contact details (name / surname, phone, email) for the hunter
/// who placed a booking, so the outfitter booking dashboard can surface a
/// "Contact the hunter" card with tappable tel: / mailto: intents.
///
/// The booking document carries `hunterId` (the Firebase Auth uid of the
/// hunter). The hunter profile lives in `users/{hunterId}` and carries
/// `fullName` / `name` (+ first/last name aliases), `phoneNumber` / `phone`,
/// and `email`. The `users` collection allows `read: if isSignedIn()` per
/// `firestore.rules`, so a signed-in outfitter can read a hunter's profile.
///
/// Resolution is best-effort + tolerant: a missing `hunterId`, a missing
/// user doc, or any field-level absence resolves to a partially-populated
/// [HunterContact] (fields default to empty strings) so the UI can render
/// graceful fallbacks instead of crashing. A Firestore fetch error (offline
/// / permissions / `[core/no-app]` during a cold-launch race) is caught and
/// yields an empty contact.
class HunterContactResolver {
  HunterContactResolver._();
  static final HunterContactResolver instance = HunterContactResolver._();

  /// Injection seam so the resolver can be exercised against a
  /// `FakeFirebaseFirestore` without a live Firebase app.
  @visibleForTesting
  factory HunterContactResolver.forTesting(FirebaseFirestore firestore) {
    final r = HunterContactResolver._();
    r._firestoreOverride = firestore;
    return r;
  }

  FirebaseFirestore? _firestoreOverride;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  /// Resolves the hunter contact details from the booking document.
  ///
  /// [bookingData] is the raw `bookings/{bookingId}` document map. Only
  /// `hunterId` is required; a snapshot `hunterName` on the booking (written
  /// at booking time) is used as a display fallback when the user profile
  /// cannot be fetched.
  Future<HunterContact> resolve(Map<String, dynamic> bookingData) async {
    final hunterId = (bookingData['hunterId'] as String?)?.trim() ?? '';
    final snapshotName = (bookingData['hunterName'] as String?)?.trim() ?? '';

    String firstName = '';
    String lastName = '';
    String fullName = '';
    String phone = '';
    String email = '';

    if (hunterId.isNotEmpty) {
      try {
        final snap =
            await _firestore.collection('users').doc(hunterId).get();
        if (snap.exists) {
          final d = snap.data() ?? const <String, dynamic>{};
          firstName = (d['firstName'] as String?)?.trim() ??
              (d['name'] as String?)?.trim() ??
              (d['first_name'] as String?)?.trim() ??
              '';
          lastName = (d['lastName'] as String?)?.trim() ??
              (d['surname'] as String?)?.trim() ??
              (d['last_name'] as String?)?.trim() ??
              '';
          fullName = (d['fullName'] as String?)?.trim() ??
              (d['displayName'] as String?)?.trim() ??
              '';
          phone = (d['phoneNumber'] as String?)?.trim() ??
              (d['phone'] as String?)?.trim() ??
              (d['cellNumber'] as String?)?.trim() ??
              (d['cell'] as String?)?.trim() ??
              '';
          email = (d['email'] as String?)?.trim() ?? '';
        }
      } catch (_) {
        // Offline / permissions / not-found -- fall back to snapshot.
      }
    }

    // Prefer the composed full name; fall back to the stored `fullName` and
    // finally to the booking-doc snapshot so the card never shows an empty
    // name when the profile exists but uses a different field convention.
    final composedFullName = _composeFullName(firstName, lastName, fullName);

    return HunterContact(
      hunterId: hunterId,
      firstName: firstName,
      lastName: lastName,
      fullName: composedFullName.isNotEmpty
          ? composedFullName
          : (snapshotName.isNotEmpty ? snapshotName : ''),
      phone: phone,
      email: email,
    );
  }

  /// Composes a display name from the first + last name fields, falling back
  /// to the stored `fullName` when the parts are absent.
  static String _composeFullName(
      String firstName, String lastName, String fullName) {
    final parts = [firstName, lastName].where((p) => p.isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(' ');
    return fullName;
  }
}

/// Immutable snapshot of a hunter's contact details resolved from a booking.
///
/// Every field defaults to an empty string; the `has*` getters report whether
/// a usable value is present so the UI can omit rows / show fallbacks cleanly.
class HunterContact {
  final String hunterId;
  final String firstName;
  final String lastName;
  final String fullName;
  final String phone;
  final String email;

  const HunterContact({
    this.hunterId = '',
    this.firstName = '',
    this.lastName = '',
    this.fullName = '',
    this.phone = '',
    this.email = '',
  });

  bool get hasFirstName => firstName.isNotEmpty;
  bool get hasLastName => lastName.isNotEmpty;
  bool get hasFullName => fullName.isNotEmpty;
  bool get hasPhone => phone.isNotEmpty;
  bool get hasEmail => email.isNotEmpty;

  /// Whether any contact field (phone or email) is present at all.
  bool get hasAnyContactDetail => hasPhone || hasEmail;

  /// Whether the mandatory profile fields (name + a contact detail) are
  /// present. Mirrors the [HunterProfileCompleteness] contract so the
  /// outfitter card's "contact unavailable" fallback only fires when the
  /// hunter genuinely has no contact info on file.
  bool get hasMandatoryProfile =>
      (hasFirstName || hasFullName) &&
      (hasLastName || (hasFullName && fullName.contains(' '))) &&
      hasAnyContactDetail;
}
