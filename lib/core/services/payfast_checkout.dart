import 'package:url_launcher/url_launcher.dart';

/// PayFast **sandbox** checkout launcher.
///
/// JagSpoor's published sandbox test credentials (NOT production secrets).
/// Swap `merchantId` / `merchantKey` / host for live values before launch.
class PayfastCheckout {
  PayfastCheckout._();

  static const String _sandboxHost = 'https://sandbox.payfast.co.za';
  static const String _merchantId = '10000100';
  static const String _merchantKey = '46f0cd694581a';

  /// Instant Transaction Notification endpoint — the deployed
  /// `payfastITNHandler` Cloud Function. Update region/host after deploy.
  static const String notifyUrl =
      'https://us-central1-jagspoor.cloudfunctions.net/payfastITNHandler';

  /// Base deep-link host for the PayFast return flow (a Firebase Dynamic Links
  /// `*.page.link` domain). The per-booking return URL is built via
  /// [buildReturnUrl] so the app can detect a return from the browser checkout
  /// and prompt to refresh the booking status. (v4.5 to-do Item #10.)
  static const String returnBaseUrl = 'https://jagspoor.page.link/payment-return';
  static const String cancelUrl = 'https://jagspoor.web.app/booking-cancelled';

  /// Builds the per-booking PayFast `return_url` deep link carrying the booking
  /// id and a success flag, e.g.
  /// `https://jagspoor.page.link/payment-return?booking_id=<id>&status=success`.
  ///
  /// The marketplace's app-resume lifecycle listener checks for this link shape
  /// to detect that the user returned from the browser checkout and prompts a
  /// booking-status refresh.
  static String buildReturnUrl(String bookingId) {
    final params = <String, String>{
      'booking_id': bookingId,
      'status': 'success',
    };
    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$returnBaseUrl?$query';
  }

  /// Builds the PayFast sandbox payment URL from [bookingId] + [amount] and
  /// launches it in the external browser. The booking id is passed as
  /// `m_payment_id` so the ITN handler can reconcile the payment back to the
  /// booking (it flips the booking `status` to `Paid` on COMPLETE), and as the
  /// `booking_id` query param on the per-booking return deep link so the app
  /// can detect the browser-checkout return. (v4.5 to-do Item #10.)
  ///
  /// Returns `false` when the URL cannot be launched (so the caller can show a
  /// graceful SnackBar); `true` when the external checkout was opened.
  static Future<bool> launchDeposit({
    required String bookingId,
    required double amount,
    String? itemName,
  }) async {
    final params = <String, String>{
      'merchant_id': _merchantId,
      'merchant_key': _merchantKey,
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
    final uri = Uri.parse('$_sandboxHost/eng/process?$query');

    if (!await canLaunchUrl(uri)) {
      return false;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return true;
  }
}
