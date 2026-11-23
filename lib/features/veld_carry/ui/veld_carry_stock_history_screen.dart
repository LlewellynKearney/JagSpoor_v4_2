import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'package:jagspoor/core/widgets/safe_bottom_inset.dart';
import 'package:jagspoor/features/outfitter_mode/widgets/outfitter_scaffold.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/models/stock_entry.dart';
import 'package:jagspoor/features/veld_carry/models/stock_movement.dart';
import 'package:jagspoor/features/veld_carry/species_defaults.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Stock movement history for one camp, or for the whole farm.
///
/// This is the audit trail behind a camp's stock snapshot: every add, move,
/// hunt, death and sale. Recording a movement updates the affected camp
/// ledgers in the same Firestore transaction (see
/// [VeldCarryRepository.recordStockMovement]), so the numbers on the camp
/// screen and the rows here can never disagree.
///
/// Reachable only through `VeldCarryGate` — with the feature flag OFF nothing
/// links here. A hunter never sees this screen: it is an outfitter tool and
/// exposes counts, reasons and camp names.
class VeldCarryStockHistoryScreen extends StatefulWidget {
  const VeldCarryStockHistoryScreen({
    super.key,
    required this.farmId,
    this.campId,
    this.campName,
    this.farmName,
    this.camp,
    this.theme,
    this.repository,
    this.currentUidOverride,
  });

  final String farmId;

  /// Null renders the farm-wide history (read-only — a movement always belongs
  /// to a camp).
  final String? campId;
  final String? campName;
  final String? farmName;

  /// The camp whose history is shown, when known. Used for the default source
  /// camp of a move.
  final Camp? camp;

  final ThemeController? theme;
  final VeldCarryRepository? repository;

  /// Test seam: pins the signed-in uid so widget tests can drive the screen
  /// against a fake Firestore without a Firebase app.
  @visibleForTesting
  final String? currentUidOverride;

  @override
  State<VeldCarryStockHistoryScreen> createState() =>
      _VeldCarryStockHistoryScreenState();
}

class _VeldCarryStockHistoryScreenState
    extends State<VeldCarryStockHistoryScreen> {
  late final ThemeController _theme = widget.theme ?? ThemeController.instance;
  late final VeldCarryRepository _repository =
      widget.repository ?? VeldCarryRepository.instance;

  bool _loading = true;
  String? _error;
  List<StockMovement> _movements = const [];
  List<StockEntry> _stock = const [];
  List<Camp> _camps = const [];

  String? get _campId {
    final id = (widget.campId ?? '').trim();
    return id.isEmpty ? null : id;
  }

  bool get _isCampScoped => _campId != null;

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
        _error = 'You must be signed in to view stock history.';
      });
      return;
    }
    try {
      final movements = await _repository.getStockMovements(
        uid,
        widget.farmId,
        campId: _campId,
      );
      final camps = await _repository.getCamps(uid, widget.farmId);
      final stock = _isCampScoped
          ? await _repository.getStockEntries(uid, widget.farmId, _campId!)
          : const <StockEntry>[];
      if (!mounted) return;
      setState(() {
        _movements = movements;
        _camps = camps;
        _stock = stock;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load stock history: $e';
      });
    }
  }

  String _campName(String? campId) {
    final id = (campId ?? '').trim();
    if (id.isEmpty) return '—';
    for (final camp in _camps) {
      if (camp.id == id) return camp.name.isEmpty ? 'Unnamed camp' : camp.name;
    }
    if (id == _campId && (widget.campName ?? '').isNotEmpty) {
      return widget.campName!;
    }
    return 'Camp';
  }

  Future<void> _openAddMovement() async {
    final campId = _campId;
    if (campId == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OutfitterUi.cardColor(_theme),
      builder: (_) => _MovementFormSheet(
        theme: _theme,
        repository: _repository,
        farmId: widget.farmId,
        campId: campId,
        camps: _camps,
        stock: _stock,
        currentUid: _currentUid(),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    final title = widget.campName?.trim().isNotEmpty == true
        ? widget.campName!.trim()
        : (_isCampScoped ? 'Stock history' : 'Farm stock history');
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isCampScoped ? 'Stock History' : 'Farm Stock History',
              style: TextStyle(
                color: OutfitterUi.titleColor(theme),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              [title, if ((widget.farmName ?? '').isNotEmpty) widget.farmName!]
                  .join(' · '),
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
          if (_isCampScoped)
            OutfitterActionChip(
              key: const ValueKey('veldHistoryAddButton'),
              icon: Icons.add_rounded,
              tooltip: 'Record movement',
              iconColor: theme.accentColor,
              onPressed: _openAddMovement,
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
    return ListView(
      padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
      children: [
        if (!_isCampScoped)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Every movement across the farm, newest first. Open a camp to '
              'record a new movement.',
              style: TextStyle(
                color: OutfitterUi.subtitleColor(theme),
                fontSize: 12,
              ),
            ),
          ),
        if (_movements.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: OutfitterUi.cardDecoration(theme),
            child: Text(
              'No stock movements recorded yet.',
              key: const ValueKey('veldHistoryEmpty'),
              style: TextStyle(
                color: OutfitterUi.subtitleColor(theme),
                fontSize: 12,
              ),
            ),
          )
        else
          for (final movement in _movements)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _movementCard(theme, movement),
            ),
        const SizedBox(height: 8),
        const CopyrightFooter(),
      ],
    );
  }

  Widget _movementCard(ThemeController theme, StockMovement movement) {
    final incoming = movement.count > 0;
    final badgeColor = _movementColor(movement.movementType);
    return Container(
      key: ValueKey('veldHistoryMovement_${movement.id}'),
      padding: const EdgeInsets.all(12),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  speciesDisplayName(movement.speciesName),
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              VeldCarryBadge(
                label: StockMovement.movementTypeLabel(movement.movementType),
                color: badgeColor,
                darkMode: theme.isDarkMode,
              ),
              const SizedBox(width: 6),
              Text(
                movement.signedCountLabel,
                style: TextStyle(
                  color: incoming ? const Color(0xFF1B5E20) : badgeColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            formatPermitDate(movement.recordedAt),
            style: TextStyle(
              color: OutfitterUi.subtitleColor(theme),
              fontSize: 11,
            ),
          ),
          if (movement.isMove) ...[
            const SizedBox(height: 4),
            Text(
              '${_campName(movement.fromCampId)} → '
              '${_campName(movement.toCampId)}',
              style: TextStyle(
                color: OutfitterUi.subtitleColor(theme),
                fontSize: 12,
              ),
            ),
          ],
          if ((movement.reason ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              movement.reason!.trim(),
              style: TextStyle(color: theme.textColor, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Color _movementColor(String movementType) {
    switch (StockMovement.normalizeMovementType(movementType)) {
      case StockMovement.typeAdded:
      case StockMovement.typeMovedIn:
        return const Color(0xFF1B5E20);
      case StockMovement.typeHunted:
        return const Color(0xFFB26A00);
      case StockMovement.typeDied:
        return const Color(0xFFB71C1C);
      case StockMovement.typeSold:
        return const Color(0xFF1565C0);
      case StockMovement.typeCountAdjustment:
        return const Color(0xFF6A1B9A);
      case StockMovement.typeMovedOut:
      default:
        return const Color(0xFFB26A00);
    }
  }
}

/// Add-movement form.
///
/// The user always types a POSITIVE magnitude; the sign is derived from the
/// movement type ([StockMovement.isSignValid] is the contract). For a move the
/// source/destination camps are chosen explicitly.
class _MovementFormSheet extends StatefulWidget {
  const _MovementFormSheet({
    required this.theme,
    required this.repository,
    required this.farmId,
    required this.campId,
    required this.camps,
    required this.stock,
    required this.currentUid,
  });

  final ThemeController theme;
  final VeldCarryRepository repository;
  final String farmId;
  final String campId;
  final List<Camp> camps;
  final List<StockEntry> stock;
  final String? currentUid;

  @override
  State<_MovementFormSheet> createState() => _MovementFormSheetState();
}

class _MovementFormSheetState extends State<_MovementFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _countController = TextEditingController();
  final _reasonController = TextEditingController();

  String _movementType = StockMovement.typeHunted;
  String? _speciesName;
  String? _fromCampId;
  String? _toCampId;
  bool _decreaseAdjustment = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fromCampId = widget.campId;
    if (widget.camps.length > 1) {
      for (final camp in widget.camps) {
        if (camp.id != widget.campId) {
          _toCampId = camp.id;
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _countController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  /// Species offered for the current movement type.
  ///
  /// Outgoing movements may only take species the camp already holds; incoming
  /// movements may introduce any counted species from the authorised table.
  List<String> get _speciesOptions {
    if (StockMovement.requiresPositiveCount(_movementType)) {
      return countedSpeciesDefaults
          .map((species) => species.speciesName)
          .toList(growable: false);
    }
    return widget.stock
        .where((entry) => entry.count > 0)
        .map((entry) => entry.speciesName)
        .toList(growable: false);
  }

  int _signedCount(int magnitude) {
    if (StockMovement.requiresPositiveCount(_movementType)) return magnitude;
    if (StockMovement.requiresNegativeCount(_movementType)) return -magnitude;
    return _decreaseAdjustment ? -magnitude : magnitude;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final magnitude = int.tryParse(_countController.text.trim()) ?? 0;
    final species = (_speciesName ?? '').trim();
    if (magnitude <= 0 || species.isEmpty) {
      setState(() => _error = 'Enter a species and a count above zero.');
      return;
    }
    final isMove = StockMovement.isMoveType(_movementType);
    final movement = StockMovement(
      id: VeldCarryRepository.newId(),
      farmId: widget.farmId,
      campId: isMove
          ? (StockMovement.requiresPositiveCount(_movementType)
              ? (_toCampId ?? widget.campId)
              : (_fromCampId ?? widget.campId))
          : widget.campId,
      speciesId: VeldCarryRepository.speciesStockEntryId(species),
      speciesName: species,
      movementType: _movementType,
      count: _signedCount(magnitude),
      fromCampId: isMove ? _fromCampId : null,
      toCampId: isMove ? _toCampId : null,
      reason: _reasonController.text.trim().isEmpty
          ? null
          : _reasonController.text.trim(),
      recordedBy: widget.currentUid,
    );
    final validation = movement.validationError;
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
      await widget.repository.recordStockMovement(
        widget.currentUid ?? '',
        movement,
      );
      if (!mounted) return;
      navigator.pop(true);
    } on StockBelowZeroException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'That would take the camp below zero — '
            '${e.speciesName} has ${e.currentCount} head.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not record the movement: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isMove = StockMovement.isMoveType(_movementType);
    final reasonRequired = StockMovement.requiresReason(_movementType);
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
                VeldCarrySectionLabel(label: 'RECORD MOVEMENT', theme: theme),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('veldMovementTypeField'),
                  value: _movementType,
                  decoration: _decoration(theme, 'Movement type'),
                  items: [
                    for (final type in StockMovement.movementTypes)
                      DropdownMenuItem(
                        value: type,
                        child: Text(StockMovement.movementTypeLabel(type)),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _movementType = value;
                            _speciesName = null;
                            _error = null;
                          });
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('veldMovementSpeciesField'),
                  value: _speciesName,
                  isExpanded: true,
                  decoration: _decoration(theme, 'Species'),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Choose a species.' : null,
                  items: [
                    for (final species in _speciesOptions)
                      DropdownMenuItem(
                        value: species,
                        child: Text(
                          speciesDisplayName(species),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _speciesName = value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('veldMovementCountField'),
                  controller: _countController,
                  keyboardType: TextInputType.number,
                  enabled: !_saving,
                  decoration: _decoration(theme, 'Count (number of animals)'),
                  validator: (value) {
                    final parsed = int.tryParse((value ?? '').trim());
                    if (parsed == null || parsed <= 0) {
                      return 'Enter a count greater than zero.';
                    }
                    return null;
                  },
                ),
                if (StockMovement.allowsAnySign(_movementType)) ...[
                  const SizedBox(height: 4),
                  SwitchListTile(
                    key: const ValueKey('veldMovementDecreaseSwitch'),
                    contentPadding: EdgeInsets.zero,
                    value: _decreaseAdjustment,
                    title: Text(
                      'Decrease the count (negative adjustment)',
                      style: TextStyle(color: theme.textColor, fontSize: 12),
                    ),
                    onChanged: _saving
                        ? null
                        : (value) =>
                            setState(() => _decreaseAdjustment = value),
                  ),
                ],
                if (isMove) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('veldMovementFromCampField'),
                    value: _fromCampId,
                    isExpanded: true,
                    decoration: _decoration(theme, 'From camp'),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Choose the source camp.'
                        : null,
                    items: [
                      for (final camp in widget.camps)
                        DropdownMenuItem(
                          value: camp.id,
                          child: Text(
                            camp.name.isEmpty ? 'Unnamed camp' : camp.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _fromCampId = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('veldMovementToCampField'),
                    value: _toCampId,
                    isExpanded: true,
                    decoration: _decoration(theme, 'To camp'),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Choose the destination camp.'
                        : null,
                    items: [
                      for (final camp in widget.camps)
                        DropdownMenuItem(
                          value: camp.id,
                          child: Text(
                            camp.name.isEmpty ? 'Unnamed camp' : camp.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _toCampId = value),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('veldMovementReasonField'),
                  controller: _reasonController,
                  enabled: !_saving,
                  maxLines: 2,
                  decoration: _decoration(
                    theme,
                    reasonRequired ? 'Cause / notes (required)' : 'Reason (optional)',
                  ),
                  validator: (value) {
                    if (reasonRequired && (value ?? '').trim().isEmpty) {
                      return 'A cause / notes entry is required.';
                    }
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    key: const ValueKey('veldMovementErrorText'),
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
                    key: const ValueKey('veldMovementSaveButton'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'SAVING…' : 'RECORD MOVEMENT'),
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

  InputDecoration _decoration(ThemeController theme, String label) =>
      OutfitterUi.inputDecoration(theme, labelText: label);
}
