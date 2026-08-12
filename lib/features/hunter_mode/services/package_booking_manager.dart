import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/package_pricing.dart';

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
  /// Publishes a new hunting package to the marketplace.
  ///
  /// Parameters:
  /// - [title]: Package title/name
  /// - [description]: Detailed description of the package
  /// - [pricing]: Full pricing definition (all-inclusive or itemized), which
  ///   resolves the outfitter base price, the line-item/species breakdown, and
  ///   the availability window. See [PackagePricing].
  /// - [inclusions]: List of what's included (e.g., ["Transport", "Accommodation", "Meals"])
  /// - [farmId]: Optional farm/concession ID to bind the package to
  ///
  /// Commission Calculation (7.5%):
  /// - `basePriceRands` = resolved base price from [pricing]
  /// - `platformCommissionZAR` = basePriceRands × 0.075
  /// - `totalPriceZAR` = basePriceRands + platformCommissionZAR
  ///
  /// Returns: void (saves to Firestore 'packages' collection)
  ///
  /// Throws: Exception if user is not authenticated or save fails
  Future<void> publishPackage({
    required String title,
    required String description,
    required PackagePricing pricing,
    required List<String> inclusions,
    String? farmId,
  }) async {
    // Validate authentication
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to publish a package');
    }

    // Validate inputs
    if (title.trim().isEmpty) {
      throw Exception('Package title cannot be empty');
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
      ...pricing.toMap(),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _firestore.collection('packages').add(packageData);
  }

  // ==========================================
  // HUNTER - BOOK PACKAGE WITH 7.5% COMMISSION
  // ==========================================
  /// Books a hunting package with automatic 7.5% platform commission
  /// calculation.
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
  /// Returns: void (saves to Firestore 'bookings' collection)
  ///
  /// Throws: Exception if user is not authenticated or save fails
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

    final bookingData = {
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
    };

    await _firestore.collection('bookings').add(bookingData);
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

  /// Get all packages (for marketplace browsing)
  Future<QuerySnapshot> getAllPackages() async {
    return await _firestore
        .collection('packages')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .get();
  }

  /// Get packages published by the current outfitter
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

  /// Delete a package (only by the owning outfitter)
  Future<void> deletePackage(String packageId) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    await _firestore.collection('packages').doc(packageId).update({
      'status': 'deleted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
