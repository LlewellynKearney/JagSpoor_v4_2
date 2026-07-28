import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// TransportPermitManager - Central statutory South African Game Transport Permit engine
/// 
/// Handles the creation and management of transport permits in compliance with
/// South African wildlife and game transport regulations (Nemba Act / Cape Nature ordinances).
class TransportPermitManager {
  static final TransportPermitManager _instance = TransportPermitManager._internal();
  static TransportPermitManager get instance => _instance;

  TransportPermitManager._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Issue a new South African Game Transport Permit
  /// 
  /// Parameters:
  /// - [farmId]: Document ID of the issuing farm/concession
  /// - [farmName]: Registered name of the farm
  /// - [exemptionNumber]: CAE or Provincial Exemption Number (e.g., "CAE-2024-001234")
  /// - [hunterName]: Full legal name of the licensed hunter
  /// - [hunterIdNumber]: South African ID number or passport number
  /// - [hunterAddress]: Registered residential address of the hunter
  /// - [vehicleReg]: Vehicle registration number
  /// - [vehicleMake]: Vehicle make and model
  /// - [speciesList]: List of species being transported with quantity and sex
  ///   e.g. [{'species': 'Kudu', 'quantity': 1, 'sex': 'Male', 'tagNumber': 'TAG-001'}]
  /// - [destinationAddress]: Destination address for the game transport
  Future<String> issueTransportPermit({
    required String farmId,
    required String farmName,
    required String exemptionNumber,
    required String hunterName,
    required String hunterIdNumber,
    required String hunterAddress,
    required String vehicleReg,
    required String vehicleMake,
    required List<Map<String, dynamic>> speciesList,
    required String destinationAddress,
  }) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final permitData = {
      'outfitterId': currentUserId,
      'farmId': farmId,
      'farmName': farmName,
      'exemptionNumber': exemptionNumber,
      'hunterName': hunterName,
      'hunterIdNumber': hunterIdNumber,
      'hunterAddress': hunterAddress,
      'vehicleReg': vehicleReg,
      'vehicleMake': vehicleMake,
      'speciesList': speciesList,
      'destinationAddress': destinationAddress,
      'status': 'Issued',
      'issuedTimestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'permitNumber': _generatePermitNumber(),
    };

    final docRef = await _firestore.collection('transport_permits').add(permitData);
    return docRef.id;
  }

  /// Generate a unique permit number in SA format
  String _generatePermitNumber() {
    final now = DateTime.now();
    final year = now.year.toString();
    final random = now.millisecondsSinceEpoch.toString().substring(6);
    return 'JST-$year-$random';
  }

  /// Get all transport permits for the current outfitter
  Stream<List<Map<String, dynamic>>> getOutfitterPermitsStream() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('transport_permits')
        .where('outfitterId', isEqualTo: currentUserId)
        .orderBy('issuedTimestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
        });
  }

  /// Get permits by farm
  Stream<List<Map<String, dynamic>>> getPermitsByFarmStream(String farmId) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('transport_permits')
        .where('outfitterId', isEqualTo: currentUserId)
        .where('farmId', isEqualTo: farmId)
        .orderBy('issuedTimestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
        });
  }

  /// Update permit status
  Future<void> updatePermitStatus({
    required String permitId,
    required String newStatus,
    String? notes,
  }) async {
    await _firestore.collection('transport_permits').doc(permitId).update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
      if (notes != null) 'notes': notes,
    });
  }

  /// Get a single permit by ID
  Future<Map<String, dynamic>?> getPermitById(String permitId) async {
    final doc = await _firestore.collection('transport_permits').doc(permitId).get();
    if (!doc.exists) return null;
    
    final data = doc.data()!;
    data['id'] = doc.id;
    return data;
  }

  /// Delete a permit (admin only)
  Future<void> deletePermit(String permitId) async {
    await _firestore.collection('transport_permits').doc(permitId).delete();
  }

  /// Validate species against farm trophy stock
  Future<bool> validateSpeciesAvailability({
    required String farmId,
    required List<Map<String, dynamic>> requestedSpecies,
  }) async {
    final farmDoc = await _firestore.collection('farms').doc(farmId).get();
    if (!farmDoc.exists) return false;

    final farmData = farmDoc.data()!;
    final trophyStock = List<Map<String, dynamic>>.from(farmData['trophyStock'] ?? []);

    for (final requested in requestedSpecies) {
      final speciesName = requested['species'] as String;
      final requestedQty = (requested['quantity'] as num?)?.toInt() ?? 1;

      final available = trophyStock.firstWhere(
        (t) => t['species'] == speciesName,
        orElse: () => {'available': 0},
      );

      final availableQty = (available['available'] as num?)?.toInt() ?? 0;
      if (availableQty < requestedQty) {
        return false;
      }
    }
    return true;
  }

  /// Calculate total species count from permit
  int calculateTotalSpecies(Map<String, dynamic> permitData) {
    final speciesList = List<Map<String, dynamic>>.from(permitData['speciesList'] ?? []);
    return speciesList.fold(0, (total, species) {
      return total + ((species['quantity'] as num?)?.toInt() ?? 0);
    });
  }

  /// Format species list for display
  String formatSpeciesSummary(List<Map<String, dynamic>> speciesList) {
    return speciesList.map((s) {
      final name = s['species'] ?? 'Unknown';
      final qty = (s['quantity'] as num?)?.toInt() ?? 1;
      final sex = s['sex'] ?? '';
      return '$name (${qty}x ${sex.isNotEmpty ? sex : "N/A"})';
    }).join(', ');
  }
}
