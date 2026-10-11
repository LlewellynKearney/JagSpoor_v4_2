import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jagspoor/features/admin/services/usage_analytics_service.dart';
import 'package:jagspoor/features/review/models/review_config.dart';
import 'package:jagspoor/features/review/services/review_service.dart';

void main() {
  // Pin the fake FieldValue platform before any test realises a production
  // FieldValue (see optic_log_service_test.dart for the rationale).
  FakeFirebaseFirestore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReviewService.resetTestSeams();
  });

  group('ReviewConfig', () {
    test('defaults match the documented control-plane seed', () {
      expect(ReviewConfig.defaultEnabled, isTrue);
      expect(ReviewConfig.defaultMinLaunches, 3);
      expect(ReviewConfig.defaultCooldownDays, 30);
      expect(ReviewConfig.defaults.enabled, isTrue);
      expect(ReviewConfig.defaults.minLaunches, 3);
      expect(ReviewConfig.defaults.cooldownDays, 30);
      expect(ReviewConfig.defaults.facebookUrl,
          'https://www.facebook.com/JagSpoor/reviews/');
      expect(ReviewConfig.defaults.playStoreUrl,
          contains('id=za.co.jagspoor.app'));
      expect(ReviewConfig.defaults.promptTitleHunter, 'LOVE JAGSPOOR?');
      expect(ReviewConfig.defaults.promptTitleOutfitter,
          'LOVE JAGSPOOR FOR OUTFITTERS?');
      expect(ReviewConfig.defaults.promptMessage, contains('Bush'));
      expect(ReviewConfig.collection, 'admin_config');
      expect(ReviewConfig.documentId, 'review_config');
    });

    test('promptTitleFor switches on the outfitter flag', () {
      expect(ReviewConfig.defaults.promptTitleFor(false), 'LOVE JAGSPOOR?');
      expect(ReviewConfig.defaults.promptTitleFor(true),
          'LOVE JAGSPOOR FOR OUTFITTERS?');
    });

    test('fromMap hydrates a stored doc (numeric-string tolerant)', () {
      final config = ReviewConfig.fromMap({
        'enabled': 'false',
        'min_launches': '5',
        'cooldown_days': 14,
        'facebook_url': 'https://example.com/fb',
        'play_store_url': 'https://example.com/ps',
        'prompt_title_hunter': 'TITLE H',
        'prompt_title_outfitter': 'TITLE O',
        'prompt_message': 'MSG',
      });
      expect(config.enabled, isFalse);
      expect(config.minLaunches, 5);
      expect(config.cooldownDays, 14);
      expect(config.facebookUrl, 'https://example.com/fb');
      expect(config.playStoreUrl, 'https://example.com/ps');
      expect(config.promptTitleHunter, 'TITLE H');
      expect(config.promptTitleOutfitter, 'TITLE O');
      expect(config.promptMessage, 'MSG');
    });

    test('fromMap falls back to defaults for missing/blank fields', () {
      final config = ReviewConfig.fromMap({'enabled': true});
      expect(config.enabled, isTrue);
      expect(config.minLaunches, ReviewConfig.defaultMinLaunches);
      expect(config.cooldownDays, ReviewConfig.defaultCooldownDays);
      expect(config.facebookUrl, ReviewConfig.defaultFacebookUrl);
      expect(config.promptTitleHunter, ReviewConfig.defaultPromptTitleHunter);
    });

    test('fromMap(null) returns defaults; toMap round-trips', () {
      expect(ReviewConfig.fromMap(null).minLaunches, 3);
      final map = ReviewConfig.defaults.toMap();
      expect(map['enabled'], isTrue);
      expect(map['min_launches'], 3);
      expect(map['cooldown_days'], 30);
      expect(map['facebook_url'], ReviewConfig.defaultFacebookUrl);
      expect(map['play_store_url'], ReviewConfig.defaultPlayStoreUrl);
      expect(map['prompt_title_hunter'], ReviewConfig.defaultPromptTitleHunter);
      expect(map['prompt_title_outfitter'],
          ReviewConfig.defaultPromptTitleOutfitter);
      expect(map['prompt_message'], ReviewConfig.defaultPromptMessage);
    });
  });

  group('ReviewService.shouldPrompt gating', () {
    test('false when the device has not reached min_launches', () async {
      final service = ReviewService.instance;
      service.firestoreForTesting = FakeFirebaseFirestore();
      // 0 launches recorded.
      expect(await service.shouldPrompt(), isFalse);
    });

    test('false when config is disabled', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection(ReviewConfig.collection)
          .doc(ReviewConfig.documentId)
          .set(ReviewConfig.defaults.copyWith(enabled: false).toMap());
      final service = ReviewService.instance;
      service.firestoreForTesting = firestore;

      SharedPreferences.setMockInitialValues({'review_launch_count': 10});
      expect(await service.shouldPrompt(), isFalse);
    });

    test('true once launches >= min_launches and no prior prompt', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection(ReviewConfig.collection)
          .doc(ReviewConfig.documentId)
          .set(ReviewConfig.defaults.toMap());
      final service = ReviewService.instance;
      service.firestoreForTesting = firestore;

      SharedPreferences.setMockInitialValues({'review_launch_count': 3});
      expect(await service.shouldPrompt(), isTrue);
    });

    test('false while within the cooldown window', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection(ReviewConfig.collection)
          .doc(ReviewConfig.documentId)
          .set(ReviewConfig.defaults.toMap());
      final service = ReviewService.instance;
      service.firestoreForTesting = firestore;

      SharedPreferences.setMockInitialValues({
        'review_launch_count': 5,
        'review_last_prompt_at':
            DateTime.now().millisecondsSinceEpoch,
      });
      expect(await service.shouldPrompt(), isFalse);
    });

    test('true again once the cooldown has elapsed', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection(ReviewConfig.collection)
          .doc(ReviewConfig.documentId)
          .set(ReviewConfig.defaults.toMap());
      final service = ReviewService.instance;
      service.firestoreForTesting = firestore;

      final old = DateTime.now().subtract(const Duration(days: 40));
      SharedPreferences.setMockInitialValues({
        'review_launch_count': 5,
        'review_last_prompt_at': old.millisecondsSinceEpoch,
      });
      expect(await service.shouldPrompt(), isTrue);
    });

    test('fails open to defaults when Firestore is unavailable', () async {
      // No firestoreForTesting + no initialised Firebase -> loadConfig returns
      // the documented defaults (enabled), so the launch gate alone decides.
      final service = ReviewService.instance;
      SharedPreferences.setMockInitialValues({'review_launch_count': 3});
      expect(await service.shouldPrompt(), isTrue);
    });
  });

  group('ReviewService.recordLaunch / markPrompted', () {
    test('recordLaunch increments the persisted device counter', () async {
      final service = ReviewService.instance;
      expect(await service.launchCount(), 0);
      await service.recordLaunch();
      await service.recordLaunch();
      expect(await service.launchCount(), 2);
    });

    test('markPrompted stamps the last-prompt time', () async {
      final service = ReviewService.instance;
      service.firestoreForTesting = FakeFirebaseFirestore();
      expect(await service.lastPromptAt(), isNull);
      await service.markPrompted();
      expect(await service.lastPromptAt(), isNotNull);
    });
  });

  group('ReviewService.ensureConfig', () {
    test('creates admin_config/review_config with the seed when absent',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = ReviewService.instance;
      service.firestoreForTesting = firestore;

      await service.ensureConfig();

      final snap = await firestore
          .collection(ReviewConfig.collection)
          .doc(ReviewConfig.documentId)
          .get();
      expect(snap.exists, isTrue);
      final data = snap.data()!;
      expect(data['enabled'], isTrue);
      expect(data['min_launches'], 3);
      expect(data['cooldown_days'], 30);
      expect(data['facebook_url'], 'https://www.facebook.com/JagSpoor/reviews/');
      expect(data['play_store_url'], ReviewConfig.defaultPlayStoreUrl);
      expect(data['prompt_title_hunter'], 'LOVE JAGSPOOR?');
      expect(data['prompt_title_outfitter'], 'LOVE JAGSPOOR FOR OUTFITTERS?');
      expect(data['prompt_message'], contains('Bush'));
      expect(data.containsKey('updated_at'), isTrue);
    });

    test('leaves an existing document untouched (idempotent)', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection(ReviewConfig.collection)
          .doc(ReviewConfig.documentId)
          .set(ReviewConfig.defaults.copyWith(minLaunches: 9).toMap());
      final service = ReviewService.instance;
      service.firestoreForTesting = firestore;

      await service.ensureConfig();
      final snap = await firestore
          .collection(ReviewConfig.collection)
          .doc(ReviewConfig.documentId)
          .get();
      expect(snap.data()!['min_launches'], 9);
    });
  });

  group('ReviewService.logPromptShown', () {
    test('appends the review_prompt_shown event to feature_usage_events',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = ReviewService.instance;
      service.firestoreForTesting = firestore;

      await service.logPromptShown();

      final snap = await firestore
          .collection(UsageAnalyticsService.eventsCollection)
          .get();
      expect(snap.docs, hasLength(1));
      final data = snap.docs.first.data();
      expect(data['event'], ReviewService.promptShownEvent);
      expect(data['event'], 'review_prompt_shown');
      expect(data['type'], 'feature_usage');
      expect(data.containsKey('timestamp'), isTrue);
    });

    test('never throws when Firestore is unavailable', () async {
      final service = ReviewService.instance;
      // No firestoreForTesting + no initialised Firebase app.
      await expectLater(service.logPromptShown(), completes);
    });
  });
}
