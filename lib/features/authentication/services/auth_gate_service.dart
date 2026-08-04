import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
    await _firebaseAuth.signOut();
    await _googleSignIn.signOut();
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
}
