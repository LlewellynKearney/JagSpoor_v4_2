import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../models/package_pricing.dart';
import 'deposit_payment_simulator.dart';

class PackageBookingManager {
  static final PackageBookingManager _instance =
      PackageBookingManager._internal();
  static PackageBookingManager get instance => _instance;

  PackageBookingManager._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get _currentUser => _auth.currentUser;
  String? get _currentUserId => _currentUser?.uid;

  /// Platform commission rate (7.5%).
  ///
  /// Applied to the outfitter's base price; the hunter pays
  /// `basePrice + (basePrice * 0.075)`.
  static const double platformCommissionRate = 0.075;

  /// Non-refundable deposit fraction charged to the hunter once the outfitter
  /// approves a booking request.
  static const double depositFraction = 0.25;

  // ==========================================
  // OUTFITTER - PUBLISH PACKAGE
  // ==========================================
  /// Publishes (or saves as draft) a new hunting package to the marketplace.
  ///
  /// Parameters:
  /// - [title]: Package title/name
  /// - [description]: Detailed description of the package
  /// - [pricing]: Full pricing definition (all-inclusive or itemized), which
  ///   resolves the outfitter base price, the line-item/species breakdown, and
  ///   the availability window. See [PackagePricing].
  /// - [inclusions]: List of what's included (e.g., ["Transport", "Accommodation", "Meals"])
  /// - [farmId]: Optional farm/concession ID to bind the package to
  /// - [status]: Lifecycle status (defaults to [PackageStatus.active] so the
  ///   package is immediately listed; pass [PackageStatus.draft] to save an
  ///   unlisted work-in-progress).
  /// - [imageUrls]: Download URLs of uploaded package gallery images.
  /// - [depositPercentage]: Per-package non-refundable deposit percentage
  ///   (0–100, default 25). Stored as the fractional [depositFraction].
  ///
  /// Commission Calculation (7.5%):
  /// - `basePriceRands` = resolved base price from [pricing]
  /// - `platformCommissionZAR` = basePriceRands × 0.075
  /// - `totalPriceZAR` = basePriceRands + platformCommissionZAR
  ///
  /// Returns: void (saves to Firestore 'packages' collection)
  ///
  /// Throws: Exception if user is not authenticated or save fails
  Future<String> publishPackage({
    required String title,
    required String description,
    required PackagePricing pricing,
    required List<String> inclusions,
    String? farmId,
    PackageStatus status = PackageStatus.active,
    List<String> imageUrls = const [],
    double depositPercentage = 25,
    int quantityAvailable = PackageQuantity.defaultQuantity,
  }) async {
    // Validate authentication
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to publish a package');
    }

    // Validate inputs
    if (title.trim().isEmpty) {
      throw Exception('Package title cannot be empty');
    }
    if (description.trim().isEmpty) {
      throw Exception('Package description cannot be empty');
    }

    final basePriceRands = pricing.basePrice;
    if (basePriceRands <= 0) {
      throw Exception('Base price must be greater than zero');
    }

    if (pricing.availabilityStart != null &&
        pricing.availabilityEnd != null &&
        pricing.availabilityEnd!.isBefore(pricing.availabilityStart!)) {
      throw Exception(
          'Availability end date cannot be before the start date');
    }

    // Per-package deposit percentage, clamped to [0, 100].
    final clampedDeposit = depositPercentage.clamp(0, 100);

    // Bookable slot count, clamped to >= 1. A package must offer at least one
    // slot to be bookable.
    final clampedQty = quantityAvailable < 1 ? 1 : quantityAvailable;

    // Calculate commission metrics (7.5%)
    final double fee = basePriceRands * platformCommissionRate;
    final double total = basePriceRands + fee;

    final packageData = {
      'outfitterId': _currentUserId,
      'title': title.trim(),
      'description': description.trim(),
      'basePriceRands': basePriceRands,
      'platformCommissionZAR': fee,
      'totalPriceZAR': total,
      'platformCommissionRate': platformCommissionRate,
      'inclusions': inclusions,
      'farmId': farmId,
      'imageUrls': imageUrls,
      'depositPercentage': clampedDeposit,
      'depositFraction': clampedDeposit / 100,
      'quantityAvailable': clampedQty,
      ...pricing.toMap(),
      'status': status.label,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final docRef =
        await _firestore.collection('packages').add(packageData);
    return docRef.id;
  }

  /// Updates an existing package owned by the current outfitter.
  ///
  /// Any of the optional fields, when non-null, replace the stored value. The
  /// 7.5% commission split is recomputed whenever [pricing] (and thus the base
  /// price) changes. Status is left untouched here — use [setPackageStatus]
  /// for lifecycle transitions.
  ///
  /// Throws: Exception if not authenticated or the update fails.
  Future<void> updatePackage({
    required String packageId,
    String? title,
    String? description,
    PackagePricing? pricing,
    List<String>? inclusions,
    String? farmId,
    List<String>? imageUrls,
    double? depositPercentage,
    int? quantityAvailable,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to update a package');
    }

    final update = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (title != null) update['title'] = title.trim();
    if (description != null) update['description'] = description.trim();
    if (inclusions != null) update['inclusions'] = inclusions;
    if (farmId != null) update['farmId'] = farmId;
    if (imageUrls != null) update['imageUrls'] = imageUrls;
    if (depositPercentage != null) {
      final clamped = depositPercentage.clamp(0, 100);
      update['depositPercentage'] = clamped;
      update['depositFraction'] = clamped / 100;
    }
    if (quantityAvailable != null) {
      // Clamp to >= 1; the outfitter may restock a sold-out package by
      // raising the count back above 0 (the sold-out → active transition is
      // applied via setPackageStatus when restocking).
      update['quantityAvailable'] =
          quantityAvailable < 1 ? 1 : quantityAvailable;
    }

    if (pricing != null) {
      final basePriceRands = pricing.basePrice;
      if (basePriceRands <= 0) {
        throw Exception('Base price must be greater than zero');
      }
      if (pricing.availabilityStart != null &&
          pricing.availabilityEnd != null &&
          pricing.availabilityEnd!.isBefore(pricing.availabilityStart!)) {
        throw Exception(
            'Availability end date cannot be before the start date');
      }
      final double fee = basePriceRands * platformCommissionRate;
      final double total = basePriceRands + fee;
      update
        ..addAll({
          'basePriceRands': basePriceRands,
          'platformCommissionZAR': fee,
          'totalPriceZAR': total,
          'platformCommissionRate': platformCommissionRate,
        })
        ..addAll(pricing.toMap());
    }

    await _firestore.collection('packages').doc(packageId).update(update);
  }

  /// Transitions a package to a new lifecycle [status] (active / draft /
  /// archived / deleted). Soft-deletes set [PackageStatus.deleted] rather than
  /// removing the document, preserving booking references and audit history.
  ///
  /// Throws: Exception if not authenticated or the update fails.
  Future<void> setPackageStatus({
    required String packageId,
    required PackageStatus status,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to change package status');
    }

    await _firestore.collection('packages').doc(packageId).update({
      'status': status.label,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==========================================
  // HUNTER - BOOK PACKAGE WITH 7.5% COMMISSION
  // ==========================================
  /// Books a hunting package with automatic 7.5% platform commission
  /// calculation.
  ///
  /// Executes as an **atomic Firestore transaction**: it reads the package,
  /// verifies at least one slot remains (`quantityAvailable > 0`), creates the
  /// booking, and decrements `quantityAvailable` by 1. If the count reaches 0
  /// the package status is flipped to [PackageStatus.soldOut] so it can no
  /// longer be booked. This is race-safe — concurrent booking attempts are
  /// serialized by the transaction, and a hunter that hits a 0-slot package has
  /// its booking cancelled with a clear "Package Sold Out" error.
  ///
  /// Parameters:
  /// - [packageId]: Firestore document ID of the package being booked
  /// - [outfitterId]: UID of the outfitter who owns the package
  /// - [basePriceRands]: Base price of the package in Rand
  /// - [packageName]: Optional package title snapshot (for booking display)
  ///
  /// Commission Calculation (7.5%):
  /// - Commission Fee = basePriceRands × 0.075 (7.5%)
  /// - Total Hunter Price = basePriceRands + commissionFee
  ///
  /// Returns: void (saves to Firestore 'bookings' collection + updates package)
  ///
  /// Throws:
  /// - Exception if user is not authenticated.
  /// - `PackageSoldOutException` if the package has no remaining slots.
  /// - Exception if the package is missing or the save fails.
  Future<void> bookPackage({
    required String packageId,
    required String outfitterId,
    required double basePriceRands,
    String? packageName,
  }) async {
    // Validate authentication
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to book a package');
    }

    // Prevent outfitter from booking their own package
    if (_currentUserId == outfitterId) {
      throw Exception('Outfitters cannot book their own packages');
    }

    // Validate inputs
    if (packageId.trim().isEmpty) {
      throw Exception('Package ID cannot be empty');
    }
    if (basePriceRands <= 0) {
      throw Exception('Base price must be greater than zero');
    }

    // Calculate platform split metrics (7.5% commission)
    final double commissionFee = basePriceRands * platformCommissionRate;
    final double totalHunterPrice = basePriceRands + commissionFee;

    final packageRef = _firestore.collection('packages').doc(packageId.trim());

    // Atomic booking + inventory decrement. The transaction guarantees that
    // the slot-count check and the decrement are consistent under concurrent
    // bookings — two hunters cannot both grab the last slot.
    await _firestore.runTransaction((transaction) async {
      final packageSnap = await transaction.get(packageRef);

      if (!packageSnap.exists) {
        throw Exception('Package not found');
      }

      final pkgData = packageSnap.data() as Map<String, dynamic>;
      final currentQty =
          PackageQuantity.fromData(pkgData['quantityAvailable']);
      final currentStatus =
          PackageStatus.fromString(pkgData['status'] as String?);

      // Reject the booking if no slots remain or the package is already sold
      // out / not actively listed (draft, archived, deleted).
      if (currentStatus != PackageStatus.active ||
          currentQty <= 0) {
        throw PackageSoldOutException(packageId: packageId);
      }

      // Create the booking inside the same transaction.
      final bookingRef = _firestore.collection('bookings').doc();
      transaction.set(bookingRef, {
        'packageId': packageId.trim(),
        'outfitterId': outfitterId.trim(),
        'hunterId': _currentUserId,
        if (packageName != null) 'packageName': packageName,
        'basePriceRands': basePriceRands,
        'platformCommissionRands': commissionFee,
        'platformCommissionRate': platformCommissionRate,
        'totalHunterPriceRands': totalHunterPrice,
        'depositFraction': depositFraction,
        'depositAmountRands': totalHunterPrice * depositFraction,
        'balanceAmountRands': totalHunterPrice * (1 - depositFraction),
        'status': 'Pending Approval',
        'bookingTimestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Decrement the slot count. When the last slot is claimed, flip the
      // status to sold_out so the listing becomes read-only in the UI.
      final newQty = currentQty - 1;
      final newStatus = newQty <= 0
          ? PackageStatus.soldOut.label
          : currentStatus.label;
      transaction.update(packageRef, {
        'quantityAvailable': newQty,
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Restocks a sold-out / low-stock package by setting [quantityAvailable]
  /// and (optionally) re-activating the listing. Only the owning outfitter may
  /// call this. Pass [reactivate] (default true) to flip a `sold_out` package
  /// back to `active` once slots are available again.
  Future<void> restockPackage({
    required String packageId,
    required int quantityAvailable,
    bool reactivate = true,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to restock a package');
    }
    if (quantityAvailable < 1) {
      throw Exception('Restock quantity must be at least 1');
    }

    final packageRef = _firestore.collection('packages').doc(packageId);
    final snap = await packageRef.get();
    if (!snap.exists) {
      throw Exception('Package not found');
    }
    final data = snap.data() as Map<String, dynamic>;
    final currentStatus =
        PackageStatus.fromString(data['status'] as String?);

    final update = <String, dynamic>{
      'quantityAvailable': quantityAvailable,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    // Only re-activate if the package is currently sold out; never override an
    // archived/deleted/draft lifecycle choice from a restock.
    if (reactivate && currentStatus == PackageStatus.soldOut) {
      update['status'] = PackageStatus.active.label;
    }

    await packageRef.update(update);
  }

  // ==========================================
  // UTILITY METHODS
  // ==========================================

  /// Calculate commission, totals, and deposit split without saving.
  /// Returns a map with the full commission + deposit breakdown.
  Map<String, double> calculateCommission(double basePriceRands) {
    final double commissionFee = basePriceRands * platformCommissionRate;
    final double totalPrice = basePriceRands + commissionFee;
    final double depositAmount = totalPrice * depositFraction;

    return {
      'basePriceRands': basePriceRands,
      'commissionFee': commissionFee,
      'totalHunterPriceRands': totalPrice,
      'depositAmountRands': depositAmount,
      'balanceAmountRands': totalPrice - depositAmount,
    };
  }

  /// Get all packages (for marketplace browsing). Includes `active` and
  /// `sold_out` so sold-out listings render read-only in the marketplace.
  Future<QuerySnapshot> getAllPackages() async {
    return await _firestore
        .collection('packages')
        .where('status', whereIn: ['active', 'sold_out'])
        .orderBy('createdAt', descending: true)
        .get();
  }

  /// Get packages published by the current outfitter (all statuses except
  /// soft-deleted). Use [getMyPackagesStream] for a reactive management UI.
  Future<QuerySnapshot> getMyPackages() async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    return await _firestore
        .collection('packages')
        .where('outfitterId', isEqualTo: _currentUserId)
        .orderBy('createdAt', descending: true)
        .get();
  }

  /// Reactive stream of packages published by the current outfitter, scoped to
  /// a lifecycle [status] filter (defaults to all non-deleted packages). Powers
  /// the "My Packages" management screen. With offline persistence enabled the
  /// stream serves cached packages when the network drops; a hard error (e.g.
  /// missing composite index) is surfaced to the consumer's `snapshot.hasError`
  /// branch rather than thrown synchronously.
  Stream<QuerySnapshot> getMyPackagesStream({
    PackageStatus? status,
  }) {
    if (_currentUserId == null) {
      // Unauthenticated callers get a stable empty stream instead of a thrown
      // exception that would crash the screen's StreamBuilder.
      return const Stream.empty();
    }

    var query = _firestore
        .collection('packages')
        .where('outfitterId', isEqualTo: _currentUserId);

    if (status != null) {
      query = query.where('status', isEqualTo: status.label);
    }

    return query.orderBy('createdAt', descending: true).snapshots();
  }

  /// Get bookings for the current user (as hunter or outfitter)
  Future<QuerySnapshot> getMyBookings() async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    return await _firestore
        .collection('bookings')
        .where('hunterId', isEqualTo: _currentUserId)
        .get();
  }

  /// Get bookings received by the current outfitter
  Future<QuerySnapshot> getBookingsForMyPackages() async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    return await _firestore
        .collection('bookings')
        .where('outfitterId', isEqualTo: _currentUserId)
        .get();
  }

  /// Update booking status (for outfitters).
  ///
  /// When an outfitter approves a booking, the status transitions to
  /// `Pending Deposit`, which prompts the hunter to pay the 25%
  /// non-refundable deposit. Once the deposit is paid (PayFast ITN), the
  /// status flips to `Paid`.
  Future<void> updateBookingStatus({
    required String bookingId,
    required String newStatus,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    // Valid statuses. `Pending Deposit` is the post-approval state that
    // prompts the hunter for the 25% non-refundable deposit.
    const validStatuses = [
      'Pending Approval',
      'Approved',
      'Pending Deposit',
      'Paid',
      'Declined',
      'Completed',
      'Cancelled',
    ];

    if (!validStatuses.contains(newStatus)) {
      throw Exception('Invalid booking status: $newStatus');
    }

    await _firestore.collection('bookings').doc(bookingId).update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks a booking as approved and transitions it to the deposit-pending
  /// state so the hunter is prompted to pay the 25% non-refundable deposit.
  ///
  /// Stores the computed deposit/balance amounts on the booking so the hunter
  /// PayFast checkout charges exactly the deposit.
  Future<void> approveBookingAndRequestDeposit({
    required String bookingId,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    final snap = await bookingRef.get();
    if (!snap.exists) {
      throw Exception('Booking not found');
    }

    final data = snap.data() as Map<String, dynamic>;
    final basePrice = (data['basePriceRands'] as num?)?.toDouble() ?? 0.0;
    final commissionFee = basePrice * platformCommissionRate;
    final totalPrice = basePrice + commissionFee;
    final depositAmount = totalPrice * depositFraction;

    await bookingRef.update({
      'status': 'Pending Deposit',
      'platformCommissionRate': platformCommissionRate,
      'platformCommissionRands': commissionFee,
      'totalHunterPriceRands': totalPrice,
      'depositFraction': depositFraction,
      'depositAmountRands': depositAmount,
      'balanceAmountRands': totalPrice - depositAmount,
      'approvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==========================================
  // DEBUG PAYMENT SIMULATOR (kDebugMode only)
  // ==========================================
  /// **Debug-only** simulator that flips a booking's status directly to `Paid`
  /// and stamps `depositPaidAt`, mirroring the state the deployed PayFast ITN
  /// handler writes when a `payment_status==COMPLETE` ITN is reconciled.
  ///
  /// Gated behind `kDebugMode` (stripped from release builds) so it can never
  /// ship. The pure decision logic lives in `DepositPaymentSimulator`; this
  /// method appends the server-timestamp fields (which require
  /// `FieldValue.serverTimestamp()` and so are not pure) and performs the
  /// Firestore write.
  ///
  /// **Production security note**: the `bookings` Firestore rule only permits
  /// the outfitter (or the Admin-SDK-backed ITN Cloud Function, which bypasses
  /// rules entirely) to flip the `status` field. A hunter-triggered debug
  /// write that flips `status` to `Paid` is therefore permission-denied under
  /// the production rules. Use as the outfitter/admin sandbox tester or in a
  /// locally-relaxed rules env. (v4.5 to-do Item #10.)
  Future<void> simulateDepositPaid({required String bookingId}) async {
    assert(kDebugMode,
        'DepositPaymentSimulator is a debug-only feature and must not run in release builds.');
    if (!kDebugMode) {
      throw StateError(
          'DepositPaymentSimulator is disabled outside debug mode.');
    }
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    final update = <String, dynamic>{
      ...DepositPaymentSimulator.simulateUpdateMap(),
      DepositPaymentSimulator.depositPaidAtField:
          FieldValue.serverTimestamp(),
      'paymentTimestamp': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _firestore.collection('bookings').doc(bookingId).update(update);
  }

  // ==========================================
  // DATE CHANGE REQUESTS
  // ==========================================

  /// Hunter raises a date-change request against a booking. Writes a pending
  /// request to the booking document under the `dateChangeRequest` map and
  /// flags `dateChangeRequestPending: true` for the outfitter dashboard.
  Future<void> requestDateChange({
    required String bookingId,
    required DateChangeRequest request,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to request a date change');
    }

    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    final snap = await bookingRef.get();
    if (!snap.exists) {
      throw Exception('Booking not found');
    }

    final data = snap.data() as Map<String, dynamic>;
    if (data['hunterId'] != _currentUserId) {
      throw Exception(
          'Only the hunter who placed this booking may request a date change');
    }

    await bookingRef.update({
      'dateChangeRequest': {
        ...request.toMap(),
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      },
      'dateChangeRequestPending': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Outfitter resolves a pending date-change request. On approval the booking
  /// dates are updated to the requested dates; on either resolution the
  /// `dateChangeRequestPending` flag is cleared and the request status flips.
  Future<void> resolveDateChange({
    required String bookingId,
    required bool approved,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to resolve a date change');
    }

    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    final snap = await bookingRef.get();
    if (!snap.exists) {
      throw Exception('Booking not found');
    }

    final data = snap.data() as Map<String, dynamic>;
    if (data['outfitterId'] != _currentUserId) {
      throw Exception(
          'Only the outfitter who owns this booking may resolve a date change');
    }

    final existing =
        data['dateChangeRequest'] as Map<String, dynamic>? ?? {};
    final request = DateChangeRequest.fromMap(existing);

    final update = <String, dynamic>{
      'dateChangeRequestPending': false,
      'dateChangeRequest': {
        ...existing,
        'status': approved ? 'approved' : 'declined',
        'resolvedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (approved) {
      if (request.requestedStartDate != null) {
        update['confirmedStartDate'] =
            Timestamp.fromDate(request.requestedStartDate!);
      }
      if (request.requestedEndDate != null) {
        update['confirmedEndDate'] =
            Timestamp.fromDate(request.requestedEndDate!);
      }
    }

    await bookingRef.update(update);
  }

  /// Soft-deletes a package owned by the current outfitter by marking its
  /// status `deleted`. The document is retained so existing booking references
  /// and audit history remain intact; deleted packages never appear in the
  /// marketplace or the "My Packages" management list.
  ///
  /// Use [setPackageStatus] with [PackageStatus.active] to restore a package.
  ///
  /// Throws: Exception if not authenticated or the update fails.
  Future<void> deletePackage(String packageId) async {
    await setPackageStatus(
      packageId: packageId,
      status: PackageStatus.deleted,
    );
  }

  // ==========================================
  // AMMUNITION MANAGER - CALIBER MATCHING
  // ==========================================
  /// Stream or query factory ammunition inventory matching selected firearm caliber.
  /// Enforces structural caliber dimension filter constraints.
  Stream<QuerySnapshot> getFactoryAmmunitionByCaliber(String firearmCaliber) {
    return _firestore
        .collection('factory_ammunition')
        .where('caliber', isEqualTo: firearmCaliber)
        .snapshots();
  }

  /// Fetch snapshot of factory ammunition matching selected firearm caliber.
  Future<QuerySnapshot> fetchFactoryAmmunitionByCaliber(
    String firearmCaliber,
  ) async {
    return await _firestore
        .collection('factory_ammunition')
        .where('caliber', isEqualTo: firearmCaliber)
        .get();
  }
}
