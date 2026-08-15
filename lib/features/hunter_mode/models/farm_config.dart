/// Per-farm cost configuration for the Custom Package Builder.
class FarmCostConfig {
  /// Daily rate per hunter (ZAR/day).
  final double? dailyRateHunter;

  /// Daily rate per non-hunter observer (ZAR/day).
  final double? dailyRateObserver;

  /// Accommodation rate per person per night (ZAR).
  final double? accommodationPerNight;

  /// Catering rate per person per day (ZAR).
  final double? cateringPerDay;

  /// Once-off vehicle/bakkie fee (ZAR).
  final double? vehicleFee;

  /// Once-off guide/PH fee (ZAR).
  final double? guideFee;

  /// Free-form additional package-builder options the outfitter offers at this
  /// farm (e.g. "Game drive — R350", "Airport transfer — R600"). Each entry is
  /// `{name, priceZAR}`.
  final List<FarmExtraOption> extraOptions;

  const FarmCostConfig({
    this.dailyRateHunter,
    this.dailyRateObserver,
    this.accommodationPerNight,
    this.cateringPerDay,
    this.vehicleFee,
    this.guideFee,
    this.extraOptions = const [],
  });

  /// Zero-cost config used as a safe default when a farm has no cost config.
  static const FarmCostConfig empty = FarmCostConfig();

  bool get isEmpty =>
      dailyRateHunter == null &&
      dailyRateObserver == null &&
      accommodationPerNight == null &&
      cateringPerDay == null &&
      vehicleFee == null &&
      guideFee == null &&
      extraOptions.isEmpty;

  Map<String, dynamic> toMap() => {
        if (dailyRateHunter != null) 'dailyRateHunter': dailyRateHunter,
        if (dailyRateObserver != null) 'dailyRateObserver': dailyRateObserver,
        if (accommodationPerNight != null)
          'accommodationPerNight': accommodationPerNight,
        if (cateringPerDay != null) 'cateringPerDay': cateringPerDay,
        if (vehicleFee != null) 'vehicleFee': vehicleFee,
        if (guideFee != null) 'guideFee': guideFee,
        if (extraOptions.isNotEmpty)
          'extraOptions': extraOptions.map((e) => e.toMap()).toList(),
      };

  static FarmCostConfig fromMap(Map<String, dynamic>? map) {
    if (map == null) return const FarmCostConfig();
    return FarmCostConfig(
      dailyRateHunter: (map['dailyRateHunter'] as num?)?.toDouble(),
      dailyRateObserver: (map['dailyRateObserver'] as num?)?.toDouble(),
      accommodationPerNight:
          (map['accommodationPerNight'] as num?)?.toDouble(),
      cateringPerDay: (map['cateringPerDay'] as num?)?.toDouble(),
      vehicleFee: (map['vehicleFee'] as num?)?.toDouble(),
      guideFee: (map['guideFee'] as num?)?.toDouble(),
      extraOptions: (map['extraOptions'] as List?)
              ?.map((e) => FarmExtraOption.fromMap(
                  e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
    );
  }

  FarmCostConfig copyWith({
    double? dailyRateHunter,
    double? dailyRateObserver,
    double? accommodationPerNight,
    double? cateringPerDay,
    double? vehicleFee,
    double? guideFee,
    List<FarmExtraOption>? extraOptions,
  }) =>
      FarmCostConfig(
        dailyRateHunter: dailyRateHunter ?? this.dailyRateHunter,
        dailyRateObserver: dailyRateObserver ?? this.dailyRateObserver,
        accommodationPerNight:
            accommodationPerNight ?? this.accommodationPerNight,
        cateringPerDay: cateringPerDay ?? this.cateringPerDay,
        vehicleFee: vehicleFee ?? this.vehicleFee,
        guideFee: guideFee ?? this.guideFee,
        extraOptions: extraOptions ?? this.extraOptions,
      );
}

/// A single additional package-builder option offered at a farm
/// (e.g. "Game drive — R350").
class FarmExtraOption {
  final String name;
  final double priceZAR;

  const FarmExtraOption({required this.name, required this.priceZAR});

  Map<String, dynamic> toMap() => {'name': name, 'priceZAR': priceZAR};

  static FarmExtraOption fromMap(Map<String, dynamic> map) => FarmExtraOption(
        name: (map['name'] as String?) ?? '',
        priceZAR: (map['priceZAR'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Per-farm PayFast merchant profile for direct payout routing.
///
/// When attached to a farm, hunter deposit payments for custom packages built
/// against that farm are routed to this farm's PayFast merchant account
/// (instead of the platform default sandbox merchant). Stored as a nested
/// `payfastProfile` map on the `farms/{farmId}` document; owner-scoped write
/// via the existing `farms` Firestore rule.
///
/// **Security note**: the merchant key + passphrase are credentials. They are
/// stored on the owner-scoped farm document (only the outfitter can write;
/// reads are signed-in for the marketplace farm-selection flow). For a
/// production hardening pass, prefer routing deposits through a Cloud Function
/// that holds the passphrase server-side and signs the PayFast request, so the
/// passphrase never reaches the client. The per-farm profile here enables the
/// direct-routing MVP requested by the task.
class FarmPayFastProfile {
  /// PayFast merchant ID.
  final String merchantId;

  /// PayFast merchant key.
  final String merchantKey;

  /// PayFast passphrase (used for signature generation). May be empty when the
  /// merchant account has no passphrase set.
  final String passphrase;

  /// When true, use the PayFast **live** host instead of the sandbox host for
  /// this farm's deposits.
  final bool useLive;

  const FarmPayFastProfile({
    required this.merchantId,
    required this.merchantKey,
    this.passphrase = '',
    this.useLive = false,
  });

  /// A profile is considered configured (usable for direct routing) when it
  /// has a non-empty merchant id + key.
  bool get isConfigured =>
      merchantId.trim().isNotEmpty && merchantKey.trim().isNotEmpty;

  static const FarmPayFastProfile empty =
      FarmPayFastProfile(merchantId: '', merchantKey: '');

  Map<String, dynamic> toMap() => {
        'merchantId': merchantId,
        'merchantKey': merchantKey,
        if (passphrase.isNotEmpty) 'passphrase': passphrase,
        'useLive': useLive,
      };

  static FarmPayFastProfile fromMap(Map<String, dynamic>? map) {
    if (map == null) return FarmPayFastProfile.empty;
    return FarmPayFastProfile(
      merchantId: (map['merchantId'] as String?) ?? '',
      merchantKey: (map['merchantKey'] as String?) ?? '',
      passphrase: (map['passphrase'] as String?) ?? '',
      useLive: (map['useLive'] as bool?) ?? false,
    );
  }

  FarmPayFastProfile copyWith({
    String? merchantId,
    String? merchantKey,
    String? passphrase,
    bool? useLive,
  }) =>
      FarmPayFastProfile(
        merchantId: merchantId ?? this.merchantId,
        merchantKey: merchantKey ?? this.merchantKey,
        passphrase: passphrase ?? this.passphrase,
        useLive: useLive ?? this.useLive,
      );
}

/// Sentinel `FieldValue` helpers for merging nested farm config maps without
/// clobbering sibling fields. Kept here so the manager + UI share one shape.
class FarmConfigField {
  static const String costConfig = 'costConfig';
  static const String payfastProfile = 'payfastProfile';
}

/// A single animal available for hunting at a farm, derived from the farm's
/// active scanned price list.
class FarmAnimalListing {
  /// Canonical system species id (e.g. "Greater Kudu").
  final String speciesId;

  /// Display label as scanned (preserves Afrikaans + sex/class + size tier).
  final String displayLabel;

  /// Normalized sex bucket: 'Male', 'Female', 'Young Male', or ''.
  final String sex;

  /// Original sex/class token (e.g. 'Bul', 'Koei').
  final String sexLabel;

  /// Trophy size range token (e.g. '>50"') or ''.
  final String trophySizeRange;

  /// Outfitter base price per animal in ZAR (before 7.5% commission).
  final double basePriceZAR;

  /// Hunter-facing price per animal in ZAR (base × 1.075, incl. commission).
  final double hunterPriceZAR;

  /// Max animals available/allowed at this price, or `null` (unlimited).
  final int? quantityLimit;

  const FarmAnimalListing({
    required this.speciesId,
    required this.displayLabel,
    required this.sex,
    required this.sexLabel,
    required this.trophySizeRange,
    required this.basePriceZAR,
    required this.hunterPriceZAR,
    this.quantityLimit,
  });

  @override
  String toString() =>
      'FarmAnimalListing($displayLabel | R$basePriceZAR | qty<=$quantityLimit)';
}

/// A fee line at a farm (daily rate, accommodation, vehicle, guide, etc.).
class FarmFeeListing {
  final String feeType;
  final String displayLabel;
  final double basePriceZAR;
  final double hunterPriceZAR;
  final int? quantityLimit;

  const FarmFeeListing({
    required this.feeType,
    required this.displayLabel,
    required this.basePriceZAR,
    required this.hunterPriceZAR,
    this.quantityLimit,
  });
}

/// Structured hunting catalog for a farm: the animals available for hunting
/// (with per-animal prices + quantity limits) plus the fee lines, grouped
/// from the farm's most-recent active scanned price list. Pure transformation
/// of a `scanned_pricelists` doc — unit-testable without Firestore.
class FarmHuntingCatalog {
  final String farmId;
  final String farmName;
  final String outfitterId;
  final String pricelistId;
  final List<FarmAnimalListing> animals;
  final List<FarmFeeListing> fees;

  const FarmHuntingCatalog({
    required this.farmId,
    required this.farmName,
    required this.outfitterId,
    required this.pricelistId,
    required this.animals,
    required this.fees,
  });

  /// Builds a [FarmHuntingCatalog] from a raw `scanned_pricelists` doc map
  /// (the shape returned by `getActivePricelistForFarm`). Splits the `items`
  /// list into animals (`itemType == 'species'`) and fees (`itemType == 'fee'`).
  factory FarmHuntingCatalog.fromPricelist(Map<String, dynamic> pricelist) {
    final items = (pricelist['items'] as List?) ?? const [];
    final animals = <FarmAnimalListing>[];
    final fees = <FarmFeeListing>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final itemType = (item['itemType'] ?? 'species').toString();
      final base = (item['outfitterBasePrice'] as num?)?.toDouble() ?? 0.0;
      final hunter = (item['hunterDisplayPriceZAR'] as num?)?.toDouble() ??
          base * 1.075;
      final qty = item['quantityLimit'] is int
          ? item['quantityLimit'] as int
          : (item['quantityLimit'] is num
              ? (item['quantityLimit'] as num).toInt()
              : int.tryParse('${item['quantityLimit'] ?? ''}'));
      final qtyLimit = (qty != null && qty > 0) ? qty : null;
      if (itemType == 'fee') {
        fees.add(FarmFeeListing(
          feeType: (item['feeType'] ?? '').toString(),
          displayLabel: (item['displayLabel'] ?? item['name'] ?? '').toString(),
          basePriceZAR: base,
          hunterPriceZAR: hunter,
          quantityLimit: qtyLimit,
        ));
      } else {
        animals.add(FarmAnimalListing(
          speciesId: (item['speciesId'] ?? item['speciesName'] ?? '').toString(),
          displayLabel: (item['displayLabel'] ?? item['name'] ?? '').toString(),
          sex: (item['sex'] ?? '').toString(),
          sexLabel: (item['sexLabel'] ?? '').toString(),
          trophySizeRange: (item['trophySizeRange'] ?? '').toString(),
          basePriceZAR: base,
          hunterPriceZAR: hunter,
          quantityLimit: qtyLimit,
        ));
      }
    }
    return FarmHuntingCatalog(
      farmId: (pricelist['farmId'] ?? '').toString(),
      farmName: (pricelist['farmName'] ?? '').toString(),
      outfitterId: (pricelist['outfitterId'] ?? '').toString(),
      pricelistId: (pricelist['id'] ?? '').toString(),
      animals: animals,
      fees: fees,
    );
  }
}
