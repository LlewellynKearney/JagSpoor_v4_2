import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PackageBookingManager {
  static final PackageBookingManager _instance = PackageBookingManager._internal();
  static PackageBookingManager get instance => _instance;

  PackageBookingManager._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get _currentUser => _auth.currentUser;
  String? get _currentUserId => _currentUser?.uid;

  /// Platform commission rate (5%)
  static const double platformCommissionRate = 0.05;

  // ==========================================
  // OUTFITTER - PUBLISH PACKAGE
  // ==========================================
  /// Publishes a new hunting package to the marketplace.
  /// 
  /// Parameters:
  /// - [title]: Package title/name
  /// - [description]: Detailed description of the package
  /// - [basePriceRands]: Base price in South African Rand
  /// - [inclusions]: List of what's included (e.g., ["Transport", "Accommodation", "Meals"])
  /// - [farmId]: Optional farm/concession ID to bind the package to
  /// 
  /// Returns: void (saves to Firestore 'packages' collection)
  /// 
  /// Throws: Exception if user is not authenticated or save fails
  Future<void> publishPackage({
    required String title,
    required String description,
    required double basePriceRands,
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
    if (basePriceRands <= 0) {
      throw Exception('Base price must be greater than zero');
    }

    final packageData = {
      'outfitterId': _currentUserId,
      'title': title.trim(),
      'description': description.trim(),
      'basePriceRands': basePriceRands,
      'inclusions': inclusions,
      'farmId': farmId,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _firestore.collection('packages').add(packageData);
  }

  // ==========================================
  // HUNTER - BOOK PACKAGE WITH 5% COMMISSION
  // ==========================================
  /// Books a hunting package with automatic 5% platform commission calculation.
  /// 
  /// Parameters:
  /// - [packageId]: Firestore document ID of the package being booked
  /// - [outfitterId]: UID of the outfitter who owns the package
  /// - [basePriceRands]: Base price of the package in Rand
  /// 
  /// Commission Calculation:
  /// - Commission Fee = basePriceRands × 0.05 (5%)
  /// - Total Hunter Price = basePriceRands + commissionFee
  /// 
  /// Returns: void (saves to Firestore 'bookings' collection)
  /// 
  /// Throws: Exception if user is not authenticated or save fails
  Future<void> bookPackage({
    required String packageId,
    required String outfitterId,
    required double basePriceRands,
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

    // Calculate platform split metrics (5% commission)
    final double commissionFee = basePriceRands * platformCommissionRate;
    final double totalHunterPrice = basePriceRands + commissionFee;

    final bookingData = {
      'packageId': packageId.trim(),
      'outfitterId': outfitterId.trim(),
      'hunterId': _currentUserId,
      'basePriceRands': basePriceRands,
      'platformCommissionRands': commissionFee,
      'totalHunterPriceRands': totalHunterPrice,
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

  /// Calculate commission and totals without saving
  /// Returns a map with commission breakdown
  Map<String, double> calculateCommission(double basePriceRands) {
    final double commissionFee = basePriceRands * platformCommissionRate;
    final double totalPrice = basePriceRands + commissionFee;
    
    return {
      'basePriceRands': basePriceRands,
      'commissionFee': commissionFee,
      'totalHunterPriceRands': totalPrice,
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

  /// Update booking status (for outfitters)
  Future<void> updateBookingStatus({
    required String bookingId,
    required String newStatus,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    // Valid statuses
    const validStatuses = [
      'Pending Approval',
      'Approved',
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
}
