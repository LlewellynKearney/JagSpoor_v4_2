import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'package:jagspoor/core/widgets/safe_bottom_inset.dart';
import 'package:jagspoor/features/outfitter_mode/widgets/outfitter_scaffold.dart';
import 'package:jagspoor/features/veld_carry/models/rainfall_entry.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Monthly rainfall log for one camp.
///
/// One figure per month — the document id IS the month key, so recording the
/// same month twice overwrites it. The trailing 12-month total feeds the veld
/// condition hint on the camp screen (a suggestion only; the outfitter still
/// decides the condition).
///
/// Reachable only through `VeldCarryGate`. Outfitter-only: no hunter path
/// reads this data.
class VeldCarryRainfallScreen extends StatefulWidget {
  const VeldCarryRainfallScreen({
    super.key,
    required this.farmId,
    required this.campId,
    this.campName,
    this.farmName,
    this.expectedAnnualMm,
    this.theme,
    this.repository,
    this.currentUidOverride,
    this.now,
  });

  final String farmId;
  final String campId;
  final String? campName;
  final String? farmName;

  /// The camp's own recorded annual rainfall, used for the condition hint.
  final double? expectedAnnualMm;

  final ThemeController? theme;
  final VeldCarryRepository? repository;

  /// Test seam: pins the signed-in uid so widget tests can drive the screen
  /// against a fake Firestore without a Firebase app.
  @visibleForTesting
  final String? currentUidOverride;

  /// Test seam: pins "today" so the 12-month window is deterministic.
  @visibleForTesting
  final DateTime? now;

  @override
  State<VeldCarryRainfallScreen> createState() =>
      _VeldCarryRainfallScreenState();
}

class _VeldCarryRainfallScreenState extends State<VeldCarryRainfallScreen> {
  late final ThemeController _theme = widget.theme ?? ThemeController.instance;
  late final VeldCarryRepository _repository =
      widget.repository ?? VeldCarryRepository.instance;

  bool _loading = true;
  String? _error;
  List<RainfallEntry> _entries = const [];

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _currentUid() {
    final override = widget.currentUidOverride;
    if (override != null) return override;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'You must be signed in to view rainfall.';
      });
      return;
    }
    try {
      final entries = await _repository.getRainfallEntries(
        uid,
        widget.farmId,
        widget.campId,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load rainfall: $e';
      });
    }
  }

  Map<String, RainfallEntry> get _byMonth => {
        for (final entry in _entries) entry.month: entry,
      };

  Future<void> _openForm({RainfallEntry? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OutfitterUi.cardColor(_theme),
      builder: (_) => _RainfallFormSheet(
        theme: _theme,
        repository: _repository,
        farmId: widget.farmId,
        campId: widget.campId,
        currentUid: _currentUid(),
        existing: existing,
        now: _now,
      ),
    );
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Rainfall',
              style: TextStyle(
                color: OutfitterUi.titleColor(theme),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              [
                if ((widget.campName ?? '').isNotEmpty) widget.campName!,
                if ((widget.farmName ?? '').isNotEmpty) widget.farmName!,
              ].join(' · '),
              style: TextStyle(
                color: OutfitterUi.subtitleColor(theme),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
        actions: [
          OutfitterActionChip(
            key: const ValueKey('veldRainfallAddButton'),
            icon: Icons.add_rounded,
            tooltip: 'Record rainfall',
            iconColor: theme.accentColor,
            onPressed: () => _openForm(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: OutfitterBushveldBackground.stack(
        fallbackColor: theme.backgroundColor,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _buildBody(theme),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeController theme) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.green),
      );
    }
    if (_error != null) {
      return ListView(
        padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: OutfitterUi.cardDecoration(theme),
            child: Text(
              _error!,
              style: TextStyle(color: theme.textColor, fontSize: 13),
            ),
          ),
        ],
      );
    }

    final months = RainfallEntry.recentMonths(_now, count: 12);
    final byMonth = _byMonth;
    final last12 = rainfallTotalLastTwelveMonths(_entries, now: _now);
    final calendarYear = rainfallTotalForYear(_entries, _now.year);
    final peak = months
        .map((month) => byMonth[month]?.rainfallMm ?? 0.0)
        .fold<double>(0.0, (a, b) => b > a ? b : a);

    return ListView(
      padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: OutfitterUi.cardDecoration(theme),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VeldCarrySectionLabel(label: 'RAINFALL TOTAL', theme: theme),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _totalCell(
                      theme,
                      key: const ValueKey('veldRainfallLast12Total'),
                      label: 'Last 12 months',
                      value: last12,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _totalCell(
                      theme,
                      key: const ValueKey('veldRainfallYearTotal'),
                      label: '${_now.year}',
                      value: calendarYear,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: OutfitterUi.cardDecoration(theme),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VeldCarrySectionLabel(
                label: 'LAST 12 MONTHS',
                theme: theme,
              ),
              const SizedBox(height: 8),
              for (final month in months)
                _barRow(
                  theme,
                  month: month,
                  entry: byMonth[month],
                  peak: peak,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: OutfitterUi.cardDecoration(theme),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VeldCarrySectionLabel(
                label: 'RECORDED MONTHS (${_entries.length})',
                theme: theme,
              ),
              const SizedBox(height: 8),
              if (_entries.isEmpty)
                Text(
                  'No rainfall recorded yet.',
                  key: const ValueKey('veldRainfallEmpty'),
                  style: TextStyle(
                    color: OutfitterUi.subtitleColor(theme),
                    fontSize: 12,
                  ),
                )
              else
                for (final entry in _entries)
                  _recordedRow(theme, entry),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const CopyrightFooter(),
      ],
    );
  }

  Widget _totalCell(
    ThemeController theme, {
    required Key key,
    required String label,
    required double value,
  }) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${value.toStringAsFixed(1)} mm',
          style: TextStyle(
            color: theme.textColor,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: OutfitterUi.subtitleColor(theme),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _barRow(
    ThemeController theme, {
    required String month,
    required RainfallEntry? entry,
    required double peak,
  }) {
    final mm = entry?.rainfallMm ?? 0.0;
    final fraction = peak <= 0 ? 0.0 : (mm / peak).clamp(0.0, 1.0);
    final label = RainfallEntry(
      id: month,
      farmId: widget.farmId,
      campId: widget.campId,
      month: month,
    ).monthLabel;
    return Padding(
      key: ValueKey('veldRainfallBar_$month'),
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: TextStyle(
                color: OutfitterUi.subtitleColor(theme),
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth * fraction;
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 10,
                    width: width,
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 58,
            child: Text(
              entry == null ? '—' : '${mm.toStringAsFixed(1)} mm',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: theme.textColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordedRow(ThemeController theme, RainfallEntry entry) {
    return InkWell(
      key: ValueKey('veldRainfallRow_${entry.month}'),
      onTap: () => _openForm(existing: entry),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                entry.monthLabel,
                style: TextStyle(color: theme.textColor, fontSize: 13),
              ),
            ),
            Text(
              '${entry.rainfallMm.toStringAsFixed(1)} mm',
              style: TextStyle(
                color: theme.textColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.edit_outlined, size: 16, color: theme.accentColor),
          ],
        ),
      ),
    );
  }
}

/// Add / edit one month's rainfall.
///
/// The month is fixed when editing — the document id is the month key, so
/// changing it would create a second row rather than moving the figure.
class _RainfallFormSheet extends StatefulWidget {
  const _RainfallFormSheet({
    required this.theme,
    required this.repository,
    required this.farmId,
    required this.campId,
    required this.currentUid,
    required this.now,
    this.existing,
  });

  final ThemeController theme;
  final VeldCarryRepository repository;
  final String farmId;
  final String campId;
  final String? currentUid;
  final DateTime now;
  final RainfallEntry? existing;

  @override
  State<_RainfallFormSheet> createState() => _RainfallFormSheetState();
}

class _RainfallFormSheetState extends State<_RainfallFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _mmController = TextEditingController();

  late int _year;
  late int _month;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _year = existing.year ?? widget.now.year;
      _month = existing.monthNumber ?? widget.now.month;
      _mmController.text = existing.rainfallMm.toStringAsFixed(1);
    } else {
      _year = widget.now.year;
      _month = widget.now.month;
    }
  }

  @override
  void dispose() {
    _mmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final mm = double.tryParse(_mmController.text.trim().replaceAll(',', '.'));
    if (mm == null || mm < 0) {
      setState(() => _error = 'Enter a rainfall figure of zero or more mm.');
      return;
    }
    final month =
        '${_year.toString().padLeft(4, '0')}-${_month.toString().padLeft(2, '0')}';
    final entry = RainfallEntry(
      id: month,
      farmId: widget.farmId,
      campId: widget.campId,
      month: month,
      rainfallMm: mm,
      recordedBy: widget.currentUid,
    );
    final validation = entry.validationError;
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await widget.repository.saveRainfallEntry(
        widget.currentUid ?? '',
        entry,
      );
      if (!mounted) return;
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the rainfall entry: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final editing = widget.existing != null;
    final years = <int>[
      for (var offset = 5; offset >= -1; offset--) widget.now.year - offset,
    ];
    return SafeArea(
      top: false,
      bottom: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                VeldCarrySectionLabel(
                  label: editing ? 'EDIT RAINFALL' : 'RECORD RAINFALL',
                  theme: theme,
                ),
                const SizedBox(height: 12),
                if (editing)
                  Text(
                    widget.existing!.monthLabel,
                    key: const ValueKey('veldRainfallMonthLabel'),
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else ...[
                  DropdownButtonFormField<int>(
                    key: const ValueKey('veldRainfallYearField'),
                    value: _year,
                    decoration:
                        OutfitterUi.inputDecoration(theme, labelText: 'Year'),
                    items: [
                      for (final year in years)
                        DropdownMenuItem(value: year, child: Text('$year')),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _year = value);
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: const ValueKey('veldRainfallMonthField'),
                    value: _month,
                    decoration:
                        OutfitterUi.inputDecoration(theme, labelText: 'Month'),
                    items: [
                      for (var index = 1; index <= 12; index++)
                        DropdownMenuItem(
                          value: index,
                          child: Text(_monthName(index)),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _month = value);
                          },
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('veldRainfallMmField'),
                  controller: _mmController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  enabled: !_saving,
                  decoration: OutfitterUi.inputDecoration(
                    theme,
                    labelText: 'Rainfall (mm)',
                    suffixText: 'mm',
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim().replaceAll(',', '.');
                    if (text.isEmpty) return 'Enter the rainfall in mm.';
                    final parsed = double.tryParse(text);
                    if (parsed == null) return 'Enter a valid number.';
                    if (parsed < 0) return 'Rainfall cannot be negative.';
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    key: const ValueKey('veldRainfallErrorText'),
                    style: const TextStyle(
                      color: Color(0xFFB71C1C),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('veldRainfallSaveButton'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'SAVING…' : 'SAVE RAINFALL'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.accentColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 46),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (month < 1 || month > 12) return '$month';
    return names[month - 1];
  }
}
