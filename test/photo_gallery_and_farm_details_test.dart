import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/models/farm_details.dart';
import 'package:jagspoor/features/hunter_mode/services/farm_details_resolver.dart';
import 'package:jagspoor/features/hunter_mode/services/photo_gallery_resolver.dart';

void main() {
  group('resolveGalleryUrls', () {
    test('collects across imageUrls, photoUrls, trophyPhotoUrls, single fields',
        () {
      final urls = resolveGalleryUrls({
        'imageUrls': ['https://a/1.jpg'],
        'photoUrls': ['https://a/2.jpg'],
        'trophyPhotoUrls': ['https://a/3.jpg'],
        'photoUrl': 'https://a/4.jpg',
        'imageUrl': 'https://a/5.jpg',
      });
      expect(urls, [
        'https://a/1.jpg',
        'https://a/2.jpg',
        'https://a/3.jpg',
        'https://a/4.jpg',
        'https://a/5.jpg',
      ]);
    });

    test('de-duplicates while preserving priority order', () {
      final urls = resolveGalleryUrls({
        'imageUrls': ['https://a/1.jpg', 'https://a/2.jpg'],
        'photoUrls': ['https://a/2.jpg', 'https://a/3.jpg'],
        'photoUrl': 'https://a/1.jpg',
      });
      expect(urls, ['https://a/1.jpg', 'https://a/2.jpg', 'https://a/3.jpg']);
    });

    test('skips blank and non-string entries', () {
      final urls = resolveGalleryUrls({
        'imageUrls': ['', '   ', 42, null, 'https://a/x.jpg'],
      });
      expect(urls, ['https://a/x.jpg']);
    });

    test('trims whitespace from URLs', () {
      expect(
        resolveGalleryUrls({'photoUrl': '  https://a/y.jpg  '}),
        ['https://a/y.jpg'],
      );
    });

    test('returns empty for null / missing / unrelated fields', () {
      expect(resolveGalleryUrls(null), isEmpty);
      expect(resolveGalleryUrls(const {}), isEmpty);
      expect(
        resolveGalleryUrls({'title': 'no photos here'}),
        isEmpty,
      );
    });
  });

  group('FarmDetails.fromMap', () {
    test('resolves name / farmName alias with fallback', () {
      expect(
        FarmDetails.fromMap({'name': 'Bosveld Ranch'}).displayName,
        'Bosveld Ranch',
      );
      expect(
        FarmDetails.fromMap({'farmName': 'Kalahari'}).displayName,
        'Kalahari',
      );
      expect(FarmDetails.fromMap(const {}).displayName, 'Unnamed Farm');
    });

    test('town falls back to district', () {
      expect(
        FarmDetails.fromMap({'district': 'Waterberg'}).town,
        'Waterberg',
      );
      expect(
        FarmDetails.fromMap({'town': 'Alldays', 'district': 'X'}).town,
        'Alldays',
      );
    });

    test('infoChips only includes non-empty details', () {
      final chips = FarmDetails.fromMap({
        'province': 'Limpopo',
        'sizeHectares': 2500,
        'contactNumber': '+27 82 000 0000',
      }).infoChips;
      final labels = chips.map((c) => c.$2).toList();
      expect(labels, contains('Limpopo'));
      expect(labels, contains('2500 ha'));
      expect(labels, contains('+27 82 000 0000'));
      expect(labels.any((l) => l.trim().isEmpty), isFalse);
    });

    test('empty farm produces no info chips', () {
      expect(FarmDetails.fromMap(const {}).infoChips, isEmpty);
    });

    test('photoUrls resolved through gallery resolver with dedup + trim',
        () {
      final details = FarmDetails.fromMap({
        'photoUrls': ['https://f/1.jpg', ' ', 'https://f/2.jpg'],
        'photoUrl': 'https://f/1.jpg',
      });
      expect(details.photoUrls, ['https://f/1.jpg', 'https://f/2.jpg']);
      expect(details.primaryPhotoUrl, 'https://f/1.jpg');
    });

    test('primaryPhotoUrl is null without photos', () {
      expect(FarmDetails.fromMap(const {}).primaryPhotoUrl, isNull);
    });
  });

  group('FarmDetailsResolver', () {
    setUp(() {
      FarmDetailsResolver.firestoreForTesting = FakeFirebaseFirestore();
    });

    tearDown(() {
      FarmDetailsResolver.firestoreForTesting = null;
    });

    test('resolves a farm document into FarmDetails with id', () async {
      final fake = FarmDetailsResolver.firestoreForTesting!
          as FakeFirebaseFirestore;
      await fake.collection('farms').doc('farm1').set({
        'name': 'Bosveld Ranch',
        'province': 'Limpopo',
        'district': 'Waterberg',
        'contactNumber': '+27 82 000 0000',
        'sizeHectares': 2500,
        'photoUrl': 'https://f/main.jpg',
      });

      final details =
          await FarmDetailsResolver.instance.resolveFarm('farm1');
      expect(details.farmId, 'farm1');
      expect(details.displayName, 'Bosveld Ranch');
      expect(details.province, 'Limpopo');
      expect(details.town, 'Waterberg');
      expect(details.photoUrls, ['https://f/main.jpg']);
    });

    test('missing doc yields empty-details snapshot (no throw)', () async {
      final details =
          await FarmDetailsResolver.instance.resolveFarm('missing');
      expect(details.farmId, 'missing');
      expect(details.photoUrls, isEmpty);
    });

    test('blank farmId short-circuits to empty snapshot', () async {
      final details = await FarmDetailsResolver.instance.resolveFarm('  ');
      expect(details.farmId, '');
    });
  });
}
