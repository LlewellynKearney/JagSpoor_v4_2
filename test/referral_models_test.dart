import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/referral/models/referral_conversion.dart';
import 'package:jagspoor/features/referral/models/referral_profile.dart';
import 'package:jagspoor/features/referral/models/referral_reward_config.dart';

void main() {
  // Construct a FakeFirebaseFirestore FIRST, before any test touches
  // `FieldValue.serverTimestamp()` — fake_cloud_firestore installs its mock
  // FieldValuePlatform as a side-effect of construction (see
  // optic_log_service_test.dart for the documented pattern).
  FakeFirebaseFirestore();

  group('ReferralProfile', () {
    test('fromMap hydrates all fields + aliases', () {
      final profile = ReferralProfile.fromMap({
        'userId': 'uid-1',
        'referralCode': 'jagspoor-7q3x',
        'bankingDetailsProvided': true,
        'bankAccountHolder': 'Jaco van Rensburg',
        'bankName': 'Standard Bank',
        'bankAccountNumber': '0045612345678',
        'bankAccountType': 'Current',
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 6)),
      }, id: 'uid-1');
      expect(profile.userId, 'uid-1');
      // Codes are normalized to upper-case.
      expect(profile.referralCode, 'JAGSPOOR-7Q3X');
      expect(profile.bankingDetailsProvided, isTrue);
      expect(profile.bankAccountHolder, 'Jaco van Rensburg');
      expect(profile.bankName, 'Standard Bank');
      expect(profile.bankAccountNumber, '0045612345678');
      expect(profile.bankAccountType, 'Current');
      expect(profile.createdAt, DateTime(2026, 9, 6));
      expect(profile.hasReferralCode, isTrue);
      expect(profile.hasPayoutDetails, isTrue);
    });

    test('fromMap tolerates the code + banking field aliases', () {
      final profile = ReferralProfile.fromMap({
        'userId': 'uid-2',
        'code': 'ABCD1234',
        'bankHolder': 'A. Smit',
        'bankAccountNr': '123456789012',
        'accountType': 'Savings',
      }, id: 'uid-2');
      expect(profile.referralCode, 'ABCD1234');
      expect(profile.bankAccountHolder, 'A. Smit');
      expect(profile.bankAccountNumber, '123456789012');
      expect(profile.bankAccountType, 'Savings');
      // bankingDetailsProvided is driven by the presence of the submap in the
      // alias path — a bare banking fields doc defaults to false.
      expect(profile.bankingDetailsProvided, isFalse);
    });

    test('fromMap defaults safely for a partial doc', () {
      final profile = ReferralProfile.fromMap({'userId': 'uid-3'}, id: 'uid-3');
      expect(profile.referralCode, '');
      expect(profile.bankingDetailsProvided, isFalse);
      expect(profile.bankAccountHolder, '');
      expect(profile.bankName, '');
      expect(profile.bankAccountNumber, '');
      expect(profile.bankAccountType, '');
      expect(profile.hasReferralCode, isFalse);
      expect(profile.hasPayoutDetails, isFalse);
      expect(profile.createdAt, isNull);
      expect(profile.updatedAt, isNull);
    });

    test('toMap round-trips + omits empty banking fields', () {
      final profile = ReferralProfile(
        userId: 'uid-4',
        referralCode: 'ZZ9XYZ',
        createdAt: DateTime(2026, 9, 6, 8, 0),
      );
      final map = profile.toMap();
      expect(map['userId'], 'uid-4');
      expect(map['referralCode'], 'ZZ9XYZ');
      expect(map['bankingDetailsProvided'], isFalse);
      // No banking fields -> not serialized.
      expect(map.containsKey('bankAccountHolder'), isFalse);
      expect(map.containsKey('bankName'), isFalse);
      expect(map.containsKey('bankAccountNumber'), isFalse);
      expect(map['createdAt'], isA<Timestamp>());

      final filled = profile.copyWith(
        bankAccountHolder: 'B. Botha',
        bankName: 'FNB',
        bankAccountNumber: '987654321012',
        bankingDetailsProvided: true,
      );
      final filledMap = filled.toMap();
      expect(filledMap['bankAccountHolder'], 'B. Botha');
      expect(filledMap['bankName'], 'FNB');
      expect(filledMap['bankAccountNumber'], '987654321012');
      expect(filledMap['bankingDetailsProvided'], isTrue);
      // copyWith preserves createdAt.
      expect(filled.createdAt, DateTime(2026, 9, 6, 8, 0));
    });

    test('copyWith overrides only the supplied fields', () {
      final updated = ReferralProfile(
        userId: 'uid-5',
        referralCode: 'CODE1',
      ).copyWith(referralCode: 'CODE2');
      expect(updated.referralCode, 'CODE2');
      expect(updated.userId, 'uid-5');
      expect(updated.bankingDetailsProvided, isFalse);
      expect(updated.hasPayoutDetails, isFalse);
    });
  });

  group('ReferralConversion', () {
    test('fromMap hydrates all fields + status/tier enums', () {
      final conversion = ReferralConversion.fromMap({
        'referrerId': 'uid-referrer',
        'referredUserId': 'uid-new',
        'referralCode': 'jagspoor-7q3x',
        'subscriptionTier': 'outfitter',
        'status': 'rewarded',
        'rewardAmountZAR': 199.99,
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 6)),
      }, id: 'conv-1');
      expect(conversion.id, 'conv-1');
      expect(conversion.referrerId, 'uid-referrer');
      expect(conversion.referredUserId, 'uid-new');
      expect(conversion.referralCode, 'JAGSPOOR-7Q3X');
      expect(conversion.subscriptionTier,
          ReferralSubscriptionTier.outfitter);
      expect(conversion.status, ReferralConversionStatus.rewarded);
      expect(conversion.rewardAmountZAR, 199.99);
      expect(conversion.createdAt, DateTime(2026, 9, 6));
    });

    test('fromMap tolerates legacy aliases + defaults unknown enums', () {
      final conversion = ReferralConversion.fromMap({
        'referredBy': 'uid-referrer',
        'referredUid': 'uid-new',
        'code': 'ABC123',
        'tier': 'outfitter',
        'status': 'pending',
      }, id: 'conv-2');
      expect(conversion.referrerId, 'uid-referrer');
      expect(conversion.referredUserId, 'uid-new');
      expect(conversion.referralCode, 'ABC123');
      expect(conversion.subscriptionTier,
          ReferralSubscriptionTier.outfitter);
      expect(conversion.status, ReferralConversionStatus.pending);
      expect(conversion.rewardAmountZAR, 0.0);

      final unknown = ReferralConversion.fromMap({
        'referrerId': 'a',
        'referredUserId': 'b',
        'subscriptionTier': 'premium-unknown',
        'status': 'weird',
      }, id: 'conv-3');
      expect(unknown.subscriptionTier, ReferralSubscriptionTier.hunter);
      expect(unknown.status, ReferralConversionStatus.pending);
    });

    test('toMap omits a zero reward + round-trips', () {
      final pending = ReferralConversion(
        id: 'conv-4',
        referrerId: 'uid-referrer',
        referredUserId: 'uid-new',
        referralCode: 'CODE1',
        subscriptionTier: ReferralSubscriptionTier.hunter,
      );
      final map = pending.toMap();
      expect(map['status'], 'pending');
      expect(map['subscriptionTier'], 'hunter');
      expect(map.containsKey('rewardAmountZAR'), isFalse);

      final rewarded = pending.copyWith(
        status: ReferralConversionStatus.rewarded,
        rewardAmountZAR: 19.99,
      );
      final rewardedMap = rewarded.toMap();
      expect(rewardedMap['status'], 'rewarded');
      expect(rewardedMap['rewardAmountZAR'], 19.99);
    });

    test('status + tier enum parsing', () {
      expect(ReferralConversionStatus.fromString('rewarded'),
          ReferralConversionStatus.rewarded);
      expect(ReferralConversionStatus.fromString('REJECTED'),
          ReferralConversionStatus.rejected);
      expect(ReferralConversionStatus.fromString(null),
          ReferralConversionStatus.pending);
      expect(ReferralConversionStatus.fromString('bogus'),
          ReferralConversionStatus.pending);
      expect(ReferralSubscriptionTier.fromString('OUTFITTER'),
          ReferralSubscriptionTier.outfitter);
      expect(ReferralSubscriptionTier.fromString(null),
          ReferralSubscriptionTier.hunter);
    });
  });

  group('ReferralRewards + ReferralRewardConfig', () {
    test('documented defaults + tier mapping', () {
      expect(ReferralRewards.defaultHunterRewardZAR, 19.99);
      expect(ReferralRewards.defaultOutfitterRewardZAR, 199.99);
      expect(ReferralRewards.adminConfigDocId, 'referral_rewards');
      expect(ReferralRewards.amountFor(ReferralSubscriptionTier.hunter),
          19.99);
      expect(ReferralRewards.amountFor(ReferralSubscriptionTier.outfitter),
          199.99);
      expect(ReferralRewards.labelFor(ReferralSubscriptionTier.hunter),
          'R 19.99');
      expect(ReferralRewards.labelFor(ReferralSubscriptionTier.outfitter),
          'R 199.99');
    });

    test('fromMap hydrates the dynamic amounts (numeric strings tolerated)', () {
      final config = ReferralRewardConfig.fromMap({
        'hunterRewardZAR': '25',
        'outfitterRewardZAR': '250',
      });
      expect(config.hunterRewardZAR, 25.0);
      expect(config.outfitterRewardZAR, 250.0);
      expect(config.amountFor(ReferralSubscriptionTier.hunter), 25.0);
      expect(config.amountFor(ReferralSubscriptionTier.outfitter), 250.0);
    });

    test('fromMap tolerates aliases + clamps negatives + falls back', () {
      final aliased = ReferralRewardConfig.fromMap({
        'hunter': '30',
        'outfitterAmountZAR': '-5',
      });
      expect(aliased.hunterRewardZAR, 30.0);
      expect(aliased.outfitterRewardZAR, 0.0,
          reason: 'negative rewards are clamped to zero');

      final defaults = ReferralRewardConfig.fromMap(null);
      expect(defaults.hunterRewardZAR,
          ReferralRewards.defaultHunterRewardZAR);
      expect(defaults.outfitterRewardZAR,
          ReferralRewards.defaultOutfitterRewardZAR);

      final empty = ReferralRewardConfig.fromMap({});
      expect(empty.hunterRewardZAR, ReferralRewards.defaultHunterRewardZAR);
      expect(empty.outfitterRewardZAR,
          ReferralRewards.defaultOutfitterRewardZAR);
    });

    test('toMap writes the canonical keys', () {
      final config = ReferralRewardConfig(hunterRewardZAR: 20, outfitterRewardZAR: 200);
      final map = config.toMap();
      expect(map['hunterRewardZAR'], 20.0);
      expect(map['outfitterRewardZAR'], 200.0);
    });
  });

  group('collection-name contract', () {
    test('constants point at the Phase-1 collections', () {
      expect(kReferralProfilesCollection, 'referral_profiles');
      expect(kReferralConversionsCollection, 'referral_conversions');
      expect(kAdminConfigCollection, 'admin_config');
    });

    test('referral code alphabet excludes ambiguous characters', () {
      expect(kReferralCodeAlphabet.contains('0'), isFalse);
      expect(kReferralCodeAlphabet.contains('O'), isFalse);
      expect(kReferralCodeAlphabet.contains('1'), isFalse);
      expect(kReferralCodeAlphabet.contains('I'), isFalse);
      final alpha = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      expect(kReferralCodeAlphabet, alpha);
      expect(kReferralCodeMaxLength, 12);
    });
  });
}