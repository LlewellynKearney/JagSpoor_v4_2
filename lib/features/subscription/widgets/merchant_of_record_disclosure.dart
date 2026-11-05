import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../alternative_billing_copy.dart';

/// The Google Play alternative-billing **merchant-of-record** disclosure.
///
/// Programme terms require that a user choosing the alternative system
/// (PayFast) is told, on the checkout surface, which legal entity stands
/// behind the payment — and that Google is not responsible for the product,
/// its guarantees, the payment processing or the VAT on those transactions.
///
/// This is the single rendering of that copy so the subscription screen, the
/// paywall and any future checkout surface cannot drift apart. The wording
/// lives on [AlternativeBillingCopy.merchantOfRecordDisclosure].
class MerchantOfRecordDisclosure extends StatelessWidget {
  const MerchantOfRecordDisclosure({super.key, this.theme});

  /// Optional theme override; falls back to the process-wide controller.
  final ThemeController? theme;

  @override
  Widget build(BuildContext context) {
    final t = theme ?? ThemeController.instance;
    return Text(
      AlternativeBillingCopy.merchantOfRecordDisclosure,
      key: const ValueKey('merchantOfRecordDisclosure'),
      style: TextStyle(
        color: t.subtitleColor,
        fontSize: 10,
        height: 1.35,
      ),
    );
  }
}
