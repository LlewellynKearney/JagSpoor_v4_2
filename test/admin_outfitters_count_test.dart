import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/admin/services/admin_analytics_service.dart';

/// Verifies the admin dashboard "Outfitters" metric counts every registered
/// outfitter regardless of which collection their record lives in:
/// - `users` with `role == 'outfitter'` (self-registered via role selection)
/// - `outfitters` docs (admin-provisioned)
/// matched by document id so an outfitter present in both is counted once.
void main() {
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    AdminAnalyticsService.firestoreForTesting = fakeFirestore;
  });

  tearDown(() {
    AdminAnalyticsService.firestoreForTesting = null;
  });

  Future<int> fetchOutfitterCount() async {
    final metrics = await AdminAnalyticsService.instance.fetchEntityMetrics();
    return metrics.totalOutfitters;
  }

  group('AdminAnalyticsService outfitters count', () {
    test('returns 0 when no outfitters exist anywhere', () async {
      expect(await fetchOutfitterCount(), 0);
    });

    test('counts self-registered outfitters from users.role', () async {
      await fakeFirestore.collection('users').doc('u1').set({
        'role': 'outfitter',
      });
      await fakeFirestore.collection('users').doc('u2').set({
        'role': 'outfitter',
      });
      await fakeFirestore.collection('users').doc('u3').set({
        'role': 'hunter',
      });
      expect(await fetchOutfitterCount(), 2);
    });

    test('counts admin-provisioned outfitters from the outfitters collection',
        () async {
      await fakeFirestore.collection('outfitters').doc('o1').set({
        'role': 'outfitter',
      });
      await fakeFirestore.collection('outfitters').doc('o2').set({
        'role': 'outfitter',
      });
      expect(await fetchOutfitterCount(), 2);
    });

    test('unions both collections (no outfitter left out)', () async {
      await fakeFirestore.collection('users').doc('u1').set({
        'role': 'outfitter',
      });
      await fakeFirestore.collection('users').doc('u2').set({
        'role': 'outfitter',
      });
      await fakeFirestore.collection('outfitters').doc('o1').set({
        'role': 'outfitter',
      });
      expect(await fetchOutfitterCount(), 3);
    });

    test('an outfitter present in BOTH collections is counted once', () async {
      await fakeFirestore.collection('users').doc('sharedUid').set({
        'role': 'outfitter',
      });
      await fakeFirestore.collection('outfitters').doc('sharedUid').set({
        'role': 'outfitter',
      });
      await fakeFirestore.collection('users').doc('otherUid').set({
        'role': 'outfitter',
      });
      expect(await fetchOutfitterCount(), 2);
    });

    test('does not count hunters or role-less users', () async {
      await fakeFirestore.collection('users').doc('h1').set({
        'role': 'hunter',
      });
      await fakeFirestore.collection('users').doc('h2').set({
        'email': 'no-role@example.com',
      });
      expect(await fetchOutfitterCount(), 0);
    });
  });
}
