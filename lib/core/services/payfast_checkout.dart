import 'package:url_launcher/url_launcher.dart';

import '../../features/hunter_mode/models/farm_config.dart';

/// PayFast **sandbox** checkout launcher.
///
/// JagSpoor's published sandbox test credentials (NOT production secrets).
/// Swap `merchantId` / `merchantKey` / host for live values before launch.
class PayfastCheckout {
  PayfastCheckout._();

  static const String _sandboxHost = 'https://sandbox.payfast.co.za';
  static const String _liveHost = 'https://www.payfast.co.za';
  static const String _merchantId = '10000100';
  static const String _merchantKey = '46f0cd694581a';

  /// PayFast merchant account registration URL — opened by the farm-config
  /// "Register a new PayFast account" button when a farm has no PayFast
  /// profile attached.
  static const String payfastRegistrationUrl =
      'https://payfast.co.za/apply-now';

  /// Instant Transaction Notification endpoint — the deployed
  /// `payfastITNHandler` Cloud Function. Update region/host after deploy.
  static const String notifyUrl =
      'https://us-central1-jagspoor.cloudfunctions.net/payfastITNHandler';

  /// Base custom-scheme return URI for the PayFast return flow. Uses a direct
  /// app deep-link custom scheme (`jagspoor://`) instead of a Firebase
  /// Dynamic Links `*.page.link` domain (Dynamic Links is deprecated /
  /// unconfigured for this project), so the per-booking return URL is resolved
  /// by the OS intent filter on `MainActivity` (`jagspoor://payment-return`)
  /// and the app-resume lifecycle listener detects the browser-checkout
  /// return. (v4.5 to-do Item #10; migrated off page.link in Phase 45.)
  static const String returnScheme = 'jagspoor://payment-return';
  static const String cancelUrl = 'https://jagspoor.web.app/booking-cancelled';

  /// Builds the per-booking PayFast `return_url` custom-scheme deep link
  /// carrying the booking id and a success flag, e.g.
  /// `jagspoor://payment-return?booking_id=<id>&status=success`.
  ///
  /// The Android `MainActivity` intent filter (`android:scheme="jagspoor"`
  /// `android:host="payment-return"`) captures this URI when the browser
  /// redirects back to the app, and the marketplace's app-resume lifecycle
  /// listener prompts a booking-status refresh.
  static String buildReturnUrl(String bookingId) {
    final encodedId = Uri.encodeComponent(bookingId);
    return '$returnScheme?booking_id=$encodedId&status=success';
  }

  /// Resolves the PayFast host + merchant credentials for a deposit launch.
  /// When [farmProfile] is configured (`isConfigured`), the farm's merchant
  /// id / key / live-vs-sandbox host are used so the deposit routes directly
  /// to the farm's PayFast account; otherwise the platform default sandbox
  /// credentials are used. Pure / unit-testable.
  static PayFastEndpoint resolveEndpoint([
    FarmPayFastProfile? farmProfile,
  ]) {
    if (farmProfile != null && farmProfile.isConfigured) {
      return PayFastEndpoint(
        host: farmProfile.useLive ? _liveHost : _sandboxHost,
        merchantId: farmProfile.merchantId,
        merchantKey: farmProfile.merchantKey,
      );
    }
    return PayFastEndpoint(
      host: _sandboxHost,
      merchantId: _merchantId,
      merchantKey: _merchantKey,
    );
  }

  /// Builds the PayFast payment URL from [bookingId] + [amount] and launches
  /// it in the external browser. When [farmProfile] is supplied and
  /// configured, the deposit routes to that farm's PayFast merchant account
  /// (per-farm direct payout routing); otherwise the platform default sandbox
  /// merchant is used. The booking id is passed as `m_payment_id` so the ITN
  /// handler can reconcile the payment back to the booking (it flips the
  /// booking `status` to `Paid` on COMPLETE), and as the `booking_id` query
  /// param on the per-booking return deep link so the app can detect the
  /// browser-checkout return.
  ///
  /// Returns `false` when the URL cannot be launched (so the caller can show a
  /// graceful SnackBar); `true` when the external checkout was opened.
  static Future<bool> launchDeposit({
    required String bookingId,
    required double amount,
    String? itemName,
    FarmPayFastProfile? farmProfile,
  }) async {
    final endpoint = resolveEndpoint(farmProfile);
    final params = <String, String>{
      'merchant_id': endpoint.merchantId,
      'merchant_key': endpoint.merchantKey,
      'return_url': buildReturnUrl(bookingId),
      'cancel_url': cancelUrl,
      'notify_url': notifyUrl,
      'm_payment_id': bookingId,
      'amount': amount.toStringAsFixed(2),
      'item_name': itemName ?? 'JagSpoor Booking $bookingId',
    };
    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final uri = Uri.parse('${endpoint.host}/eng/process?$query');

    if (!await canLaunchUrl(uri)) {
      return false;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return true;
  }

  /// Opens the PayFast merchant-account registration page in the external
  /// browser. Used by the farm-config "Register a new PayFast account" button.
  /// Returns whether a browser accepted the handoff.
  static Future<bool> openPayFastRegistration() async {
    final uri = Uri.parse(payfastRegistrationUrl);
    if (!await canLaunchUrl(uri)) return false;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return true;
  }
}

/// Resolved PayFast endpoint (host + merchant credentials) for a deposit
/// launch — either a per-farm profile or the platform default. Pure value
/// type returned by [PayfastCheckout.resolveEndpoint].
class PayFastEndpoint {
  final String host;
  final String merchantId;
  final String merchantKey;

  const PayFastEndpoint({
    required this.host,
    required this.merchantId,
    required this.merchantKey,
  });

  bool get isLive => host.contains('://www.payfast.co.za');

  @override
  String toString() =>
      'PayFastEndpoint($merchantId @ ${isLive ? "live" : "sandbox"})';
}
