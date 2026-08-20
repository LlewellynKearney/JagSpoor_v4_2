import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/booking_category_classifier.dart';

void main() {
  group('BookingCategoryClassifier.classify', () {
    test('a real marketplace package booking is standard', () {
      expect(
        BookingCategoryClassifier.classify({
          'packageId': 'abc123',
          'packageName': 'Kudu Package',
          'status': 'Pending Approval',
        }),
        BookingCategory.standard,
      );
    });

    test('an empty booking map defaults to standard', () {
      expect(
        BookingCategoryClassifier.classify(const {}),
        BookingCategory.standard,
      );
    });

    test('isCustomPackage == true is custom', () {
      expect(
        BookingCategoryClassifier.classify({
          'isCustomPackage': true,
          'packageId': 'CUSTOM_BUILT',
          'selectedItemsList': [],
        }),
        BookingCategory.custom,
      );
    });

    test('packageId == CUSTOM_BUILT alone is custom', () {
      expect(
        BookingCategoryClassifier.classify({'packageId': 'CUSTOM_BUILT'}),
        BookingCategory.custom,
      );
    });

    test('isTrophyStockBooking == true is trophy', () {
      expect(
        BookingCategoryClassifier.classify({
          'isTrophyStockBooking': true,
          'packageId': 'CUSTOM_BUILT',
        }),
        BookingCategory.trophy,
      );
    });

    test('a trophyStockId reference alone is trophy', () {
      expect(
        BookingCategoryClassifier.classify({'trophyStockId': 'stockDocId'}),
        BookingCategory.trophy,
      );
    });

    test('trophy wins over custom (both markers present)', () {
      // A trophy-stock booking also uses the CUSTOM_BUILT package sentinel;
      // the trophy markers must take precedence.
      expect(
        BookingCategoryClassifier.classify({
          'isCustomPackage': true,
          'isTrophyStockBooking': true,
          'packageId': 'CUSTOM_BUILT',
          'trophyStockId': 'stockDocId',
        }),
        BookingCategory.trophy,
      );
    });

    test('blank trophyStockId string is NOT trophy', () {
      expect(
        BookingCategoryClassifier.classify({
          'trophyStockId': '   ',
          'packageId': 'CUSTOM_BUILT',
        }),
        BookingCategory.custom,
      );
    });

    test('false flags do not trigger their categories', () {
      expect(
        BookingCategoryClassifier.classify({
          'isCustomPackage': false,
          'isTrophyStockBooking': false,
          'packageId': 'abc123',
        }),
        BookingCategory.standard,
      );
    });
  });
}
