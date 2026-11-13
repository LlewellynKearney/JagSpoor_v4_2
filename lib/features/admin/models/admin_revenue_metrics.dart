import 'admin_user_metrics.dart';

/// Subscription prices (ZAR) — the SERVER truth.
///
/// Mirrors `functions/src/payfast/plans.ts` (`PAYFAST_PLAN_CATALOG`). These are
/// the FINAL, VAT-inclusive charges (Option A: 15% SA VAT is absorbed out of
/// the listed price). The yearly figures are the ANNUAL charge; their
/// monthly-recurring contribution ([kHunterYearlyMrrZar] /
/// [kOutfitterYearlyMrrZar]) is the annual amount divided by 12 and rounded to
/// cents, exactly as the brief specifies (349.99 / 12 = 29.17 and
/// 2999.99 / 12 = 250.00).
const double kHunterMonthlyZar = 34.99;
const double kHunterYearlyZar = 349.99;
const double kOutfitterMonthlyZar = 299.99;
const double kOutfitterYearlyZar = 2999.99;

/// The monthly-recurring contribution of a yearly subscriber (annual / 12,
/// rounded to cents).
const double kHunterYearlyMrrZar = 29.17;
const double kOutfitterYearlyMrrZar = 250.00;

/// The four subscription plan buckets the MRR split is built from.
enum AdminPlanBucket {
  hunterMonthly('Hunter Monthly'),
  hunterYearly('Hunter Yearly'),
  outfitterMonthly('Outfitter Monthly'),
  outfitterYearly('Outfitter Yearly');

  const AdminPlanBucket(this.label);

  /// The human label rendered on the breakdown.
  final String label;

  /// The per-subscriber monthly-recurring contribution (ZAR) for this bucket.
  double get mrrPerSubscriber => switch (this) {
        AdminPlanBucket.hunterMonthly => kHunterMonthlyZar,
        AdminPlanBucket.hunterYearly => kHunterYearlyMrrZar,
        AdminPlanBucket.outfitterMonthly => kOutfitterMonthlyZar,
        AdminPlanBucket.outfitterYearly => kOutfitterYearlyMrrZar,
      };

  /// Whether this bucket is an outfitter plan.
  bool get isOutfitter =>
      this == AdminPlanBucket.outfitterMonthly ||
      this == AdminPlanBucket.outfitterYearly;
}

/// The billing provider buckets the "PayFast vs Play Split" is built from.
enum AdminProviderBucket {
  payfast('PayFast'),
  play('Google Play'),
  userChoice('User Choice'),
  unknown('Unknown');

  const AdminProviderBucket(this.label);

  /// The human label rendered on the split.
  final String label;
}

/// Resolves a raw `subscriptionProduct` / plan id into one of the four
/// [AdminPlanBucket]s, or `null` when it cannot be priced.
///
/// Tolerates the three id families in the codebase:
///  * the PayFast catalog ids (`hunter_monthly`, `outfitter_yearly`);
///  * the Google Play product ids (`jagspoor_hunter_monthly`);
///  * the alternative-billing ids (`jagspoor_hunter_monthly_payfast`).
///
/// The role is detected from the substring, the cycle from `year` / `annual`
/// vs `month`. An unrecognised id (or a blank one) returns `null` so it is
/// surfaced in the "Unknown plan" note rather than silently mispriced.
AdminPlanBucket? resolveAdminPlanBucket(String? plan) {
  final value = (plan ?? '').trim().toLowerCase();
  if (value.isEmpty) return null;

  final isOutfitter = value.contains('outfitter');
  final isHunter = value.contains('hunter');
  if (!isOutfitter && !isHunter) return null;

  final isYearly = value.contains('year') || value.contains('annual');
  final isMonthly = value.contains('month');

  if (isOutfitter) {
    if (isYearly) return AdminPlanBucket.outfitterYearly;
    if (isMonthly) return AdminPlanBucket.outfitterMonthly;
    return null;
  }
  if (isYearly) return AdminPlanBucket.hunterYearly;
  if (isMonthly) return AdminPlanBucket.hunterMonthly;
  return null;
}

/// Resolves a raw provider string into one of the [AdminProviderBucket]s.
///
/// The brief's buckets are matched FIRST for `user_choice` (so a User Choice
/// purchase is never swallowed by the `payfast` prefix match), then `payfast`,
/// then Play (`play` / `google_play`). Anything unrecognised — including a
/// blank value — lands in [AdminProviderBucket.unknown] so the split always
/// reconciles.
AdminProviderBucket resolveAdminProviderBucket(String? provider) {
  final value = (provider ?? '').trim().toLowerCase();
  if (value.isEmpty) return AdminProviderBucket.unknown;
  if (value.contains('user_choice') || value.contains('userchoice')) {
    return AdminProviderBucket.userChoice;
  }
  if (value.contains('payfast')) return AdminProviderBucket.payfast;
  if (value.contains('play') || value.contains('google')) {
    return AdminProviderBucket.play;
  }
  return AdminProviderBucket.unknown;
}

/// Formats [amount] as ZAR with comma thousands and two decimals, e.g.
/// `1234.5` → `'R1,234.50'` (the brief's `R1,234.56` shape). Locale-independent
/// (pure string arithmetic, no `intl` dependency).
String formatAdminZar(double amount) {
  final neg = amount < 0;
  final abs = amount.abs();
  final rounded = abs.toStringAsFixed(2);
  final dot = rounded.indexOf('.');
  final intPart = dot == -1 ? rounded : rounded.substring(0, dot);
  final decPart = dot == -1 ? '00' : rounded.substring(dot + 1);
  final grouped = _groupThousandsComma(intPart);
  return '${neg ? '-' : ''}R$grouped.$decPart';
}

/// Groups an integer string with comma thousands separators
/// (`'1234567'` → `'1,234,567'`). Pure string arithmetic.
String _groupThousandsComma(String intPart) {
  if (intPart.length <= 3) return intPart;
  final buf = StringBuffer();
  var count = 0;
  for (var i = intPart.length - 1; i >= 0; i--) {
    if (count == 3) {
      buf.write(',');
      count = 0;
    }
    buf.write(intPart[i]);
    count++;
  }
  return buf.toString().split('').reversed.join();
}

/// One churned account row: the email, the plan it was on, and when it was
/// cancelled (falling back to `updatedAt` when no explicit cancellation
/// timestamp exists).
class AdminChurnedRow {
  final String uid;
  final String email;
  final String plan;
  final DateTime? cancelledAt;

  const AdminChurnedRow({
    required this.uid,
    this.email = '',
    this.plan = '',
    this.cancelledAt,
  });

  /// The plan label rendered on the row (`—` when the plan is missing).
  String get planLabel => plan.trim().isEmpty ? '—' : plan.trim();

  /// The cancellation date rendered as `yyyy-MM-dd`, or `—` when unknown.
  String get cancelledAtLabel {
    final d = cancelledAt;
    if (d == null) return '—';
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }
}

/// The Admin Portal V2 subscription-revenue KPI bundle.
///
/// Every figure is a point-in-time SNAPSHOT ("as of now") derived locally from
/// the already-fetched [AdminUserRecord]s — no extra Firestore read, no date
/// filter.
///
/// ONLY subscription revenue is reported. JagSpoor does not take booking
/// payment in-app (booking payment is off-platform: EFT / cash), so no booking
/// amount is ever surfaced as revenue.
class AdminRevenueMetrics {
  /// Active paid subscribers per plan bucket (used for the MRR breakdown).
  final Map<AdminPlanBucket, int> planCounts;

  /// Active paid subscribers whose plan could not be priced (blank /
  /// unrecognised `subscriptionProduct`). Excluded from MRR but surfaced so
  /// the numbers reconcile.
  final int unknownPlanActiveSubscribers;

  /// Active paid subscribers per provider bucket (used for the split).
  final Map<AdminProviderBucket, int> providerCounts;

  /// Total active paid subscribers (the split denominator).
  final int activeSubscribers;

  /// Accounts whose `subscriptionStatus` is `cancelled`.
  final int churnedCount;

  /// The churned account rows (email + plan + cancellation date).
  final List<AdminChurnedRow> churned;

  /// Trial-active accounts bucketed as hunter (the pipeline numerator).
  final int trialActiveHunters;

  /// Trial-active accounts bucketed as outfitter (the pipeline numerator).
  final int trialActiveOutfitters;

  const AdminRevenueMetrics({
    this.planCounts = const {},
    this.unknownPlanActiveSubscribers = 0,
    this.providerCounts = const {},
    this.activeSubscribers = 0,
    this.churnedCount = 0,
    this.churned = const [],
    this.trialActiveHunters = 0,
    this.trialActiveOutfitters = 0,
  });

  /// The active-subscriber count for [bucket].
  int countFor(AdminPlanBucket bucket) => planCounts[bucket] ?? 0;

  /// The active-subscriber count for [bucket].
  int providerCountFor(AdminProviderBucket bucket) =>
      providerCounts[bucket] ?? 0;

  /// The monthly-recurring revenue contributed by [bucket].
  double mrrFor(AdminPlanBucket bucket) =>
      countFor(bucket) * bucket.mrrPerSubscriber;

  /// Total MRR = sum of every plan bucket's contribution.
  ///
  /// `(Hunter Monthly × 34.99) + (Hunter Yearly × 29.17) +
  /// (Outfitter Monthly × 299.99) + (Outfitter Yearly × 250.00)`.
  double get totalMrr {
    var sum = 0.0;
    for (final bucket in AdminPlanBucket.values) {
      sum += mrrFor(bucket);
    }
    return sum;
  }

  /// The hunter-side MRR (hunter monthly + hunter yearly).
  double get hunterMrr =>
      mrrFor(AdminPlanBucket.hunterMonthly) +
      mrrFor(AdminPlanBucket.hunterYearly);

  /// The outfitter-side MRR (outfitter monthly + outfitter yearly).
  double get outfitterMrr =>
      mrrFor(AdminPlanBucket.outfitterMonthly) +
      mrrFor(AdminPlanBucket.outfitterYearly);

  /// Annual recurring revenue = MRR × 12.
  double get arr => totalMrr * 12.0;

  /// [totalMrr] rendered as ZAR (e.g. `'R1,234.56'`).
  String get totalMrrLabel => formatAdminZar(totalMrr);

  /// [hunterMrr] rendered as ZAR.
  String get hunterMrrLabel => formatAdminZar(hunterMrr);

  /// [outfitterMrr] rendered as ZAR.
  String get outfitterMrrLabel => formatAdminZar(outfitterMrr);

  /// [arr] rendered as ZAR.
  String get arrLabel => formatAdminZar(arr);

  /// [pipelineValue] rendered as ZAR.
  String get pipelineLabel => formatAdminZar(pipelineValue);

  /// The four plan buckets in canonical order with their counts + MRR.
  List<AdminPlanSplitRow> get planSplit => [
        for (final bucket in AdminPlanBucket.values)
          AdminPlanSplitRow(
            label: bucket.label,
            count: countFor(bucket),
            mrr: mrrFor(bucket),
          ),
      ];

  /// The four provider buckets in canonical order with their counts + share.
  List<AdminProviderSplitRow> get providerSplit => [
        for (final bucket in AdminProviderBucket.values)
          AdminProviderSplitRow(
            label: bucket.label,
            count: providerCountFor(bucket),
            percent: providerPercent(bucket),
          ),
      ];

  /// The provider-split percentage for [bucket], one decimal (e.g. `42.9`).
  /// Returns `0.0` when there are no active subscribers.
  double providerPercent(AdminProviderBucket bucket) {
    if (activeSubscribers <= 0) return 0.0;
    return providerCountFor(bucket) / activeSubscribers * 100.0;
  }

  /// The provider-split percentage rendered to one decimal (e.g. `"42.9%"`).
  String providerPercentLabel(AdminProviderBucket bucket) =>
      '${providerPercent(bucket).toStringAsFixed(1)}%';

  /// The "pipeline" value: what the recurring revenue would be if EVERY active
  /// trial converted — `(Trial Active Hunters × 34.99) +
  /// (Trial Active Outfitters × 299.99)`.
  ///
  /// Labelled on screen as "PIPELINE — If all trials convert" so it is never
  /// mistaken for realized revenue.
  double get pipelineValue =>
      trialActiveHunters * kHunterMonthlyZar +
      trialActiveOutfitters * kOutfitterMonthlyZar;

  /// Total trial-active accounts (hunters + outfitters).
  int get trialActiveTotal => trialActiveHunters + trialActiveOutfitters;

  /// Aggregates the revenue KPIs locally. Pure + synchronous.
  ///
  /// [now] makes every trial / premium comparison deterministic in tests.
  factory AdminRevenueMetrics.aggregate(
    Iterable<AdminUserRecord> records, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final planCounts = <AdminPlanBucket, int>{
      for (final b in AdminPlanBucket.values) b: 0,
    };
    final providerCounts = <AdminProviderBucket, int>{
      for (final b in AdminProviderBucket.values) b: 0,
    };
    var unknownPlan = 0;
    var activeSubscribers = 0;
    var churnedCount = 0;
    final churned = <AdminChurnedRow>[];
    var trialHunters = 0;
    var trialOutfitters = 0;

    for (final r in records) {
      final premiumNow = r.isPremiumActive(ref);

      if (premiumNow) {
        activeSubscribers++;
        providerCounts[resolveAdminProviderBucket(r.provider)] =
            (providerCounts[resolveAdminProviderBucket(r.provider)] ?? 0) + 1;
        final bucket = resolveAdminPlanBucket(r.plan);
        if (bucket == null) {
          unknownPlan++;
        } else {
          planCounts[bucket] = (planCounts[bucket] ?? 0) + 1;
        }
      }

      if (r.subscriptionStatus == 'cancelled') {
        churnedCount++;
        churned.add(AdminChurnedRow(
          uid: r.uid,
          email: r.email,
          plan: r.plan,
          // The brief's fallback: an explicit cancellation timestamp when the
          // document carries one, otherwise the document's `updatedAt`.
          cancelledAt: r.cancelledAt ?? r.updatedAt,
        ));
      }

      // Pipeline: trial-active accounts that are NOT already paying, bucketed
      // into exactly one side. A `dual` account counts as a hunter (its
      // default landing per `RoleGuard.defaultHomeFor`).
      if (r.isTrialActive(ref) && !premiumNow) {
        if (r.isOutfitterRole && !r.isHunterRole) {
          trialOutfitters++;
        } else if (r.isHunterRole || r.isOutfitterRole) {
          trialHunters++;
        }
      }
    }

    // Newest-first churned list so the most recent cancellations lead.
    churned.sort((a, b) {
      final da = a.cancelledAt;
      final db = b.cancelledAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    return AdminRevenueMetrics(
      planCounts: planCounts,
      unknownPlanActiveSubscribers: unknownPlan,
      providerCounts: providerCounts,
      activeSubscribers: activeSubscribers,
      churnedCount: churnedCount,
      churned: churned,
      trialActiveHunters: trialHunters,
      trialActiveOutfitters: trialOutfitters,
    );
  }
}

/// One row of the MRR plan breakdown (label + subscriber count + MRR).
class AdminPlanSplitRow {
  final String label;
  final int count;
  final double mrr;

  const AdminPlanSplitRow({
    required this.label,
    required this.count,
    required this.mrr,
  });

  /// The MRR rendered as ZAR.
  String get mrrLabel => formatAdminZar(mrr);
}

/// One row of the PayFast vs Play provider split (label + count + share).
class AdminProviderSplitRow {
  final String label;
  final int count;
  final double percent;

  const AdminProviderSplitRow({
    required this.label,
    required this.count,
    required this.percent,
  });

  /// The share rendered to one decimal (e.g. `"42.9%"`).
  String get percentLabel => '${percent.toStringAsFixed(1)}%';
}
