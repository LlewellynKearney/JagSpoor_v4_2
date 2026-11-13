import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../services/entitlement_service.dart'
    show trialEndFieldAliases, trialStartFieldAliases;

/// Date-range filter for the Admin Portal V2 "New Users" metric.
///
/// The filter deliberately applies ONLY to the New Users count — the trial /
/// subscription figures are point-in-time snapshots ("as of now") and do not
/// change when the filter changes. The screen fetches the user documents once
/// and re-runs [AdminUserMetrics.aggregate] locally on every filter change, so
/// switching the filter never hits Firestore again.
enum AdminDateFilter {
  today('Today'),
  last7Days('7d'),
  last30Days('30d'),
  allTime('All Time');

  const AdminDateFilter(this.label);

  /// The short chip label rendered in the filter bar.
  final String label;

  /// The window start for this filter, or `null` for [allTime].
  ///
  /// The window is inclusive of today and counts backwards from the start of
  /// the local day, so `7d` covers today plus the previous six days.
  DateTime? startFor(DateTime now) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    switch (this) {
      case AdminDateFilter.today:
        return startOfToday;
      case AdminDateFilter.last7Days:
        return startOfToday.subtract(const Duration(days: 6));
      case AdminDateFilter.last30Days:
        return startOfToday.subtract(const Duration(days: 29));
      case AdminDateFilter.allTime:
        return null;
    }
  }

  /// Whether [timestamp] falls inside this filter's window.
  ///
  /// A `null` timestamp never counts (an account with no creation date can't
  /// be placed in a window), and a future timestamp never counts.
  bool includes(DateTime? timestamp, DateTime now) {
    if (timestamp == null) return false;
    if (timestamp.isAfter(now)) return false;
    final start = startFor(now);
    if (start == null) return true;
    return !timestamp.isBefore(start);
  }
}

/// A single `users/{uid}` document reduced to the fields the Admin Portal V2
/// metrics need.
///
/// The raw Firestore document is parsed ONCE into this typed snapshot; every
/// metric is then derived from these fields, so the aggregation is pure and
/// unit-testable without a Firestore emulator. Trial / premium activity is
/// COMPUTED here (never read from a stored flag) because the stored
/// `isTrialActive` / `isPremiumActive` / `trialEndDate` fields do not exist —
/// see [AdminUserRecord.fromMap] for the field aliases that DO exist.
class AdminUserRecord {
  final String uid;
  final String email;
  final String role;
  final String subscriptionStatus;
  final String plan;
  final String provider;
  final String subscriptionTier;
  final bool isPremium;
  final bool requiresPayment;
  final bool hasActivePurchase;
  final DateTime? createdAt;
  final DateTime? trialStart;
  final DateTime? trialEnd;
  final DateTime? premiumExpiry;

  /// When the subscription was cancelled, if the document records it. Used by
  /// the Task 5 churned list, with [updatedAt] as the documented fallback.
  final DateTime? cancelledAt;

  /// The document's `updatedAt` — the fallback cancellation timestamp.
  final DateTime? updatedAt;

  const AdminUserRecord({
    required this.uid,
    this.email = '',
    this.role = '',
    this.subscriptionStatus = '',
    this.plan = '',
    this.provider = '',
    this.subscriptionTier = '',
    this.isPremium = false,
    this.requiresPayment = false,
    this.hasActivePurchase = false,
    this.createdAt,
    this.trialStart,
    this.trialEnd,
    this.premiumExpiry,
    this.cancelledAt,
    this.updatedAt,
  });

  /// Status strings that indicate an in-progress free trial (mirrors
  /// `UserEntitlement._isTrialStatus`).
  static bool _isTrialStatus(String status) =>
      status == 'trial' ||
      status == 'trialing' ||
      status == 'trialling' ||
      status == 'trial_active';

  /// Status strings that indicate an actively-billed subscription (mirrors
  /// `UserEntitlement._isActiveStatus`).
  static bool _isActiveStatus(String status) =>
      status == 'active' || status == 'subscribed' || status == 'premium';

  /// The 30-day creation-window fallback mirrored from
  /// `entitlement_service.dart` (`trialWindow`).
  static const Duration _trialWindow = Duration(days: 30);

  /// Whether the account is inside its free-trial window.
  ///
  /// Mirrors `UserEntitlement.isTrialActive` exactly so the admin figures
  /// agree with the in-app paywall gate:
  ///  1. an explicit trial-end timestamp (any documented alias) — future =
  ///     active, past = ended;
  ///  2. a trial status with no timestamp — active;
  ///  3. no timestamp and no status, but the account was created within the
  ///     30-day window — active.
  /// `requiresPayment == true` blocks trial access at every step.
  bool isTrialActive(DateTime now) {
    if (requiresPayment) return false;
    final end = trialEnd;
    if (end != null) return end.isAfter(now);
    if (_isTrialStatus(subscriptionStatus)) return true;
    final created = createdAt;
    if (created == null) return false;
    final age = now.difference(created);
    return age >= Duration.zero && age < _trialWindow;
  }

  /// Whether the account has an active premium entitlement.
  ///
  /// Mirrors `UserEntitlement.isPremiumActive`: a server-confirmed purchase
  /// flag grants access outright; otherwise a non-null future
  /// `premiumExpiry` is required (a bare `subscriptionStatus == 'active'`
  /// with no expiry does NOT count — the v1.0.12 hotfix).
  bool isPremiumActive(DateTime now) {
    if (hasActivePurchase) return true;
    final expiry = premiumExpiry;
    if (expiry == null) return false;
    if (isPremium && expiry.isAfter(now)) return true;
    if (_isActiveStatus(subscriptionStatus) && expiry.isAfter(now)) return true;
    return false;
  }

  /// Whether the account ever started a trial — the denominator of the
  /// trial-to-paid conversion rate.
  bool get everStartedTrial => trialStart != null;

  bool get isHunterRole => role.trim().toLowerCase() == 'hunter';
  bool get isOutfitterRole => role.trim().toLowerCase() == 'outfitter';

  /// Whether this account was created inside [filter]'s window.
  bool isNewUser(AdminDateFilter filter, DateTime now) =>
      filter.includes(createdAt, now);

  /// Parses a `users/{uid}` document into the typed snapshot.
  ///
  /// Field aliases (all confirmed to exist on real documents — the brief's
  /// "old names" like `trialStartDate` / `plan` / `paymentProvider` are NOT
  /// stored):
  ///  * trial dates — the `entitlement_service.dart` alias lists
  ///    (`trialStartedAt` / `trialStart` / `subscriptionTrial*` etc.).
  ///  * plan — `subscriptionProduct` (canonical) with `subscription_product`
  ///    and `plan` as fallbacks.
  ///  * payment provider — `subscriptionProvider` / `subscriptionPlatform` /
  ///    `subscriptionSource` (+ snake_case variants).
  ///
  /// Every field is defaulted so a partial / legacy document parses without
  /// throwing.
  factory AdminUserRecord.fromMap(String uid, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    final status =
        (d['subscriptionStatus'] ?? '').toString().trim().toLowerCase();
    final nested = d['subscription'];
    final nestedMap =
        nested is Map ? Map<String, dynamic>.from(nested) : const <String, dynamic>{};

    String firstString(List<dynamic> candidates) {
      for (final raw in candidates) {
        final value = (raw ?? '').toString().trim();
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    return AdminUserRecord(
      uid: uid,
      email: (d['email'] ?? '').toString().trim().toLowerCase(),
      role: (d['role'] ?? '').toString(),
      subscriptionStatus: status.isNotEmpty
          ? status
          : (nestedMap['status'] ?? '').toString().trim().toLowerCase(),
      plan: firstString([
        d['subscriptionProduct'],
        d['subscription_product'],
        d['plan'],
        nestedMap['plan'],
      ]),
      provider: firstString([
        d['subscriptionProvider'],
        d['subscription_provider'],
        d['subscriptionPlatform'],
        d['subscription_platform'],
        d['billingPlatform'],
        d['subscriptionSource'],
        d['subscription_source'],
      ]).toLowerCase(),
      subscriptionTier: (d['subscriptionTier'] ?? '').toString().trim().toLowerCase(),
      isPremium: d['isPremium'] == true || nestedMap['isActive'] == true,
      requiresPayment: d['requiresPayment'] == true,
      hasActivePurchase: d['hasActivePurchase'] == true,
      createdAt: _toDate(d['createdAt']) ?? _toDate(d['created_at']),
      trialStart: _resolveTrialStart(d),
      trialEnd: _resolveTrialEnd(d),
      premiumExpiry: _toDate(d['premiumExpiry']) ?? _toDate(nestedMap['expiresAt']),
      cancelledAt: _toDate(d['subscriptionCancelledAt']) ??
          _toDate(d['subscription_cancelled_at']) ??
          _toDate(d['cancelledAt']) ??
          _toDate(d['cancelled_at']),
      updatedAt: _toDate(d['updatedAt']) ?? _toDate(d['updated_at']),
    );
  }

  static DateTime? _resolveTrialEnd(Map<String, dynamic> data) {
    for (final key in trialEndFieldAliases) {
      final value = _toDate(data[key]);
      if (value != null) return value;
    }
    return null;
  }

  static DateTime? _resolveTrialStart(Map<String, dynamic> data) {
    for (final key in trialStartFieldAliases) {
      final value = _toDate(data[key]);
      if (value != null) return value;
    }
    return null;
  }

  static DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    if (v is num) {
      return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
    }
    return null;
  }
}

/// The Admin Portal V2 user-level KPI bundle.
///
/// [newUsers] is the ONLY figure that responds to the [AdminDateFilter]; the
/// trial / subscription figures are point-in-time snapshots. Every count is
/// derived locally from the fetched [AdminUserRecord]s, so the numbers match a
/// Firestore console spot-check of the same documents.
class AdminUserMetrics {
  /// Accounts created inside the active date-filter window.
  final int newUsers;

  /// Accounts whose computed trial is currently active.
  final int trialActive;

  /// Accounts whose trial window has ended and which are NOT premium.
  final int trialExpiredNoSub;

  /// `role == 'hunter'` accounts with an active premium entitlement.
  final int subscribedHunters;

  /// `role == 'outfitter'` accounts with an active premium entitlement.
  final int subscribedOutfitters;

  /// Accounts that ever started a trial (trial-start timestamp present) —
  /// the denominator of the trial-to-paid conversion rate.
  final int usersEverStartedTrial;

  /// Active subscribers whose plan (`subscriptionProduct` / `plan`) is missing.
  /// Surfaced as the "Unknown" bucket so the plan split reconciles.
  final int unknownPlanSubscribers;

  const AdminUserMetrics({
    this.newUsers = 0,
    this.trialActive = 0,
    this.trialExpiredNoSub = 0,
    this.subscribedHunters = 0,
    this.subscribedOutfitters = 0,
    this.usersEverStartedTrial = 0,
    this.unknownPlanSubscribers = 0,
  });

  /// Total subscribers = subscribed hunters + subscribed outfitters.
  int get totalSubscribers => subscribedHunters + subscribedOutfitters;

  /// Trial-to-paid conversion as a percentage, e.g. `42.9`.
  ///
  /// Numerator = subscribed hunters + subscribed outfitters; denominator =
  /// accounts that ever started a trial. Returns `0.0` when the denominator
  /// is zero (never a divide-by-zero).
  double get trialToPaidConversionPercent {
    if (usersEverStartedTrial <= 0) return 0.0;
    return totalSubscribers / usersEverStartedTrial * 100.0;
  }

  /// The conversion rendered to exactly one decimal place (e.g. `"42.9%"`).
  String get trialToPaidConversionLabel =>
      '${trialToPaidConversionPercent.toStringAsFixed(1)}%';

  /// Aggregates the KPI bundle from the fetched records.
  ///
  /// Pure + synchronous so the screen can re-run it locally on every date-
  /// filter change without another Firestore read.
  factory AdminUserMetrics.aggregate(
    Iterable<AdminUserRecord> records, {
    required AdminDateFilter filter,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    var newUsers = 0;
    var trialActive = 0;
    var trialExpiredNoSub = 0;
    var subscribedHunters = 0;
    var subscribedOutfitters = 0;
    var everStarted = 0;
    var unknownPlan = 0;

    for (final r in records) {
      if (r.isNewUser(filter, ref)) newUsers++;
      if (r.everStartedTrial) everStarted++;

      final trialActiveNow = r.isTrialActive(ref);
      final premiumNow = r.isPremiumActive(ref);

      // Trial Active and the subscription buckets are MUTUALLY EXCLUSIVE: an
      // account that is already an active subscriber is never also "Trial
      // Active" (the sibling bucket is explicitly "Trial Expired — No Sub").
      // Without this guard the entitlement creation-window fallback would
      // classify a brand-new PAID subscriber (created recently, no trial
      // fields) as trial-active and double-count them.
      if (trialActiveNow && !premiumNow) trialActive++;

      // Trial expired with no subscription: an explicit trial-end timestamp in
      // the past AND no premium. An account with no trial dates at all is NOT
      // counted here (it never had a trial to expire).
      final end = r.trialEnd;
      if (end != null && !end.isAfter(ref) && !premiumNow) {
        trialExpiredNoSub++;
      }

      if (premiumNow) {
        if (r.isHunterRole) subscribedHunters++;
        if (r.isOutfitterRole) subscribedOutfitters++;
        if (r.plan.isEmpty) unknownPlan++;
      }
    }

    return AdminUserMetrics(
      newUsers: newUsers,
      trialActive: trialActive,
      trialExpiredNoSub: trialExpiredNoSub,
      subscribedHunters: subscribedHunters,
      subscribedOutfitters: subscribedOutfitters,
      usersEverStartedTrial: everStarted,
      unknownPlanSubscribers: unknownPlan,
    );
  }
}
