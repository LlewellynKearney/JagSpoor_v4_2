/// The exact alternative-billing compliance copy Google requires on the
/// choice / checkout surface, plus the dispute contact published on the Play
/// Console alternative-billing form.
///
/// Kept as named constants (not inline literals) so the compliance copy is
/// asserted verbatim by tests and cannot drift silently. Lives in its own
/// file so the subscription screen, the paywall and the shared disclosure
/// widget can all read the same source without importing the screen.
class AlternativeBillingCopy {
  AlternativeBillingCopy._();

  /// The required service-fee disclosure.
  static const String disclosure =
      'You can choose to pay with Google Play or with an alternative billing '
      'system (PayFast). Google will charge a service fee for alternative '
      'billing transactions.';

  /// The alternative-billing **merchant-of-record** disclosure Google's
  /// programme terms require on the choice / checkout surface.
  ///
  /// It must name the legal entity behind the alternative payment and state
  /// that JagSpoor (not Google) is responsible for the product, its
  /// guarantees, the payment processing and the VAT on those transactions.
  /// Kept as a named constant so the compliance copy is asserted verbatim.
  static const String merchantOfRecordDisclosure =
      'JAGSPOOR VELD AND VENTURES (PTY) LTD is the merchant of record. '
      'JAGSPOOR, not Google, is responsible for this product, including '
      'guarantees and payment processing. VAT/taxes on PayFast transactions '
      'are handled by JAGSPOOR.';

  /// Short caption rendering [merchantOfRecordDisclosure] beneath the PayFast
  /// checkout CTA. Rendered in the muted subtitle colour at the same small
  /// size as the other checkout fine print.
  static const String merchantOfRecordCaption = merchantOfRecordDisclosure;

  /// The dispute route published on the Play Console form.
  static const String disputeEmail = 'support@jagspoor.co.za';

  /// The dispute link text.
  static const String dispute =
      'To dispute unauthorized alternative billing transactions, contact '
      'support@jagspoor.co.za';

  /// The mailto: target for the dispute link.
  static const String disputeMailto = 'mailto:support@jagspoor.co.za';
}
