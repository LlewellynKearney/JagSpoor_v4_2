import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../auth/services/password_reset_action_code_settings.dart';

/// Outcome of a single account-provisioning attempt.
class ProvisionResult {
  final String email;
  final String fullName;
  final String role;
  final bool success;
  final String? uid;
  final String? error;
  final bool resetEmailSent;

  const ProvisionResult({
    required this.email,
    required this.fullName,
    required this.role,
    required this.success,
    this.uid,
    this.error,
    this.resetEmailSent = false,
  });
}

/// Creates user accounts on behalf of users from the admin portal.
///
/// Because the client Firebase Auth SDK cannot create Auth users for *other*
/// people without logging the current admin out, provisioning follows the
/// prompt's specified flow:
///
///   1. Create the user document in Firestore (`users/{uid}` for hunters,
///      `outfitters/{uid}` for outfitters) with a generated uid.
///   2. Trigger a password reset / account setup email via
///      `sendPasswordResetEmail`, which lets the new user set their own
///      password and complete Auth account setup.
///
/// For outfitters, the firestore.rules allow the `/outfitters/{uid}` document
/// to be created only by an admin (`allow create: if isAdmin()`), so this
/// service relies on the caller carrying the admin custom claim.
class UserManagementService {
  UserManagementService._();
  static final UserManagementService instance = UserManagementService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Provisions a single user account (Firestore document + password reset
  /// email). Returns a [ProvisionResult] describing the outcome.
  Future<ProvisionResult> provisionUser({
    required String fullName,
    required String email,
    required String role,
    String? phoneNumber,
    Map<String, dynamic>? optionalDetails,
  }) async {
    final cleanedEmail = email.trim().toLowerCase();
    final cleanedName = fullName.trim();
    final normalizedRole = role.trim().toLowerCase();

    if (cleanedEmail.isEmpty || cleanedName.isEmpty) {
      return ProvisionResult(
        email: cleanedEmail,
        fullName: cleanedName,
        role: normalizedRole,
        success: false,
        error: 'Full name and email are required.',
      );
    }

    if (normalizedRole != 'hunter' && normalizedRole != 'outfitter') {
      return ProvisionResult(
        email: cleanedEmail,
        fullName: cleanedName,
        role: normalizedRole,
        success: false,
        error: 'Role must be "hunter" or "outfitter".',
      );
    }

    final collectionName =
        normalizedRole == 'outfitter' ? 'outfitters' : 'users';
    final ownerField = normalizedRole == 'outfitter' ? 'outfitterId' : 'ownerId';

    // 1. Create the Firestore document with a generated uid.
    final docRef = _db.collection(collectionName).doc();
    final uid = docRef.id;
    final now = FieldValue.serverTimestamp();

    final data = <String, dynamic>{
      'uid': uid,
      'email': cleanedEmail,
      'displayName': cleanedName,
      'role': normalizedRole,
      ownerField: uid,
      if (phoneNumber != null && phoneNumber.trim().isNotEmpty)
        'phoneNumber': phoneNumber.trim(),
      'accountSetupComplete': false,
      'createdAt': now,
      'updatedAt': now,
      'createdBy': _auth.currentUser?.uid,
      if (optionalDetails != null && optionalDetails.isNotEmpty)
        'details': optionalDetails,
    };

    try {
      await docRef.set(data);
    } catch (e) {
      return ProvisionResult(
        email: cleanedEmail,
        fullName: cleanedName,
        role: normalizedRole,
        success: false,
        error: 'Failed to create Firestore document: $e',
      );
    }

    // 2. Trigger the password reset / account setup email.
    bool resetSent = false;
    try {
      await _auth.sendPasswordResetEmail(
        email: cleanedEmail,
        actionCodeSettings: PasswordResetActionCodeSettings.build(),
      );
      resetSent = true;
    } catch (e) {
      // The Auth account may not exist yet, so the reset email can fail. The
      // Firestore document is still created; we report the reset failure but
      // treat the provisioning as successful (the admin can resend later or
      // provision the Auth account via a Cloud Function).
      return ProvisionResult(
        email: cleanedEmail,
        fullName: cleanedName,
        role: normalizedRole,
        success: true,
        uid: uid,
        resetEmailSent: false,
        error: 'Firestore doc created, but password reset email failed: $e',
      );
    }

    return ProvisionResult(
      email: cleanedEmail,
      fullName: cleanedName,
      role: normalizedRole,
      success: true,
      uid: uid,
      resetEmailSent: resetSent,
    );
  }
}
