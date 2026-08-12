import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/venison_transport_permit.dart';

/// VenisonPermitManager — central engine for the legal South African Venison /
/// Game Transport & Hunt Permit.
///
/// Owns the full issue lifecycle:
/// 1. Write the permit document to `venison_permits` (with placeholder sig URLs)
///    so we obtain a stable `{permitId}`.
/// 2. Upload both signature PNGs to Firebase Storage under
///    `permit_signatures/{permitId}/hunter_signature.png` and
///    `permit_signatures/{permitId}/outfitter_signature.png`.
/// 3. Patch the document with the real download URLs + signed timestamps.
///
/// Both Hunters and Outfitters may issue permits; read access is governed by the
/// Firestore rules (`hunterId` OR `outfitterId` party).
class VenisonPermitManager {
  static final VenisonPermitManager _instance = VenisonPermitManager._internal();
  static VenisonPermitManager get instance => _instance;

  VenisonPermitManager._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Issues a new venison transport permit. Both signature PNGs are optional —
  /// a permit can be saved unsigned and countersigned later, but a fully legal
  /// permit requires both signatures.
  ///
  /// Returns the new permit document ID.
  Future<String> issueVenisonPermit({
    required VenisonTransportPermit permit,
    Uint8List? hunterSignatureBytes,
    Uint8List? outfitterSignatureBytes,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User must be authenticated to issue a permit');
    }

    // 1. Create the document first to obtain a stable permitId.
    final baseData = {
      ...permit.toMap(),
      'outfitterId': permit.outfitterId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final docRef = await _firestore.collection('venison_permits').add(baseData);
    final permitId = docRef.id;

    String? hunterSignatureUrl;
    String? outfitterSignatureUrl;

    // 2. Upload signatures (if provided) to permit_signatures/{permitId}/.
    if (hunterSignatureBytes != null) {
      hunterSignatureUrl = await _uploadSignature(
        permitId: permitId,
        role: 'hunter',
        bytes: hunterSignatureBytes,
      );
    }
    if (outfitterSignatureBytes != null) {
      outfitterSignatureUrl = await _uploadSignature(
        permitId: permitId,
        role: 'outfitter',
        bytes: outfitterSignatureBytes,
      );
    }

    // 3. Patch the document with signature URLs + signed timestamps.
    await docRef.update({
      if (hunterSignatureUrl != null) 'hunterSignatureUrl': hunterSignatureUrl,
      if (outfitterSignatureUrl != null)
        'outfitterSignatureUrl': outfitterSignatureUrl,
      if (hunterSignatureBytes != null)
        'hunterSignedDate': FieldValue.serverTimestamp(),
      if (outfitterSignatureBytes != null)
        'outfitterSignedDate': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return permitId;
  }

  /// Uploads a single signature PNG and returns its download URL.
  Future<String> _uploadSignature({
    required String permitId,
    required String role,
    required Uint8List bytes,
  }) async {
    final ref = _storage.ref().child(
      'permit_signatures/$permitId/${role}_signature.png',
    );
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/png'),
    );
    return task.ref.getDownloadURL();
  }

  /// Generates a unique permit number in the JagSpoor venison-permit format.
  String generatePermitNumber() {
    final now = DateTime.now();
    final year = now.year.toString();
    final random = now.millisecondsSinceEpoch.toString().substring(6);
    return 'JSV-$year-$random';
  }

  /// Reactive stream of permits for the authenticated user.
  ///
  /// Outfitters see permits they issued (`outfitterId`); hunters see permits
  /// issued to them (`hunterId`). Resolved via [UserRoleResolver] upstream —
  /// here we simply query both fields against the current uid and merge.
  Stream<List<VenisonTransportPermit>> getMyPermitsStream({
    required bool isOutfitter,
  }) async* {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      yield [];
      return;
    }

    final field = isOutfitter ? 'outfitterId' : 'hunterId';
    yield* _firestore
        .collection('venison_permits')
        .where(field, isEqualTo: currentUser.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['id'] = doc.id;
              return VenisonTransportPermit.fromMap(data);
            }).toList());
  }

  /// Fetch a single permit by ID.
  Future<VenisonTransportPermit?> getPermitById(String permitId) async {
    final doc =
        await _firestore.collection('venison_permits').doc(permitId).get();
    if (!doc.exists) return null;
    final data = Map<String, dynamic>.from(doc.data()!);
    data['id'] = doc.id;
    return VenisonTransportPermit.fromMap(data);
  }

  /// Update permit status (e.g. 'Issued' → 'Voided' / 'Completed').
  Future<void> updatePermitStatus({
    required String permitId,
    required String newStatus,
  }) async {
    await _firestore.collection('venison_permits').doc(permitId).update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete a permit and its stored signatures.
  Future<void> deletePermit(String permitId) async {
    // Best-effort cleanup of signature storage.
    try {
      final folder = _storage.ref().child('permit_signatures/$permitId');
      final items = await folder.listAll();
      for (final item in items.items) {
        await item.delete();
      }
    } catch (_) {
      // Non-fatal — the Firestore doc is the source of truth.
    }
    await _firestore.collection('venison_permits').doc(permitId).delete();
  }

  /// Pre-fills permit fields from a booking + the linked user/outfitter docs.
  ///
  /// Returns a partial map of field hints that the form can apply. Used when a
  /// permit is opened in the context of an active booking.
  Future<Map<String, dynamic>> prefillFromBooking(String bookingId) async {
    final result = <String, dynamic>{};

    final bookingDoc =
        await _firestore.collection('bookings').doc(bookingId).get();
    if (!bookingDoc.exists) return result;
    final booking = bookingDoc.data()!;

    final outfitterId = booking['outfitterId'] as String?;
    final hunterId = booking['hunterId'] as String?;
    final packageName = booking['packageName'] as String?;

    result
      ..['bookingId'] = bookingId
      ..['outfitterId'] = outfitterId ?? ''
      ..['hunterId'] = hunterId ?? '';

    // Outfitter / farm details.
    if (outfitterId != null) {
      final outfitterDoc =
          await _firestore.collection('outfitters').doc(outfitterId).get();
      if (outfitterDoc.exists) {
        final o = outfitterDoc.data()!;
        result['authorizedPersonName'] = o['contactName'] ?? o['name'] ?? '';
        result['farmName'] = o['farmName'] ?? o['businessName'] ?? '';
        result['farmAddress'] = o['address'] ?? o['farmAddress'] ?? '';
        result['farmCell'] = o['cellNumber'] ?? o['phone'] ?? '';
      }
    }

    // Hunter details.
    if (hunterId != null) {
      final userDoc = await _firestore.collection('users').doc(hunterId).get();
      if (userDoc.exists) {
        final u = userDoc.data()!;
        result['hunterName'] = u['fullName'] ?? u['name'] ?? '';
        result['hunterCell'] = u['phoneNumber'] ?? u['cellNumber'] ?? '';
        result['hunterAddress'] = u['address'] ?? '';
        result['hunterIdNumber'] = u['idNumber'] ?? '';
      }
    }

    if (packageName != null) result['packageName'] = packageName;
    return result;
  }
}
