import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Centralized FCM push-notification service.
///
/// Responsibilities:
///  * **Token registration** — on login (and on cold start with a persisted
///    session) the device's FCM token is stored on the user's Firestore
///    document (`users/{uid}.fcmTokens`, an array merged via `arrayUnion` so
///    multiple devices per account are supported). Token refreshes are
///    re-persisted automatically.
///  * **Token cleanup** — on sign-out the device's token is removed from the
///    user document so the account stops receiving pushes on that device.
///  * **Foreground delivery** — FCM messages that arrive while the app is in
///    the foreground are surfaced through the local notification plugin
///    (background/terminated messages are displayed by the OS directly).
///
/// The server side (Cloud Functions `onBookingCreated` / `onBookingUpdated` /
/// `onPackageUpdated` / `onNewChatMessage`) reads `fcmTokens` from
/// `users/{uid}` to dispatch high-priority pushes.
class PushNotificationService {
  PushNotificationService._();

  /// Production singleton.
  static final PushNotificationService instance = PushNotificationService._();

  /// Test seam: build an instance backed by fakes instead of the live
  /// Firebase plugins (mirrors the `forTesting` factories used across the
  /// codebase).
  @visibleForTesting
  PushNotificationService.forTesting({
    FirebaseFirestore? firestore,
    String? Function()? currentUserIdResolver,
    Future<String?> Function()? tokenProvider,
    Stream<String>? tokenRefreshStream,
    Future<void> Function(String title, String body, String? payload)?
    notificationDisplayer,
  }) : _firestoreOverride = firestore,
       _currentUserIdResolver = currentUserIdResolver,
       _tokenProvider = tokenProvider,
       _tokenRefreshStream = tokenRefreshStream,
       _notificationDisplayer = notificationDisplayer;

  // ── Injectable seams ────────────────────────────────────────────────────

  FirebaseFirestore? _firestoreOverride;
  FirebaseFirestore? _firestoreInstance;

  FirebaseFirestore? get _firestore {
    if (_firestoreOverride != null) return _firestoreOverride;
    try {
      return _firestoreInstance ??= FirebaseFirestore.instance;
    } catch (_) {
      // `[core/no-app]` — Firebase not initialized yet (cold-launch race).
      return null;
    }
  }

  String? Function()? _currentUserIdResolver;

  String? get _currentUserId {
    final resolver = _currentUserIdResolver;
    if (resolver != null) return resolver();
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  Future<String?> Function()? _tokenProvider;

  /// Requests the push-notification permission and returns the device's FCM
  /// registration token (or null when permission is denied / unavailable).
  Future<String?> _resolveToken() {
    final provider = _tokenProvider;
    if (provider != null) return provider();
    return _resolveTokenProduction();
  }

  Future<String?> _resolveTokenProduction() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('PushNotificationService: permission denied by user');
        return null;
      }
      return await messaging.getToken();
    } catch (e) {
      debugPrint('PushNotificationService: token resolution failed: $e');
      return null;
    }
  }

  Stream<String>? _tokenRefreshStream;

  Stream<String>? get _refreshStream {
    final injected = _tokenRefreshStream;
    if (injected != null) return injected;
    try {
      return FirebaseMessaging.instance.onTokenRefresh;
    } catch (_) {
      return null;
    }
  }

  Future<void> Function(String title, String body, String? payload)?
  _notificationDisplayer;

  Future<void> Function(String title, String body, String? payload)
  get _displayer => _notificationDisplayer ??= _showLocalNotification;

  StreamSubscription<String>? _refreshSubscription;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;

  // ── Token persistence (pure Firestore contract, unit-testable) ─────────

  /// Stores [token] on `users/{uid}.fcmTokens` (array-union, so concurrent
  /// devices never clobber each other) and stamps `fcmTokensUpdatedAt`.
  /// Returns whether the write succeeded. Blank uids/tokens are a no-op.
  Future<bool> saveTokenForUser(String uid, String token) async {
    final firestore = _firestore;
    if (firestore == null || uid.trim().isEmpty || token.trim().isEmpty) {
      return false;
    }
    try {
      await firestore.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'fcmTokensUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('PushNotificationService: failed to save FCM token: $e');
      return false;
    }
  }

  /// Removes [token] from `users/{uid}.fcmTokens` (used on sign-out so the
  /// device stops receiving the account's pushes). Best-effort.
  Future<bool> removeTokenForUser(String uid, String token) async {
    final firestore = _firestore;
    if (firestore == null || uid.trim().isEmpty || token.trim().isEmpty) {
      return false;
    }
    try {
      await firestore.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayRemove([token]),
        'fcmTokensUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('PushNotificationService: failed to remove FCM token: $e');
      return false;
    }
  }

  // ── Device registration lifecycle ───────────────────────────────────────

  /// Registers the current device for the signed-in user: resolves the FCM
  /// token, persists it on `users/{uid}`, and subscribes to the token-refresh
  /// stream so a rotated token is re-persisted automatically. Returns the
  /// registered token (or null when unauthenticated / unavailable).
  Future<String?> registerCurrentDevice() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return null;

    final token = await _resolveToken();
    if (token == null || token.isEmpty) return null;

    await saveTokenForUser(uid, token);

    _refreshSubscription ??= _refreshStream?.listen((newToken) {
      final currentUid = _currentUserId;
      if (currentUid != null && currentUid.isNotEmpty) {
        unawaited(saveTokenForUser(currentUid, newToken));
      }
    });

    return token;
  }

  /// Removes the current device's token from the signed-in user's document.
  /// Call BEFORE signing out (the uid must still be resolvable). Best-effort:
  /// a failure never blocks the sign-out.
  Future<void> unregisterCurrentDevice() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return;
    final token = await _resolveToken();
    if (token == null || token.isEmpty) return;
    await removeTokenForUser(uid, token);
  }

  // ── Production wiring ───────────────────────────────────────────────────

  /// Initializes the production pipeline: registers the current device when a
  /// session already exists, re-registers on every subsequent sign-in, and
  /// surfaces foreground FCM messages as local notifications. Safe to call
  /// multiple times (listeners are only attached once). Best-effort: a
  /// plugin failure never blocks app startup.
  Future<void> initialize() async {
    // Cold start with a persisted session.
    unawaited(registerCurrentDevice());

    // Register on every sign-in (email, Google, 2FA-verified).
    _authSubscription ??= _authStateChanges()?.listen((user) {
      if (user != null) unawaited(registerCurrentDevice());
    });

    // Foreground messages: the OS only displays notification payloads when
    // the app is backgrounded/terminated, so foreground arrivals are shown
    // through the local notification plugin.
    _messageSubscription ??= _foregroundMessages()?.listen(
      (message) => unawaited(handleForegroundMessage(message)),
    );
  }

  Stream<User?>? _authStateChanges() {
    try {
      return FirebaseAuth.instance.authStateChanges();
    } catch (_) {
      return null;
    }
  }

  Stream<RemoteMessage>? _foregroundMessages() {
    try {
      return FirebaseMessaging.onMessage;
    } catch (_) {
      return null;
    }
  }

  // ── Foreground message handling ─────────────────────────────────────────

  /// The local-notification channel used to surface foreground FCM messages.
  /// Matches the channel the booking-status service already uses.
  static const String foregroundChannelId = 'booking_status_channel';
  static const String foregroundChannelName = 'Booking Status';

  /// Maps an incoming [RemoteMessage] to the (title, body, payload) triple
  /// shown as a local notification. Prefers the message's notification
  /// payload, then falls back to the data payload so a data-only message
  /// still renders meaningful text. Pure — unit-testable.
  static ({String title, String body, String? payload}) describeMessage(
    RemoteMessage message,
  ) {
    final data = message.data;
    final title =
        message.notification?.title ??
        (data['title'] as String?) ??
        'JagSpoor Notification';
    final body =
        message.notification?.body ?? (data['body'] as String?) ?? '';
    final payload =
        (data['bookingId'] as String?) ?? (data['packageId'] as String?);
    return (title: title, body: body, payload: payload);
  }

  /// Handles a foreground FCM message by surfacing it through the local
  /// notification displayer. Swallows display failures.
  Future<void> handleForegroundMessage(RemoteMessage message) async {
    final description = describeMessage(message);
    try {
      await _displayer(description.title, description.body, description.payload);
    } catch (e) {
      debugPrint('PushNotificationService: foreground display failed: $e');
    }
  }

  FlutterLocalNotificationsPlugin? _localNotifications;
  bool _localNotificationsReady = false;

  /// Default displayer: shows a high-priority local notification via
  /// `flutter_local_notifications` on the shared booking-status channel.
  Future<void> _showLocalNotification(
    String title,
    String body,
    String? payload,
  ) async {
    final plugin = _localNotifications ??= FlutterLocalNotificationsPlugin();
    if (!_localNotificationsReady) {
      const initializationSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      );
      await plugin.initialize(initializationSettings);
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              foregroundChannelId,
              foregroundChannelName,
              description: 'Notifications for booking status updates',
              importance: Importance.high,
            ),
          );
      _localNotificationsReady = true;
    }
    await plugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          foregroundChannelId,
          foregroundChannelName,
          channelDescription: 'Notifications for booking status updates',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  /// Cancels all subscriptions. Primarily for tests.
  @visibleForTesting
  Future<void> dispose() async {
    await _refreshSubscription?.cancel();
    await _authSubscription?.cancel();
    await _messageSubscription?.cancel();
    _refreshSubscription = null;
    _authSubscription = null;
    _messageSubscription = null;
  }
}
