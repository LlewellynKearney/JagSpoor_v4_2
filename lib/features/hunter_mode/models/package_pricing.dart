import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle status for a hunting package.
///
/// - [active]    — visible in the marketplace and bookable by hunters.
/// - [draft]     — saved but hidden from the marketplace (work in progress).
/// - [archived]  — retired from the marketplace but retained for history.
/// - [deleted]   — soft-deleted (excluded from all listings; recoverable).
enum PackageStatus {
  active,
  draft,
  archived,
  deleted;

  String get label {
    switch (this) {
      case PackageStatus.active:
        return 'active';
      case PackageStatus.draft:
        return 'draft';
      case PackageStatus.archived:
        return 'archived';
      case PackageStatus.deleted:
        return 'deleted';
    }
  }

  static PackageStatus fromString(String? value) {
    switch (value) {
      case 'draft':
        return PackageStatus.draft;
      case 'archived':
        return PackageStatus.archived;
      case 'deleted':
        return PackageStatus.deleted;
      default:
        return PackageStatus.active;
    }
  }

  /// Whether the package should appear in the public marketplace.
  bool get isListed => this == PackageStatus.active;
}

/// Pricing mode for a hunting package.
enum PackagePricingMode {
  /// Outfitter inputs a single total package price.
  allInclusive,

  /// Outfitter expands a full breakdown of line items + species.
  itemized;

  String get label {
    switch (this) {
      case PackagePricingMode.allInclusive:
        return 'all_inclusive';
      case PackagePricingMode.itemized:
        return 'itemized';
    }
  }

  static PackagePricingMode fromString(String? value) {
    if (value == 'itemized') return PackagePricingMode.itemized;
    return PackagePricingMode.allInclusive;
  }
}

/// A single itemized cost line (e.g. "Bakkie / Hunting Vehicle Fees").
///
/// The [total] is `quantity * pricePerUnit`.
class ItemizedLineItem {
  final String key;
  final String label;
  final int quantity;
  final double pricePerUnit;

  const ItemizedLineItem({
    required this.key,
    required this.label,
    required this.quantity,
    required this.pricePerUnit,
  });

  double get total => quantity * pricePerUnit;

  Map<String, dynamic> toMap() => {
        'key': key,
        'label': label,
        'quantity': quantity,
        'pricePerUnit': pricePerUnit,
        'total': total,
      };

  factory ItemizedLineItem.fromMap(Map<String, dynamic> map) {
    return ItemizedLineItem(
      key: map['key'] as String? ?? '',
      label: map['label'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      pricePerUnit: (map['pricePerUnit'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// A species line item drawn from the SA Game Guide taxonomy list.
class SpeciesLineItem {
  final String speciesId;
  final String speciesName;
  final int quantity;
  final double pricePerAnimal;

  const SpeciesLineItem({
    required this.speciesId,
    required this.speciesName,
    required this.quantity,
    required this.pricePerAnimal,
  });

  double get total => quantity * pricePerAnimal;

  Map<String, dynamic> toMap() => {
        'speciesId': speciesId,
        'speciesName': speciesName,
        'quantity': quantity,
        'pricePerAnimal': pricePerAnimal,
        'total': total,
      };

  factory SpeciesLineItem.fromMap(Map<String, dynamic> map) {
    return SpeciesLineItem(
      speciesId: map['speciesId'] as String? ?? '',
      speciesName: map['speciesName'] as String? ?? 'Unknown',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      pricePerAnimal: (map['pricePerAnimal'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// The seven standard itemized breakdown categories used by the publisher.
class ItemizedBreakdownCategory {
  final String key;
  final String label;

  const ItemizedBreakdownCategory(this.key, this.label);

  static const List<ItemizedBreakdownCategory> all = [
    ItemizedBreakdownCategory('bakkie_vehicle', 'Bakkie / Hunting Vehicle Fees'),
    ItemizedBreakdownCategory('slaughtering', 'Slaughtering Fees'),
    ItemizedBreakdownCategory('coldroom', 'Coldroom / Cold Storage Fees'),
    ItemizedBreakdownCategory('hunter_daily', 'Hunter Daily Fees'),
    ItemizedBreakdownCategory(
        'non_hunter_observer_daily', 'Non-Hunter Observer Daily Fees'),
    ItemizedBreakdownCategory(
        'overnight_accommodation', 'Overnight Accommodation Fees (Per Hunter / Non-Hunter)'),
    ItemizedBreakdownCategory('catering', 'Catering Services'),
  ];
}

/// Full pricing definition for a hunting package.
class PackagePricing {
  final PackagePricingMode mode;

  /// Used when [mode] is [PackagePricingMode.allInclusive].
  final double allInclusivePrice;

  /// Used when [mode] is [PackagePricingMode.itemized].
  final List<ItemizedLineItem> lineItems;

  /// Species selections (used in itemized mode; may also supplement an
  /// all-inclusive package when the outfitter wants to advertise species).
  final List<SpeciesLineItem> speciesItems;

  /// Availability window for the package.
  final DateTime? availabilityStart;
  final DateTime? availabilityEnd;

  const PackagePricing({
    required this.mode,
    this.allInclusivePrice = 0.0,
    this.lineItems = const [],
    this.speciesItems = const [],
    this.availabilityStart,
    this.availabilityEnd,
  });

  /// Outfitter's base price (before the 7.5% platform fee).
  double get basePrice {
    switch (mode) {
      case PackagePricingMode.allInclusive:
        return allInclusivePrice;
      case PackagePricingMode.itemized:
        double sum = 0;
        for (final item in lineItems) {
          sum += item.total;
        }
        for (final species in speciesItems) {
          sum += species.total;
        }
        return sum;
    }
  }

  Map<String, dynamic> toMap() => {
        'mode': mode.label,
        'allInclusivePrice': allInclusivePrice,
        'lineItems': lineItems.map((e) => e.toMap()).toList(),
        'speciesItems': speciesItems.map((e) => e.toMap()).toList(),
        'availabilityStart': availabilityStart != null
            ? Timestamp.fromDate(availabilityStart!)
            : null,
        'availabilityEnd': availabilityEnd != null
            ? Timestamp.fromDate(availabilityEnd!)
            : null,
      };

  factory PackagePricing.fromMap(Map<String, dynamic> map) {
    final lineItemsRaw = map['lineItems'];
    final speciesRaw = map['speciesItems'];

    return PackagePricing(
      mode: PackagePricingMode.fromString(map['mode'] as String?),
      allInclusivePrice:
          (map['allInclusivePrice'] as num?)?.toDouble() ?? 0.0,
      lineItems: lineItemsRaw is List
          ? lineItemsRaw
              .whereType<Map>()
              .map((e) =>
                  ItemizedLineItem.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      speciesItems: speciesRaw is List
          ? speciesRaw
              .whereType<Map>()
              .map((e) =>
                  SpeciesLineItem.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      availabilityStart: _toDate(map['availabilityStart']),
      availabilityEnd: _toDate(map['availabilityEnd']),
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// A date-change request raised by a hunter against an approved/paid booking.
class DateChangeRequest {
  final DateTime? requestedStartDate;
  final DateTime? requestedEndDate;
  final String reason;

  /// 'pending' | 'approved' | 'declined'
  final String status;
  final DateTime? requestedAt;
  final DateTime? resolvedAt;

  const DateChangeRequest({
    this.requestedStartDate,
    this.requestedEndDate,
    required this.reason,
    this.status = 'pending',
    this.requestedAt,
    this.resolvedAt,
  });

  bool get isPending => status == 'pending';

  Map<String, dynamic> toMap() => {
        'requestedStartDate': requestedStartDate != null
            ? Timestamp.fromDate(requestedStartDate!)
            : null,
        'requestedEndDate': requestedEndDate != null
            ? Timestamp.fromDate(requestedEndDate!)
            : null,
        'reason': reason,
        'status': status,
        'requestedAt':
            requestedAt != null ? Timestamp.fromDate(requestedAt!) : null,
        'resolvedAt':
            resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
      };

  factory DateChangeRequest.fromMap(Map<String, dynamic> map) {
    return DateChangeRequest(
      requestedStartDate: PackagePricing._toDate(map['requestedStartDate']),
      requestedEndDate: PackagePricing._toDate(map['requestedEndDate']),
      reason: map['reason'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      requestedAt: PackagePricing._toDate(map['requestedAt']),
      resolvedAt: PackagePricing._toDate(map['resolvedAt']),
    );
  }
}
