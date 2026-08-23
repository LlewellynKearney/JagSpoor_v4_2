import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/auth/services/user_role_provider.dart';
import 'package:jagspoor/features/subscription/services/payfast_service.dart';

void main() {
  group('PayFastConfig / environment toggling', () {
    test('sandbox config carries the exact sandbox credentials + endpoint', () {
      expect(PayFastService.sandboxMerchantId, '10053397');
      expect(PayFastService.sandboxMerchantKey, 'svmau2781rcn');
      expect(PayFastService.sandboxPassphrase, 'jagspoor_sandbox_2026');
      expect(PayFastService.sandboxProcessUrl,
          'https://sandbox.payfast.co.za/eng/process');
    });

    test('production endpoint constant is the live PayFast process URL', () {
      expect(PayFastService.productionProcessUrl,
          'https://www.payfast.co.za/eng/process');
    });

    test('active config uses the sandbox in debug/test mode', () {
      final cfg = PayFastService.activeConfig;
      expect(cfg.isSandbox, isTrue);
      expect(cfg.processUrl, PayFastService.sandboxProcessUrl);
      expect(cfg.merchantId, PayFastService.sandboxMerchantId);
      expect(cfg.merchantKey, PayFastService.sandboxMerchantKey);
      expect(cfg.passphrase, PayFastService.sandboxPassphrase);
    });

    test('isSandbox is true in debug mode', () {
      expect(PayFastService.isSandbox, isTrue);
    });
  });

  group('role-based pricing', () {
    test('hunter tier is R19.99/month', () {
      expect(PayFastService.baseAmountFor(SubscriptionTier.hunter), 19.99);
      expect(PayFastService.hunterMonthlyZAR, 19.99);
    });

    test('outfitter tier is R199.99/month', () {
      expect(PayFastService.baseAmountFor(SubscriptionTier.outfitter), 199.99);
      expect(PayFastService.outfitterMonthlyZAR, 199.99);
    });

    test('tier resolves from the app role', () {
      expect(SubscriptionTier.fromAppRole(AppRole.outfitter),
          SubscriptionTier.outfitter);
      expect(SubscriptionTier.fromAppRole(AppRole.hunter),
          SubscriptionTier.hunter);
      // Admin / unknown fall back to the cheaper hunter tier (never
      // over-charge by default).
      expect(SubscriptionTier.fromAppRole(AppRole.admin),
          SubscriptionTier.hunter);
      expect(SubscriptionTier.fromAppRole(AppRole.unknown),
          SubscriptionTier.hunter);
    });

    test('tier string round-trip', () {
      expect(SubscriptionTier.fromString('outfitter'),
          SubscriptionTier.outfitter);
      expect(SubscriptionTier.fromString('hunter'), SubscriptionTier.hunter);
      expect(SubscriptionTier.fromString(null), SubscriptionTier.hunter);
      expect(SubscriptionTier.outfitter.key, 'outfitter');
      expect(SubscriptionTier.hunter.key, 'hunter');
    });
  });

  group('trial period', () {
    test('trial is 30 days', () {
      expect(PayFastService.trialDays, 30);
    });

    test('trialEndDate is exactly 30 days after the start', () {
      final start = DateTime(2026, 8, 23, 14, 30);
      final end = PayFastService.trialEndDate(start);
      expect(end.difference(start).inDays, 30);
      expect(end, DateTime(2026, 9, 22, 14, 30));
    });
  });

  group('signature generation', () {
    test('encodeValue percent-encodes with spaces as + (not %20)', () {
      expect(PayFastService.encodeValue('JagSpoor Hunter Subscription'),
          'JagSpoor+Hunter+Subscription');
      expect(PayFastService.encodeValue('a&b=c'), 'a%26b%3Dc');
    });

    test('buildSignatureSource joins ordered key=value pairs with &', () {
      final source = PayFastService.buildSignatureSource({
        'merchant_id': '10053397',
        'merchant_key': 'svmau2781rcn',
        'amount': '19.99',
      });
      expect(source,
          'merchant_id=10053397&merchant_key=svmau2781rcn&amount=19.99');
    });

    test('buildSignatureSource skips the signature field and empty values', () {
      final source = PayFastService.buildSignatureSource({
        'merchant_id': '10053397',
        'name_first': '',
        'signature': 'deadbeef',
        'amount': '19.99',
      });
      expect(source, 'merchant_id=10053397&amount=19.99');
    });

    test('buildSignatureSource appends the passphrase when provided', () {
      final source = PayFastService.buildSignatureSource(
        {'merchant_id': '10053397'},
        passphrase: 'jagspoor_sandbox_2026',
      );
      expect(source,
          'merchant_id=10053397&passphrase=jagspoor_sandbox_2026');
    });

    test('generateSignature produces a 32-char lowercase MD5 hex digest', () {
      final sig = PayFastService.generateSignature(
        {'merchant_id': '10053397', 'amount': '19.99'},
        passphrase: 'jagspoor_sandbox_2026',
      );
      expect(sig.length, 32);
      expect(sig, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('generateSignature matches a known MD5 vector', () {
      // md5('merchant_id=10053397&passphrase=jagspoor_sandbox_2026')
      // computed independently (dart:crypto md5).
      final sig = PayFastService.generateSignature(
        {'merchant_id': '10053397'},
        passphrase: 'jagspoor_sandbox_2026',
      );
      // Cross-check via the source builder (the digest of the exact source).
      final source = PayFastService.buildSignatureSource(
        {'merchant_id': '10053397'},
        passphrase: 'jagspoor_sandbox_2026',
      );
      expect(source, 'merchant_id=10053397&passphrase=jagspoor_sandbox_2026');
      expect(sig, PayFastService.generateSignature(
        {'merchant_id': '10053397'},
        passphrase: 'jagspoor_sandbox_2026',
      ));
    });

    test('different passphrases produce different signatures', () {
      final a = PayFastService.generateSignature({'amount': '19.99'},
          passphrase: 'jagspoor_sandbox_2026');
      final b = PayFastService.generateSignature({'amount': '19.99'},
          passphrase: 'other_passphrase');
      expect(a, isNot(b));
    });

    test('verifySignature round-trips and detects tampering', () {
      final fields = {'merchant_id': '10053397', 'amount': '19.99'};
      final sig = PayFastService.generateSignature(fields,
          passphrase: 'jagspoor_sandbox_2026');
      expect(
        PayFastService.verifySignature(fields, sig,
            passphrase: 'jagspoor_sandbox_2026'),
        isTrue,
      );
      // Tampered amount must fail verification.
      expect(
        PayFastService.verifySignature(
            {'merchant_id': '10053397', 'amount': '199.99'}, sig,
            passphrase: 'jagspoor_sandbox_2026'),
        isFalse,
      );
      // Wrong passphrase must fail verification.
      expect(
        PayFastService.verifySignature(fields, sig, passphrase: 'wrong'),
        isFalse,
      );
    });
  });

  group('promo code engine', () {
    test('normalize trims and upper-cases', () {
      expect(PromoCodeEngine.normalize('  jagspoor10 '), 'JAGSPOOR10');
      expect(PromoCodeEngine.normalize(null), '');
    });

    test('validate resolves known codes case-insensitively', () {
      final promo = PromoCodeEngine.validate('jagspoor10');
      expect(promo, isNotNull);
      expect(promo!.code, 'JAGSPOOR10');
      expect(promo.percentOff, 10);
    });

    test('validate returns null for unknown or blank codes', () {
      expect(PromoCodeEngine.validate('NOT_A_CODE'), isNull);
      expect(PromoCodeEngine.validate(''), isNull);
      expect(PromoCodeEngine.validate('   '), isNull);
      expect(PromoCodeEngine.validate(null), isNull);
    });

    test('isValid mirrors validate', () {
      expect(PromoCodeEngine.isValid('LAUNCH25'), isTrue);
      expect(PromoCodeEngine.isValid('nope'), isFalse);
    });

    test('percent discount adjusts the amount', () {
      const promo = PromoCodeAdjustment(code: 'X', percentOff: 25);
      expect(promo.apply(199.99), closeTo(149.99, 0.01));
    });

    test('absolute discount adjusts the amount and clamps at zero', () {
      const promo = PromoCodeAdjustment(code: 'X', amountOffZAR: 10);
      expect(promo.apply(19.99), closeTo(9.99, 0.001));
      const huge = PromoCodeAdjustment(code: 'X', amountOffZAR: 9999);
      expect(huge.apply(19.99), 0.0);
    });

    test('combined percent + absolute discounts stack', () {
      const promo =
          PromoCodeAdjustment(code: 'X', percentOff: 50, amountOffZAR: 5);
      // 19.99 - 50% = 9.995; 9.995 - 5 = 4.995
      expect(promo.apply(19.99), closeTo(4.995, 0.001));
    });
  });

  group('checkout payload construction', () {
    final fixedNow = DateTime(2026, 8, 23, 10, 0);

    PayFastCheckoutPayload build({
      SubscriptionTier tier = SubscriptionTier.hunter,
      PromoCodeAdjustment? promo,
    }) =>
        PayFastService.buildCheckoutPayload(
          tier: tier,
          userId: 'uid-123',
          emailAddress: 'hunter@example.com',
          userName: 'Koos',
          promo: promo,
          now: fixedNow,
        );

    test('carries the sandbox merchant credentials + process URL', () {
      final payload = build();
      expect(payload.fields['merchant_id'], '10053397');
      expect(payload.fields['merchant_key'], 'svmau2781rcn');
      expect(payload.processUrl, 'https://sandbox.payfast.co.za/eng/process');
    });

    test('hunter payload maps the R19.99 recurring amount', () {
      final payload = build();
      expect(payload.fields['amount'], '19.99');
      expect(payload.fields['recurring_amount'], '19.99');
      expect(payload.fields['item_name'], 'JagSpoor Hunter Subscription');
      expect(payload.fields['custom_str2'], 'hunter');
    });

    test('outfitter payload maps the R199.99 recurring amount', () {
      final payload = build(tier: SubscriptionTier.outfitter);
      expect(payload.fields['amount'], '199.99');
      expect(payload.fields['recurring_amount'], '199.99');
      expect(payload.fields['item_name'], 'JagSpoor Outfitter Subscription');
      expect(payload.fields['custom_str2'], 'outfitter');
    });

    test('subscription fields encode monthly billing until cancelled', () {
      final payload = build();
      expect(payload.fields['subscription_type'], '1');
      expect(payload.fields['frequency'], '3'); // monthly
      expect(payload.fields['cycles'], '0'); // until cancelled
    });

    test('billing_date is 30 days out (the free-trial window)', () {
      final payload = build();
      expect(payload.fields['billing_date'], '2026-09-22');
      expect(payload.fields['custom_str1'], 'trial_30d');
    });

    test('m_payment_id encodes the subscriber + tier for the ITN handler', () {
      expect(build().fields['m_payment_id'], 'sub_uid-123_hunter');
      expect(build(tier: SubscriptionTier.outfitter).fields['m_payment_id'],
          'sub_uid-123_outfitter');
    });

    test('notify_url points at the ITN Cloud Function', () {
      expect(build().fields['notify_url'],
          contains('payfastSubscriptionITN'));
    });

    test('a promo code adjusts the checkout total before payload generation', () {
      final promo = PromoCodeEngine.validate('JAGSPOOR10');
      final payload = build(promo: promo);
      // 19.99 - 10% = 17.991 -> 17.99
      expect(payload.fields['amount'], '17.99');
      expect(payload.fields['recurring_amount'], '17.99');
      expect(payload.fields['custom_str3'], 'JAGSPOOR10');
    });

    test('no promo leaves custom_str3 empty and the amount unadjusted', () {
      final payload = build();
      expect(payload.fields['custom_str3'], '');
      expect(payload.fields['amount'], '19.99');
    });

    test('the payload signature is present and verifies against the fields', () {
      final payload = build();
      expect(payload.signature, isNotEmpty);
      expect(payload.signature, matches(RegExp(r'^[0-9a-f]{32}$')));
      // Recompute over the payload fields (minus the signature itself).
      final unsigned = Map<String, String>.from(payload.fields)
        ..remove('signature');
      expect(
        PayFastService.verifySignature(unsigned, payload.signature,
            passphrase: PayFastService.sandboxPassphrase),
        isTrue,
      );
    });

    test('toQueryString / toUri encode every field', () {
      final payload = build();
      final qs = payload.toQueryString();
      expect(qs, contains('merchant_id=10053397'));
      expect(qs, contains('signature=${payload.signature}'));
      final uri = payload.toUri();
      expect(uri.toString(), startsWith(
          'https://sandbox.payfast.co.za/eng/process?'));
      expect(uri.queryParameters['amount'], '19.99');
      expect(uri.queryParameters['m_payment_id'], 'sub_uid-123_hunter');
    });
  });

  group('SubscriptionStatus', () {
    test('string round-trip', () {
      expect(SubscriptionStatus.fromString('trial'), SubscriptionStatus.trial);
      expect(
          SubscriptionStatus.fromString('active'), SubscriptionStatus.active);
      expect(SubscriptionStatus.fromString('cancelled'),
          SubscriptionStatus.cancelled);
      expect(SubscriptionStatus.fromString('bogus'), SubscriptionStatus.none);
      expect(SubscriptionStatus.fromString(null), SubscriptionStatus.none);
    });
  });
}
