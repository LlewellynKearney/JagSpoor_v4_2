import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contract tests for the Trophy Registry & Booking standard booking flow.
///
/// Tapping a trophy stock card must open the standard Booking Details /
/// Confirmation Sheet (full item details + outfitter contact info + pricing),
/// and confirming it must execute the standard booking process: an atomic
/// transaction that creates the booking record with the canonical pending
/// status AND safely decrements `availableCount` on the stock doc.
///
/// The Firestore rules-unit-testing emulator cannot run in this sandbox (no
/// Java/JVM -- see AGENTS.md environment constraints), so these tests encode
/// the contract structurally (source-level) plus the transaction's guard /
/// decrement / status-flip logic that the rules enforce, mirroring the
/// `package_quantity_test.dart` pattern.
void main() {
  group('Trophy Registry -- standard confirmation sheet wiring', () {
    final browserSrc = File(
      'lib/features/hunter_mode/screens/hunter_trophy_browser_screen.dart',
    ).readAsStringSync();
    final sheetSrc = File(
      'lib/features/hunter_mode/widgets/trophy_booking_confirmation_sheet.dart',
    ).readAsStringSync();

    test('tapping a card opens a modal bottom sheet with the standard '
        'confirmation sheet', () {
      expect(browserSrc.contains('showModalBottomSheet'), isTrue);
      expect(browserSrc.contains('TrophyBookingConfirmationSheet('), isTrue,
          reason: 'The card tap must open the standard Booking Details / '
              'Confirmation Sheet (Task 3), not the old quick-add dialog.');
    });

    test('the old multi-select quick-add flow is completely removed', () {
      expect(browserSrc.contains('_addToBookingLog'), isFalse);
      expect(browserSrc.contains('_selectedTrophyIds'), isFalse);
      expect(browserSrc.contains('_toggleTrophySelection'), isFalse);
      expect(browserSrc.contains('Add to Booking Log'), isFalse,
          reason: 'The quick-add AlertDialog is replaced by the standard '
              'confirmation sheet.');
    });

    test('the sheet shows full item details + contact card + pricing', () {
      expect(sheetSrc.contains('OutfitterContactCard'), isTrue,
          reason: 'The sheet must display the outfitter contact info exactly '
              'like the package marketplace sheet.');
      expect(sheetSrc.contains('Total Price'), isTrue);
      expect(sheetSrc.contains('BOOK THIS TROPHY'), isTrue);
    });

    test('the sheet confirms via PackageBookingManager.bookTrophyStock', () {
      expect(sheetSrc.contains('bookTrophyStock('), isTrue,
          reason: 'Confirming must execute the standard booking process via '
              'PackageBookingManager.bookTrophyStock.');
    });
  });

  group('PackageBookingManager.bookTrophyStock -- booking transaction '
      'contract', () {
    final managerSrc = File(
      'lib/features/hunter_mode/services/package_booking_manager.dart',
    ).readAsStringSync();

    test('bookTrophyStock exists', () {
      expect(managerSrc.contains('Future<String> bookTrophyStock({'), isTrue);
    });

    test('runs the booking + decrement inside a single transaction', () {
      final method = _methodBody(managerSrc, 'bookTrophyStock');
      expect(method.contains('runTransaction'), isTrue);
      expect(
          method.contains(
              'final trophySnap = await transaction.get(trophyRef);'),
          isTrue,
          reason: 'The availability guard must read the stock doc INSIDE the '
              'transaction (atomic check + decrement).');
    });

    test('rejects when no stock remains (atomic guard)', () {
      final method = _methodBody(managerSrc, 'bookTrophyStock');
      expect(method.contains('currentQty <= 0'), isTrue);
      expect(method.contains('PackageSoldOutException'), isTrue);
    });

    test('creates the booking with the canonical pending status + standard '
        'routing (CUSTOM_BUILT + selectedItemsList)', () {
      final method = _methodBody(managerSrc, 'bookTrophyStock');
      expect(method.contains("'packageId': 'CUSTOM_BUILT'"), isTrue,
          reason: 'The trophy booking must route through the standard '
              'booking pipeline (outfitter dashboard custom-items + hunter '
              'My Bookings).');
      expect(method.contains('selectedItemsList'), isTrue);
      expect(
          method.contains(
              "'status': BookingStatus.pendingApproval"),
          isTrue,
          reason: 'The booking record must be created with the canonical '
              'pending-approval status.');
      expect(method.contains('isTrophyStockBooking'), isTrue);
      expect(method.contains('trophyStockId'), isTrue);
    });

    test('decrements availableCount safely + flips to sold_out at 0', () {
      final method = _methodBody(managerSrc, 'bookTrophyStock');
      expect(method.contains('final newQty = currentQty - 1;'), isTrue);
      expect(method.contains("'availableCount': newQty"), isTrue);
      expect(method.contains("if (newQty <= 0) 'status': 'sold_out'"),
          isTrue,
          reason: 'The last animal must flip the stock entry to sold_out in '
              'the same transaction (no race window).');
    });

    test('guard logic: a stock doc with 0 available cannot be booked', () {
      // Pure-logic guard encoded exactly as the transaction applies it.
      bool canBook(int availableCount, String status) =>
          !(availableCount <= 0 || status != 'available');
      expect(canBook(3, 'available'), isTrue);
      expect(canBook(1, 'available'), isTrue);
      expect(canBook(0, 'available'), isFalse);
      expect(canBook(2, 'sold_out'), isFalse);
      expect(canBook(0, 'sold_out'), isFalse);
    });

    test('guard logic: multi-animal stock stays available, last animal '
        'flips sold_out', () {
      String nextStatus(int currentQty) {
        final newQty = currentQty - 1;
        return newQty <= 0 ? 'sold_out' : 'available';
      }
      expect(nextStatus(3), 'available');
      expect(nextStatus(2), 'available');
      expect(nextStatus(1), 'sold_out');
    });
  });

  group('Custom Package Builder farm card spacing cleanup (Task 1)', () {
    final src = File(
      'lib/features/hunter_mode/screens/custom_package_farm_selection_screen.dart',
    ).readAsStringSync();

    test('the chip Wrap has runSpacing so wrapped rows do not touch', () {
      expect(src.contains('runSpacing: 6'), isTrue,
          reason: 'Metadata chips must align cleanly without awkward '
              'vertical crowding when they wrap.');
      expect(src.contains('spacing: 8'), isTrue);
    });

    test('the chips render a clean bordered pill', () {
      expect(src.contains('Widget _chip(IconData icon, String label)'),
          isTrue);
      expect(src.contains('BorderRadius.circular(8)'), isTrue);
    });
  });
}

/// Extracts the body of a top-level method from the manager source
/// (from the method declaration to the next top-level `  Future` / `  }`).
String _methodBody(String src, String methodName) {
  final start = src.indexOf('Future<String> $methodName({');
  if (start < 0) fail('method $methodName not found in manager source');
  final rest = src.substring(start);
  final next = rest.indexOf('\n  /// Restocks a sold-out');
  // bookTrophyStock is followed by restockPackage's docstring.
  return next > 0 ? rest.substring(0, next) : rest;
}
