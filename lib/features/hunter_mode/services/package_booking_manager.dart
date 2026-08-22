import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/booking_status.dart';
import '../models/package_pricing.dart';
import 'outfitter_enterprise_manager.dart';

class PackageBookingManager {
  static final PackageBookingManager _instance =
      PackageBookingManager._internal();
  static PackageBookingManager get instance => _instance;

  PackageBookingManager._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get _currentUser => _auth.currentUser;
  String? get _currentUserId => _currentUser?.uid;

  // ==========================================
  // OUTFITTER - PUBLISH PACKAGE
  // ==========================================
  /// Publishes (or saves as draft) a new hunting package to the marketplace.
  ///
  /// Parameters:
  /// - [title]: Package title/name
  /// - [description]: Detailed description of the package
  /// - [pricing]: Full pricing definition (all-inclusive or itemized), which
  ///   resolves the outfitter base price, the line-item/species breakdown, and
  ///   the availability window. See [PackagePricing].
  /// - [inclusions]: List of what's included (e.g., ["Transport", "Accommodation", "Meals"])
  /// - [farmId]: Optional farm/concession ID to bind the package to
  /// - [status]: Lifecycle status (defaults to [PackageStatus.active] so the
  ///   package is immediately listed; pass [PackageStatus.draft] to save an
  ///   unlisted work-in-progress).
  /// - [imageUrls]: Download URLs of uploaded package gallery images.
  ///
  /// Pricing:
  /// - `basePriceRands` = resolved base price from [pricing]
  /// - `totalPriceZAR` = `basePriceRands` (the hunter pays the base package
  ///   cost; there is no platform commission / markup).
  ///
  /// Returns: void (saves to Firestore 'packages' collection)
  ///
  /// Throws: Exception if user is not authenticated or save fails
  Future<String> publishPackage({
    required String title,
    required String description,
    required PackagePricing pricing,
    required List<String> inclusions,
    String? farmId,
    PackageStatus status = PackageStatus.active,
    List<String> imageUrls = const [],
    int quantityAvailable = PackageQuantity.defaultQuantity,
  }) async {
    // Validate authentication
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to publish a package');
    }

    // Validate inputs
    if (title.trim().isEmpty) {
      throw Exception('Package title cannot be empty');
    }
    if (description.trim().isEmpty) {
      throw Exception('Package description cannot be empty');
    }

    final basePriceRands = pricing.basePrice;
    if (basePriceRands <= 0) {
      throw Exception('Base price must be greater than zero');
    }

    if (pricing.availabilityStart != null &&
        pricing.availabilityEnd != null &&
        pricing.availabilityEnd!.isBefore(pricing.availabilityStart!)) {
      throw Exception(
          'Availability end date cannot be before the start date');
    }

    // Bookable slot count, clamped to >= 1. A package must offer at least one
    // slot to be bookable.
    final clampedQty = quantityAvailable < 1 ? 1 : quantityAvailable;

    // The hunter pays the base package cost; there is no platform commission.
    final double total = basePriceRands;

    final packageData = {
      'outfitterId': _currentUserId,
      'title': title.trim(),
      'description': description.trim(),
      'basePriceRands': basePriceRands,
      'totalPriceZAR': total,
      'inclusions': inclusions,
      'farmId': farmId,
      'imageUrls': imageUrls,
      'quantityAvailable': clampedQty,
      ...pricing.toMap(),
      'status': status.label,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final docRef =
        await _firestore.collection('packages').add(packageData);
    return docRef.id;
  }

  /// Updates an existing package owned by the current outfitter.
  ///
  /// Any of the optional fields, when non-null, replace the stored value.
  /// `totalPriceZAR` is recomputed to equal `basePriceRands` whenever
  /// [pricing] (and thus the base price) changes (the hunter pays the base
  /// package cost; there is no platform commission). Status is left
  /// untouched here — use [setPackageStatus] for lifecycle transitions.
  ///
  /// Throws: Exception if not authenticated or the update fails.
  Future<void> updatePackage({
    required String packageId,
    String? title,
    String? description,
    PackagePricing? pricing,
    List<String>? inclusions,
    String? farmId,
    List<String>? imageUrls,
    int? quantityAvailable,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to update a package');
    }

    final update = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (title != null) update['title'] = title.trim();
    if (description != null) update['description'] = description.trim();
    if (inclusions != null) update['inclusions'] = inclusions;
    if (farmId != null) update['farmId'] = farmId;
    if (imageUrls != null) update['imageUrls'] = imageUrls;
    if (quantityAvailable != null) {
      // Clamp to >= 1; the outfitter may restock a sold-out package by
      // raising the count back above 0 (the sold-out → active transition is
      // applied via setPackageStatus when restocking).
      update['quantityAvailable'] =
          quantityAvailable < 1 ? 1 : quantityAvailable;
    }

    if (pricing != null) {
      final basePriceRands = pricing.basePrice;
      if (basePriceRands <= 0) {
        throw Exception('Base price must be greater than zero');
      }
      if (pricing.availabilityStart != null &&
          pricing.availabilityEnd != null &&
          pricing.availabilityEnd!.isBefore(pricing.availabilityStart!)) {
        throw Exception(
            'Availability end date cannot be before the start date');
      }
      final double total = basePriceRands;
      update
        ..addAll({
          'basePriceRands': basePriceRands,
          'totalPriceZAR': total,
        })
        ..addAll(pricing.toMap());
    }

    await _firestore.collection('packages').doc(packageId).update(update);
  }

  /// Transitions a package to a new lifecycle [status] (active / draft /
  /// archived / deleted). Soft-deletes set [PackageStatus.deleted] rather than
  /// removing the document, preserving booking references and audit history.
  ///
  /// Throws: Exception if not authenticated or the update fails.
  Future<void> setPackageStatus({
    required String packageId,
    required PackageStatus status,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to change package status');
    }

    await _firestore.collection('packages').doc(packageId).update({
      'status': status.label,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==========================================
  // HUNTER - BOOK PACKAGE
  // ==========================================
  /// Books a hunting package.
  ///
  /// Executes as an **atomic Firestore transaction**: it reads the package,
  /// verifies at least one slot remains (`quantityAvailable > 0`), creates the
  /// booking, and decrements `quantityAvailable` by 1. If the count reaches 0
  /// the package status is flipped to [PackageStatus.soldOut] so it can no
  /// longer be booked. This is race-safe — concurrent booking attempts are
  /// serialized by the transaction, and a hunter that hits a 0-slot package has
  /// its booking cancelled with a clear "Package Sold Out" error.
  ///
  /// Parameters:
  /// - [packageId]: Firestore document ID of the package being booked
  /// - [outfitterId]: UID of the outfitter who owns the package
  /// - [basePriceRands]: Base price of the package in Rand
  /// - [packageName]: Optional package title snapshot (for booking display)
  ///
  /// Pricing:
  /// - Total Hunter Price = `basePriceRands` (the hunter pays the base package
  ///   cost; there is no platform commission).
  ///
  /// Returns: void (saves to Firestore 'bookings' collection + updates package)
  ///
  /// Throws:
  /// - Exception if user is not authenticated.
  /// - `PackageSoldOutException` if the package has no remaining slots.
  /// - Exception if the package is missing or the save fails.
  Future<void> bookPackage({
    required String packageId,
    required String outfitterId,
    required double basePriceRands,
    String? packageName,

    /// The hunt window the hunter selected on the interactive booking
    /// availability strip. When supplied, it OVERRIDES the package's
    /// advertised availability window on the booking document (written under
    /// both the `startDate`/`endDate` AND `availabilityStart`/
    /// `availabilityEnd` key families so every downstream consumer resolves
    /// it). When omitted the package's own window is copied as before.
    DateTime? selectedStart,
    DateTime? selectedEnd,
  }) async {
    // Validate authentication
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to book a package');
    }

    // Prevent outfitter from booking their own package
    if (_currentUserId == outfitterId) {
      throw Exception('Outfitters cannot book their own packages');
    }

    // Validate inputs
    if (packageId.trim().isEmpty) {
      throw Exception('Package ID cannot be empty');
    }
    if (basePriceRands <= 0) {
      throw Exception('Base price must be greater than zero');
    }

    // Normalize a partial hunter selection: an end-only selection collapses
    // to a single-day window; a null start with a null end leaves the
    // package's advertised window untouched.
    final DateTime? selStart = selectedStart ?? selectedEnd;
    final DateTime? selEnd = selectedStart != null ? selectedEnd : null;

    // The hunter pays the base package cost; there is no platform commission.
    final double totalHunterPrice = basePriceRands;

    final packageRef = _firestore.collection('packages').doc(packageId.trim());

    // Atomic booking + inventory decrement. The transaction guarantees that
    // the slot-count check and the decrement are consistent under concurrent
    // bookings — two hunters cannot both grab the last slot.
    await _firestore.runTransaction((transaction) async {
      final packageSnap = await transaction.get(packageRef);

      if (!packageSnap.exists) {
        throw Exception('Package not found');
      }

      final pkgData = packageSnap.data() as Map<String, dynamic>;
      final currentQty =
          PackageQuantity.fromData(pkgData['quantityAvailable']);
      final currentStatus =
          PackageStatus.fromString(pkgData['status'] as String?);

      // Reject the booking if no slots remain or the package is already sold
      // out / not actively listed (draft, archived, deleted).
      if (currentStatus != PackageStatus.active ||
          currentQty <= 0) {
        throw PackageSoldOutException(packageId: packageId);
      }

      // Create the booking inside the same transaction.
      final bookingRef = _firestore.collection('bookings').doc();
      // Copy the package's hunt window (availability dates) + farm reference
      // onto the booking so the hunter's "My Bookings" card can display the
      // dates and the "Add to Calendar" action can resolve a hunt window
      // without a separate package read. The package's availability fields
      // are stored as Firestore `Timestamp?` (see PackagePricing.toMap); we
      // pass them through verbatim so they keep their server-accurate
      // precision on the booking doc.
      //
      // DUAL-KEY FALLBACK: the package may store its hunt window under either
      // `availabilityStart`/`availabilityEnd` (the canonical PackagePricing
      // keys) OR `startDate`/`endDate` (a legacy / third-party alias). We
      // resolve whichever is present (availabilityStart wins, then falls
      // back to startDate) and then write BOTH key sets onto the booking doc
      // so that no matter which key a downstream screen / widget looks for,
      // the booking document carries it. This guarantees the booking is
      // self-contained for the calendar resolver (which scans both alias
      // families) and for any UI card that reads either key directly.
      // HUNTER-SELECTED WINDOW OVERRIDE: when the hunter picked dates on the
      // interactive availability strip, that selection takes precedence over
      // the package's advertised window (written as Firestore Timestamps so
      // the shape matches the package-copied path exactly). A missing end
      // collapses to a single-day window; an end before the start is clamped
      // to the start.
      final dynamic availabilityStart = selStart != null
          ? Timestamp.fromDate(selStart)
          : (pkgData['availabilityStart'] ?? pkgData['startDate']);
      final dynamic availabilityEnd = selStart != null
          ? Timestamp.fromDate(
              (selEnd != null && !selEnd.isBefore(selStart))
                  ? selEnd
                  : selStart,
            )
          : (pkgData['availabilityEnd'] ?? pkgData['endDate']);
      final farmId = pkgData['farmId'] as String?;
      // Resolve the farm's display name + region from `farms/{farmId}` so the
      // booking is self-contained for the calendar event (title "@ Farm"
      // suffix, location, description Farm/region lines). The `packages`
      // doc only carries `farmId` (not the farm name); the marketplace
      // resolves the name via a runtime farms-join at read time, but the
      // booking doc must carry it itself so the calendar service can build a
      // located event without a farm read. Best-effort: a missing/empty
      // farmId or a missing farms doc simply omits the fields (the calendar
      // falls back to the package name only).
      String? farmName;
      String? farmDistrict;
      String? farmProvince;
      if (farmId != null && farmId.isNotEmpty) {
        try {
          final farmSnap = await transaction
              .get(_firestore.collection('farms').doc(farmId));
          if (farmSnap.exists) {
            final farmData = farmSnap.data() ?? const <String, dynamic>{};
            farmName = (farmData['name'] as String?)?.trim();
            farmDistrict = (farmData['district'] as String?)?.trim();
            farmProvince = (farmData['province'] as String?)?.trim();
          }
        } catch (_) {
          // A farm read failure must never block the booking -- the calendar
          // event simply omits the farm location.
        }
      }
      transaction.set(bookingRef, {
        'packageId': packageId.trim(),
        'outfitterId': outfitterId.trim(),
        'hunterId': _currentUserId,
        if (packageName != null) 'packageName': packageName,
        'basePriceRands': basePriceRands,
        'totalHunterPriceRands': totalHunterPrice,
        'status': BookingStatus.pendingApproval,
        'bookingTimestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        // Hunt window (copied from the package so the booking is
        // self-contained for the calendar + the booking card).
        //
        // We write BOTH the `availabilityStart`/`availabilityEnd` AND the
        // `startDate`/`endDate` key sets so a downstream consumer reading
        // either key always finds a value. The resolved `availabilityStart`/
        // `availabilityEnd` locals already carry the dual-key fallback
        // (availabilityStart ?? startDate), so when the package stored its
        // window under `startDate`/`endDate` only, the booking still ends up
        // with both sets populated from the single source value. A null
        // window (package with no dates) writes neither set.
        if (availabilityStart != null) 'startDate': availabilityStart,
        if (availabilityEnd != null) 'endDate': availabilityEnd,
        if (availabilityStart != null) 'availabilityStart': availabilityStart,
        if (availabilityEnd != null) 'availabilityEnd': availabilityEnd,
        if (farmId != null && farmId.isNotEmpty) 'farmId': farmId,
        // Farm location snapshot (resolved from farms/{farmId}) so the
        // calendar event carries a located title + location + description
        // without a separate farm read at calendar-build time.
        if (farmName != null && farmName.isNotEmpty) 'farmName': farmName,
        if (farmDistrict != null && farmDistrict.isNotEmpty)
          'district': farmDistrict,
        if (farmProvince != null && farmProvince.isNotEmpty)
          'province': farmProvince,
      });

      // Decrement the slot count. When the last slot is claimed, flip the
      // status to sold_out so the listing becomes read-only in the UI.
      final newQty = currentQty - 1;
      final newStatus = newQty <= 0
          ? PackageStatus.soldOut.label
          : currentStatus.label;
      transaction.update(packageRef, {
        'quantityAvailable': newQty,
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ==========================================
  // HUNTER - BOOK TROPHY STOCK
  // ==========================================
  /// Books one animal out of an outfitter's saleable trophy stock inventory
  /// (the `trophy_stock` collection). This is the standard booking flow the
  /// Trophy Registry & Booking browser executes when a hunter confirms the
  /// Booking Details / Confirmation Sheet -- it mirrors [bookPackage]:
  /// atomically creates the booking record with the canonical pending status
  /// AND safely decrements the stock's `availableCount` in the same
  /// transaction, so two hunters cannot both grab the last animal.
  ///
  /// The booking is written with `packageId: 'CUSTOM_BUILT'` +
  /// `isTrophyStockBooking: true` + a one-entry `selectedItemsList`, so it
  /// routes through the standard booking pipeline exactly like a custom /
  /// package booking: it appears in the outfitter's Incoming Booking Requests
  /// dashboard (with the expandable item breakdown + APPROVE / DECLINE
  /// actions) AND in the hunter's "My Bookings" tab, with status
  /// [BookingStatus.pendingApproval].
  ///
  /// Parameters:
  /// - [trophyId]: Firestore document ID of the trophy stock entry.
  /// - [outfitterId]: The owning outfitter's uid (from the stock doc).
  /// - [pricePerTrophyRands]: The price for the single trophy animal (must
  ///   be > 0). The hunter pays the base trophy cost -- there is no platform
  ///   commission.
  /// - [species]/[sex]/[trophyMeasurement]/[farmId]/[farmName]/[district]/
  ///   [province]: display + routing fields copied onto the booking so the
  ///   booking card is self-contained (matching the package booking flow's
  ///   farm-location enrichment). Omitted when blank.
  ///
  /// Returns: the new booking document ID.
  ///
  /// Throws:
  /// - Exception if the user is not authenticated, the trophy id is empty,
  ///   the price is not positive, or the outfitter tries to book their own
  ///   stock.
  /// - [PackageSoldOutException] when the stock has no remaining availability
  ///   (or is already sold out) at transaction time.
  Future<String> bookTrophyStock({
    required String trophyId,
    required String outfitterId,
    required double pricePerTrophyRands,
    String? species,
    String? sex,
    double? trophyMeasurement,
    String? farmId,
    String? farmName,
    String? district,
    String? province,

    /// The hunt window the hunter selected on the interactive booking
    /// availability strip (REQUIRED by the trophy booking confirmation
    /// sheet). Written onto the booking document under BOTH the
    /// `startDate`/`endDate` AND `availabilityStart`/`availabilityEnd` key
    /// families (as Firestore Timestamps) so every downstream consumer --
    /// the booking cards, the calendar resolver, the availability service's
    /// local-state blocker -- resolves the hunter-chosen window under
    /// whichever alias it reads.
    DateTime? selectedStart,
    DateTime? selectedEnd,
  }) async {
    // Validate authentication
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to book a trophy');
    }

    // Prevent the outfitter from booking their own trophy stock
    if (_currentUserId == outfitterId) {
      throw Exception('Outfitters cannot book their own trophy stock');
    }

    // Validate inputs
    if (trophyId.trim().isEmpty) {
      throw Exception('Trophy stock ID cannot be empty');
    }
    if (pricePerTrophyRands <= 0) {
      throw Exception('Price per trophy must be greater than zero');
    }

    // Normalize a partial hunter selection (same contract as bookPackage):
    // an end-only selection collapses to a single-day window; a null start
    // with a null end leaves the booking without date keys.
    final DateTime? selStart = selectedStart ?? selectedEnd;
    final DateTime? selEnd = selectedStart != null ? selectedEnd : null;

    final trophyRef = _firestore
        .collection(OutfitterEnterpriseManager.trophyStockCollection)
        .doc(trophyId.trim());
    String bookingId = '';

    // Atomic booking + stock decrement. The transaction guarantees the
    // availability check and the decrement are consistent under concurrent
    // bookings -- two hunters cannot both grab the last animal.
    await _firestore.runTransaction((transaction) async {
      final trophySnap = await transaction.get(trophyRef);
      if (!trophySnap.exists) {
        throw Exception('Trophy stock entry not found');
      }

      final trophyData = trophySnap.data() as Map<String, dynamic>;
      final currentQty =
          (trophyData['availableCount'] as num?)?.toInt() ?? 0;
      final currentStatus = (trophyData['status'] as String?) ?? 'available';

      // Reject the booking when no animals remain or the entry is already
      // sold out (the last booking flips the status to 'sold_out').
      if (currentQty <= 0 || currentStatus != 'available') {
        throw PackageSoldOutException(
          packageId: trophyId,
          message: 'This trophy is no longer available.',
        );
      }

      final resolvedSpecies = (species != null && species.trim().isNotEmpty)
          ? species.trim()
          : ((trophyData['species'] as String?) ?? 'Trophy');

      // Create the booking inside the same transaction. The 'CUSTOM_BUILT'
      // packageId + one-entry selectedItemsList route it through the standard
      // pipeline (the outfitter dashboard renders the custom-items expandable
      // section with APPROVE / DECLINE; the hunter "My Bookings" tab renders
      // it as a standard booking card).
      final bookingRef = _firestore.collection('bookings').doc();
      bookingId = bookingRef.id;
      transaction.set(bookingRef, {
        'packageId': 'CUSTOM_BUILT',
        'isTrophyStockBooking': true,
        'trophyStockId': trophyId.trim(),
        'packageName': 'Trophy Hunt - $resolvedSpecies',
        'outfitterId': outfitterId.trim(),
        'hunterId': _currentUserId,
        'bookingType': 'trophy_stock',
        'species': resolvedSpecies,
        if (sex != null && sex.trim().isNotEmpty) 'sex': sex.trim(),
        if (trophyMeasurement != null && trophyMeasurement > 0) ...{
          'trophyMeasurement': trophyMeasurement,
          'trophyLengthInches': trophyMeasurement,
        },
        if (farmId != null && farmId.isNotEmpty) 'farmId': farmId,
        if (farmName != null && farmName.isNotEmpty) 'farmName': farmName,
        if (district != null && district.isNotEmpty) 'district': district,
        if (province != null && province.isNotEmpty) 'province': province,
        'selectedItemsList': [
          {
            'name': resolvedSpecies,
            if (sex != null && sex.trim().isNotEmpty) 'sex': sex.trim(),
            'itemType': 'species',
            'quantity': 1,
            'unitPriceHunterZAR': pricePerTrophyRands,
            'lineTotal': pricePerTrophyRands,
            'hunterPrice': pricePerTrophyRands,
            'basePrice': pricePerTrophyRands,
            if (trophyMeasurement != null && trophyMeasurement > 0)
              'trophyMeasurementInches': trophyMeasurement,
            'trophyStockId': trophyId.trim(),
          },
        ],
        // The hunter pays the base trophy cost; there is no platform
        // commission.
        'basePriceRands': pricePerTrophyRands,
        'totalHunterPriceRands': pricePerTrophyRands,
        // The hunter's interactive availability-strip hunt window, written
        // under BOTH date-key families (mirrors bookPackage's dual-key
        // guarantee) so the booking cards, the calendar resolver, and the
        // availability service's local-state blocker all resolve it. The
        // trophy sheet gates booking on a strip selection, so this is always
        // populated for new bookings.
        if (selStart != null) ...{
          'startDate': Timestamp.fromDate(selStart),
          'endDate': Timestamp.fromDate(
            (selEnd != null && !selEnd.isBefore(selStart))
                ? selEnd
                : selStart,
          ),
          'availabilityStart': Timestamp.fromDate(selStart),
          'availabilityEnd': Timestamp.fromDate(
            (selEnd != null && !selEnd.isBefore(selStart))
                ? selEnd
                : selStart,
          ),
        },
        'status': BookingStatus.pendingApproval,
        'bookingTimestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Decrement the stock. When the last animal is claimed, flip the entry
      // to 'sold_out' so the Trophy Registry shows it as no longer available.
      final newQty = currentQty - 1;
      transaction.update(trophyRef, {
        'availableCount': newQty,
        if (newQty <= 0) 'status': 'sold_out',
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });

    return bookingId;
  }

  /// Restocks a sold-out / low-stock package by setting [quantityAvailable]
  /// and (optionally) re-activating the listing. Only the owning outfitter may
  /// call this. Pass [reactivate] (default true) to flip a `sold_out` package
  /// back to `active` once slots are available again.
  Future<void> restockPackage({
    required String packageId,
    required int quantityAvailable,
    bool reactivate = true,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to restock a package');
    }
    if (quantityAvailable < 1) {
      throw Exception('Restock quantity must be at least 1');
    }

    final packageRef = _firestore.collection('packages').doc(packageId);
    final snap = await packageRef.get();
    if (!snap.exists) {
      throw Exception('Package not found');
    }
    final data = snap.data() as Map<String, dynamic>;
    final currentStatus =
        PackageStatus.fromString(data['status'] as String?);

    final update = <String, dynamic>{
      'quantityAvailable': quantityAvailable,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    // Only re-activate if the package is currently sold out; never override an
    // archived/deleted/draft lifecycle choice from a restock.
    if (reactivate && currentStatus == PackageStatus.soldOut) {
      update['status'] = PackageStatus.active.label;
    }

    await packageRef.update(update);
  }

  // ==========================================
  // UTILITY METHODS
  // ==========================================

  /// Calculate the booking totals without saving. Returns a map with the
  /// total price. There is no platform commission and no deposit split: the
  /// total equals the base price.
  Map<String, double> calculatePricing(double basePriceRands) {
    final double totalPrice = basePriceRands;

    return {
      'basePriceRands': basePriceRands,
      'totalHunterPriceRands': totalPrice,
    };
  }

  /// Get all packages (for marketplace browsing). Includes `active` and
  /// `sold_out` so sold-out listings render read-only in the marketplace.
  Future<QuerySnapshot> getAllPackages() async {
    return await _firestore
        .collection('packages')
        .where('status', whereIn: ['active', 'sold_out'])
        .orderBy('createdAt', descending: true)
        .get();
  }

  /// Get packages published by the current outfitter (all statuses except
  /// soft-deleted). Use [getMyPackagesStream] for a reactive management UI.
  Future<QuerySnapshot> getMyPackages() async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    return await _firestore
        .collection('packages')
        .where('outfitterId', isEqualTo: _currentUserId)
        .orderBy('createdAt', descending: true)
        .get();
  }

  /// Reactive stream of packages published by the current outfitter, scoped to
  /// a lifecycle [status] filter (defaults to all non-deleted packages). Powers
  /// the "My Packages" management screen. With offline persistence enabled the
  /// stream serves cached packages when the network drops; a hard error (e.g.
  /// missing composite index) is surfaced to the consumer's `snapshot.hasError`
  /// branch rather than thrown synchronously.
  Stream<QuerySnapshot> getMyPackagesStream({
    PackageStatus? status,
  }) {
    if (_currentUserId == null) {
      // Unauthenticated callers get a stable empty stream instead of a thrown
      // exception that would crash the screen's StreamBuilder.
      return const Stream.empty();
    }

    var query = _firestore
        .collection('packages')
        .where('outfitterId', isEqualTo: _currentUserId);

    if (status != null) {
      query = query.where('status', isEqualTo: status.label);
    }

    return query.orderBy('createdAt', descending: true).snapshots();
  }

  /// Get bookings for the current user (as hunter or outfitter)
  Future<QuerySnapshot> getMyBookings() async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    return await _firestore
        .collection('bookings')
        .where('hunterId', isEqualTo: _currentUserId)
        .get();
  }

  /// Get bookings received by the current outfitter
  Future<QuerySnapshot> getBookingsForMyPackages() async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    return await _firestore
        .collection('bookings')
        .where('outfitterId', isEqualTo: _currentUserId)
        .get();
  }

  /// Update booking status (for outfitters).
  ///
  /// Accepts any value in [BookingStatus.allStatuses].
  Future<void> updateBookingStatus({
    required String bookingId,
    required String newStatus,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    if (!BookingStatus.allStatuses.contains(newStatus)) {
      throw Exception('Invalid booking status: $newStatus');
    }

    await _firestore.collection('bookings').doc(bookingId).update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks a booking as approved -- transitions the status to
  /// [BookingStatus.approvedAwaitingPayment] ("Awaiting Payment"). The hunter
  /// is then expected to pay the outfitter directly (off-platform). Revenue is
  /// NOT yet realized (the booking only counts toward revenue once the
  /// outfitter verifies payment via [confirmPaymentReceived]).
  ///
  /// Stores the resolved total price on the booking (the hunter pays the base
  /// package cost; there is no platform commission and no deposit split).
  Future<void> approveBookingAndRequestDeposit({
    required String bookingId,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    final snap = await bookingRef.get();
    if (!snap.exists) {
      throw Exception('Booking not found');
    }

    final data = snap.data() as Map<String, dynamic>;
    final basePrice = (data['basePriceRands'] as num?)?.toDouble() ?? 0.0;
    // The hunter pays the base package cost; there is no platform commission.
    final totalPrice = basePrice;

    await bookingRef.update({
      'status': BookingStatus.approvedAwaitingPayment,
      'totalHunterPriceRands': totalPrice,
      'approvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Outfitter verifies that they have received the direct (off-platform)
  /// payment from the hunter. Transitions the booking from
  /// [BookingStatus.approvedAwaitingPayment] to [BookingStatus.confirmed].
  ///
  /// `confirmed` is the first **earned** revenue state -- the booking now
  /// counts toward the outfitter's realized revenue. The booking
  /// automatically moves out of the active-requests view (it is no longer
  /// pending approval or awaiting payment) and into the archived / completed
  /// view.
  ///
  /// Only callable on a booking currently in the `approvedAwaitingPayment`
  /// (or legacy `Approved`) state; a booking in any other state is rejected
  /// (the outfitter cannot confirm payment on a request that hasn't been
  /// approved, or re-confirm an already-confirmed booking).
  Future<void> confirmPaymentReceived({
    required String bookingId,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated');
    }

    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    final snap = await bookingRef.get();
    if (!snap.exists) {
      throw Exception('Booking not found');
    }

    final data = snap.data() as Map<String, dynamic>;
    final currentStatus = data['status'] as String? ?? '';
    // Allow confirmation from the canonical awaiting-payment state, plus the
    // legacy 'Approved' status (pre-payment-verification-flow bookings that
    // were approved under the old lifecycle).
    if (currentStatus != BookingStatus.approvedAwaitingPayment &&
        currentStatus != 'Approved') {
      throw Exception(
        'Payment can only be verified on a booking awaiting payment '
        '(current status: "$currentStatus").',
      );
    }

    await bookingRef.update({
      'status': BookingStatus.confirmed,
      'paymentVerifiedAt': FieldValue.serverTimestamp(),
      'paymentVerified': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==========================================
  // DATE CHANGE REQUESTS
  // ==========================================

  /// Hunter raises a date-change request against a booking. Writes a pending
  /// request to the booking document under the `dateChangeRequest` map and
  /// flags `dateChangeRequestPending: true` for the outfitter dashboard.
  Future<void> requestDateChange({
    required String bookingId,
    required DateChangeRequest request,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to request a date change');
    }

    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    final snap = await bookingRef.get();
    if (!snap.exists) {
      throw Exception('Booking not found');
    }

    final data = snap.data() as Map<String, dynamic>;
    if (data['hunterId'] != _currentUserId) {
      throw Exception(
          'Only the hunter who placed this booking may request a date change');
    }

    await bookingRef.update({
      'dateChangeRequest': {
        ...request.toMap(),
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      },
      'dateChangeRequestPending': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Outfitter resolves a pending date-change request. On approval the booking
  /// dates are updated to the requested dates; on either resolution the
  /// `dateChangeRequestPending` flag is cleared and the request status flips.
  Future<void> resolveDateChange({
    required String bookingId,
    required bool approved,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User must be authenticated to resolve a date change');
    }

    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    final snap = await bookingRef.get();
    if (!snap.exists) {
      throw Exception('Booking not found');
    }

    final data = snap.data() as Map<String, dynamic>;
    if (data['outfitterId'] != _currentUserId) {
      throw Exception(
          'Only the outfitter who owns this booking may resolve a date change');
    }

    final existing =
        data['dateChangeRequest'] as Map<String, dynamic>? ?? {};
    final request = DateChangeRequest.fromMap(existing);

    final update = <String, dynamic>{
      'dateChangeRequestPending': false,
      'dateChangeRequest': {
        ...existing,
        'status': approved ? 'approved' : 'declined',
        'resolvedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (approved) {
      if (request.requestedStartDate != null) {
        update['confirmedStartDate'] =
            Timestamp.fromDate(request.requestedStartDate!);
      }
      if (request.requestedEndDate != null) {
        update['confirmedEndDate'] =
            Timestamp.fromDate(request.requestedEndDate!);
      }
    }

    await bookingRef.update(update);
  }

  /// Soft-deletes a package owned by the current outfitter by marking its
  /// status `deleted`. The document is retained so existing booking references
  /// and audit history remain intact; deleted packages never appear in the
  /// marketplace or the "My Packages" management list.
  ///
  /// Use [setPackageStatus] with [PackageStatus.active] to restore a package.
  ///
  /// Throws: Exception if not authenticated or the update fails.
  Future<void> deletePackage(String packageId) async {
    await setPackageStatus(
      packageId: packageId,
      status: PackageStatus.deleted,
    );
  }

  // ==========================================
  // AMMUNITION MANAGER - CALIBER MATCHING
  // ==========================================
  /// Stream or query factory ammunition inventory matching selected firearm caliber.
  /// Enforces structural caliber dimension filter constraints.
  Stream<QuerySnapshot> getFactoryAmmunitionByCaliber(String firearmCaliber) {
    return _firestore
        .collection('factory_ammunition')
        .where('caliber', isEqualTo: firearmCaliber)
        .snapshots();
  }

  /// Fetch snapshot of factory ammunition matching selected firearm caliber.
  Future<QuerySnapshot> fetchFactoryAmmunitionByCaliber(
    String firearmCaliber,
  ) async {
    return await _firestore
        .collection('factory_ammunition')
        .where('caliber', isEqualTo: firearmCaliber)
        .get();
  }
}
