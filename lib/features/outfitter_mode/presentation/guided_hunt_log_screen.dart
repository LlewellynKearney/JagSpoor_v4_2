import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/models/client_profile.dart';
import '../data/models/guided_hunt_log.dart';
import '../data/services/client_roster_manager.dart';
import '../data/services/guided_hunt_log_manager.dart';
import '../../hunter_mode/screens/venison_permit_form_screen.dart';

/// Outfitter Guided Hunt Log — harvest logging workflow.
///
/// Reactive, searchable list of [GuidedHuntLog] entries for the signed-in
/// outfitter. Each harvest is explicitly assigned to a client from the active
/// roster and records species, carcass weight, trophy details, and shot
/// location. From a log the outfitter can generate a venison transport permit
/// (pre-filled with the client + harvested species) and push the carcass to
/// the slaughterhouse / coldroom manifest.
class GuidedHuntLogScreen extends StatefulWidget {
  final ThemeController theme;

  const GuidedHuntLogScreen({super.key, required this.theme});

  @override
  State<GuidedHuntLogScreen> createState() => _GuidedHuntLogScreenState();
}

class _GuidedHuntLogScreenState extends State<GuidedHuntLogScreen> {
  final _manager = GuidedHuntLogManager.instance;
  final _rosterManager = ClientRosterManager.instance;
  final _searchController = TextEditingController();
  String _query = '';

  /// Cached hunt-logs stream. Rebuilt on retry so the [StreamBuilder]
  /// re-subscribes (a fresh `.snapshots()` instance) — this is what stops the
  /// indefinite loading loop on a hard stream error: tapping RETRY creates a
  /// new stream and re-evaluates the subscription.
  Stream<List<GuidedHuntLog>>? _logsStream;

  @override
  void initState() {
    super.initState();
    _logsStream = _manager.getMyHuntLogsStream();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _logsStream = _manager.getMyHuntLogsStream();
    });
  }

  List<GuidedHuntLog> _filter(List<GuidedHuntLog> logs) {
    if (_query.isEmpty) return logs;
    final q = _query.toLowerCase();
    return logs
        .where((l) =>
            l.clientName.toLowerCase().contains(q) ||
            l.species.toLowerCase().contains(q) ||
            l.shotLocationDescription.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.cardColor,
        foregroundColor: theme.textColor,
        title: const Text('Guided Hunt Logs'),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: theme.accentColor,
        foregroundColor: theme.backgroundColor,
        onPressed: _openLogEditor,
        child: const Icon(Icons.edit_note_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: theme.textColor),
              decoration: InputDecoration(
                hintText: 'Search by client, species, location…',
                hintStyle: TextStyle(color: theme.subtitleColor),
                prefixIcon: Icon(Icons.search, color: theme.subtitleColor),
                filled: true,
                fillColor: theme.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<GuidedHuntLog>>(
              stream: _logsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorState(
                    theme: theme,
                    message:
                        'Could not load your guided hunt logs. This is '
                        'usually a permission or connection issue.',
                    detail: snapshot.error.toString(),
                    onRetry: _retry,
                  );
                }
                final all = snapshot.data ?? const <GuidedHuntLog>[];
                final logs = _filter(all);
                if (logs.isEmpty) {
                  return _EmptyState(
                    theme: theme,
                    icon: Icons.history_edu_rounded,
                    title: all.isEmpty
                        ? 'No guided hunt logs yet'
                        : 'No logs match your search',
                    message: all.isEmpty
                        ? 'Tap ✎ to log your first harvested hunt.'
                        : 'Try a different search term.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final log = logs[i];
                    return _HuntLogCard(
                      log: log,
                      theme: theme,
                      onGeneratePermit: () => _generatePermit(log),
                      onPushCarcass: () => _pushCarcass(log),
                      onDelete: () => _confirmDelete(log),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLogEditor() async {
    final clients = await _rosterManager.getMyClientsStream().first;
    if (!mounted) return;
    if (clients.isEmpty) {
      _snack('Add a client to your roster first.', isError: true);
      return;
    }
    _showEditorSheet(null, clients);
  }

  void _showEditorSheet(GuidedHuntLog? existing, List<ClientProfile> clients) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _HuntLogEditorSheet(
        theme: widget.theme,
        existing: existing,
        clients: clients,
        onSave: (log) async {
          final messenger = ScaffoldMessenger.of(context);
          final navigator = Navigator.of(context);
          try {
            if (existing == null) {
              await _manager.addHuntLog(log);
              navigator.pop();
              _snack('Hunt log recorded');
            } else {
              await _manager.updateHuntLog(log);
              navigator.pop();
              _snack('Hunt log updated');
            }
          } catch (e) {
            // Permission-denied (rules not deployed) or network failure:
            // surface a user-facing snackbar and KEEP the editor sheet open so
            // the user can retry instead of losing their input to a raw
            // unhandled crash.
            messenger.showSnackBar(
              SnackBar(
                content: Text('⚠️ Failed to save hunt log: $e'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _generatePermit(GuidedHuntLog log) async {
    final client = await _rosterManager.getClientById(log.clientId);
    if (!mounted) return;
    if (client == null) {
      _snack('The client on this log is no longer in your roster.',
          isError: true);
      return;
    }
    final prefill = await _manager.buildPermitPrefill(log: log, client: client);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VenisonPermitFormScreen(
          theme: widget.theme,
          isOutfitterMode: true,
          prefillData: prefill,
          clientId: client.id,
          guidedHuntLogId: log.id,
        ),
      ),
    );
  }

  Future<void> _pushCarcass(GuidedHuntLog log) async {
    if (log.carcassWeightKg <= 0) {
      _snack('This log has no carcass weight to manifest.', isError: true);
      return;
    }
    if (log.carcassRecordId != null) {
      _snack('Carcass already pushed to the slaughterhouse manifest.',
          isError: true);
      return;
    }
    final id = await _manager.pushToSlaughterhouseManifest(log);
    if (!mounted) return;
    if (id.isEmpty) {
      _snack('Could not push carcass to manifest.', isError: true);
    } else {
      _snack('Carcass pushed to Slaghuis Matrix coldroom.');
    }
  }

  void _confirmDelete(GuidedHuntLog log) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.theme.cardColor,
        title: Text('Delete hunt log?',
            style: TextStyle(color: widget.theme.textColor)),
        content: Text(
          'Delete the ${log.species} harvest log for ${log.clientName}? '
          'Linked permits and carcass records are kept.',
          style: TextStyle(color: widget.theme.subtitleColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(context).pop();
              try {
                await _manager.deleteHuntLog(log.id);
                _snack('Hunt log deleted');
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('⚠️ Failed to delete hunt log: $e'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            },
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? Colors.red : widget.theme.accentColor,
      ),
    );
  }
}

class _HuntLogCard extends StatelessWidget {
  final GuidedHuntLog log;
  final ThemeController theme;
  final VoidCallback onGeneratePermit;
  final VoidCallback onPushCarcass;
  final VoidCallback onDelete;

  const _HuntLogCard({
    required this.log,
    required this.theme,
    required this.onGeneratePermit,
    required this.onPushCarcass,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${log.huntDate.year}-${log.huntDate.month.toString().padLeft(2, '0')}-${log.huntDate.day.toString().padLeft(2, '0')}';
    return Card(
      color: theme.cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.textColor.withAlpha(20), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pets_rounded, color: theme.accentColor, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    log.species,
                    style: TextStyle(
                      color: theme.textColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(dateStr,
                    style: TextStyle(
                        color: theme.subtitleColor, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            _row(Icons.person_outline_rounded, log.clientName),
            if (log.carcassWeightKg > 0)
              _row(Icons.scale_outlined,
                  '${log.carcassWeightKg.toStringAsFixed(1)} kg carcass'),
            if (log.trophyMeasurementInches != null)
              _row(Icons.emoji_events_outlined,
                  'Trophy ${log.trophyMeasurementLabel ?? 'measurement'}: '
                  '${log.trophyMeasurementInches!.toStringAsFixed(1)}"'),
            if (log.shotLocationDescription.isNotEmpty ||
                log.shotLat != null)
              _row(Icons.place_outlined, log.shotLocationDescription.isNotEmpty
                  ? log.shotLocationDescription
                  : '${log.shotLat!.toStringAsFixed(4)}, ${log.shotLng?.toStringAsFixed(4) ?? ''}'),
            if (log.shotPlacement.isNotEmpty)
              _row(Icons.gps_fixed, log.shotPlacement),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (log.permitId != null)
                  _statusChip(Icons.description_outlined, 'Permit issued',
                      Colors.green)
                else
                  _actionChip('Generate Permit',
                      Icons.assignment_turned_in_outlined, onGeneratePermit),
                if (log.carcassRecordId != null)
                  _statusChip(Icons.ac_unit_outlined, 'In coldroom',
                      Colors.blue)
                else if (log.carcassWeightKg > 0)
                  _actionChip('Push to Manifest',
                      Icons.kitchen_outlined, onPushCarcass),
                _actionChip('Delete', Icons.delete_outline_rounded, onDelete,
                    danger: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: theme.subtitleColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style:
                    TextStyle(color: theme.subtitleColor, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _actionChip(String label, IconData icon, VoidCallback onTap,
      {bool danger = false}) {
    final color = danger ? Colors.red : theme.accentColor;
    return ActionChip(
      label: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      avatar: Icon(icon, size: 16, color: color),
      backgroundColor: color.withAlpha(20),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onPressed: onTap,
    );
  }

  Widget _statusChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _HuntLogEditorSheet extends StatefulWidget {
  final ThemeController theme;
  final GuidedHuntLog? existing;
  final List<ClientProfile> clients;
  final Future<void> Function(GuidedHuntLog log) onSave;

  const _HuntLogEditorSheet({
    required this.theme,
    required this.clients,
    required this.onSave,
    this.existing,
  });

  @override
  State<_HuntLogEditorSheet> createState() => _HuntLogEditorSheetState();
}

class _HuntLogEditorSheetState extends State<_HuntLogEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _speciesController = TextEditingController();
  final _weightController = TextEditingController();
  final _trophyController = TextEditingController();
  final _trophyLabelController = TextEditingController();
  final _shotLocController = TextEditingController();
  final _shotLatController = TextEditingController();
  final _shotLngController = TextEditingController();
  final _shotPlacementController = TextEditingController();
  final _calibreController = TextEditingController();
  final _distanceController = TextEditingController();
  final _notesController = TextEditingController();

  String _sex = 'Unknown';
  ClientProfile? _selectedClient;
  DateTime _huntDate = DateTime.now();

  static const _sexOptions = ['Male', 'Female', 'Unknown'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _speciesController.text = e.species;
      _weightController.text =
          e.carcassWeightKg > 0 ? e.carcassWeightKg.toStringAsFixed(1) : '';
      _trophyController.text = e.trophyMeasurementInches != null
          ? e.trophyMeasurementInches!.toStringAsFixed(1)
          : '';
      _trophyLabelController.text = e.trophyMeasurementLabel ?? '';
      _shotLocController.text = e.shotLocationDescription;
      _shotLatController.text = e.shotLat?.toStringAsFixed(6) ?? '';
      _shotLngController.text = e.shotLng?.toStringAsFixed(6) ?? '';
      _shotPlacementController.text = e.shotPlacement;
      _calibreController.text =
          e.rifleCalibreMm?.toStringAsFixed(1) ?? '';
      _distanceController.text =
          e.distanceMeters?.toStringAsFixed(0) ?? '';
      _notesController.text = e.notes ?? '';
      _sex = e.sex;
      _huntDate = e.huntDate;
      _selectedClient = widget.clients
          .where((c) => c.id == e.clientId)
          .firstOrNull;
    }
  }

  @override
  void dispose() {
    _speciesController.dispose();
    _weightController.dispose();
    _trophyController.dispose();
    _trophyLabelController.dispose();
    _shotLocController.dispose();
    _shotLatController.dispose();
    _shotLngController.dispose();
    _shotPlacementController.dispose();
    _calibreController.dispose();
    _distanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final padBottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: padBottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.subtitleColor.withAlpha(60),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                widget.existing == null ? 'Log Harvested Hunt' : 'Edit Hunt Log',
                style: TextStyle(
                    color: theme.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),

              // Client picker — required.
              DropdownButtonFormField<ClientProfile>(
                value: _selectedClient,
                decoration: _deco('Client Hunter *'),
                dropdownColor: theme.cardColor,
                items: widget.clients
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.fullName,
                              style: TextStyle(color: theme.textColor)),
                        ))
                    .toList(),
                validator: (v) => v == null ? 'Select a client' : null,
                onChanged: (v) => setState(() => _selectedClient = v),
              ),
              const SizedBox(height: 12),

              _field(_speciesController, 'Species *',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Species is required'
                      : null),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _sexOptions.contains(_sex) ? _sex : 'Unknown',
                decoration: _deco('Sex'),
                dropdownColor: theme.cardColor,
                items: _sexOptions
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s,
                              style: TextStyle(color: theme.textColor)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _sex = v ?? 'Unknown'),
              ),
              const SizedBox(height: 12),

              _field(_weightController, 'Carcass Weight (kg)',
                  keyboard:
                      const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _field(_trophyController, 'Trophy (in)',
                        keyboard: const TextInputType.numberWithOptions(
                            decimal: true)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                        _trophyLabelController, 'Measurement',
                        hint: 'e.g. horn length'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _field(_shotLocController, 'Shot Location Description',
                  hint: 'e.g. Kudu pan, north fence'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _field(_shotLatController, 'Lat',
                        keyboard: const TextInputType.numberWithOptions(
                            decimal: true, signed: true)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(_shotLngController, 'Lng',
                        keyboard: const TextInputType.numberWithOptions(
                            decimal: true, signed: true)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _field(_shotPlacementController, 'Shot Placement',
                  hint: 'e.g. Broadside - heart/lung'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _field(_calibreController, 'Calibre (mm)',
                        keyboard: const TextInputType.numberWithOptions(
                            decimal: true)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(_distanceController, 'Distance (m)',
                        keyboard: TextInputType.number),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Hunt date.
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _huntDate,
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 365 * 3)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _huntDate = picked);
                },
                child: InputDecorator(
                  decoration: _deco('Hunt Date'),
                  child: Text(
                    '${_huntDate.year}-${_huntDate.month.toString().padLeft(2, '0')}-${_huntDate.day.toString().padLeft(2, '0')}',
                    style: TextStyle(color: theme.textColor),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _field(_notesController, 'Notes', maxLines: 3),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.accentColor,
                  foregroundColor: theme.backgroundColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.save_rounded),
                label: Text(
                    widget.existing == null ? 'RECORD HUNT LOG' : 'SAVE'),
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;
                  final c = _selectedClient!;
                  final existing = widget.existing;
                  final log = GuidedHuntLog(
                    id: existing?.id ?? '',
                    outfitterId: existing?.outfitterId ?? '',
                    clientId: c.id,
                    clientName: c.fullName,
                    clientIdPassport: c.idPassportNumber,
                    bookingId: existing?.bookingId ?? c.assignedBookingId,
                    species: _speciesController.text.trim(),
                    sex: _sex,
                    carcassWeightKg:
                        double.tryParse(_weightController.text) ?? 0.0,
                    shotLocationDescription: _shotLocController.text.trim(),
                    shotLat: double.tryParse(_shotLatController.text),
                    shotLng: double.tryParse(_shotLngController.text),
                    trophyMeasurementInches:
                        double.tryParse(_trophyController.text),
                    trophyMeasurementLabel:
                        _trophyLabelController.text.trim().isEmpty
                            ? null
                            : _trophyLabelController.text.trim(),
                    shotPlacement: _shotPlacementController.text.trim(),
                    rifleCalibreMm: double.tryParse(_calibreController.text),
                    distanceMeters: double.tryParse(_distanceController.text),
                    permitId: existing?.permitId,
                    carcassRecordId: existing?.carcassRecordId,
                    notes: _notesController.text.trim().isEmpty
                        ? null
                        : _notesController.text.trim(),
                    huntDate: _huntDate,
                    createdAt: existing?.createdAt,
                  );
                  await widget.onSave(log);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _deco(String label) {
    final theme = widget.theme;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: theme.subtitleColor),
      filled: true,
      fillColor: theme.backgroundColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.textColor.withAlpha(20)),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    TextInputType? keyboard,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    final theme = widget.theme;
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      maxLines: maxLines,
      style: TextStyle(color: theme.textColor),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: theme.subtitleColor),
        hintText: hint,
        hintStyle: TextStyle(color: theme.subtitleColor.withAlpha(80)),
        filled: true,
        fillColor: theme.backgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.textColor.withAlpha(20)),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ThemeController theme;
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.theme,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.subtitleColor.withAlpha(120)),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: theme.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.subtitleColor, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Error state for the guided hunt logs stream. Rendered (instead of the
/// indefinite spinner) when `getMyHuntLogsStream` errors — e.g. a
/// permission-denied because the `guided_hunt_logs` Firestore rules have not
/// been deployed, or a missing composite index. The RETRY button rebuilds
/// the stream so the [StreamBuilder] re-subscribes.
class _ErrorState extends StatelessWidget {
  final ThemeController theme;
  final String message;
  final String detail;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.theme,
    required this.message,
    required this.detail,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 64, color: theme.subtitleColor.withAlpha(120)),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: theme.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.subtitleColor, fontSize: 12),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.accentColor,
                foregroundColor: theme.backgroundColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('RETRY'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
