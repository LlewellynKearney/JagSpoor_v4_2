import 'dart:async';
import 'dart:ui' show Color;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BookingStatusService {
  static final BookingStatusService _instance =
      BookingStatusService._internal();
  static BookingStatusService get instance => _instance;

  BookingStatusService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<QuerySnapshot>? _bookingSubscription;
  String? _lastKnownStatus;

  /// Initialize the notification service
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Request permissions on Android 13+
    await _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    final androidPlugin =
        _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap - navigate to booking details
  }

  /// Start listening to booking status changes for the current hunter
  void startListening() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null) {
      return;
    }

    _bookingSubscription?.cancel();

    _bookingSubscription = _firestore
        .collection('bookings')
        .where('hunterId', isEqualTo: currentUserId)
        .orderBy('bookingTimestamp', descending: true)
        .limit(10)
        .snapshots()
        .listen(_onBookingSnapshot);
  }

  /// Stop listening to booking changes
  void stopListening() {
    _bookingSubscription?.cancel();
    _bookingSubscription = null;
    _lastKnownStatus = null;
  }

  void _onBookingSnapshot(QuerySnapshot snapshot) {
    if (snapshot.docs.isEmpty) return;

    // Check the most recent booking for status changes
    final latestBooking = snapshot.docs.first;
    final data = latestBooking.data() as Map<String, dynamic>;
    final currentStatus = data['status'] as String?;
    final bookingId = latestBooking.id;
    final packageName = data['packageName'] as String? ?? 'Hunting Package';

    if (currentStatus != null && currentStatus != _lastKnownStatus) {
      _lastKnownStatus = currentStatus;

      // Only trigger notifications for status changes to Approved or Declined
      if (currentStatus == 'Approved') {
        _showBookingApprovedNotification(bookingId, packageName, data);
      } else if (currentStatus == 'Declined') {
        _showBookingDeclinedNotification(bookingId, packageName);
      }
    }
  }

  Future<void> _showBookingApprovedNotification(
    String bookingId,
    String packageName,
    Map<String, dynamic> data,
  ) async {
    final totalPrice = (data['totalHunterPriceRands'] ?? 0).toDouble();

    final androidDetails = AndroidNotificationDetails(
      'booking_status_channel',
      'Booking Status',
      channelDescription: 'Notifications for booking status updates',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF2E7D32), // Green
      enableLights: true,
      ledColor: const Color(0xFF2E7D32),
      ledOnMs: 1000,
      ledOffMs: 500,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      bookingId.hashCode,
      '✅ BOOKING APPROVED!',
      'Your $packageName booking has been approved!\nTotal: R ${totalPrice.toStringAsFixed(2)} ZAR',
      details,
      payload: bookingId,
    );
  }

  Future<void> _showBookingDeclinedNotification(
    String bookingId,
    String packageName,
  ) async {
    final androidDetails = AndroidNotificationDetails(
      'booking_status_channel',
      'Booking Status',
      channelDescription: 'Notifications for booking status updates',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFC62828), // Red
      enableLights: true,
      ledColor: const Color(0xFFC62828),
      ledOnMs: 1000,
      ledOffMs: 500,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      bookingId.hashCode,
      '❌ Booking Declined',
      'Your $packageName booking was not approved. Please try another package.',
      details,
      payload: bookingId,
    );
  }

  /// Manually trigger a notification (for testing)
  Future<void> showTestNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'booking_status_channel',
      'Booking Status',
      channelDescription: 'Notifications for booking status updates',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      0,
      'JagSpoor Alert',
      'Booking notifications are active!',
      details,
    );
  }
}
