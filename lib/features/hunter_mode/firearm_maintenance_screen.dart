import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'maintenance.dart';

class FirearmMaintenanceScreen extends StatefulWidget {
  final ThemeController theme;
  final Map<String, String> firearm;

  /// Called when the hunter completes maintenance, so the safe can persist the log.
  final void Function(MaintenanceRecord record) onLogAdded;

  const FirearmMaintenanceScreen({
    super.key,
    required this.theme,
    required this.firearm,
    required this.onLogAdded,
  });

  @override
  State<FirearmMaintenanceScreen> createState() => _FirearmMaintenanceScreenState();
}

class _FirearmMaintenanceScreenState extends State<FirearmMaintenanceScreen> {
  late Map<String, String> _firearm;
  final Set<String> _checked = {};

  @override
  void initState() {
    super.initState();
    _firearm = Map<String, String>.from(widget.firearm);
  }

  int get _rounds => int.tryParse(_firearm['roundCount'] ?? '0') ?? 0;

  void _completeMaintenance() {
    if (_checked.isEmpty) return;
    final record = MaintenanceRecord(
      date: DateTime.now().toIso8601String().split('T').first,
      rounds: _rounds,
      tasks: _checked.toList(),
    );
    widget.onLogAdded(record);

    // Reflect the new log locally so statuses reset immediately.
    final log = parseLog(_firearm)..add(record);
    setState(() {
      _firearm['maintenanceLog'] = encodeLog(log);
      _checked.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Logged ${record.tasks.length} maintenance task(s)'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final schedule = scheduleFor(_firearm);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text('MAINTENANCE', style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold)),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Maintenance logs',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MaintenanceLogScreen(theme: theme, firearm: _firearm),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_firearm['make']} ${_firearm['model'] ?? ''}  •  $_rounds rounds fired',
                style: TextStyle(color: theme.subtitleColor, fontSize: 13),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: schedule.length,
              itemBuilder: (context, i) => _taskTile(theme, schedule[i]),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _checked.isEmpty ? theme.subtitleColor : theme.accentColor,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(Icons.check_circle_outline, color: theme.isDarkMode ? Colors.black : Colors.white),
                label: Text('CONFIRM MAINTENANCE DONE',
                    style: TextStyle(fontWeight: FontWeight.bold, color: theme.isDarkMode ? Colors.black : Colors.white)),
                onPressed: _checked.isEmpty ? null : _completeMaintenance,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskTile(ThemeController theme, MaintenanceTask task) {
    final due = isTaskDue(_firearm, task);
    final until = roundsUntilDue(_firearm, task);
    final status = due ? 'DUE NOW (overdue ${-until} rds)' : 'OK • due in $until rds';

    return Card(
      color: theme.cardColor,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: due ? Colors.red.withValues(alpha: 0.6) : Colors.transparent),
      ),
      child: CheckboxListTile(
        value: _checked.contains(task.name),
        activeColor: theme.accentColor,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (v) => setState(() {
          if (v == true) {
            _checked.add(task.name);
          } else {
            _checked.remove(task.name);
          }
        }),
        title: Text(task.name, style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(task.description, style: TextStyle(color: theme.subtitleColor, fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(due ? Icons.warning_amber_rounded : Icons.check_circle,
                    size: 14, color: due ? Colors.red : Colors.green),
                const SizedBox(width: 4),
                Text(status,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: due ? Colors.red : theme.subtitleColor)),
              ],
            ),
            Text('Interval: every ${task.intervalRounds} rds',
                style: TextStyle(fontSize: 11, color: theme.subtitleColor)),
          ],
        ),
      ),
    );
  }
}

class MaintenanceLogScreen extends StatelessWidget {
  final ThemeController theme;
  final Map<String, String> firearm;
  const MaintenanceLogScreen({super.key, required this.theme, required this.firearm});

  @override
  Widget build(BuildContext context) {
    final records = parseLog(firearm).reversed.toList();
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text('MAINTENANCE LOG', style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold)),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
      ),
      body: records.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off_rounded, size: 56, color: theme.subtitleColor),
                  const SizedBox(height: 12),
                  Text('No maintenance logged yet', style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: records.length,
              itemBuilder: (context, i) {
                final r = records[i];
                return Card(
                  color: theme.cardColor,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(r.date, style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold)),
                            Text('@ ${r.rounds} rds', style: TextStyle(color: theme.subtitleColor, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...r.tasks.map((t) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.check_rounded, size: 16, color: Colors.green),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(t, style: TextStyle(color: theme.subtitleColor, fontSize: 13))),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
