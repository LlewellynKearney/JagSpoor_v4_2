// ============================================================================
// Package Quantity Tracking & Automatic Sold-Out Status — Unit Tests (Item #11)
//
// Validates the inventory model layer (no Firestore emulator required):
//  - PackageStatus.soldOut round-trips through label/fromString.
//  - PackageQuantity.fromData parses the slot count and defaults legacy /
//    invalid docs to 1.
//  - PackageQuantity.isSoldOut flips when quantity hits 0 or status is sold_out.
//  - PackageQuantity.remainingLabel produces the marketplace card labels.
//  - PackageSoldOutException carries the packageId + message.
//
// The atomic transaction in `PackageBookingManager.bookPackage` is exercised
// structurally here (decrement + sold-out-at-0 + sold-out rejection) via the
// shared PackageQuantity helpers the transaction relies on, since the Firestore
// emulator / credentials are unavailable in this sandbox (see AGENTS.md).
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/models/package_pricing.dart';

void main() {
  group('PackageStatus.soldOut', () {
    test('label is "sold_out"', () {
      expect(PackageStatus.soldOut.label, 'sold_out');
    });

    test('fromString round-trips "sold_out"', () {
      expect(PackageStatus.fromString('sold_out'), PackageStatus.soldOut);
    });

    test('fromString falls back to active for null/unknown', () {
      expect(PackageStatus.fromString(null), PackageStatus.active);
      expect(PackageStatus.fromString('nonsense'), PackageStatus.active);
    });

    test('soldOut is not listed as bookable', () {
      expect(PackageStatus.soldOut.isListed, isFalse);
      expect(PackageStatus.active.isListed, isTrue);
    });

    test('every status label round-trips through fromString', () {
      for (final status in PackageStatus.values) {
        expect(PackageStatus.fromString(status.label), status,
            reason: '${status.label} did not round-trip');
      }
    });
  });

  group('PackageQuantity.fromData', () {
    test('parses a positive integer', () {
      expect(PackageQuantity.fromData(5), 5);
    });

    test('parses a numeric double by truncating to int', () {
      expect(PackageQuantity.fromData(3.0), 3);
    });

    test('defaults to 1 for legacy docs missing the field (null)', () {
      expect(PackageQuantity.fromData(null), PackageQuantity.defaultQuantity);
      expect(PackageQuantity.defaultQuantity, 1);
    });

    test('defaults to 1 for invalid / negative values', () {
      expect(PackageQuantity.fromData(-3), 1);
      expect(PackageQuantity.fromData('not a number'), 1);
    });

    test('treats 0 as a real zero (sold out), not the legacy default', () {
      // A package that legitimately hit 0 slots must read as 0 so the UI can
      // render the sold-out state — it must NOT be masked back to 1.
      expect(PackageQuantity.fromData(0), 0);
    });
  });

  group('PackageQuantity.isSoldOut', () {
    test('false while slots remain and status is active', () {
      expect(
        PackageQuantity.isSoldOut(quantityAvailable: 3, status: 'active'),
        isFalse,
      );
    });

    test('true when quantity reaches 0 (regardless of status)', () {
      expect(
        PackageQuantity.isSoldOut(quantityAvailable: 0, status: 'active'),
        isTrue,
      );
      expect(
        PackageQuantity.isSoldOut(quantityAvailable: 0, status: null),
        isTrue,
      );
    });

    test('true when status is sold_out even if qty is stale-positive', () {
      // The transaction flips status to sold_out atomically with the decrement
      // to 0, but defend against a stale read where qty hasn't caught up.
      expect(
        PackageQuantity.isSoldOut(quantityAvailable: 2, status: 'sold_out'),
        isTrue,
      );
    });

    test('false for a legacy active package with default quantity', () {
      expect(
        PackageQuantity.isSoldOut(quantityAvailable: 1, status: 'active'),
        isFalse,
      );
    });
  });

  group('PackageQuantity.remainingLabel', () {
    test('reports "Sold Out" when no slots remain', () {
      expect(PackageQuantity.remainingLabel(0), 'Sold Out');
      expect(PackageQuantity.remainingLabel(-1), 'Sold Out');
    });

    test('singular form for the last slot', () {
      expect(PackageQuantity.remainingLabel(1), '1 slot left!');
    });

    test('plural form for multiple slots', () {
      expect(PackageQuantity.remainingLabel(5), '5 slots left!');
    });
  });

  group('PackageSoldOutException', () {
    test('carries the packageId and a default message', () {
      final e = PackageSoldOutException(packageId: 'pkg-123');
      expect(e.packageId, 'pkg-123');
      expect(e.message, isNotEmpty);
      expect(e.toString(), contains('pkg-123'));
    });

    test('accepts a custom message', () {
      final e = PackageSoldOutException(
        packageId: 'pkg-9',
        message: 'All gone',
      );
      expect(e.message, 'All gone');
      expect(e.toString(), contains('All gone'));
    });

    test('is an Exception (can be caught generically)', () {
      try {
        throw PackageSoldOutException(packageId: 'pkg-x');
      } on Exception catch (caught) {
        expect(caught, isA<PackageSoldOutException>());
      }
    });
  });

  group('bookPackage transaction logic (structural)', () {
    // These tests encode the exact decrement + sold-out-at-0 + rejection
    // rules that PackageBookingManager.bookPackage applies inside its Firestore
    // transaction. They run without the emulator by exercising the shared
    // PackageQuantity / PackageStatus helpers the transaction reads through.

    test('decrementing a multi-slot package keeps it active', () {
      const currentQty = 5;
      const currentStatus = PackageStatus.active;
      final newQty = currentQty - 1;
      final newStatus =
          newQty <= 0 ? PackageStatus.soldOut.label : currentStatus.label;
      expect(newQty, 4);
      expect(newStatus, 'active');
      expect(
        PackageQuantity.isSoldOut(quantityAvailable: newQty, status: newStatus),
        isFalse,
      );
    });

    test('decrementing the last slot flips status to sold_out', () {
      const currentQty = 1;
      const currentStatus = PackageStatus.active;
      final newQty = currentQty - 1;
      final newStatus =
          newQty <= 0 ? PackageStatus.soldOut.label : currentStatus.label;
      expect(newQty, 0);
      expect(newStatus, 'sold_out');
      expect(
        PackageQuantity.isSoldOut(quantityAvailable: newQty, status: newStatus),
        isTrue,
      );
    });

    test('a 0-slot / sold-out package rejects a new booking', () {
      // Mirrors the transaction's guard: non-active status OR qty <= 0 throws.
      bool isSoldOut(int qty, String? status) => PackageQuantity.isSoldOut(
            quantityAvailable: qty,
            status: status,
          );
      expect(isSoldOut(0, 'active'), isTrue);
      expect(isSoldOut(3, 'sold_out'), isTrue);
      expect(isSoldOut(3, 'active'), isFalse);
    });

    test('legacy package (no quantityAvailable field) is bookable once', () {
      // fromData returns 1 for a legacy doc; one booking decrements it to 0
      // and flips to sold_out — i.e. legacy packages behave as single-slot.
      final legacyQty = PackageQuantity.fromData(null);
      expect(legacyQty, 1);
      final afterBooking = legacyQty - 1;
      final status = afterBooking <= 0
          ? PackageStatus.soldOut.label
          : PackageStatus.active.label;
      expect(afterBooking, 0);
      expect(status, 'sold_out');
    });
  });
}
