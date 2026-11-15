import 'admin_revenue_metrics.dart';
import 'admin_user_metrics.dart';

/// The billing provider an active subscriber is billed through, reduced to the
/// two buckets the Admin Portal V2 brief asks for.
///
/// The provider is read (never inferred) from the same `users/{uid}` fields the
/// app already writes — `subscriptionPlatform` / `subscriptionSource` /
/// `subscriptionProvider` (resolved in [AdminUserRecord.fromMap] and classified
/// by [resolveAdminProviderBucket]). Google Play Billing and the PayFast
/// alternative billing (User Choice Billing SA, recorded as
/// `payfast_alternative`) are the only two payment paths in the app.
enum AdminSubscriptionProvider {
  google('Google'),
  payfast('PayFast'),
  none('Unknown');

  const AdminSubscriptionProvider(this.label);

  /// The badge label rendered in the Subscribers List + CSV.
  final String label;

  /// Whether this bucket is a real billing provider (not [none]).
  bool get isKnown => this != AdminSubscriptionProvider.none;
}

/// The subscription lifecycle state shown in the Subscribers List Status
/// column.
enum AdminSubscriberStatus {
  active('Active'),
  trial('Trial'),
  cancelled('Cancelled'),
  expired('Expired');

  const AdminSubscriberStatus(this.label);

  final String label;
}

/// The Subscribers List filter dropdown options.
enum AdminSubscriberFilter {
  all('All'),
  google('Google'),
  payfast('PayFast'),
  trial('Trial'),
  active('Active');

  const AdminSubscriberFilter(this.label);

  final String label;
}

/// Resolves a raw provider string into a two-bucket
/// [AdminSubscriptionProvider].
///
/// Google Play Billing (`google_play` / `google_play_billing`) maps to
/// [AdminSubscriptionProvider.google]. PayFast — including the alternative
/// billing variant (`payfast` / `payfast_alternative` / `user_choice`, which is
/// PayFast taken through Play's User Choice Billing) — maps to
/// [AdminSubscriptionProvider.payfast]. Anything unrecognised (including a
/// blank value) maps to [AdminSubscriptionProvider.none] so the count is
/// honest rather than guessed.
AdminSubscriptionProvider resolveAdminSubscriptionProvider(String? provider) {
  switch (resolveAdminProviderBucket(provider)) {
    case AdminProviderBucket.play:
      return AdminSubscriptionProvider.google;
    case AdminProviderBucket.payfast:
    case AdminProviderBucket.userChoice:
      return AdminSubscriptionProvider.payfast;
    case AdminProviderBucket.unknown:
      return AdminSubscriptionProvider.none;
  }
}

/// One row of the Admin Portal V2 Subscribers List.
class AdminSubscriberRow {
  final String uid;
  final String name;
  final String email;
  final AdminSubscriptionProvider provider;
  final String planLabel;
  final DateTime? startDate;
  final AdminSubscriberStatus status;

  /// Whether this row's plan could not be priced (blank / unrecognised
  /// `subscriptionProduct`). Such a row is shown with Plan = Unknown so the
  /// operator can identify + fix it manually (nothing is invented).
  final bool isUnknownPlan;

  const AdminSubscriberRow({
    required this.uid,
    this.name = '',
    this.email = '',
    this.provider = AdminSubscriptionProvider.none,
    this.planLabel = '—',
    this.startDate,
    this.status = AdminSubscriberStatus.expired,
    this.isUnknownPlan = false,
  });

  /// The Start Date rendered as `yyyy-MM-dd`, or an em dash when unknown.
  String get startDateLabel => formatAdminDate(startDate);

  /// Whether the provider is unknown (blank / unrecognised).
  bool get isUnknownProvider => provider == AdminSubscriptionProvider.none;

  /// Whether this row matches a free-text [query] (name or email,
  /// case-insensitive).
  bool matchesQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) || email.toLowerCase().contains(q);
  }

  /// Whether this row passes the [filter] dropdown.
  bool matchesFilter(AdminSubscriberFilter filter) {
    switch (filter) {
      case AdminSubscriberFilter.all:
        return true;
      case AdminSubscriberFilter.google:
        return provider == AdminSubscriptionProvider.google;
      case AdminSubscriberFilter.payfast:
        return provider == AdminSubscriptionProvider.payfast;
      case AdminSubscriberFilter.trial:
        return status == AdminSubscriberStatus.trial;
      case AdminSubscriberFilter.active:
        return status == AdminSubscriberStatus.active;
    }
  }
}

/// The Admin Portal V2 subscription KPIs + the Subscribers List payload.
///
/// Every figure is derived from the SAME `users/{uid}` records the rest of the
/// portal aggregates (a snapshot "as of now"), so the numbers reconcile with a
/// Firestore console spot-check and no extra Firestore read is needed.
///
/// [googleCount] + [payfastCount] + [unknownProviderCount] == [totalSubscribers]
/// always holds. The brief's "Total = Google + PayFast" is the expected case;
/// [unknownProviderCount] is surfaced so a subscriber missing a provider is
/// visible instead of silently breaking the equation.
class AdminSubscriptionMetrics {
  /// Active subscribers of any provider (the "Total Subscribers" card).
  final int totalSubscribers;

  /// Active subscribers billed through Google Play Billing.
  final int googleCount;

  /// Active subscribers billed through PayFast (incl. alternative billing).
  final int payfastCount;

  /// Active subscribers whose provider field is blank / unrecognised.
  final int unknownProviderCount;

  /// Accounts whose trial is currently running and which are not yet paying.
  final int trialCount;

  /// The Subscribers List rows (newest Start Date first).
  final List<AdminSubscriberRow> subscribers;

  const AdminSubscriptionMetrics({
    this.totalSubscribers = 0,
    this.googleCount = 0,
    this.payfastCount = 0,
    this.unknownProviderCount = 0,
    this.trialCount = 0,
    this.subscribers = const [],
  });

  /// Aggregates the subscription KPIs + rows locally. Pure + synchronous.
  ///
  /// [now] makes every trial / premium comparison deterministic in tests.
  factory AdminSubscriptionMetrics.aggregate(
    Iterable<AdminUserRecord> records, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    var total = 0;
    var google = 0;
    var payfast = 0;
    var unknown = 0;
    var trial = 0;
    final rows = <AdminSubscriberRow>[];

    for (final r in records) {
      final premiumNow = r.isPremiumActive(ref);
      final trialNow = r.isTrialActive(ref) && !premiumNow;
      final cancelled = r.subscriptionStatus == 'cancelled' || r.cancelledAt != null;
      final expired = _isExpired(r, ref, premiumNow: premiumNow, trialNow: trialNow);

      if (premiumNow) {
        total++;
        switch (resolveAdminSubscriptionProvider(r.provider)) {
          case AdminSubscriptionProvider.google:
            google++;
          case AdminSubscriptionProvider.payfast:
            payfast++;
          case AdminSubscriptionProvider.none:
            unknown++;
        }
      }
      if (trialNow) trial++;

      // The list includes anyone who is (or was) on a subscription path: active
      // subscribers, running trials, cancellations, and expired subscriptions.
      if (!premiumNow && !trialNow && !cancelled && !expired) continue;

      final bucket = resolveAdminPlanBucket(r.plan);
      rows.add(AdminSubscriberRow(
        uid: r.uid,
        name: r.displayName,
        email: r.email,
        provider: resolveAdminSubscriptionProvider(r.provider),
        planLabel: _planLabel(r.plan),
        startDate: r.subscriptionStart,
        status: _statusFor(
          premiumNow: premiumNow,
          trialNow: trialNow,
          cancelled: cancelled,
        ),
        // An ACTIVE subscriber whose plan cannot be priced is flagged so the
        // list shows Plan = Unknown and the operator can fix it manually.
        isUnknownPlan: premiumNow && bucket == null,
      ));
    }

    // Newest Start Date first; undated rows sort last (email tie-break so the
    // order is stable).
    rows.sort((a, b) {
      final da = a.startDate;
      final db = b.startDate;
      if (da == null && db == null) return a.email.compareTo(b.email);
      if (da == null) return 1;
      if (db == null) return -1;
      final cmp = db.compareTo(da);
      return cmp != 0 ? cmp : a.email.compareTo(b.email);
    });

    return AdminSubscriptionMetrics(
      totalSubscribers: total,
      googleCount: google,
      payfastCount: payfast,
      unknownProviderCount: unknown,
      trialCount: trial,
      subscribers: rows,
    );
  }

  /// Filters + searches the Subscribers List rows (newest-first order is
  /// preserved).
  List<AdminSubscriberRow> visibleSubscribers({
    String query = '',
    AdminSubscriberFilter filter = AdminSubscriberFilter.all,
  }) {
    return subscribers
        .where((r) => r.matchesFilter(filter) && r.matchesQuery(query))
        .toList(growable: false);
  }

  /// The Dashboard "Total Subscribers" card count — active paid subscribers
  /// ONLY, so it matches the Revenue tab's "Active subscribers" exactly.
  ///
  /// This is the ONE definition used everywhere: trials are reported
  /// separately (the "Trial Users" card), never folded into "Total
  /// Subscribers". See [subscribersDefinitionLabel].
  String get totalSubscribersCountLabel => totalSubscribers.toString();

  /// The one-line DEFINITION note under the Dashboard subscription row so the
  /// operator knows what "Total Subscribers" means and how it reconciles with
  /// the Revenue tab.
  String get subscribersDefinitionLabel =>
      'Total Subscribers = active paid subscribers only (excludes trials; '
      'trials are the "Trial Users" card). '
      'Active = Google $googleCount + PayFast $payfastCount'
      '${unknownProviderCount > 0 ? ' + Unknown $unknownProviderCount' : ''} '
      '= $totalSubscribers.';

  /// The Subscribers List rows for ACTIVE subscribers whose plan could not be
  /// priced (`subscriptionProduct` / `plan` blank or unrecognised).
  ///
  /// Surfaced in the list with Provider = Unknown / Plan = Unknown so the
  /// operator can identify each account (email + provider + start date) and
  /// fix it manually. READ-ONLY — nothing is backfilled or invented.
  List<AdminSubscriberRow> get unknownPlanRows =>
      subscribers.where((r) => r.isUnknownPlan).toList(growable: false);

  static AdminSubscriberStatus _statusFor({
    required bool premiumNow,
    required bool trialNow,
    required bool cancelled,
  }) {
    if (cancelled && !premiumNow && !trialNow) return AdminSubscriberStatus.cancelled;
    if (premiumNow) return AdminSubscriberStatus.active;
    if (trialNow) return AdminSubscriberStatus.trial;
    return cancelled
        ? AdminSubscriberStatus.cancelled
        : AdminSubscriberStatus.expired;
  }

  /// Whether the account had a subscription path that has now lapsed: a
  /// premium expiry or trial end in the past with no active state.
  static bool _isExpired(
    AdminUserRecord r,
    DateTime ref, {
    required bool premiumNow,
    required bool trialNow,
  }) {
    if (premiumNow || trialNow) return false;
    if (r.cancelledAt != null || r.subscriptionStatus == 'cancelled') {
      return false; // handled as Cancelled
    }
    final expiry = r.premiumExpiry;
    if (expiry != null && !expiry.isAfter(ref)) return true;
    final end = r.trialEnd;
    if (end != null && !end.isAfter(ref)) return true;
    return false;
  }

  /// The plan label for the Subscribers List — the canonical bucket label when
  /// the plan id resolves, otherwise `Unknown` (an unpriced plan is surfaced,
  /// never hidden behind an em dash or the raw id), or an em dash when there is
  /// no plan at all AND the account is not an active subscriber.
  static String _planLabel(String plan) {
    final bucket = resolveAdminPlanBucket(plan);
    if (bucket != null) return bucket.label;
    final trimmed = plan.trim();
    // A blank plan (no `subscriptionProduct` at all) on an active subscriber
    // is the "Unknown" bucket the operator must identify + fix manually.
    return trimmed.isEmpty ? 'Unknown' : trimmed;
  }
}
