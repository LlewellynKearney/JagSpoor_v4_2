import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OutfitterEnterpriseManager {
  static final OutfitterEnterpriseManager _instance =
      OutfitterEnterpriseManager._internal();
  static OutfitterEnterpriseManager get instance => _instance;

  OutfitterEnterpriseManager._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get _currentUser => _auth.currentUser;
  String? get _currentUserId => _currentUser?.uid;

  // ==========================================
  // RECORD NEW FARM / CONCESSION LOCATION
  // ==========================================
  /// Creates a new farm/concession entry for the authenticated outfitter.
  ///
  /// Parameters:
  /// - [name]: Farm or concession name (e.g., "Kgalagadi Game Farm")
  /// - [district]: District or region name
  /// - [province]: Province (e.g., "Northern Cape")
  ///
  /// Returns: void (saves to Firestore 'farms' collection)
  ///
  /// Throws: Exception if user is not authenticated or save fails
  Future<void> addFarm({
    required String name,
    required String district,
    required String province,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to add a farm');
    }

    if (name.trim().isEmpty) {
      throw Exception('Farm name cannot be empty');
    }

    final farmData = {
      'outfitterId': _currentUserId,
      'name': name.trim(),
      'district': district.trim(),
      'province': province.trim(),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _firestore.collection('farms').add(farmData);
  }

  // ==========================================
  // UPDATE FARM / CONCESSION DETAILS
  // ==========================================
  /// Updates an existing farm/concession entry for the authenticated outfitter.
  ///
  /// Parameters:
  /// - [farmId]: Firestore document ID of the farm to update.
  /// - [name]: Farm or concession name.
  /// - [district]: District or region name.
  /// - [province]: Province.
  /// - [sizeHectares]: Optional farm size in hectares.
  /// - [contactNumber]: Optional contact phone number.
  /// - [registrationNumber]: Optional farm/concession registration number.
  ///
  /// Throws: Exception if user is not authenticated, [farmId] is empty, or the
  /// save fails. Only the outfitter that owns the farm should call this
  /// (enforced by `firestore.rules` `isOwnerOf('outfitterId')`).
  Future<void> updateFarm({
    required String farmId,
    required String name,
    required String district,
    required String province,
    double? sizeHectares,
    String? contactNumber,
    String? registrationNumber,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to update a farm');
    }
    if (farmId.trim().isEmpty) {
      throw Exception('Farm ID cannot be empty');
    }
    if (name.trim().isEmpty) {
      throw Exception('Farm name cannot be empty');
    }

    final updates = <String, dynamic>{
      'name': name.trim(),
      'district': district.trim(),
      'province': province.trim(),
      'sizeHectares': sizeHectares,
      'contactNumber': contactNumber?.trim(),
      'registrationNumber': registrationNumber?.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _firestore.collection('farms').doc(farmId).update(updates);
  }

  // ==========================================
  // ASSIGN MANAGER TO FARM
  // ==========================================
  /// Assigns a manager to a specific farm/concession.
  ///
  /// Parameters:
  /// - [farmId]: Firestore document ID of the farm
  /// - [managerEmail]: Email address of the manager
  /// - [managerName]: Full name of the manager
  /// - [managerCell]: Cell phone number of the manager
  ///
  /// Returns: void (saves to Firestore 'farm_managers' collection)
  ///
  /// Throws: Exception if user is not authenticated or save fails
  Future<void> assignManager({
    required String farmId,
    required String managerEmail,
    required String managerName,
    required String managerCell,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to assign a manager');
    }

    if (farmId.trim().isEmpty) {
      throw Exception('Farm ID cannot be empty');
    }
    if (managerEmail.trim().isEmpty) {
      throw Exception('Manager email cannot be empty');
    }
    if (managerName.trim().isEmpty) {
      throw Exception('Manager name cannot be empty');
    }
    if (managerCell.trim().isEmpty) {
      throw Exception('Manager cell number cannot be empty');
    }

    final managerData = {
      'farmId': farmId.trim(),
      'outfitterId': _currentUserId,
      'managerEmail': managerEmail.trim().toLowerCase(),
      'managerName': managerName.trim(),
      'managerCell': managerCell.trim(),
      'cellNr': managerCell.trim(),
      'status': 'Active',
      'assignedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _firestore.collection('farm_managers').add(managerData);
  }

  // ==========================================
  // UPLOAD AVAILABLE TROPHY STOCK BY FARM
  // ==========================================
  /// Syncs trophy species availability and pricing for a specific farm.
  ///
  /// Parameters:
  /// - [farmId]: Firestore document ID of the farm
  /// - [species]: Animal species name (e.g., "African Lion", "Cape Buffalo")
  /// - [availableCount]: Number of available trophy permits/quota
  /// - [pricePerTrophyRands]: Price per trophy in South African Rand
  /// - [trophyMeasurement]: Optional trophy length/size in inches (horn, tusk,
  ///   or skull measurement). Stored as both `trophyMeasurement` and
  ///   `trophyLengthInches` for read compatibility. Null/empty when omitted.
  /// - [trophyPhotoUrls]: Optional list of up to 3 photo download URLs for the
  ///   trophy animal. Stored as the `trophyPhotoUrls` array.
  ///
  /// Returns: void (saves to Firestore 'trophies' collection)
  ///
  /// Throws: Exception if user is not authenticated or save fails
  Future<void> syncTrophyStock({
    required String farmId,
    required String species,
    required int availableCount,
    required double pricePerTrophyRands,
    double? trophyMeasurement,
    List<String> trophyPhotoUrls = const [],
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to sync trophy stock');
    }

    if (farmId.trim().isEmpty) {
      throw Exception('Farm ID cannot be empty');
    }
    if (species.trim().isEmpty) {
      throw Exception('Species name cannot be empty');
    }
    if (availableCount < 0) {
      throw Exception('Available count cannot be negative');
    }
    if (pricePerTrophyRands < 0) {
      throw Exception('Price per trophy cannot be negative');
    }

    final trophyData = <String, dynamic>{
      'farmId': farmId.trim(),
      'outfitterId': _currentUserId,
      'species': species.trim(),
      'availableCount': availableCount,
      'pricePerTrophyRands': pricePerTrophyRands,
      'status': 'available',
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    // Trophy measurement (horn/tusk/skull length in inches). Written under two
    // aliases so either read convention resolves.
    if (trophyMeasurement != null && trophyMeasurement > 0) {
      trophyData['trophyMeasurement'] = trophyMeasurement;
      trophyData['trophyLengthInches'] = trophyMeasurement;
    }

    // Up to 3 attached photo URLs.
    if (trophyPhotoUrls.isNotEmpty) {
      trophyData['trophyPhotoUrls'] = trophyPhotoUrls.take(3).toList();
    }

    await _firestore.collection('trophies').add(trophyData);
  }

  // ==========================================
  // APPROVE / DECLINE BOOKING TRANSACTIONS
  // ==========================================
  /// Updates the status of a booking request (Approve or Decline).
  ///
  /// Parameters:
  /// - [bookingId]: Firestore document ID of the booking
  /// - [newStatus]: New status ('Approved' or 'Declined')
  ///
  /// Valid statuses: 'Pending Approval', 'Approved', 'Declined', 'Completed', 'Cancelled'
  ///
  /// Returns: void (updates Firestore 'bookings' collection)
  ///
  /// Throws: Exception if user is not authenticated or update fails
  Future<void> updateBookingStatus({
    required String bookingId,
    required String newStatus,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to update booking status');
    }

    if (bookingId.trim().isEmpty) {
      throw Exception('Booking ID cannot be empty');
    }

    // Validate status transitions
    const validStatuses = [
      'Pending Approval',
      'Approved',
      'Declined',
      'Completed',
      'Cancelled',
    ];

    if (!validStatuses.contains(newStatus)) {
      throw Exception(
        'Invalid booking status: $newStatus. Valid options: ${validStatuses.join(", ")}',
      );
    }

    // Verify the booking belongs to this outfitter
    final bookingDoc =
        await _firestore.collection('bookings').doc(bookingId).get();

    if (!bookingDoc.exists) {
      throw Exception('Booking not found');
    }

    final bookingData = bookingDoc.data() as Map<String, dynamic>;
    final bookingOutfitterId = bookingData['outfitterId'] as String?;

    if (bookingOutfitterId != _currentUserId) {
      throw Exception('You do not have permission to update this booking');
    }

    await _firestore.collection('bookings').doc(bookingId).update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==========================================
  // UTILITY METHODS
  // ==========================================

  /// Get all farms for the authenticated outfitter
  Future<QuerySnapshot> getMyFarms() async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    return await _firestore
        .collection('farms')
        .where('outfitterId', isEqualTo: _currentUserId)
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .get();
  }

  /// Get all managers assigned to a specific farm
  Future<QuerySnapshot> getFarmManagers(String farmId) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    return await _firestore
        .collection('farm_managers')
        .where('farmId', isEqualTo: farmId)
        .where('outfitterId', isEqualTo: _currentUserId)
        .get();
  }

  /// Get trophy stock for a specific farm
  Future<QuerySnapshot> getFarmTrophyStock(String farmId) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    return await _firestore
        .collection('trophies')
        .where('farmId', isEqualTo: farmId)
        .where('outfitterId', isEqualTo: _currentUserId)
        .get();
  }

  /// Get all pending bookings for the authenticated outfitter's packages
  Future<QuerySnapshot> getPendingBookings() async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    return await _firestore
        .collection('bookings')
        .where('outfitterId', isEqualTo: _currentUserId)
        .where('status', isEqualTo: 'Pending Approval')
        .orderBy('bookingTimestamp', descending: true)
        .get();
  }

  /// Get all bookings for the authenticated outfitter
  Future<QuerySnapshot> getAllMyBookings() async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    return await _firestore
        .collection('bookings')
        .where('outfitterId', isEqualTo: _currentUserId)
        .orderBy('bookingTimestamp', descending: true)
        .get();
  }

  /// Deactivate a manager (soft delete)
  Future<void> deactivateManager(String managerId) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    await _firestore.collection('farm_managers').doc(managerId).update({
      'status': 'Inactive',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete a farm (soft delete)
  Future<void> deleteFarm(String farmId) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    await _firestore.collection('farms').doc(farmId).update({
      'status': 'deleted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
