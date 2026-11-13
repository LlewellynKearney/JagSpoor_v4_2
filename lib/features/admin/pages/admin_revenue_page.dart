import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/admin_revenue_metrics.dart';
import '../widgets/admin_v2_common.dart';

/// The Admin Portal V2 **Revenue** page (Task 6, Phase 1 — READ ONLY).
///
/// Shows subscription revenue ONLY: MRR, ARR, the PayFast vs Play vs User
/// Choice split, Churned and the Pipeline (labelled "PIPELINE — If all trials
/// convert" so it is never mistaken for realized revenue).
///
/// Booking amounts are NEVER surfaced as revenue — JagSpoor does not take
/// booking payment in-app (off-platform EFT / cash). Every amount is rendered
/// in ZAR as `R1,234.56`.
///
/// This page performs NO writes — Phase 1 is read-only.
class AdminRevenuePage extends StatelessWidget {
  final ThemeController theme;
  final AdminRevenueMetrics metrics;

  const AdminRevenuePage({
    super.key,
    required this.theme,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('adminV2RevenuePage'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminV2MetricGrid(
          children: [
            AdminV2MetricCard(
              key: const ValueKey('adminV2PageCardTotalMrr'),
              theme: theme,
              icon: Icons.payments_outlined,
              label: 'Total MRR',
              valueLabel: metrics.totalMrrLabel,
              caption: 'Recurring, monthly',
            ),
            AdminV2MetricCard(
              key: const ValueKey('adminV2PageCardArr'),
              theme: theme,
              icon: Icons.calendar_month_outlined,
              label: 'ARR',
              valueLabel: metrics.arrLabel,
              caption: 'MRR × 12',
            ),
            AdminV2MetricCard(
              key: const ValueKey('adminV2PageCardHunterMrr'),
              theme: theme,
              icon: Icons.person_outline,
              label: 'Hunter MRR',
              valueLabel: metrics.hunterMrrLabel,
            ),
            AdminV2MetricCard(
              key: const ValueKey('adminV2PageCardOutfitterMrr'),
              theme: theme,
              icon: Icons.business_outlined,
              label: 'Outfitter MRR',
              valueLabel: metrics.outfitterMrrLabel,
            ),
          ],
        ),
        AdminV2BreakdownCard(
          key: const ValueKey('adminV2PagePlanSplit'),
          theme: theme,
          title: 'MRR By Plan',
          entries: [
            for (final row in metrics.planSplit)
              MapEntry('${row.label} × ${row.count}', row.mrrLabel),
          ],
          note: metrics.unknownPlanActiveSubscribers > 0
              ? 'Unknown plan (unpriced): '
                  '${metrics.unknownPlanActiveSubscribers} active subscriber'
                  '${metrics.unknownPlanActiveSubscribers == 1 ? '' : 's'}'
              : null,
        ),
        AdminV2BreakdownCard(
          key: const ValueKey('adminV2PageProviderSplit'),
          theme: theme,
          title: 'PayFast vs Play vs User Choice',
          entries: [
            for (final row in metrics.providerSplit)
              MapEntry(row.label, '${row.count}  ·  ${row.percentLabel}'),
          ],
          note: 'Active subscribers: ${metrics.activeSubscribers}',
        ),
        _pipelineCard(),
        AdminV2MetricCard(
          key: const ValueKey('adminV2PageCardChurned'),
          theme: theme,
          icon: Icons.person_remove_outlined,
          label: 'Churned (Cancelled)',
          value: metrics.churnedCount,
        ),
        AdminV2TableCard(
          key: const ValueKey('adminV2PageChurnedTable'),
          theme: theme,
          title: 'Churned Accounts',
          emptyLabel: 'No cancelled subscriptions.',
          headers: const ['Email', 'Plan', 'Cancelled'],
          rows: [
            for (final r in metrics.churned)
              [
                r.email.isEmpty ? '—' : r.email,
                r.planLabel,
                r.cancelledAtLabel,
              ],
          ],
        ),
        AdminV2Note(
          theme: theme,
          text: 'Read-only (Phase 1). Subscription revenue ONLY — booking '
              'payment is off-platform (EFT / cash), so no booking amount is '
              'reported as revenue. Snapshot "as of now" (ignores the date '
              'filter). Prices: hunter R34.99/mo · R349.99/yr (MRR R29.17) · '
              'outfitter R299.99/mo · R2999.99/yr (MRR R250.00).',
        ),
      ],
    );
  }

  Widget _pipelineCard() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        key: const ValueKey('adminV2PagePipelineCard'),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.accentColor.withAlpha(60)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up_rounded,
                    color: theme.accentColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'PIPELINE — If all trials convert',
                    style: TextStyle(
                      color: theme.subtitleColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              metrics.pipelineLabel,
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 26,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '(Trial Active Hunters × ${formatAdminZar(kHunterMonthlyZar)}) + '
              '(Trial Active Outfitters × '
              '${formatAdminZar(kOutfitterMonthlyZar)})  ·  '
              '${metrics.trialActiveHunters} hunter'
              '${metrics.trialActiveHunters == 1 ? '' : 's'} + '
              '${metrics.trialActiveOutfitters} outfitter'
              '${metrics.trialActiveOutfitters == 1 ? '' : 's'}',
              style: TextStyle(color: theme.subtitleColor, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
