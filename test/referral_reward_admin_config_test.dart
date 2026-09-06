import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/referral/models/referral_conversion.dart';
import 'package:jagspoor/features/referral/models/referral_reward_config.dart';
import 'package:jagspoor/features/referral/services/referral_repository.dart';

/// Admin Portal referral-rewards config — validation + repository
/// persistence contract for `admin_config/referral_rewards`.
///
/// Covers [ReferralRewardValidator] (the pure ZAR input validation the Admin
/// settings card enforces) and [ReferralRepository.saveRewardConfig] (the
/// merge write + negative clamp) against a real `FakeFirebaseFirestore`.
void main() {
  FakeFirebaseFirestore();

  group('ReferralRewardValidator', () {
    test('accepts a positive whole amount', () {
      expect(ReferralRewardValidator.validateZar('150'), isNull);
      expect(ReferralRewardValidator.validateZar('19.99'), isNull);
      expect(ReferralRewardValidator.validateZar('0'), isNull);
      expect(ReferralRewardValidator.validateZar('0.00'), isNull);
    });

    test('tolerates an optional R prefix + surrounding spaces', () {
      expect(ReferralRewardValidator.validateZar(' R 199.99 '), isNull);
      expect(ReferralRewardValidator.validateZar('R150'), isNull);
    });

    test('rejects blank input', () {
      expect(ReferralRewardValidator.validateZar(null), isNotNull);
      expect(ReferralRewardValidator.validateZar(''), isNotNull);
      expect(ReferralRewardValidator.validateZar('   '), isNotNull);
    });

    test('rejects non-numeric input', () {
      expect(ReferralRewardValidator.validateZar('abc'), isNotNull);
      expect(ReferralRewardValidator.validateZar('1x5'), isNotNull);
      expect(ReferralRewardValidator.validateZar('--'), isNotNull);
    });

    test('rejects negative amounts', () {
      final message = ReferralRewardValidator.validateZar('-10');
      expect(message, isNotNull);
      expect(message, contains('negative'));
      expect(ReferralRewardValidator.validateZar('-0.01'), isNotNull);
      expect(ReferralRewardValidator.validateZar('R -50'), isNotNull);
    });

    test('tryParseZar parses only valid amounts', () {
      expect(ReferralRewardValidator.tryParseZar('150'), 150.0);
      expect(ReferralRewardValidator.tryParseZar('R 19.99'), 19.99);
      expect(ReferralRewardValidator.tryParseZar('  '), isNull);
      expect(ReferralRewardValidator.tryParseZar('abc'), isNull);
    });
  });

  group('ReferralRepository.saveRewardConfig', () {
    late FakeFirebaseFirestore firestore;
    late ReferralRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = ReferralRepository.forTesting(
        firestore: firestore,
        currentUserIdResolver: () => 'admin-1',
      );
    });

    test('persists a full config to admin_config/referral_rewards', () async {
      await repo.saveRewardConfig(const ReferralRewardConfig(
        hunterRewardZAR: 49.99,
        outfitterRewardZAR: 499.99,
      ));

      final snap = await firestore
          .collection('admin_config')
          .doc(ReferralRewards.adminConfigDocId)
          .get();
      expect(snap.exists, isTrue);
      final data = snap.data()!;
      expect(data['hunterRewardZAR'], 49.99);
      expect(data['outfitterRewardZAR'], 499.99);
    });

    test('merge-writes without clobbering unrelated admin_config fields',
        () async {
      await firestore.collection('admin_config').doc('referral_rewards').set({
        'hunterRewardZAR': 19.99,
        'outfitterRewardZAR': 199.99,
        'otherField': 'keep-me',
      });

      await repo.saveRewardConfig(const ReferralRewardConfig(
        hunterRewardZAR: 25.0,
        outfitterRewardZAR: 250.0,
      ));

      final data = (await firestore
              .collection('admin_config')
              .doc(ReferralRewards.adminConfigDocId)
              .get())
          .data()!;
      expect(data['hunterRewardZAR'], 25.0);
      expect(data['outfitterRewardZAR'], 250.0);
      expect(data['otherField'], 'keep-me');
    });

    test('clamps negative amounts to zero (never persists a negative reward)',
        () async {
      await repo.saveRewardConfig(const ReferralRewardConfig(
        hunterRewardZAR: -10,
        outfitterRewardZAR: -0.01,
      ));

      final data = (await firestore
              .collection('admin_config')
              .doc(ReferralRewards.adminConfigDocId)
              .get())
          .data()!;
      expect(data['hunterRewardZAR'], 0.0);
      expect(data['outfitterRewardZAR'], 0.0);
    });

    test('save -> load round-trips the live document', () async {
      await repo.saveRewardConfig(const ReferralRewardConfig(
        hunterRewardZAR: 39.5,
        outfitterRewardZAR: 399.5,
      ));

      final config = await repo.loadRewardConfig();
      expect(config.hunterRewardZAR, 39.5);
      expect(config.outfitterRewardZAR, 399.5);
    });

    test('loadRewardConfig reads the values saved by saveRewardConfig', () async {
      await repo.saveRewardConfig(const ReferralRewardConfig(
        hunterRewardZAR: 59.99,
        outfitterRewardZAR: 599.99,
      ));
      final config = await repo.loadRewardConfig();
      expect(config.hunterRewardZAR, 59.99);
      expect(config.outfitterRewardZAR, 599.99);
    });
  });
}