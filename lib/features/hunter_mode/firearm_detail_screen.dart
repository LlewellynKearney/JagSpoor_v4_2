import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../utils/image_helper.dart';
import 'add_firearm_manual_form.dart';
import 'firearm_maintenance_screen.dart';
import 'maintenance.dart';

// ---- Shared firearm calculations (used by the safe card and the detail view) ----

int barrelLifeTotal(Map<String, String> f) =>
    int.tryParse((f['barrelLife'] ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ??
    0;

int roundCountOf(Map<String, String> f) =>
    int.tryParse(f['roundCount'] ?? '0') ?? 0;

int barrelLifeRemaining(Map<String, String> f) {
  final total = barrelLifeTotal(f);
  if (total == 0) return 0;
  final remaining = total - roundCountOf(f);
  return remaining < 0 ? 0 : remaining;
}

/// Percentage of barrel life used (0–100), 0 when no total is set.
int barrelLifeUsedPercent(Map<String, String> f) {
  final total = barrelLifeTotal(f);
  if (total == 0) return 0;
  final used = (roundCountOf(f) / total * 100).round();
  return used.clamp(0, 100);
}

/// Fraction of barrel life used 0.0–1.0 (for progress bars).
double barrelLifeUsedFraction(Map<String, String> f) {
  final total = barrelLifeTotal(f);
  if (total == 0) return 0;
  return (roundCountOf(f) / total).clamp(0.0, 1.0);
}

/// Human-readable licence validity, e.g. "2y 5m left", "8m left", or "Expired".
String licenceValidity(String? expiry) {
  if (expiry == null || expiry.isEmpty) return 'Unknown';
  final exp = DateTime.tryParse(expiry.replaceAll('/', '-'));
  if (exp == null) return 'Unknown';
  final now = DateTime.now();
  if (!exp.isAfter(now)) return 'Expired';
  int months = (exp.year - now.year) * 12 + (exp.month - now.month);
  if (exp.day < now.day) months -= 1;
  if (months < 0) months = 0;
  final years = months ~/ 12;
  final remMonths = months % 12;
  final parts = <String>[];
  if (years > 0) parts.add('${years}y');
  parts.add('${remMonths}m');
  return '${parts.join(' ')} left';
}

/// Prompt for a number of rounds to add. Returns the count, or null if cancelled.
Future<int?> showAddRoundsDialog(BuildContext context, ThemeController theme) {
  final controller = TextEditingController();
  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: theme.cardColor,
      title: Text('Add Rounds Fired', style: TextStyle(color: theme.textColor)),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        style: TextStyle(color: theme.textColor),
        decoration: InputDecoration(
          labelText: 'Rounds shot',
          labelStyle: TextStyle(color: theme.subtitleColor),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('CANCEL', style: TextStyle(color: theme.subtitleColor)),
        ),
        TextButton(
          onPressed: () {
            final n = int.tryParse(controller.text.trim());
            if (n != null && n > 0) Navigator.pop(context, n);
          },
          child: Text('ADD', style: TextStyle(color: theme.accentColor)),
        ),
      ],
    ),
  );
}

// ---- Rounds-fired log ----

class RoundsLogEntry {
  final String at; // ISO 8601 datetime
  final int qty;
  const RoundsLogEntry({required this.at, required this.qty});

  Map<String, dynamic> toJson() => {'at': at, 'qty': qty};

  factory RoundsLogEntry.fromJson(Map<String, dynamic> j) => RoundsLogEntry(
    at: (j['at'] ?? '').toString(),
    qty: j['qty'] is int ? j['qty'] as int : int.tryParse('${j['qty']}') ?? 0,
  );
}

List<RoundsLogEntry> parseRoundsLog(Map<String, String> f) {
  final raw = f['roundsLog'];
  if (raw == null || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => RoundsLogEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  } catch (_) {
    return [];
  }
}

String encodeRoundsLog(List<RoundsLogEntry> entries) =>
    jsonEncode(entries.map((e) => e.toJson()).toList());

/// Increments the round count and appends a timestamped log entry, in place.
void recordRounds(Map<String, String> f, int qty) {
  f['roundCount'] = (roundCountOf(f) + qty).toString();
  final log = parseRoundsLog(f)
    ..add(RoundsLogEntry(at: DateTime.now().toIso8601String(), qty: qty));
  f['roundsLog'] = encodeRoundsLog(log);
}

String _two(int n) => n.toString().padLeft(2, '0');
String fmtLogDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String fmtLogTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

// ---- Detail screen ----

class FirearmDetailScreen extends StatefulWidget {
  final ThemeController theme;
  final Map<String, String> firearm;

  /// Called whenever the firearm changes (rounds logged, edited, maintenance).
  final void Function(Map<String, String> updated) onUpdated;

  /// Called when the firearm is removed (e.g. the hunter sold it).
  final VoidCallback onDeleted;

  const FirearmDetailScreen({
    super.key,
    required this.theme,
    required this.firearm,
    required this.onUpdated,
    required this.onDeleted,
  });

  @override
  State<FirearmDetailScreen> createState() => _FirearmDetailScreenState();
}

class _FirearmDetailScreenState extends State<FirearmDetailScreen> {
  late Map<String, String> _firearm;

  @override
  void initState() {
    super.initState();
    _firearm = Map<String, String>.from(widget.firearm);
  }

  Future<void> _addRounds() async {
    final added = await showAddRoundsDialog(context, widget.theme);
    if (added == null) return;
    setState(() => recordRounds(_firearm, added));
    widget.onUpdated(_firearm);
  }

  void _openRoundsLog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            RoundsLogScreen(theme: widget.theme, firearm: _firearm),
      ),
    );
  }

  Future<void> _edit() async {
    final edited = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AddFirearmManualForm(theme: widget.theme, initial: _firearm),
      ),
    );
    if (edited == null || !mounted) return;
    // Preserve tracking fields the form doesn't manage.
    final merged = {
      ...edited,
      'roundCount': _firearm['roundCount'] ?? '0',
      if (_firearm['maintenanceLog'] != null)
        'maintenanceLog': _firearm['maintenanceLog']!,
    };
    setState(() => _firearm = merged);
    widget.onUpdated(_firearm);
  }

  Future<void> _delete() async {
    final theme = widget.theme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        title: Text('Remove Firearm', style: TextStyle(color: theme.textColor)),
        content: Text(
          'Remove ${_firearm['make']} (S/N ${_firearm['serial']}) from the safe? This is used when the firearm is sold.',
          style: TextStyle(color: theme.subtitleColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('CANCEL', style: TextStyle(color: theme.subtitleColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('REMOVE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      widget.onDeleted();
      Navigator.pop(context);
    }
  }

  void _openMaintenance() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FirearmMaintenanceScreen(
          theme: widget.theme,
          firearm: _firearm,
          onLogAdded: (record) {
            final log = parseLog(_firearm)..add(record);
            setState(() => _firearm['maintenanceLog'] = encodeLog(log));
            widget.onUpdated(_firearm);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final f = _firearm;
    final total = barrelLifeTotal(f);
    final remaining = barrelLifeRemaining(f);
    final usedPct = barrelLifeUsedPercent(f);
    final maintenanceDue = isMaintenanceDue(f);
    final dueCount = dueTaskCount(f);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          '${f['make']}',
          style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              Icons.build_rounded,
              color: maintenanceDue ? Colors.red : theme.accentColor,
            ),
            tooltip: 'Maintenance',
            onPressed: _openMaintenance,
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Edit',
            onPressed: _edit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete (sold)',
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          if (maintenanceDue) _maintenanceBanner(theme, dueCount),
          _FirearmPhotoCard(
            theme: theme,
            firearm: f,
            onUpdated: widget.onUpdated,
          ),
          Card(
            color: theme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'BARREL LIFE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.subtitleColor,
                          letterSpacing: 1.5,
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _openRoundsLog,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.receipt_long_rounded,
                                size: 18,
                                color: theme.accentColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'ROUNDS LOG',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: theme.accentColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (total > 0) ...[
                    Text(
                      '$remaining rounds left',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: theme.textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: barrelLifeUsedFraction(f),
                        minHeight: 10,
                        backgroundColor: theme.subtitleColor.withValues(
                          alpha: 0.2,
                        ),
                        color: usedPct >= 85 ? Colors.red : theme.accentColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$usedPct% used • ${roundCountOf(f)} of $total rounds fired',
                      style: TextStyle(
                        color: theme.subtitleColor,
                        fontSize: 13,
                      ),
                    ),
                  ] else
                    Text(
                      'Barrel life not set. Add it via Edit to track wear.',
                      style: TextStyle(
                        color: theme.subtitleColor,
                        fontSize: 13,
                      ),
                    ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentColor,
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: theme.isDarkMode ? Colors.black : Colors.white,
                    ),
                    label: Text(
                      'LOG ROUNDS FIRED',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.isDarkMode ? Colors.black : Colors.white,
                      ),
                    ),
                    onPressed: _addRounds,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _group(theme, 'LICENCE', [
            _row(theme, 'Validity', licenceValidity(f['expiry'])),
            _row(theme, 'Licence Type', f['licenceType']),
            _row(theme, 'Licence Number', f['licenceNumber']),
            _row(theme, 'Licence Section', f['licenceSection']),
            _row(theme, 'Issue Date', f['issueDate']),
            _row(theme, 'Expiry Date', f['expiry']),
          ]),
          _group(theme, 'HOLDER', [
            _row(theme, 'Name', f['holderName']),
            _row(theme, 'ID Number', f['idNumber']),
          ]),
          _group(theme, 'FIREARM', [
            _row(theme, 'Make', f['make']),
            _row(theme, 'Model', f['model']),
            _row(theme, 'Caliber', f['caliber']),
            _row(theme, 'Serial Number', f['serial']),
            _row(theme, 'Firearm Type', f['firearmType']),
            _row(theme, 'Manufacturer', f['manufacturer']),
          ]),
          _group(theme, 'SPECIFICATIONS', [
            _row(theme, 'Barrel Length', f['barrelLength']),
            _row(theme, 'Barrel Life', f['barrelLife']),
            _row(theme, 'Twist Rate', f['twistRate']),
            _row(theme, 'Action Type', f['actionType']),
          ]),
        ],
      ),
    );
  }

  Widget _maintenanceBanner(ThemeController theme, int dueCount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _openMaintenance,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.build_rounded, color: Colors.red),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$dueCount maintenance task(s) due — tap to review',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.red,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _group(ThemeController theme, String title, List<Widget> rows) {
    final visible = rows.whereType<_DetailRow>().toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.subtitleColor,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Card(
            color: theme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(children: visible),
            ),
          ),
        ],
      ),
    );
  }

  // Returns a row, or an empty placeholder filtered out by _group when blank.
  Widget _row(ThemeController theme, String label, String? value) {
    if (value == null || value.trim().isEmpty || value == 'N/A') {
      return const SizedBox.shrink();
    }
    return _DetailRow(theme: theme, label: label, value: value);
  }
}

class RoundsLogScreen extends StatelessWidget {
  final ThemeController theme;
  final Map<String, String> firearm;
  const RoundsLogScreen({
    super.key,
    required this.theme,
    required this.firearm,
  });

  @override
  Widget build(BuildContext context) {
    final entries = parseRoundsLog(firearm).reversed.toList();
    final loggedTotal = entries.fold<int>(0, (s, e) => s + e.qty);
    final grandTotal = roundCountOf(firearm);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'ROUNDS LOG',
          style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
      ),
      body: Column(
        children: [
          Card(
            color: theme.cardColor,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL ROUNDS FIRED',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.subtitleColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$grandTotal',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: theme.textColor,
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    Icons.receipt_long_rounded,
                    color: theme.accentColor,
                    size: 32,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history_toggle_off_rounded,
                          size: 56,
                          color: theme.subtitleColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No rounds logged yet',
                          style: TextStyle(
                            color: theme.textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            grandTotal > 0
                                ? 'This firearm has a starting count of $grandTotal rounds. New entries logged from now on will appear here.'
                                : 'Use "Log Rounds Fired" to record each range session.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.subtitleColor,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: entries.length + 1,
                    separatorBuilder: (_, _) => Divider(
                      color: theme.subtitleColor.withValues(alpha: 0.15),
                      height: 1,
                    ),
                    itemBuilder: (context, i) {
                      if (i == entries.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total logged',
                                style: TextStyle(
                                  color: theme.subtitleColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '$loggedTotal rounds',
                                style: TextStyle(
                                  color: theme.textColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      final e = entries[i];
                      final dt = DateTime.tryParse(e.at);
                      final date = dt != null ? fmtLogDate(dt) : e.at;
                      final time = dt != null ? fmtLogTime(dt) : '';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.adjust_rounded,
                          color: theme.accentColor,
                        ),
                        title: Text(
                          '+${e.qty} rounds',
                          style: TextStyle(
                            color: theme.textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          '$date  •  $time',
                          style: TextStyle(
                            color: theme.subtitleColor,
                            fontSize: 13,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final ThemeController theme;
  final String label;
  final String value;
  const _DetailRow({
    required this.theme,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(color: theme.subtitleColor, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirearmPhotoCard extends StatefulWidget {
  final ThemeController theme;
  final Map<String, String> firearm;
  final void Function(Map<String, String> updated) onUpdated;

  const _FirearmPhotoCard({
    required this.theme,
    required this.firearm,
    required this.onUpdated,
  });

  @override
  State<_FirearmPhotoCard> createState() => _FirearmPhotoCardState();
}

class _FirearmPhotoCardState extends State<_FirearmPhotoCard> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (image == null) return;

      // Get application documents directory
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String firearmDir = '${appDir.path}/firearm_photos';
      await Directory(firearmDir).create(recursive: true);

      // Generate unique filename
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'firearm_${timestamp}_${image.name}';
      final String savedPath = '$firearmDir/$fileName';

      // Save file locally
      await image.saveTo(savedPath);

      // Update firearm data
      final updated = Map<String, String>.from(widget.firearm);
      updated['photoPath'] = savedPath;
      widget.onUpdated(updated);

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.theme.cardColor,
        title: Text(
          'Add Photo',
          style: TextStyle(color: widget.theme.textColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt, color: widget.theme.accentColor),
              title: Text(
                'Camera',
                style: TextStyle(color: widget.theme.textColor),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library,
                color: widget.theme.accentColor,
              ),
              title: Text(
                'Gallery',
                style: TextStyle(color: widget.theme.textColor),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final make = widget.firearm['make'] ?? 'Unknown';
    final model = widget.firearm['model'] ?? '';
    final displayName = model.isNotEmpty ? '$make $model' : make;
    final photoPath = widget.firearm['photoPath'];

    return Card(
      color: widget.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FIREARM PHOTO',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: widget.theme.subtitleColor,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _showImageSourceDialog,
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: widget.theme.backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget.theme.accentColor.withValues(alpha: 0.2),
                  ),
                ),
                child: photoPath != null && photoPath.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AdaptiveImage(
                          imagePath: photoPath,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.photo_camera_rounded,
                            size: 48,
                            color: widget.theme.subtitleColor.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: widget.theme.textColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'Tap to add photo',
                              style: TextStyle(
                                fontSize: 13,
                                color: widget.theme.subtitleColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
