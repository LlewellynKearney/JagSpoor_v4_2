import 'package:pdf/widgets.dart' as pw;

import 'package:jagspoor/core/services/pdf_document_engine.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/models/farm_permit.dart';
import 'package:jagspoor/features/veld_carry/models/planted_area.dart';
import 'package:jagspoor/features/veld_carry/models/predator_entry.dart';
import 'package:jagspoor/features/veld_carry/models/rainfall_entry.dart';
import 'package:jagspoor/features/veld_carry/models/stock_entry.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_alerts.dart'
    show veldPermitStatusLabel, veldPermitTypeLabel;
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';

/// Veld report model + builder for the Veld & Carrying Capacity feature.
///
/// [buildVeldReport] is pure (models + calculator only) and produces the
/// complete, shareable snapshot; [renderVeldReportText] turns it into plain
/// text; [VeldReportPdfExporter] renders the same snapshot through the app's
/// EXISTING branded PDF engine (`JagSpoorPdfDocument`) — no new package.
///
/// **Privacy contract.** A report is outfitter-only and must never carry
/// coordinates, per-animal weights, per-animal GU/BU, permit numbers or
/// document URLs. Those fields are deliberately absent from every model here,
/// so they cannot leak into the text or the PDF by accident:
///  - [VeldReportCamp] holds aggregate capacity/usage figures only,
///  - [VeldReportSpeciesRow] holds a species name and a head count only,
///  - [VeldReportPermitRow] holds a type, an expiry date and a status only.
class Farm {
  const Farm({
    required this.id,
    required this.name,
    this.district = '',
    this.province = '',
  });

  final String id;
  final String name;
  final String district;
  final String province;

  factory Farm.fromMap(Map<String, dynamic> map, {String? id}) => Farm(
        id: id ?? (map['id'] ?? '').toString(),
        name: (map['name'] ?? map['farmName'] ?? '').toString(),
        district: (map['district'] ?? map['town'] ?? '').toString(),
        province: (map['province'] ?? '').toString(),
      );

  String get displayName => name.trim().isEmpty ? 'Unnamed farm' : name.trim();

  /// `Waterberg, Limpopo` — empty parts omitted.
  String get regionLabel {
    final parts = <String>[];
    if (district.trim().isNotEmpty) parts.add(district.trim());
    if (province.trim().isNotEmpty) parts.add(province.trim());
    return parts.join(', ');
  }
}

/// One species line in a camp's report: a name and a head count, nothing else.
class VeldReportSpeciesRow {
  const VeldReportSpeciesRow({required this.speciesName, required this.count});

  final String speciesName;
  final int count;
}

/// One planted area line: feed type label, hectares and its LSU contribution.
class VeldReportPlantedRow {
  const VeldReportPlantedRow({
    required this.label,
    required this.areaHa,
    required this.capacityLsu,
  });

  final String label;
  final double areaHa;
  final double capacityLsu;
}

/// One predator line: a name and a head count.
class VeldReportPredatorRow {
  const VeldReportPredatorRow({
    required this.predatorName,
    required this.count,
  });

  final String predatorName;
  final int count;
}

/// One permit line: type, expiry and status — never the permit number or any
/// document URL.
class VeldReportPermitRow {
  const VeldReportPermitRow({
    required this.permitType,
    required this.expiryDate,
    required this.status,
  });

  final String permitType;
  final DateTime? expiryDate;
  final String status;

  String get permitTypeLabel => veldPermitTypeLabel(permitType);
  String get statusLabel => veldPermitStatusLabel(status);
}

/// Everything one camp contributes to the report.
class VeldReportCamp {
  const VeldReportCamp({
    required this.campId,
    required this.name,
    required this.sizeHa,
    required this.veldType,
    required this.veldCondition,
    required this.deptNormHaPerLsu,
    required this.effectiveHaPerLsu,
    required this.veldCapacityLsu,
    required this.plantedCapacityLsu,
    required this.totalCapacityLsu,
    required this.stockLsu,
    required this.stockGu,
    required this.stockBu,
    required this.usagePct,
    required this.headroomLsu,
    required this.stockingStatus,
    required this.species,
    required this.planted,
    required this.predators,
    required this.rainfallLast12MonthsMm,
  });

  final String campId;
  final String name;
  final double sizeHa;
  final String veldType;
  final String veldCondition;
  final double deptNormHaPerLsu;
  final double effectiveHaPerLsu;
  final double veldCapacityLsu;
  final double plantedCapacityLsu;
  final double totalCapacityLsu;

  /// Aggregate LSU / GU / BU for the camp — never per animal.
  final double stockLsu;
  final double stockGu;
  final double stockBu;

  final double usagePct;
  final double headroomLsu;
  final String stockingStatus;

  final List<VeldReportSpeciesRow> species;
  final List<VeldReportPlantedRow> planted;
  final List<VeldReportPredatorRow> predators;
  final double rainfallLast12MonthsMm;
}

/// Farm-wide totals across every camp in the report.
class VeldReportTotals {
  const VeldReportTotals({
    required this.campCount,
    required this.totalSizeHa,
    required this.veldCapacityLsu,
    required this.plantedCapacityLsu,
    required this.totalCapacityLsu,
    required this.stockLsu,
    required this.stockGu,
    required this.stockBu,
    required this.usagePct,
    required this.headroomLsu,
    required this.stockingStatus,
  });

  final int campCount;
  final double totalSizeHa;
  final double veldCapacityLsu;
  final double plantedCapacityLsu;
  final double totalCapacityLsu;
  final double stockLsu;
  final double stockGu;
  final double stockBu;
  final double usagePct;
  final double headroomLsu;
  final String stockingStatus;
}

/// The complete, shareable veld snapshot.
class VeldReport {
  const VeldReport({
    required this.farmId,
    required this.farmName,
    required this.generatedAt,
    required this.camps,
    required this.permits,
    required this.totals,
  });

  final String farmId;
  final String farmName;
  final DateTime generatedAt;
  final List<VeldReportCamp> camps;
  final List<VeldReportPermitRow> permits;
  final VeldReportTotals totals;

  /// The plain-text rendering (the Copy / share fallback).
  String toPlainText() => renderVeldReportText(this);
}

/// Builds the report snapshot from the records the repository already loads.
///
/// [rainfallByCamp] is required because the report carries each camp's
/// trailing-12-month rainfall; omitting it would silently report `0.0 mm`.
VeldReport buildVeldReport({
  required Farm farm,
  required List<Camp> camps,
  required Map<String, List<StockEntry>> stockByCamp,
  required Map<String, List<PlantedArea>> plantedByCamp,
  required Map<String, List<PredatorEntry>> predatorsByCamp,
  required List<FarmPermit> permits,
  required Map<String, List<RainfallEntry>> rainfallByCamp,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final rows = <VeldReportCamp>[];

  for (final camp in camps) {
    rows.add(_campRow(camp, stockByCamp, plantedByCamp, predatorsByCamp,
        rainfallByCamp, reference));
  }

  var sizeHa = 0.0;
  var veldCapacity = 0.0;
  var plantedCapacity = 0.0;
  var totalCapacity = 0.0;
  var stockLsu = 0.0;
  var stockGu = 0.0;
  var stockBu = 0.0;
  for (final row in rows) {
    sizeHa += row.sizeHa;
    veldCapacity += row.veldCapacityLsu;
    plantedCapacity += row.plantedCapacityLsu;
    totalCapacity += row.totalCapacityLsu;
    stockLsu += row.stockLsu;
    stockGu += row.stockGu;
    stockBu += row.stockBu;
  }
  final totalsUsage = usagePct(stockLsu, totalCapacity);

  return VeldReport(
    farmId: farm.id,
    farmName: farm.displayName,
    generatedAt: reference,
    camps: List<VeldReportCamp>.unmodifiable(rows),
    permits: List<VeldReportPermitRow>.unmodifiable(
      permits.map(
        (permit) => VeldReportPermitRow(
          permitType: permit.permitType,
          expiryDate: permit.expiryDate,
          status: permit.status,
        ),
      ),
    ),
    totals: VeldReportTotals(
      campCount: rows.length,
      totalSizeHa: sizeHa,
      veldCapacityLsu: veldCapacity,
      plantedCapacityLsu: plantedCapacity,
      totalCapacityLsu: totalCapacity,
      stockLsu: stockLsu,
      stockGu: stockGu,
      stockBu: stockBu,
      usagePct: totalsUsage,
      headroomLsu: headroomLsu(totalCapacity, stockLsu),
      stockingStatus: stockingStatus(totalsUsage),
    ),
  );
}

VeldReportCamp _campRow(
  Camp camp,
  Map<String, List<StockEntry>> stockByCamp,
  Map<String, List<PlantedArea>> plantedByCamp,
  Map<String, List<PredatorEntry>> predatorsByCamp,
  Map<String, List<RainfallEntry>> rainfallByCamp,
  DateTime now,
) {
  final stock = stockByCamp[camp.id] ?? const <StockEntry>[];
  final planted = plantedByCamp[camp.id] ?? const <PlantedArea>[];
  final predators = predatorsByCamp[camp.id] ?? const <PredatorEntry>[];
  final rainfall = rainfallByCamp[camp.id] ?? const <RainfallEntry>[];

  final effective = effectiveHaPerLsu(camp.deptNormHaPerLsu, camp.veldCondition);
  final veldCapacity = veldCapacityLsu(camp.totalSizeHa, effective);
  final plantedCapacity = yearRoundCapacityLsu(0, planted);
  final totalCapacity = yearRoundCapacityLsu(veldCapacity, planted);

  var stockLsu = 0.0;
  var stockGu = 0.0;
  var stockBu = 0.0;
  for (final entry in stock) {
    if (!entry.isCounted) continue;
    stockLsu += entry.totalLsu;
    stockGu += entry.totalGu;
    stockBu += entry.totalBu;
  }
  final usage = usagePct(stockLsu, totalCapacity);

  final speciesRows = stock
      .map((entry) => VeldReportSpeciesRow(
            speciesName: entry.speciesName,
            count: entry.count,
          ))
      .toList(growable: false)
    ..sort((a, b) => a.speciesName.compareTo(b.speciesName));
  final predatorRows = predators
      .map((entry) => VeldReportPredatorRow(
            predatorName: entry.predatorName,
            count: entry.count,
          ))
      .toList(growable: false)
    ..sort((a, b) => a.predatorName.compareTo(b.predatorName));

  return VeldReportCamp(
    campId: camp.id,
    name: camp.name.trim().isEmpty ? 'Unnamed camp' : camp.name.trim(),
    sizeHa: camp.totalSizeHa,
    veldType: camp.veldType,
    veldCondition: camp.veldCondition,
    deptNormHaPerLsu: camp.deptNormHaPerLsu,
    effectiveHaPerLsu: effective,
    veldCapacityLsu: veldCapacity,
    plantedCapacityLsu: plantedCapacity,
    totalCapacityLsu: totalCapacity,
    stockLsu: stockLsu,
    stockGu: stockGu,
    stockBu: stockBu,
    usagePct: usage,
    headroomLsu: headroomLsu(totalCapacity, stockLsu),
    stockingStatus: stockingStatus(usage),
    species: List<VeldReportSpeciesRow>.unmodifiable(speciesRows),
    planted: List<VeldReportPlantedRow>.unmodifiable(
      planted.map(
        (area) => VeldReportPlantedRow(
          label: _plantedLabel(area),
          areaHa: area.areaHa,
          capacityLsu: plantedCapacityLsu(area.areaHa, area.haPerLsu),
        ),
      ),
    ),
    predators: List<VeldReportPredatorRow>.unmodifiable(predatorRows),
    rainfallLast12MonthsMm:
        rainfallTotalLastTwelveMonths(rainfall, now: now),
  );
}

/// `LUCERNE_IRRIGATED` -> `Lucerne irrigated`; a custom area keeps its name.
///
/// Derived from the constant rather than duplicating the UI's label table, so
/// the report can never disagree with a newly added feed type.
String _plantedLabel(PlantedArea area) {
  if (area.feedType == PlantedArea.feedTypeOtherCustom) {
    final custom = (area.customName ?? '').trim();
    return custom.isEmpty ? 'Other (custom)' : custom;
  }
  final words = area.feedType.trim().toLowerCase().split('_');
  if (words.isEmpty) return area.feedType;
  final first = words.first;
  final head = first.isEmpty
      ? first
      : '${first.substring(0, 1).toUpperCase()}${first.substring(1)}';
  return [head, ...words.skip(1)].join(' ');
}

// ── Plain text ────────────────────────────────────────────────────────

/// Renders the report as readable plain text (the Copy-to-clipboard / share
/// fallback, and the exact copy the PDF mirrors).
String renderVeldReportText(VeldReport report) {
  final out = StringBuffer();
  out.writeln('JAGSPOOR VELD CARRYING CAPACITY');
  out.writeln('Farm: ${report.farmName}');
  out.writeln(
    'Generated ${_isoDate(report.generatedAt)} — '
    'JagSpoor Veld Carrying Capacity',
  );
  out.writeln();

  final totals = report.totals;
  out.writeln('TOTALS');
  out.writeln('  Camps: ${totals.campCount}');
  out.writeln('  Total size: ${_num1(totals.totalSizeHa)} ha');
  out.writeln('  Veld capacity: ${_lsu(totals.veldCapacityLsu)}');
  out.writeln('  Planted capacity: ${_lsu(totals.plantedCapacityLsu)}');
  out.writeln('  Total capacity: ${_lsu(totals.totalCapacityLsu)}');
  out.writeln(
    '  Stock: ${_lsu(totals.stockLsu)} / ${_num1(totals.stockGu)} GU / '
    '${_num1(totals.stockBu)} BU',
  );
  out.writeln('  Usage: ${_pct(totals.usagePct)}');
  out.writeln('  Headroom: ${_lsu(totals.headroomLsu)}');
  out.writeln('  Stocking: ${_stockingLabel(totals.stockingStatus)}');
  out.writeln();

  for (final camp in report.camps) {
    out.writeln('CAMP: ${camp.name}');
    out.writeln(
      '  Size: ${_num1(camp.sizeHa)} ha · Veld type: '
      '${camp.veldType.trim().isEmpty ? '—' : camp.veldType} · Condition: '
      '${_conditionLabel(camp.veldCondition)}',
    );
    out.writeln(
      '  Departmental norm: ${_num1(camp.deptNormHaPerLsu)} ha/LSU · '
      'Effective: ${_num1(camp.effectiveHaPerLsu)} ha/LSU',
    );
    out.writeln(
      '  Veld capacity: ${_lsu(camp.veldCapacityLsu)} · Planted capacity: '
      '${_lsu(camp.plantedCapacityLsu)} · Total: '
      '${_lsu(camp.totalCapacityLsu)}',
    );
    out.writeln(
      '  Stock: ${_lsu(camp.stockLsu)} / ${_num1(camp.stockGu)} GU / '
      '${_num1(camp.stockBu)} BU',
    );
    out.writeln(
      '  Usage: ${_pct(camp.usagePct)} · Headroom: '
      '${_lsu(camp.headroomLsu)} · Stocking: '
      '${_stockingLabel(camp.stockingStatus)}',
    );
    out.writeln(
      '  Species: ${_speciesLine(camp.species)}',
    );
    if (camp.planted.isNotEmpty) {
      out.writeln('  Planted: ${_plantedLine(camp.planted)}');
    }
    if (camp.predators.isNotEmpty) {
      out.writeln('  Predators: ${_predatorLine(camp.predators)}');
    }
    out.writeln(
      '  Rainfall (last 12 months): '
      '${_num1(camp.rainfallLast12MonthsMm)} mm',
    );
    out.writeln();
  }

  out.writeln('PERMITS');
  if (report.permits.isEmpty) {
    out.writeln('  No permits recorded.');
  } else {
    for (final permit in report.permits) {
      out.writeln(
        '  ${permit.permitTypeLabel} — expires '
        '${_isoDateOrDash(permit.expiryDate)} — ${permit.statusLabel}',
      );
    }
  }
  return out.toString().trimRight();
}

String _speciesLine(List<VeldReportSpeciesRow> rows) {
  if (rows.isEmpty) return 'none recorded';
  return rows.map((row) => '${row.speciesName} × ${row.count}').join('; ');
}

String _plantedLine(List<VeldReportPlantedRow> rows) => rows
    .map(
      (row) =>
          '${row.label} ${_num1(row.areaHa)} ha → ${_lsu(row.capacityLsu)}',
    )
    .join('; ');

String _predatorLine(List<VeldReportPredatorRow> rows) =>
    rows.map((row) => '${row.predatorName} × ${row.count}').join('; ');

String _num1(double value) => value.isFinite ? value.toStringAsFixed(1) : '—';

String _lsu(double value) => '${_num1(value)} LSU';

String _pct(double value) => '${_num1(value)}%';

String _isoDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _isoDateOrDash(DateTime? date) => date == null ? '—' : _isoDate(date);

String _stockingLabel(String status) {
  switch (status) {
    case stockingOptimal:
      return 'Optimal';
    case stockingOverstocked:
      return 'Overstocked';
    case stockingSeverelyOverstocked:
      return 'Severely overstocked';
    case stockingUnderstocked:
    default:
      return 'Understocked';
  }
}

String _conditionLabel(String condition) {
  switch (Camp.normalizeVeldCondition(condition)) {
    case Camp.veldConditionFair:
      return 'Fair';
    case Camp.veldConditionPoor:
      return 'Poor';
    default:
      return 'Good';
  }
}

// ── PDF export (reuses the app's existing branded PDF engine) ──────────

/// Renders a [VeldReport] through the existing `JagSpoorPdfDocument` engine
/// (logo header, brand palette, page footer) and hands it to the OS share
/// sheet. No new PDF / printing / share dependency is introduced.
class VeldReportPdfExporter {
  /// Builds the PDF and invokes the native share sheet.
  Future<void> generateAndShare(VeldReport report) async {
    final doc = await JagSpoorPdfDocument.create(
      title: 'Veld Carrying Capacity Report',
      documentId: report.farmId.trim().isEmpty
          ? 'VELD-${report.generatedAt.millisecondsSinceEpoch}'
          : 'VELD-${report.farmId}',
    );
    doc.addPage(margin: 28, content: buildContent(report));

    final safeName = report.farmName.replaceAll(RegExp(r'[^\w\-]'), '_');
    await doc.saveAndShare(
      filename: 'JagSpoor_Veld_Report_$safeName',
      shareSubject: 'JagSpoor Veld Report · ${report.farmName}',
      shareText: 'Veld carrying capacity report for ${report.farmName}.',
    );
  }

  /// Pure content builder — returns the `pw.Widget` tree the engine wraps in
  /// its branded header + footer. Kept separate so it can be rendered to bytes
  /// in a test without touching the share sheet.
  pw.Widget buildContent(VeldReport report) {
    final totals = report.totals;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        JagSpoorPdfTheme.sectionBar('VELD CARRYING CAPACITY'),
        pw.SizedBox(height: 6),
        pw.Text(
          report.farmName,
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: JagSpoorPdfTheme.darkSlate,
          ),
        ),
        // ASCII hyphen, not an em dash: the PDF engine's built-in Helvetica
        // has no U+2014 glyph. The plain-text report keeps the em dash.
        pw.Text(
          'Generated ${_isoDate(report.generatedAt)} - '
          'JagSpoor Veld Carrying Capacity',
          style: JagSpoorPdfTheme.caption,
        ),
        pw.SizedBox(height: 10),

        JagSpoorPdfTheme.sectionBar('Farm Totals'),
        pw.SizedBox(height: 4),
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.infoRow('Camps', '${totals.campCount}'),
          JagSpoorPdfTheme.infoRow(
            'Total size',
            '${_num1(totals.totalSizeHa)} ha',
          ),
          JagSpoorPdfTheme.infoRow(
            'Veld capacity',
            _lsu(totals.veldCapacityLsu),
          ),
          JagSpoorPdfTheme.infoRow(
            'Planted capacity',
            _lsu(totals.plantedCapacityLsu),
          ),
          JagSpoorPdfTheme.infoRow(
            'Total capacity',
            _lsu(totals.totalCapacityLsu),
          ),
          JagSpoorPdfTheme.infoRow(
            'Stock',
            '${_lsu(totals.stockLsu)} / ${_num1(totals.stockGu)} GU / '
                '${_num1(totals.stockBu)} BU',
          ),
          JagSpoorPdfTheme.infoRow('Usage', _pct(totals.usagePct)),
          JagSpoorPdfTheme.infoRow(
            'Headroom',
            _lsu(totals.headroomLsu),
          ),
          JagSpoorPdfTheme.infoRow(
            'Stocking',
            _stockingLabel(totals.stockingStatus),
          ),
        ]),

        for (final camp in report.camps) ...[
          JagSpoorPdfTheme.sectionBar('Camp · ${camp.name}'),
          JagSpoorPdfTheme.detailBox([
            JagSpoorPdfTheme.infoRow(
              'Size',
              '${_num1(camp.sizeHa)} ha',
            ),
            JagSpoorPdfTheme.infoRow(
              'Veld type',
              camp.veldType.trim().isEmpty ? '—' : camp.veldType,
            ),
            JagSpoorPdfTheme.infoRow(
              'Condition',
              _conditionLabel(camp.veldCondition),
            ),
            JagSpoorPdfTheme.infoRow(
              'Departmental norm',
              '${_num1(camp.deptNormHaPerLsu)} ha/LSU',
            ),
            JagSpoorPdfTheme.infoRow(
              'Effective norm',
              '${_num1(camp.effectiveHaPerLsu)} ha/LSU',
            ),
            JagSpoorPdfTheme.infoRow(
              'Veld capacity',
              _lsu(camp.veldCapacityLsu),
            ),
            JagSpoorPdfTheme.infoRow(
              'Planted capacity',
              _lsu(camp.plantedCapacityLsu),
            ),
            JagSpoorPdfTheme.infoRow(
              'Total capacity',
              _lsu(camp.totalCapacityLsu),
            ),
            JagSpoorPdfTheme.infoRow(
              'Stock',
              '${_lsu(camp.stockLsu)} / ${_num1(camp.stockGu)} GU / '
                  '${_num1(camp.stockBu)} BU',
            ),
            JagSpoorPdfTheme.infoRow('Usage', _pct(camp.usagePct)),
            JagSpoorPdfTheme.infoRow('Headroom', _lsu(camp.headroomLsu)),
            JagSpoorPdfTheme.infoRow(
              'Stocking',
              _stockingLabel(camp.stockingStatus),
            ),
            JagSpoorPdfTheme.infoRow(
              'Rainfall (12 months)',
              '${_num1(camp.rainfallLast12MonthsMm)} mm',
            ),
          ]),
          pw.SizedBox(height: 6),
          JagSpoorPdfTheme.dataTable(
            headers: const ['Species', 'Count'],
            rows: camp.species
                .map((row) => [row.speciesName, '${row.count}'])
                .toList(growable: false),
            columnWidths: const [4, 1],
          ),
          if (camp.planted.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            JagSpoorPdfTheme.dataTable(
              headers: const ['Planted area', 'Hectares', 'LSU'],
              rows: camp.planted
                  .map(
                    (row) => [
                      row.label,
                      _num1(row.areaHa),
                      _num1(row.capacityLsu),
                    ],
                  )
                  .toList(growable: false),
              columnWidths: const [3, 1, 1],
            ),
          ],
          if (camp.predators.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            JagSpoorPdfTheme.dataTable(
              headers: const ['Predator', 'Count'],
              rows: camp.predators
                  .map((row) => [row.predatorName, '${row.count}'])
                  .toList(growable: false),
              columnWidths: const [4, 1],
            ),
          ],
        ],

        JagSpoorPdfTheme.sectionBar('Permits'),
        pw.SizedBox(height: 4),
        if (report.permits.isEmpty)
          pw.Text('No permits recorded.', style: JagSpoorPdfTheme.caption)
        else
          JagSpoorPdfTheme.dataTable(
            headers: const ['Permit type', 'Expires', 'Status'],
            rows: report.permits
                .map(
                  (row) => [
                    row.permitTypeLabel,
                    _isoDateOrDash(row.expiryDate),
                    row.statusLabel,
                  ],
                )
                .toList(growable: false),
            columnWidths: const [3, 1.4, 1.4],
          ),
      ],
    );
  }
}
