import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Central chat messaging and map range optimization service.
/// Handles negotiation chat streams and offline geographic/temporal filtering operations.
class ChatAndFilterService {
  static final ChatAndFilterService instance = ChatAndFilterService._internal();
  ChatAndFilterService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Earth radius in kilometers for Haversine formula calculations
  static const double earthRadiusKm = 6371.0;

  // ==========================================
  // 1. SEND NEGOTIATION CHAT MESSAGE
  // ==========================================

  /// Saves a chat message to the nested collection: /bookings/{bookingId}/chats
  ///
  /// Parameters:
  /// - [bookingId]: The parent booking document ID
  /// - [messageText]: The text content of the chat message
  /// - [senderName]: Display name of the message sender
  ///
  /// The message document contains:
  /// - text: The message content
  /// - senderId: Current authenticated user's UID
  /// - senderName: Provided display name
  /// - timestamp: Server-generated timestamp
  Future<void> sendChatMessage({
    required String bookingId,
    required String messageText,
    required String senderName,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User must be authenticated to send chat messages');
    }

    if (messageText.trim().isEmpty) {
      throw Exception('Message text cannot be empty');
    }

    if (bookingId.trim().isEmpty) {
      throw Exception('Booking ID cannot be empty');
    }

    final messageData = {
      'text': messageText.trim(),
      'senderId': currentUser.uid,
      'senderName': senderName.trim(),
      'timestamp': FieldValue.serverTimestamp(),
    };

    await _firestore
        .collection('bookings')
        .doc(bookingId)
        .collection('chats')
        .add(messageData);

    // Chat message sent successfully - Firestore write complete
  }

  // ==========================================
  // 2. OFFLINE GEOGRAPHIC RADIUS CALCULATOR
  // ==========================================

  /// Calculates the distance between two GPS coordinates using the Haversine formula.
  /// This operation runs entirely offline without any network calls.
  ///
  /// Parameters:
  /// - [centerLat]: Latitude of the center point in decimal degrees
  /// - [centerLon]: Longitude of the center point in decimal degrees
  /// - [targetLat]: Latitude of the target point in decimal degrees
  /// - [targetLon]: Longitude of the target point in decimal degrees
  /// - [maxRadiusKm]: Maximum allowed radius in kilometers
  ///
  /// Returns true if the target coordinate is within [maxRadiusKm] of the center coordinate.
  ///
  /// The Haversine formula:
  /// a = sin²(Δlat/2) + cos(lat1) * cos(lat2) * sin²(Δlon/2)
  /// c = 2 * atan2(√a, √(1−a))
  /// d = R * c
  bool isCoordinateWithinRadius({
    required double centerLat,
    required double centerLon,
    required double targetLat,
    required double targetLon,
    required double maxRadiusKm,
  }) {
    // Calculate distance using Haversine formula
    final distanceKm = _calculateHaversineDistance(
      lat1: centerLat,
      lon1: centerLon,
      lat2: targetLat,
      lon2: targetLon,
    );

    return distanceKm <= maxRadiusKm;
  }

  /// Internal Haversine distance calculation.
  /// Returns the distance in kilometers between two GPS coordinates.
  double _calculateHaversineDistance({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    // Convert decimal degrees to radians
    final lat1Rad = _degreesToRadians(lat1);
    final lat2Rad = _degreesToRadians(lat2);
    final deltaLatRad = _degreesToRadians(lat2 - lat1);
    final deltaLonRad = _degreesToRadians(lon2 - lon1);

    // Haversine formula
    final a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(deltaLonRad / 2) *
            math.sin(deltaLonRad / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    // Distance in kilometers
    final distance = earthRadiusKm * c;

    return distance;
  }

  /// Converts decimal degrees to radians.
  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }

  // ==========================================
  // 3. OFFLINE TIMESTAMP DURATION EVALUATOR
  // ==========================================

  /// Checks if a document timestamp is within the specified number of hours from now.
  /// This operation runs entirely offline without any network calls.
  ///
  /// Parameters:
  /// - [documentTimestampMillis]: The document's creation timestamp in milliseconds since epoch
  /// - [maxHoursFilter]: Maximum age in hours for the document to be considered valid
  ///
  /// Returns true if the difference between the current time and the document timestamp
  /// is less than [maxHoursFilter] hours.
  ///
  /// Calculation:
  /// isWithin = (DateTime.now().millisecondsSinceEpoch - documentTimestampMillis) < (maxHoursFilter * 3600000)
  bool isTimestampWithinHours({
    required int documentTimestampMillis,
    required int maxHoursFilter,
  }) {
    if (documentTimestampMillis <= 0) {
      return false;
    }

    if (maxHoursFilter <= 0) {
      return false;
    }

    final currentTimeMillis = DateTime.now().millisecondsSinceEpoch;
    final maxAgeMillis = maxHoursFilter * 3600000; // Convert hours to milliseconds

    final ageMillis = currentTimeMillis - documentTimestampMillis;

    return ageMillis < maxAgeMillis;
  }

  /// Overload that accepts a Firestore Timestamp object directly.
  /// Converts the Timestamp to milliseconds and evaluates.
  bool isTimestampWithinHoursFromTimestamp({
    required Timestamp timestamp,
    required int maxHoursFilter,
  }) {
    return isTimestampWithinHours(
      documentTimestampMillis: timestamp.millisecondsSinceEpoch,
      maxHoursFilter: maxHoursFilter,
    );
  }

  /// Overload that accepts a DateTime object directly.
  /// Converts the DateTime to milliseconds and evaluates.
  bool isTimestampWithinHoursFromDateTime({
    required DateTime documentDateTime,
    required int maxHoursFilter,
  }) {
    return isTimestampWithinHours(
      documentTimestampMillis: documentDateTime.millisecondsSinceEpoch,
      maxHoursFilter: maxHoursFilter,
    );
  }
}
