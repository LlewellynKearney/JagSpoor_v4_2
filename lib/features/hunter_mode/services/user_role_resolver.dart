import 'package:cloud_firestore/cloud_firestore.dart';

class UserRoleResolver {
  static final UserRoleResolver instance = UserRoleResolver._internal();
  UserRoleResolver._internal();

  String? _assignedFarmId;
  bool _isManagerRole = false;

  bool get isManager => _isManagerRole;
  String? get assignedFarmId => _assignedFarmId;

  /// Evaluates login parameters to restrict views dynamically
  Future<void> resolveCurrentUserRole(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('farm_managers').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        _isManagerRole = true;
        _assignedFarmId = doc.data()!['farmId'] as String?;
        print('🔒 ROLE BOUND: Authenticated user is an active Farm Manager locked to Farm ID: $_assignedFarmId');
      } else {
        _isManagerRole = false;
        _assignedFarmId = null;
        print('👑 ROLE BOUND: Authenticated user is a master corporate Outfitter.');
      }
    } catch (e) {
      _isManagerRole = false;
      _assignedFarmId = null;
      print('⚠️ Error resolving user role: $e');
    }
  }

  /// Check if the current user has manager access to a specific farm
  bool canAccessFarm(String farmId) {
    if (!_isManagerRole) return true; // Outfitters can access all
    return _assignedFarmId == farmId;
  }

  /// Reset role state (call on logout)
  void reset() {
    _isManagerRole = false;
    _assignedFarmId = null;
  }
}
