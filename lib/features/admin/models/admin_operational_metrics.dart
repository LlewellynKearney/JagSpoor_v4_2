import 'package:cloud_firestore/cloud_firestore.dart';

import '../../hunter_mode/models/booking_status.dart';

/// The nine South African provinces, in the canonical order the marketplace /
/// trophy-browser dropdowns use. Used as the fixed bucket set for the
/// "Packages Per Province" breakdown so an unlisted / missing province lands in
/// the "Unknown Province" bucket rather than silently disappearing.
const List<String> kSaProvinces = [
  'Limpopo',
  'Mpumalanga',
  'Gauteng',
  'North West',
  'Free State',
  'KwaZulu-Natal',
  'Eastern Cape',
  'Western Cape',
  'Northern Cape',
];

/// The label for packages whose farm (or farm province) could not be resolved.
const String kUnknownProvince = 'Unknown Province';

/// Parses a Firestore date-ish value (Timestamp / DateTime / ISO string / num)
/// into a local [DateTime], or `null`. Mirrors the parsing in
/// `AdminUserRecord` so the operational metrics tolerate the same document
/// shapes without throwing.
DateTime? adminParseDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  return null;
}

/// The number of whole days between [from] and [to] (never negative), or `null`
/// when either endpoint is unknown.
int? adminDaysBetween(DateTime? from, DateTime? to) {
  if (from == null || to == null) return null;
  final days = to.difference(from).inDays;
  return days < 0 ? 0 : days;
}

/// A single `packages/{id}` document reduced to the fields the admin package
/// KPIs need.
///
/// `province` / `town` are NOT stored on the package document (the brief's
/// warning) — they are resolved by joining `farms/{farmId}` via [farmId]. The
/// [resolvedProvince] is therefore filled in by the service after the join and
/// left blank here.
class AdminPackageRecord {
  final String id;
  final String outfitterId;
  final String title;
  final String farmId;
  final String status;
  final int quantityAvailable;
  final DateTime? createdAt;

  /// The province resolved from `farms/{farmId}` (set by the service join), or
  /// empty when the farm / province could not be resolved.
  final String resolvedProvince;

  const AdminPackageRecord({
    required this.id,
    this.outfitterId = '',
    this.title = '',
    this.farmId = '',
    this.status = '',
    this.quantityAvailable = 0,
    this.createdAt,
    this.resolvedProvince = '',
  });

  /// Whether the package is a bookable listing (`status == 'active'`).
  bool get isActive => status.trim().toLowerCase() == 'active';

  /// Whether the package is sold out — either the explicit `sold_out` status or
  /// a non-positive remaining quantity. Mirrors `PackageQuantity.isSoldOut`.
  bool get isSoldOut {
    final s = status.trim().toLowerCase();
    return s == 'sold_out' || quantityAvailable <= 0;
  }

  /// Whether the package sits in a draft / archived / deleted bucket.
  bool get isDraftArchived {
    final s = status.trim().toLowerCase();
    return s == 'draft' || s == 'archived' || s == 'deleted';
  }

  /// The province bucket this package counts toward: the resolved farm
  /// province when known, otherwise [kUnknownProvince].
  String get provinceBucket =>
      resolvedProvince.trim().isEmpty ? kUnknownProvince : resolvedProvince;

  /// A copy with the resolved farm province filled in.
  AdminPackageRecord withProvince(String province) => AdminPackageRecord(
        id: id,
        outfitterId: outfitterId,
        title: title,
        farmId: farmId,
        status: status,
        quantityAvailable: quantityAvailable,
        createdAt: createdAt,
        resolvedProvince: province,
      );

  /// Parses a `packages/{id}` document. Every field is defaulted so a partial /
  /// legacy document parses without throwing.
  factory AdminPackageRecord.fromMap(String id, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    final qty = d['quantityAvailable'];
    return AdminPackageRecord(
      id: id,
      outfitterId: (d['outfitterId'] ?? '').toString().trim(),
      title: (d['title'] ?? '').toString().trim(),
      farmId: (d['farmId'] ?? '').toString().trim(),
      status: (d['status'] ?? '').toString().trim().toLowerCase(),
      quantityAvailable: qty is num ? qty.toInt() : 0,
      createdAt: adminParseDate(d['createdAt']) ?? adminParseDate(d['created_at']),
    );
  }
}

/// A single `bookings/{id}` document reduced to the fields the admin booking
/// KPIs need.
///
/// `confirmedAt` does NOT exist on real bookings (the brief's warning) — the
/// payment-verified timestamp is [paymentVerifiedAt], and only rows with
/// [paymentVerified] == true are treated as payment-confirmed for the
/// "Avg Days To Confirm" metric.
class AdminBookingRecord {
  final String id;
  final String status;
  final String hunterId;
  final String outfitterId;
  final String packageId;
  final String packageName;
  final DateTime? createdAt;
  final DateTime? paymentVerifiedAt;
  final bool paymentVerified;

  const AdminBookingRecord({
    required this.id,
    this.status = '',
    this.hunterId = '',
    this.outfitterId = '',
    this.packageId = '',
    this.packageName = '',
    this.createdAt,
    this.paymentVerifiedAt,
    this.paymentVerified = false,
  });

  /// The canonical booking status (tolerant of legacy case / spelling variants
  /// via [BookingStatus.normalize]), or the raw trimmed string when unknown.
  String get normalizedStatus =>
      BookingStatus.normalize(status) ?? status.trim();

  bool get isPendingApproval =>
      BookingStatus.normalize(status) == BookingStatus.pendingApproval;
  bool get isConfirmed =>
      BookingStatus.normalize(status) == BookingStatus.confirmed;
  bool get isCompleted =>
      BookingStatus.normalize(status) == BookingStatus.completed;

  /// Whether the booking counts as "confirmed" for the conversion metric — the
  /// earned states (Confirmed + Completed).
  bool get isEarned => isConfirmed || isCompleted;

  /// Whether the booking is a stuck pending request (Pending Approval older
  /// than [thresholdDays]).
  bool isStuckPending(DateTime now, {int thresholdDays = 7}) {
    if (!isPendingApproval) return false;
    final created = createdAt;
    if (created == null) return false;
    return now.difference(created).inDays > thresholdDays;
  }

  /// The days elapsed from creation to payment verification, or `null` when
  /// either timestamp is missing (the brief: do NOT use `confirmedAt`).
  int? get daysToConfirm => adminDaysBetween(createdAt, paymentVerifiedAt);

  /// Parses a `bookings/{id}` document.
  factory AdminBookingRecord.fromMap(String id, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    return AdminBookingRecord(
      id: id,
      status: (d['status'] ?? '').toString().trim(),
      hunterId: (d['hunterId'] ?? '').toString().trim(),
      outfitterId: (d['outfitterId'] ?? '').toString().trim(),
      packageId: (d['packageId'] ?? '').toString().trim(),
      packageName: (d['packageName'] ?? '').toString().trim(),
      createdAt: adminParseDate(d['createdAt']) ?? adminParseDate(d['created_at']),
      paymentVerifiedAt: adminParseDate(d['paymentVerifiedAt']) ??
          adminParseDate(d['payment_verified_at']),
      paymentVerified: d['paymentVerified'] == true,
    );
  }
}

/// A package that is active but has zero bookings — surfaced as a
/// "needs attention" row so an operator can nudge the outfitter.
class ZeroBookingPackage {
  final String id;
  final String title;
  final String outfitterEmail;
  final DateTime? createdAt;
  final int daysLive;

  const ZeroBookingPackage({
    required this.id,
    required this.title,
    required this.outfitterEmail,
    required this.createdAt,
    required this.daysLive,
  });
}

/// A booking stuck in Pending Approval for more than the threshold.
class StuckBooking {
  final String id;
  final String hunterEmail;
  final String outfitterEmail;
  final String packageTitle;
  final int daysStuck;

  const StuckBooking({
    required this.id,
    required this.hunterEmail,
    required this.outfitterEmail,
    required this.packageTitle,
    required this.daysStuck,
  });
}

/// One row of the "Top Outfitters By Bookings" table.
class OutfitterBookingRow {
  final String outfitterId;
  final String name;
  final String email;
  final int total;
  final int confirmed;
  final double conversionPercent;

  const OutfitterBookingRow({
    required this.outfitterId,
    required this.name,
    required this.email,
    required this.total,
    required this.confirmed,
    required this.conversionPercent,
  });

  /// The conversion rendered to one decimal place (e.g. `"66.7%"`).
  String get conversionLabel => '${conversionPercent.toStringAsFixed(1)}%';
}

/// The Admin Portal V2 package-level KPI bundle.
class AdminPackageMetrics {
  final int totalPackages;
  final int activePackages;
  final int soldOutPackages;
  final int draftArchivedPackages;

  /// Active-package counts per province, keyed by the nine SA provinces plus
  /// [kUnknownProvince]. Always contains every key (zero when absent) so the
  /// breakdown reconciles.
  final Map<String, int> activeByProvince;

  /// Active packages with no booking referencing them.
  final List<ZeroBookingPackage> zeroBookingPackages;

  /// Outfitters (from the `outfitters` collection) owning zero packages.
  final int outfittersWithZeroPackages;

  const AdminPackageMetrics({
    this.totalPackages = 0,
    this.activePackages = 0,
    this.soldOutPackages = 0,
    this.draftArchivedPackages = 0,
    this.activeByProvince = const {},
    this.zeroBookingPackages = const [],
    this.outfittersWithZeroPackages = 0,
  });

  /// The province buckets in canonical order (the nine provinces + Unknown).
  List<MapEntry<String, int>> get provinceBreakdown {
    final keys = [...kSaProvinces, kUnknownProvince];
    return [
      for (final k in keys) MapEntry(k, activeByProvince[k] ?? 0),
    ];
  }

  /// Aggregates the package KPIs locally. Pure + synchronous.
  ///
  /// [bookingPackageIds] is the set of `packageId`s referenced by ANY booking
  /// (regardless of status) — a package with a booking is not "zero bookings".
  /// [outfitterIds] is the set of every outfitter uid (from the `outfitters`
  /// collection) used for the "Outfitters With 0 Packages" count.
  /// [emailByUid] resolves an outfitter uid to an email for the zero-booking
  /// rows.
  factory AdminPackageMetrics.aggregate(
    Iterable<AdminPackageRecord> packages, {
    required Set<String> bookingPackageIds,
    required Set<String> outfitterIds,
    Map<String, String> emailByUid = const {},
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    var total = 0;
    var active = 0;
    var soldOut = 0;
    var draftArchived = 0;
    final byProvince = <String, int>{for (final p in kSaProvinces) p: 0};
    byProvince[kUnknownProvince] = 0;
    final zeroBooking = <ZeroBookingPackage>[];
    final outfittersWithPackages = <String>{};

    for (final p in packages) {
      total++;
      if (p.isSoldOut) soldOut++;
      if (p.isDraftArchived) draftArchived++;
      if (p.outfitterId.isNotEmpty) outfittersWithPackages.add(p.outfitterId);
      if (p.isActive) {
        active++;
        final bucket = p.provinceBucket;
        byProvince[bucket] = (byProvince[bucket] ?? 0) + 1;
        if (!bookingPackageIds.contains(p.id)) {
          zeroBooking.add(ZeroBookingPackage(
            id: p.id,
            title: p.title.isEmpty ? '(untitled package)' : p.title,
            outfitterEmail: emailByUid[p.outfitterId] ?? '',
            createdAt: p.createdAt,
            daysLive: adminDaysBetween(p.createdAt, ref) ?? 0,
          ));
        }
      }
    }

    var zeroOutfitters = 0;
    for (final uid in outfitterIds) {
      if (!outfittersWithPackages.contains(uid)) zeroOutfitters++;
    }

    return AdminPackageMetrics(
      totalPackages: total,
      activePackages: active,
      soldOutPackages: soldOut,
      draftArchivedPackages: draftArchived,
      activeByProvince: byProvince,
      zeroBookingPackages: zeroBooking,
      outfittersWithZeroPackages: zeroOutfitters,
    );
  }
}

/// The Admin Portal V2 booking-level KPI bundle.
class AdminBookingMetrics {
  final int totalBookings;

  /// Counts keyed by the six canonical [BookingStatus] values.
  final Map<String, int> byStatus;

  /// Bookings stuck in Pending Approval for more than the threshold.
  final List<StuckBooking> stuckPending;

  /// The top five outfitters by booking count.
  final List<OutfitterBookingRow> topOutfitters;

  /// Average days from booking creation to payment verification, or `null`
  /// when no earned booking carries a `paymentVerifiedAt`.
  final double? avgDaysToConfirm;

  const AdminBookingMetrics({
    this.totalBookings = 0,
    this.byStatus = const {},
    this.stuckPending = const [],
    this.topOutfitters = const [],
    this.avgDaysToConfirm,
  });

  /// `(Confirmed + Completed) / Total * 100`, one decimal, `0.0` when total 0.
  double get conversionPercent {
    if (totalBookings <= 0) return 0.0;
    final earned = (byStatus[BookingStatus.confirmed] ?? 0) +
        (byStatus[BookingStatus.completed] ?? 0);
    return earned / totalBookings * 100.0;
  }

  String get conversionLabel => '${conversionPercent.toStringAsFixed(1)}%';

  /// The average-days value rendered to one decimal place, or `"—"`.
  String get avgDaysLabel =>
      avgDaysToConfirm == null ? '—' : avgDaysToConfirm!.toStringAsFixed(1);

  /// Aggregates the booking KPIs locally. Pure + synchronous.
  ///
  /// [emailByUid] resolves a uid to an email (hunter / outfitter) so the
  /// stuck-pending list + the top-outfitter table can show addresses without a
  /// further read. [outfitterNameByUid] supplies the display name.
  /// [packageTitleById] resolves a booking's package title.
  factory AdminBookingMetrics.aggregate(
    Iterable<AdminBookingRecord> bookings, {
    required Map<String, String> emailByUid,
    Map<String, String> outfitterNameByUid = const {},
    Map<String, String> packageTitleById = const {},
    int stuckThresholdDays = 7,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    var total = 0;
    final byStatus = <String, int>{
      for (final s in BookingStatus.allStatuses) s: 0,
    };
    final stuck = <StuckBooking>[];
    final perOutfitter = <String, _OutfitterTally>{};
    var confirmDaysSum = 0;
    var confirmDaysCount = 0;

    String emailFor(String uid) => emailByUid[uid] ?? '';

    for (final b in bookings) {
      total++;
      final status = b.normalizedStatus;
      byStatus[status] = (byStatus[status] ?? 0) + 1;

      if (b.isStuckPending(ref, thresholdDays: stuckThresholdDays)) {
        final days = b.createdAt == null ? 0 : ref.difference(b.createdAt!).inDays;
        stuck.add(StuckBooking(
          id: b.id,
          hunterEmail: emailFor(b.hunterId),
          outfitterEmail: emailFor(b.outfitterId),
          packageTitle: b.packageName.isNotEmpty
              ? b.packageName
              : (packageTitleById[b.packageId] ?? b.packageId),
          daysStuck: days,
        ));
      }

      if (b.outfitterId.isNotEmpty) {
        final tally =
            perOutfitter.putIfAbsent(b.outfitterId, () => _OutfitterTally());
        tally.total++;
        if (b.isEarned) tally.confirmed++;
      }

      // "Avg Days To Confirm" uses ONLY payment-verified earned bookings with
      // a real paymentVerifiedAt (never `confirmedAt`, which does not exist).
      if (b.isEarned && b.paymentVerified && b.paymentVerifiedAt != null) {
        final days = b.daysToConfirm;
        if (days != null) {
          confirmDaysSum += days;
          confirmDaysCount++;
        }
      }
    }

    final rows = <OutfitterBookingRow>[];
    for (final entry in perOutfitter.entries) {
      final tally = entry.value;
      rows.add(OutfitterBookingRow(
        outfitterId: entry.key,
        name: outfitterNameByUid[entry.key] ?? '',
        email: emailFor(entry.key),
        total: tally.total,
        confirmed: tally.confirmed,
        conversionPercent:
            tally.total == 0 ? 0.0 : tally.confirmed / tally.total * 100.0,
      ));
    }
    rows.sort((a, b) {
      final byTotal = b.total.compareTo(a.total);
      if (byTotal != 0) return byTotal;
      return b.confirmed.compareTo(a.confirmed);
    });

    stuck.sort((a, b) => b.daysStuck.compareTo(a.daysStuck));

    return AdminBookingMetrics(
      totalBookings: total,
      byStatus: byStatus,
      stuckPending: stuck,
      topOutfitters: rows.take(5).toList(),
      avgDaysToConfirm:
          confirmDaysCount == 0 ? null : confirmDaysSum / confirmDaysCount,
    );
  }
}

class _OutfitterTally {
  int total = 0;
  int confirmed = 0;
}
