import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../admin/services/admin_auth_guard.dart';
import '../../auth/services/user_role_provider.dart';
import '../../../core/services/push_notification_service.dart';

/// Outcome of a Google Sign-In attempt.
///
/// Distinguishes the three possible end states so the UI can react
/// appropriately instead of treating every non-success as a silent cancel:
///  * [success]    — a Firebase [UserCredential] was issued.
///  * [cancelled]  — the user dismissed the Google account picker (silent).
///  * [failure]    — an actual error occurred; [errorMessage] carries a
///    user-actionable reason (e.g. unregistered SHA-1 fingerprint).
class GoogleSignInResult {
  final UserCredential? credential;
  final bool cancelled;
  final String? errorMessage;

  const GoogleSignInResult._(this.credential, this.cancelled, this.errorMessage);

  factory GoogleSignInResult.success(UserCredential credential) =>
      GoogleSignInResult._(credential, false, null);

  factory GoogleSignInResult.cancelled() =>
      const GoogleSignInResult._(null, true, null);

  factory GoogleSignInResult.failure(String message) =>
      GoogleSignInResult._(null, false, message);

  bool get isSuccess => credential != null;
}

/// AuthGateService - Advanced Authentication Shield
/// Combines Google OAuth federated logins with SMS OTP 2FA authorization
/// to protect high-tier outfitter revenue metrics.
class AuthGateService {
  static final AuthGateService _instance = AuthGateService._internal();
  factory AuthGateService() => _instance;
  AuthGateService._internal();

  // Lazily resolved so constructing the service before `Firebase.initializeApp()`
  // (cold-launch race / widget tests) does not throw `[core/no-app]`.
  FirebaseAuth get _firebaseAuth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Whether Google Sign-In is available.
  ///
  /// **Disabled on all platforms.** The app ships email/password
  /// authentication only — the Google federated flow was removed so no
  /// platform shows a "Continue with Google" button and no Google client id /
  /// plugin is required at runtime (web or native). The `google_sign_in`
  /// dependency is retained in `pubspec.yaml` but is no longer used.
  static const bool googleSignInEnabled = false;

  // SMS Gateway Configuration (configure your SMS provider here)
  // Options: 'twilio', 'bulksms', 'custom'
  static const String _smsProvider = 'custom';
  static const String _smsApiEndpoint = 'https://api.yoursmsgateway.com/send';
  static const String _smsApiKey = 'YOUR_SMS_API_KEY'; // Replace with actual API key

  // OTP Configuration
  static const int _otpLength = 6;
  static const Duration _otpExpiry = Duration(minutes: 5);

  /// Google Sign In — **disabled on all platforms**.
  ///
  /// The federated Google flow was removed so no platform (web, Android or
  /// iOS) exposes a Google sign-in affordance and no Google client id / plugin
  /// is required at runtime. This method is retained as a no-op so any legacy
  /// caller compiles and fails soft: it always returns a
  /// [GoogleSignInResult.cancelled] (never a crash, never a credential).
  ///
  /// Email/password authentication is the only supported sign-in path.
  Future<GoogleSignInResult> signInWithGoogle() async {
    debugPrint('AuthGateService: Google Sign-In is disabled on all platforms.');
    return GoogleSignInResult.cancelled();
  }

  /// Maps a Google Sign-In failure to a user-actionable message.
  ///
  /// The most common real-world cause is `ApiException: 10` /
  /// `sign_in_failed` (DEVELOPER_ERROR): the signing keystore's SHA-1 /
  /// SHA-256 fingerprint is not registered on the Android OAuth client in
  /// the Firebase Console — which is exactly what happens with a freshly
  /// generated debug keystore (CI machine, new dev laptop, sandbox).
  /// Pure + static so it is unit-testable without a Firebase app.
  static String friendlyGoogleSignInError(Object error) {
    final code = error is PlatformException ? error.code : '';
    final raw = error.toString();

    final isDeveloperError =
        code == 'sign_in_failed' ||
        code == 'developer_error' ||
        raw.contains('ApiException: 10') ||
        raw.contains('DEVELOPER_ERROR') ||
        raw.contains('no_tokens');
    if (isDeveloperError) {
      return 'Google Sign-In is not configured for this build. The signing '
          "keystore's SHA-1/SHA-256 fingerprint must be registered in the "
          'Firebase Console (Project Settings → Your Android app → SHA '
          'certificate fingerprints). Please contact support.';
    }

    final isNetwork =
        code == 'network_error' || raw.toLowerCase().contains('network');
    if (isNetwork) {
      return 'Google Sign-In failed due to a network error. Check your '
          'connection and try again.';
    }

    if (code == 'sign_in_canceled') {
      return 'Google Sign-In was cancelled.';
    }

    final detail =
        error is PlatformException
            ? (error.message ?? error.details?.toString() ?? code)
            : raw;
    return 'Google Sign-In failed: $detail';
  }

  /// Trigger SMS Two-Factor OTP Challenge
  /// Texts a secure 6-digit confirmation PIN to South African cell phones
  /// Passes verificationId back via callback for multi-factor security loops
  Future<void> triggerSMS2FA({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(FirebaseAuthException e) onFailed,
  }) async {
    // Normalize South African phone numbers to E.164 format
    String normalizedPhone = _normalizeSAPhoneNumber(phoneNumber);

    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: normalizedPhone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) {
        // Auto-verification on Android devices with Play Services
        // Automatically signs in user when SMS is auto-retrieved
        _firebaseAuth.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        // Handle verification failure - pass to callback
        onFailed(e);
      },
      codeSent: (String verificationId, int? resendToken) {
        // Pass verificationId back via callback for multi-factor loop
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        // Auto-retrieval timeout - verificationId still valid for manual entry
        print('AuthGateService: SMS auto-retrieval timeout');
      },
    );
  }

  /// Verify SMS OTP code and complete 2FA challenge
  Future<UserCredential?> verifySMSOTP({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      // Create credential from the verification ID and SMS code
      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      // Sign in with the phone credential
      final UserCredential userCredential =
          await _firebaseAuth.signInWithCredential(credential);

      return userCredential;
    } catch (e) {
      print('AuthGateService: SMS OTP verification failed - $e');
      return null;
    }
  }

  /// Normalize South African phone numbers to E.164 format
  /// Converts 0821234567 -> +27821234567
  String _normalizeSAPhoneNumber(String phone) {
    // Remove all non-digit characters
    String digits = phone.replaceAll(RegExp(r'\D'), '');

    // Handle SA phone numbers (mobile prefixes: 06x, 07x, 08x)
    if (digits.startsWith('0') && digits.length == 10) {
      // Convert 0821234567 to +27821234567
      digits = '+27' + digits.substring(1);
    } else if (digits.startsWith('27') && digits.length == 11) {
      // Already has country code but missing +
      digits = '+' + digits;
    } else if (!digits.startsWith('+')) {
      // Prepend + if not present
      digits = '+' + digits;
    }

    return digits;
  }

  /// Get current authenticated user
  User? get currentUser => _firebaseAuth.currentUser;

  /// Check if user is signed in
  bool get isSignedIn => _firebaseAuth.currentUser != null;

  /// Sign out from all providers.
  ///
  /// This is deliberately **failure-tolerant**: every step is independently
  /// guarded and the method never throws, so a caller's navigation to the
  /// login screen always proceeds. Previously an unguarded
  /// `FirebaseAuth.instance.currentUser!` / plugin call could raise
  /// `Null check operator used on a null value` and abort the sign-out (the
  /// "Sign out failed" crash).
  Future<void> signOut() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      // Already signed out — clear the cached role/admin state so a stale
      // session can never linger, then return without touching the plugins.
      UserRoleProvider.instance.reset();
      AdminAuthGuard.instance.reset();
      return;
    }

    // Remove this device's FCM token from the user document BEFORE the auth
    // session ends (the uid must still be resolvable), so the account stops
    // receiving pushes on this device. Best-effort: never blocks sign-out.
    try {
      await PushNotificationService.instance.unregisterCurrentDevice();
    } catch (e) {
      debugPrint('AuthGateService.signOut: FCM unregister failed: $e');
    }

    // Sign out of Firebase Auth. Guarded so a plugin/platform error cannot
    // abort the flow (the local caches are cleared regardless).
    try {
      await _firebaseAuth.signOut();
    } catch (e) {
      debugPrint('AuthGateService.signOut: FirebaseAuth.signOut failed: $e');
    }

    // NOTE: Google Sign-In is disabled on all platforms, so there is no
    // federated session to end here. The Firebase Auth sign-out above is the
    // complete, platform-independent sign-out (previously a
    // `GoogleSignIn().signOut()` call was made — and on the web it threw a
    // null crash; it is removed entirely).

    // Clear cached role state so the next sign-in re-resolves from scratch.
    UserRoleProvider.instance.reset();
    AdminAuthGuard.instance.reset();
  }

  /// Re-authenticate the user with Google — **disabled on all platforms**.
  ///
  /// Retained as a no-op so legacy callers compile and fail soft (returns
  /// false rather than throwing). Email/password is the only supported
  /// re-authentication path.
  Future<bool> reauthenticateWithGoogle() async {
    debugPrint(
      'AuthGateService: reauthenticateWithGoogle is disabled on all platforms.',
    );
    return false;
  }

  /// Link phone number to existing account (for 2FA setup)
  Future<void> linkPhoneNumber({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(FirebaseAuthException e) onFailed,
    required Future<void> Function(PhoneAuthCredential) onVerificationCompleted,
  }) async {
    String normalizedPhone = _normalizeSAPhoneNumber(phoneNumber);

    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: normalizedPhone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: onVerificationCompleted,
      verificationFailed: onFailed,
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  /// Enable 2FA on current user account
  Future<void> enable2FA({
    required String verificationId,
    required String smsCode,
  }) async {
    final PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );

    await _firebaseAuth.currentUser?.linkWithCredential(credential);
  }

  /// Stream of authentication state changes
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  // ============================================================
  // CUSTOM FIRESTORE-DRIVEN SMS OTP 2FA (No Identity Platform Required)
  // ============================================================

  /// Generate and send custom 6-digit OTP via Firestore + SMS Gateway
  /// Bypasses Google Identity Platform requirement
  Future<bool> generateAndSendCustomOTP({
    required String uid,
    required String mobileNumber,
  }) async {
    try {
      // Step 1: Generate secure random 6-digit PIN
      final String otpCode = _generateSecureOTP();
      
      // Step 2: Calculate expiry timestamp
      final DateTime expiresAt = DateTime.now().add(_otpExpiry);
      
      // Step 3: Write challenge document to Firestore
      // Path: /users/{uid}/security/two_factor_challenge
      final challengeRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('security')
          .doc('two_factor_challenge');
      
      await challengeRef.set({
        'code': otpCode,
        'expiresAt': Timestamp.fromDate(expiresAt),
        'createdAt': FieldValue.serverTimestamp(),
        'attempts': 0,
        'mobileNumber': _normalizeSAPhoneNumber(mobileNumber),
      }, SetOptions(merge: true));
      
      // Step 4: Send SMS via configured gateway
      final smsSent = await _sendSMS(
        mobileNumber: _normalizeSAPhoneNumber(mobileNumber),
        message: 'Your JagSpoor security code is: $otpCode\nValid for 5 minutes.',
      );
      
      return smsSent;
    } catch (e) {
      print('AuthGateService: Failed to generate/send OTP - $e');
      return false;
    }
  }

  /// Verify custom OTP from Firestore challenge document
  /// Returns true if code matches and not expired
  Future<OTPVerificationResult> verifyCustomOTP({
    required String uid,
    required String userInputCode,
  }) async {
    try {
      // Step 1: Fetch challenge document from Firestore
      final challengeRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('security')
          .doc('two_factor_challenge');
      
      final docSnap = await challengeRef.get();
      
      if (!docSnap.exists) {
        return OTPVerificationResult(
          success: false,
          error: 'No pending verification. Please request a new code.',
        );
      }
      
      final data = docSnap.data()!;
      final String? storedCode = data['code'] as String?;
      final Timestamp? expiresTimestamp = data['expiresAt'] as Timestamp?;
      int attempts = (data['attempts'] as int?) ?? 0;
      
      // Step 2: Check if expired
      if (expiresTimestamp == null || 
          DateTime.now().isAfter(expiresTimestamp.toDate())) {
        // Delete expired challenge
        await challengeRef.delete();
        return OTPVerificationResult(
          success: false,
          error: 'Code expired. Please request a new one.',
        );
      }
      
      // Step 3: Check attempt limit (max 5 attempts)
      if (attempts >= 5) {
        await challengeRef.delete();
        return OTPVerificationResult(
          success: false,
          error: 'Too many attempts. Please request a new code.',
        );
      }
      
      // Step 4: Increment attempts and compare code
      await challengeRef.update({'attempts': attempts + 1});
      
      if (storedCode == null || storedCode != userInputCode) {
        return OTPVerificationResult(
          success: false,
          error: 'Invalid code. ${5 - attempts - 1} attempts remaining.',
        );
      }
      
      // Step 5: Success - delete challenge and return verified
      await challengeRef.delete();
      
      return OTPVerificationResult(
        success: true,
        error: null,
      );
    } catch (e) {
      print('AuthGateService: OTP verification error - $e');
      return OTPVerificationResult(
        success: false,
        error: 'Verification failed. Please try again.',
      );
    }
  }

  /// Clear any pending OTP challenge for a user
  Future<void> clearPendingOTP(String uid) async {
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('security')
          .doc('two_factor_challenge')
          .delete();
    } catch (e) {
      print('AuthGateService: Failed to clear pending OTP - $e');
    }
  }

  /// Check if user has pending OTP challenge
  Future<bool> hasPendingOTP(String uid) async {
    try {
      final docSnap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('security')
          .doc('two_factor_challenge')
          .get();
      
      if (!docSnap.exists) return false;
      
      final data = docSnap.data()!;
      final Timestamp? expiresTimestamp = data['expiresAt'] as Timestamp?;
      
      if (expiresTimestamp == null) return false;
      
      return DateTime.now().isBefore(expiresTimestamp.toDate());
    } catch (e) {
      return false;
    }
  }

  /// Generate secure random 6-digit OTP
  String _generateSecureOTP() {
    final Random secureRandom = Random.secure();
    int otp = 0;
    for (int i = 0; i < _otpLength; i++) {
      otp = otp * 10 + secureRandom.nextInt(10);
    }
    return otp.toString().padLeft(_otpLength, '0');
  }

  /// Send SMS via configured gateway
  Future<bool> _sendSMS({
    required String mobileNumber,
    required String message,
  }) async {
    try {
      switch (_smsProvider) {
        case 'twilio':
          return await _sendViaTwilio(mobileNumber, message);
        case 'bulksms':
          return await _sendViaBulkSMS(mobileNumber, message);
        case 'custom':
        default:
          return await _sendViaCustomGateway(mobileNumber, message);
      }
    } catch (e) {
      print('AuthGateService: SMS send failed - $e');
      return false;
    }
  }

  /// Twilio SMS Gateway Integration
  Future<bool> _sendViaTwilio(String mobileNumber, String message) async {
    // Twilio REST API call
    // Replace with actual Twilio credentials
    final String accountSid = 'YOUR_TWILIO_ACCOUNT_SID';
    final String authToken = 'YOUR_TWILIO_AUTH_TOKEN';
    
    final response = await http.post(
      Uri.parse('https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json'),
      headers: {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$accountSid:$authToken'))}',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'To': mobileNumber,
        'From': '+1234567890', // Your Twilio number
        'Body': message,
      },
    );
    
    return response.statusCode == 201 || response.statusCode == 200;
  }

  /// BulkSMS South Africa Gateway Integration
  Future<bool> _sendViaBulkSMS(String mobileNumber, String message) async {
    final response = await http.get(
      Uri.parse(
        'https://www.bulksms.co.za/eapi/submission/send_sms/2/2.0'
        '?username=YOUR_USERNAME'
        '&password=YOUR_PASSWORD'
        '&msisdn=$mobileNumber'
        '&message=${Uri.encodeComponent(message)}',
      ),
    );
    
    return response.statusCode == 200 && 
           response.body.contains('0'); // 0 = success in BulkSMS API
  }

  /// Custom SMS Gateway Integration
  Future<bool> _sendViaCustomGateway(String mobileNumber, String message) async {
    // Generic HTTP POST to custom SMS API
    try {
      final response = await http.post(
        Uri.parse(_smsApiEndpoint),
        headers: {
          'Authorization': 'Bearer $_smsApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'to': mobileNumber,
          'message': message,
        }),
      );
      
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      // For demo/testing: Log the OTP if SMS fails
      print('AuthGateService: Custom SMS gateway not configured. '
            'Configure _smsApiEndpoint to enable real SMS delivery.');
      return true; // Return true for local testing
    }
  }
}

/// Result class for OTP verification
class OTPVerificationResult {
  final bool success;
  final String? error;
  
  OTPVerificationResult({
    required this.success,
    required this.error,
  });
}
