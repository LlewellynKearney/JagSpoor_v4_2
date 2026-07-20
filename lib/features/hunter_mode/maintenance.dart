import 'dart:convert';

/// A single round-based maintenance task for a firearm.
class MaintenanceTask {
  final String name;
  final String description;

  /// Recommended interval, in rounds fired, between performing this task.
  final int intervalRounds;

  const MaintenanceTask({
    required this.name,
    required this.description,
    required this.intervalRounds,
  });
}

/// A logged maintenance event.
class MaintenanceRecord {
  final String date; // ISO yyyy-MM-dd
  final int rounds; // round count at time of maintenance
  final List<String> tasks;

  const MaintenanceRecord({
    required this.date,
    required this.rounds,
    required this.tasks,
  });

  Map<String, dynamic> toJson() => {'date': date, 'rounds': rounds, 'tasks': tasks};

  factory MaintenanceRecord.fromJson(Map<String, dynamic> j) => MaintenanceRecord(
        date: (j['date'] ?? '').toString(),
        rounds: j['rounds'] is int ? j['rounds'] as int : int.tryParse('${j['rounds']}') ?? 0,
        tasks: (j['tasks'] as List? ?? []).map((e) => e.toString()).toList(),
      );
}

// Schedules are derived from manufacturer and NRA/American Rifleman guidance
// (e.g. GLOCK recoil spring ~5,000 rds, gas-operated shotgun gas-system clean
// ~300 rds, bolt-rifle bore cleaning after each outing / ~200 rds).
const List<MaintenanceTask> _handgunSchedule = [
  MaintenanceTask(name: 'Field strip, clean & lubricate', description: 'Strip to field level, clean bore, slide rails and feed ramp, then re-lubricate.', intervalRounds: 400),
  MaintenanceTask(name: 'Inspect magazine springs', description: 'Check magazine springs and followers for fatigue and weak feeding.', intervalRounds: 2000),
  MaintenanceTask(name: 'Detailed strip & deep clean', description: 'Detail strip, remove carbon from internals and inspect for wear.', intervalRounds: 2500),
  MaintenanceTask(name: 'Inspect / replace recoil spring', description: 'Recoil springs are typically rated for 3,000–5,000 cycles. Inspect and replace if fatigued.', intervalRounds: 5000),
];

const List<MaintenanceTask> _rifleSchedule = [
  MaintenanceTask(name: 'Clean bore & chamber', description: 'Run patches/brush through the bore and clean the chamber after the outing.', intervalRounds: 200),
  MaintenanceTask(name: 'Field strip, clean & lubricate', description: 'Clean the action and bolt, then re-lubricate.', intervalRounds: 500),
  MaintenanceTask(name: 'Check & re-torque action screws', description: 'Verify action/stock screw torque to maintain zero and accuracy.', intervalRounds: 500),
  MaintenanceTask(name: 'Detailed inspection (bolt, crown, gas system)', description: 'Inspect bolt lugs, muzzle crown and (semi-auto) gas system for wear/carbon.', intervalRounds: 2000),
];

const List<MaintenanceTask> _shotgunSchedule = [
  MaintenanceTask(name: 'Clean bore & chamber', description: 'Clean the bore and chamber after use.', intervalRounds: 200),
  MaintenanceTask(name: 'Clean gas system / action', description: 'Gas-operated shotguns accumulate carbon in the ports/piston — clean regularly.', intervalRounds: 300),
  MaintenanceTask(name: 'Field strip, clean & lubricate', description: 'Strip, clean and re-lubricate moving parts.', intervalRounds: 500),
  MaintenanceTask(name: 'Detailed strip & deep clean', description: 'Detail strip and inspect O-rings/springs for wear.', intervalRounds: 2000),
];

const List<MaintenanceTask> _generalSchedule = [
  MaintenanceTask(name: 'Clean bore & chamber', description: 'Clean the bore and chamber.', intervalRounds: 300),
  MaintenanceTask(name: 'Field strip, clean & lubricate', description: 'Strip to field level, clean and re-lubricate.', intervalRounds: 400),
  MaintenanceTask(name: 'Detailed strip & deep clean', description: 'Detail strip, deep clean and inspect for wear.', intervalRounds: 2000),
];

/// Picks a schedule based on the firearm's type/category text. Every firearm
/// gets a schedule — handgun / rifle / shotgun by type, otherwise a general
/// schedule, so maintenance applies to all firearm types.
List<MaintenanceTask> scheduleFor(Map<String, String> firearm) {
  final t = '${firearm['firearmType'] ?? ''} ${firearm['make'] ?? ''}'.toUpperCase();
  if (t.contains('HANDGUN') ||
      t.contains('PISTOL') ||
      t.contains('REVOLVER')) {
    return _handgunSchedule;
  }
  if (t.contains('SHOTGUN')) return _shotgunSchedule;
  if (t.contains('RIFLE') ||
      t.contains('CARBINE') ||
      t.contains('SELF-LOADING') ||
      t.contains('SELF LOADING') ||
      t.contains('SEMI-AUTO') ||
      t.contains('BOLT') ||
      t.contains('MANUALLY OPERATED') ||
      t.contains('MUSKET')) {
    return _rifleSchedule;
  }
  return _generalSchedule;
}

List<MaintenanceRecord> parseLog(Map<String, String> firearm) {
  final raw = firearm['maintenanceLog'];
  if (raw == null || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => MaintenanceRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  } catch (_) {
    return [];
  }
}

String encodeLog(List<MaintenanceRecord> records) =>
    jsonEncode(records.map((r) => r.toJson()).toList());

int _roundCount(Map<String, String> firearm) =>
    int.tryParse(firearm['roundCount'] ?? '0') ?? 0;

/// Round count at which [task] was last completed (0 if never).
int lastDoneRounds(Map<String, String> firearm, String taskName) {
  int last = 0;
  for (final r in parseLog(firearm)) {
    if (r.tasks.contains(taskName) && r.rounds > last) last = r.rounds;
  }
  return last;
}

/// Rounds fired since [task] was last performed.
int roundsSince(Map<String, String> firearm, MaintenanceTask task) =>
    _roundCount(firearm) - lastDoneRounds(firearm, task.name);

/// Rounds remaining until [task] is due (negative if overdue).
int roundsUntilDue(Map<String, String> firearm, MaintenanceTask task) =>
    task.intervalRounds - roundsSince(firearm, task);

bool isTaskDue(Map<String, String> firearm, MaintenanceTask task) =>
    roundsUntilDue(firearm, task) <= 0;

/// True if any scheduled task is currently due for this firearm.
bool isMaintenanceDue(Map<String, String> firearm) =>
    scheduleFor(firearm).any((t) => isTaskDue(firearm, t));

/// Count of currently-due tasks.
int dueTaskCount(Map<String, String> firearm) =>
    scheduleFor(firearm).where((t) => isTaskDue(firearm, t)).length;
