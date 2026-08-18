import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Resolves the contact details (name, phone, email) for the outfitter and the
/// farm manager associated with a marketplace package, so the Package Details
/// view can surface a "Contact the outfitter / farm manager" card with
/// tappable tel: / mailto: intents.
///
/// The package document carries `outfitterId` (+ optional `farmId`). The
/// outfitter profile lives in `outfitters/{outfitterId}` (`displayName`,
/// `email`, `phoneNumber`); a farm manager (when assigned) lives in
/// `farm_managers` scoped by `farmId` / `outfitterId` (`managerName`,
/// `managerEmail`, `managerCell` / `cellNr`). Both collections allow
/// `read: if isSignedIn()` per `firestore.rules`, so a signed-in hunter can
/// read them.
///
/// Resolution is best-effort + tolerant: a missing/outfitter doc, a missing
/// farm doc, a missing manager, or any field-level absence resolves to a
/// partially-populated [OutfitterContact] (fields default to empty strings +
/// `null` booleans) so the UI can render graceful fallbacks instead of
/// crashing. A Firestore fetch error (offline / permissions / `[core/no-app]`
/// during a cold-launch race) is caught and yields an empty contact.
class OutfitterContactResolver {
  OutfitterContactResolver._();
  static final OutfitterContactResolver instance = OutfitterContactResolver._();

  /// Injection seam so the resolver can be exercised against a
  /// `FakeFirebaseFirestore` without a live Firebase app (mirrors the
  /// `OpticLogService.forTesting` / `FeedbackFirebaseService` pattern).
  @visibleForTesting
  factory OutfitterContactResolver.forTesting(FirebaseFirestore firestore) {
    final r = OutfitterContactResolver._();
    r._firestoreOverride = firestore;
    return r;
  }

  /// Lazily resolved so constructing the singleton (or a test instance) before
  /// `Firebase.initializeApp()` (cold-launch race / widget test) does not throw
  /// `[core/no-app]`.
  FirebaseFirestore? _firestoreOverride;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  /// Resolves the contact details for the outfitter (+ farm manager when one
  /// is assigned to the package's farm).
  ///
  /// [packageData] is the raw `packages/{packageId}` document map. Only
  /// `outfitterId` is required; `farmId` is optional (a package may be
  /// published without a bound farm).
  Future<OutfitterContact> resolve(Map<String, dynamic> packageData) async {
    final outfitterId = (packageData['outfitterId'] as String?)?.trim() ?? '';
    final farmId = (packageData['farmId'] as String?)?.trim() ?? '';

    String outfitterName = '';
    String outfitterEmail = '';
    String outfitterPhone = '';

    // 1. Outfitter profile.
    if (outfitterId.isNotEmpty) {
      try {
        final snap =
            await _firestore.collection('outfitters').doc(outfitterId).get();
        if (snap.exists) {
          final d = snap.data() ?? const <String, dynamic>{};
          outfitterName = (d['displayName'] as String?)?.trim() ??
              (d['businessName'] as String?)?.trim() ??
              (d['name'] as String?)?.trim() ??
              '';
          outfitterEmail = (d['email'] as String?)?.trim() ?? '';
          outfitterPhone = (d['phoneNumber'] as String?)?.trim() ??
              (d['phone'] as String?)?.trim() ??
              (d['cellNumber'] as String?)?.trim() ??
              '';
        }
      } catch (_) {
        // Offline / permissions / not-found -- fall back to empty.
      }
    }

    // 2. Farm manager (when a farm is bound). A farm may have multiple
    //    managers; the first active one is used as the primary contact.
    String managerName = '';
    String managerEmail = '';
    String managerPhone = '';

    if (farmId.isNotEmpty) {
      try {
        final qs = await _firestore
            .collection('farm_managers')
            .where('farmId', isEqualTo: farmId)
            .limit(1)
            .get();
        if (qs.docs.isNotEmpty) {
          final d = qs.docs.first.data();
          managerName = (d['managerName'] as String?)?.trim() ??
              (d['name'] as String?)?.trim() ??
              '';
          managerEmail = (d['managerEmail'] as String?)?.trim() ??
              (d['email'] as String?)?.trim() ??
              '';
          managerPhone = (d['managerCell'] as String?)?.trim() ??
              (d['cellNr'] as String?)?.trim() ??
              (d['phone'] as String?)?.trim() ??
              '';
        }
      } catch (_) {
        // Offline / permissions / not-found -- fall back to empty.
      }
    }

    return OutfitterContact(
      outfitterName: outfitterName,
      outfitterEmail: outfitterEmail,
      outfitterPhone: outfitterPhone,
      managerName: managerName,
      managerEmail: managerEmail,
      managerPhone: managerPhone,
    );
  }
}

/// Immutable snapshot of the contact details resolved for a package.
///
/// Every field defaults to an empty string; the `has*` getters report whether a
/// usable value is present so the UI can omit rows / show fallbacks cleanly.
class OutfitterContact {
  final String outfitterName;
  final String outfitterEmail;
  final String outfitterPhone;

  final String managerName;
  final String managerEmail;
  final String managerPhone;

  const OutfitterContact({
    this.outfitterName = '',
    this.outfitterEmail = '',
    this.outfitterPhone = '',
    this.managerName = '',
    this.managerEmail = '',
    this.managerPhone = '',
  });

  bool get hasOutfitterName => outfitterName.isNotEmpty;
  bool get hasOutfitterEmail => outfitterEmail.isNotEmpty;
  bool get hasOutfitterPhone => outfitterPhone.isNotEmpty;

  bool get hasManagerName => managerName.isNotEmpty;
  bool get hasManagerEmail => managerEmail.isNotEmpty;
  bool get hasManagerPhone => managerPhone.isNotEmpty;

  /// Whether any manager contact field is present at all.
  bool get hasAnyManager =>
      hasManagerName || hasManagerEmail || hasManagerPhone;

  /// Whether any contact field is present at all (outfitter OR manager).
  bool get hasAnyContact =>
      hasOutfitterName ||
      hasOutfitterEmail ||
      hasOutfitterPhone ||
      hasAnyManager;

  /// The primary display name for the contact card: the farm manager when one
  /// is assigned, else the outfitter.
  String get primaryContactName =>
      managerName.isNotEmpty ? managerName : outfitterName;

  /// The primary phone for the contact card's tel: intent.
  String get primaryPhone =>
      managerPhone.isNotEmpty ? managerPhone : outfitterPhone;

  /// The primary email for the contact card's mailto: intent.
  String get primaryEmail =>
      managerEmail.isNotEmpty ? managerEmail : outfitterEmail;

  /// The role label for the primary contact ("Farm Manager" / "Outfitter").
  String get primaryContactRole =>
      managerName.isNotEmpty ? 'Farm Manager' : 'Outfitter';
}
