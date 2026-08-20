/// Booking category classification for the outfitter's Incoming Booking
/// Requests dashboard.
///
/// A booking doc is classified into exactly one category:
/// - [BookingCategory.trophy] — an individual trophy-hunt request booked from
///   the Trophy Registry (`isTrophyStockBooking: true` and/or a
///   `trophyStockId` reference into `trophy_stock`).
/// - [BookingCategory.custom] — a hunter-assembled custom package
///   (`isCustomPackage: true`, `packageId == 'CUSTOM_BUILT'` with inline
///   `selectedItemsList` / `lodgingCateringList`).
/// - [BookingCategory.standard] — a standard marketplace package booking
///   (a real `packages/{packageId}` reference, neither custom nor trophy).
///
/// Pure logic with no Flutter / Firebase imports so it is fully unit-testable.
library;

enum BookingCategory { standard, custom, trophy }

class BookingCategoryClassifier {
  BookingCategoryClassifier._();

  /// Classifies a raw booking document map into its category. Trophy wins
  /// over custom (a trophy-stock booking also uses the `CUSTOM_BUILT`
  /// package sentinel but carries the trophy markers).
  static BookingCategory classify(Map<String, dynamic> data) {
    if (data['isTrophyStockBooking'] == true ||
        (data['trophyStockId'] as String?)?.trim().isNotEmpty == true) {
      return BookingCategory.trophy;
    }
    if (data['isCustomPackage'] == true ||
        (data['packageId'] as String?) == 'CUSTOM_BUILT') {
      return BookingCategory.custom;
    }
    return BookingCategory.standard;
  }
}
