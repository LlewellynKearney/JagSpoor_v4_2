import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/models/farm_permit.dart';
import 'package:jagspoor/features/veld_carry/models/rainfall_entry.dart';
import 'package:jagspoor/features/veld_carry/models/stock_entry.dart';
import 'package:jagspoor/features/veld_carry/models/veld_alert.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';

/// Pure alert derivation for the Veld & Carrying Capacity feature.
///
/// Nothing here touches Firestore, Flutter or any state: [buildAlerts] is a
/// plain function over the records the repository already loads, so the whole
/// rule set is unit-testable. Alerts are **never written back** — the next
/// read recomputes them.
///
/// A missing map key means "not loaded" (unknown) and suppresses the alert;
/// an empty list means "loaded and genuinely empty", which raises the
/// `no_*_recorded` info alert. That distinction keeps a failed child read from
/// producing a false "nothing recorded" alert.
List<VeldAlert> buildAlerts({
  required List<Camp> camps,
  required Map<String, List<StockEntry>> stockByCamp,
  required List<FarmPermit> permits,
  required Map<String, List<RainfallEntry>> rainfallByCamp,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final alerts = <VeldAlert>[];

  for (final camp in camps) {
    alerts.addAll(_campAlerts(camp, stockByCamp, rainfallByCamp, reference));
  }
  for (final permit in permits) {
    final alert = _permitAlert(permit, reference);
    if (alert != null) alerts.add(alert);
  }

  return sortAlerts(alerts);
}

/// Most urgent first: critical, then warning, then info. Ties are ordered by
/// title so the list is deterministic across reloads.
List<VeldAlert> sortAlerts(Iterable<VeldAlert> alerts) {
  final sorted = alerts.toList();
  sorted.sort((a, b) {
    final bySeverity = a.severityRank.compareTo(b.severityRank);
    if (bySeverity != 0) return bySeverity;
    final byTitle = a.title.compareTo(b.title);
    if (byTitle != 0) return byTitle;
    return a.id.compareTo(b.id);
  });
  return sorted;
}

/// Count shown on the badge: everything that needs the outfitter's attention
/// (critical + warning). Info alerts are housekeeping, not a badge.
int criticalAndWarningCount(Iterable<VeldAlert> alerts) {
  var count = 0;
  for (final alert in alerts) {
    if (alert.severity != VeldAlert.severityInfo) count++;
  }
  return count;
}

// ── Camp alerts ───────────────────────────────────────────────────────

List<VeldAlert> _campAlerts(
  Camp camp,
  Map<String, List<StockEntry>> stockByCamp,
  Map<String, List<RainfallEntry>> rainfallByCamp,
  DateTime now,
) {
  final alerts = <VeldAlert>[];
  final name = camp.name.trim().isEmpty ? 'Unnamed camp' : camp.name.trim();
  final stock = stockByCamp[camp.id];
  final rainfall = rainfallByCamp[camp.id];

  // Overstocking uses the VELD capacity only (no planted contribution), which
  // overstates pressure rather than understating it — the safe direction for
  // an alert. The camp detail screen shows the planted-inclusive figure.
  final capacity = veldCapacityLsu(
    camp.totalSizeHa,
    effectiveHaPerLsu(camp.deptNormHaPerLsu, camp.veldCondition),
  );
  final usage = usagePct(_countedLsu(stock), capacity);

  if (stock != null) {
    if (stock.isEmpty) {
      alerts.add(_campAlert(
        id: '${VeldAlert.typeNoStockRecorded}:${camp.id}',
        camp: camp,
        type: VeldAlert.typeNoStockRecorded,
        severity: VeldAlert.severityInfo,
        title: 'No stock recorded',
        message: 'Camp $name has no stock recorded yet',
        now: now,
      ));
    } else {
      final band = stockingStatus(usage);
      final usageText = _percent(usage);
      if (band == stockingSeverelyOverstocked) {
        alerts.add(_campAlert(
          id: '${VeldAlert.typeSeverelyOverstocked}:${camp.id}',
          camp: camp,
          type: VeldAlert.typeSeverelyOverstocked,
          severity: VeldAlert.severityCritical,
          title: 'Severe overstocking',
          message: 'Camp $name is severely overstocked ($usageText)',
          now: now,
        ));
      } else if (band == stockingOverstocked) {
        alerts.add(_campAlert(
          id: '${VeldAlert.typeOverstocked}:${camp.id}',
          camp: camp,
          type: VeldAlert.typeOverstocked,
          severity: VeldAlert.severityCritical,
          title: 'Overstocked',
          message: 'Camp $name is overstocked ($usageText)',
          now: now,
        ));
      }
    }
  }

  if (rainfall != null &&
      _rainfallEntriesLastTwelveMonths(rainfall, now) == 0) {
    alerts.add(_campAlert(
      id: '${VeldAlert.typeNoRainfallRecorded}:${camp.id}',
      camp: camp,
      type: VeldAlert.typeNoRainfallRecorded,
      severity: VeldAlert.severityInfo,
      title: 'No rainfall recorded',
      message: 'Camp $name has no rainfall recorded in last 12 months',
      now: now,
    ));
  }

  return alerts;
}

// ── Permits ───────────────────────────────────────────────────────────

VeldAlert? _permitAlert(FarmPermit permit, DateTime now) {
  final expiry = permit.expiryDate;
  if (expiry == null) return null;
  final status = FarmPermit.deriveStatus(expiry, now: now);
  if (status == FarmPermit.permitStatusNoExpiry) return null;

  // A permit that names exactly one camp belongs to that camp; anything else
  // (no camps, or several) is farm-wide.
  final campId = permit.campIds.length == 1 ? permit.campIds.first : null;
  final label = veldPermitTypeLabel(permit.permitType);
  final days = daysUntil(expiry, now: now) ?? 0;

  if (status == FarmPermit.permitStatusExpired) {
    return VeldAlert(
      id: '${VeldAlert.typePermitExpired}:${permit.id}',
      farmId: permit.farmId,
      campId: campId,
      alertType: VeldAlert.typePermitExpired,
      severity: VeldAlert.severityCritical,
      title: 'Permit expired',
      message: 'Permit $label expired on ${_isoDate(expiry)}',
      createdAt: now,
    );
  }

  if (status == FarmPermit.permitStatusExpiringSoon) {
    final copy = days == 0
        ? 'expires today'
        : days == 1
            ? 'expires in 1 day'
            : 'expires in $days days';
    return VeldAlert(
      id: '${VeldAlert.typePermitExpiring}:${permit.id}',
      farmId: permit.farmId,
      campId: campId,
      alertType: VeldAlert.typePermitExpiring,
      severity: VeldAlert.severityWarning,
      title: 'Permit expiring soon',
      message: 'Permit $label $copy',
      createdAt: now,
    );
  }

  return null;
}

// ── Helpers ───────────────────────────────────────────────────────────

VeldAlert _campAlert({
  required String id,
  required Camp camp,
  required String type,
  required String severity,
  required String title,
  required String message,
  required DateTime now,
}) =>
    VeldAlert(
      id: id,
      farmId: camp.farmId,
      campId: camp.id,
      alertType: type,
      severity: severity,
      title: title,
      message: message,
      createdAt: now,
    );

double _countedLsu(List<StockEntry>? stock) {
  if (stock == null) return 0.0;
  var total = 0.0;
  for (final entry in stock) {
    if (entry.isCounted) total += entry.totalLsu;
  }
  return total;
}

/// Number of rainfall entries recorded in the trailing 12 months.
int _rainfallEntriesLastTwelveMonths(
  List<RainfallEntry> entries,
  DateTime now,
) {
  final months = RainfallEntry.recentMonths(now, count: 12).toSet();
  return entries.where((entry) => months.contains(entry.month)).length;
}

String _percent(double pct) => '${pct.toStringAsFixed(1)}%';

String _isoDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Human label for a [FarmPermit.permitTypes] constant.
///
/// Pure counterpart of the UI's `permitTypeLabel` (that helper lives in a
/// Flutter-importing file, and the alert/report layers must stay pure Dart).
String veldPermitTypeLabel(String permitType) {
  switch (FarmPermit.normalizePermitType(permitType)) {
    case FarmPermit.permitTypeCae:
      return 'CAE (adequate enclosure)';
    case FarmPermit.permitTypeExemption:
      return 'Exemption';
    case FarmPermit.permitTypeTops:
      return 'TOPS';
    case FarmPermit.permitTypeCites:
      return 'CITES';
    case FarmPermit.permitTypePhLicence:
      return 'PH licence';
    case FarmPermit.permitTypeOutfitterReg:
      return 'Outfitter registration';
    case FarmPermit.permitTypePredatorCaptivity:
      return 'Predator captivity';
    case FarmPermit.permitTypePredatorFencing:
      return 'Predator fencing';
    case FarmPermit.permitTypeDangerousGameFencing:
      return 'Dangerous game fencing';
    case FarmPermit.permitTypeVet:
      return 'Veterinary';
    case FarmPermit.permitTypeTransport:
      return 'Transport';
    case FarmPermit.permitTypeGameMovement:
      return 'Game movement';
    case FarmPermit.permitTypeOther:
    default:
      return 'Other';
  }
}

/// Human label for a [FarmPermit.permitStatuses] constant.
String veldPermitStatusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case FarmPermit.permitStatusExpiringSoon:
      return 'Expiring soon';
    case FarmPermit.permitStatusExpired:
      return 'Expired';
    case FarmPermit.permitStatusNoExpiry:
      return 'No expiry';
    case FarmPermit.permitStatusValid:
    default:
      return 'Valid';
  }
}
