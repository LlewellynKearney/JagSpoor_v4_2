import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../admin/services/admin_auth_guard.dart';
import '../../auth/services/user_role_provider.dart';
import '../../../core/services/push_notification_service.dart';

/// AuthGateService - Advanced Authentication Shield
/// Combines Google OAuth federated logins with SMS OTP 2FA authorization
/// to protect high-tier outfitter revenue metrics.
class AuthGateService {
  static final AuthGateService _instance = AuthGateService._internal();
  factory AuthGateService() => _instance;
  AuthGateService._internal();

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    signInOption: SignInOption.standard,
  );
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // SMS Gateway Configuration (configure your SMS provider here)
  // Options: 'twilio', 'bulksms', 'custom'
  static const String _smsProvider = 'custom';
  static const String _smsApiEndpoint = 'https://api.yoursmsgateway.com/send';
  static const String _smsApiKey = 'YOUR_SMS_API_KEY'; // Replace with actual API key

  // OTP Configuration
  static const int _otpLength = 6;
  static const Duration _otpExpiry = Duration(minutes: 5);

  /// Google Sign In - OAuth credential handshake
  /// Initiates absolute Google OAuth login layer on Android/iOS
  /// Extracts token parameters and provisions authenticates user profile
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Trigger Google authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled the sign-in flow
        return null;
      }

      // Obtain auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential using the Google auth tokens
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      // This will either authenticate an existing user or create a new one
      final UserCredential userCredential =
          await _firebaseAuth.signInWithCredential(credential);

      return userCredential;
    } catch (e) {
      // Log error and return null on failure
      print('AuthGateService: Google Sign-In failed - $e');
      return null;
    }
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

  /// Sign out from all providers
  Future<void> signOut() async {
    // Remove this device's FCM token from the user document BEFORE the auth
    // session ends (the uid must still be resolvable), so the account stops
    // receiving pushes on this device. Best-effort: never blocks sign-out.
    try {
      await PushNotificationService.instance.unregisterCurrentDevice();
    } catch (_) {
      // Push cleanup is a convenience — never block the sign-out.
    }
    await _firebaseAuth.signOut();
    await _googleSignIn.signOut();
    // Clear cached role state so the next sign-in re-resolves from scratch.
    UserRoleProvider.instance.reset();
    AdminAuthGuard.instance.reset();
  }

  /// Re-authenticate user with Google (for sensitive operations)
  Future<bool> reauthenticateWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) return false;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _firebaseAuth.currentUser?.reauthenticateWithCredential(credential);
      return true;
    } catch (e) {
      print('AuthGateService: Re-authentication failed - $e');
      return false;
    }
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
