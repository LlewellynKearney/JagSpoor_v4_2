import 'package:flutter/foundation.dart';

import '../../../features/shared/data/services/local_database_service.dart';
import '../models/target_session_log.dart';
import '../services/shot_group_analyzer_service.dart';

export '../models/target_session_log.dart';

/// Persists analyzed Shot Group Target Analyzer sessions to the local
/// SQLite `target_session_logs` table (offline-first). A hunter can save a
/// completed group diagnostic — including the linked firearm, the shot
/// geometry, and the suggested turret correction — and review it later
/// without a network connection.
///
/// The table is created / migrated by [LocalDatabaseService]; this manager
/// only owns the read/write surface for that table.
class TargetSessionLogManager {
  TargetSessionLogManager._();
  static final TargetSessionLogManager instance = TargetSessionLogManager._();

  static const String _table = 'target_session_logs';

  /// Build the [TargetSessionLog] row for a completed analysis. Pure /
  /// testable: the id + timestamp are injected so the row is deterministic
  /// in unit tests.
  static TargetSessionLog buildLog({
    required String id,
    required String createdAt,
    required ShotGroupAnalysis analysis,
    required double distance,
    required DistanceUnit distanceUnit,
    required AngularUnit angularUnit,
    required double clickValue,
    required String firearmId,
    required String firearmLabel,
    required int suggestedUpClicks,
    required int suggestedRightClicks,
  }) {
    return TargetSessionLog.fromAnalysis(
      id: id,
      createdAt: createdAt,
      analysis: analysis,
      distance: distance,
      distanceUnit: distanceUnit,
      angularUnit: angularUnit,
      clickValue: clickValue,
      firearmId: firearmId,
      firearmLabel: firearmLabel,
      suggestedUpClicks: suggestedUpClicks,
      suggestedRightClicks: suggestedRightClicks,
    );
  }

  /// Save a completed [ShotGroupAnalysis] to the local log.
  ///
  /// [firearmId] / [firearmLabel] come from the Digital Firearm Safe
  /// dropdown selection (empty when no firearm was linked).
  /// Returns the generated session id on success, null on failure.
  Future<String?> saveSession({
    required ShotGroupAnalysis analysis,
    required double distance,
    required DistanceUnit distanceUnit,
    required AngularUnit angularUnit,
    required double clickValue,
    required String firearmId,
    required String firearmLabel,
    required int suggestedUpClicks,
    required int suggestedRightClicks,
  }) async {
    try {
      final db = await LocalDatabaseService.instance.database;
      final id = _newId();
      final log = buildLog(
        id: id,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        analysis: analysis,
        distance: distance,
        distanceUnit: distanceUnit,
        angularUnit: angularUnit,
        clickValue: clickValue,
        firearmId: firearmId,
        firearmLabel: firearmLabel,
        suggestedUpClicks: suggestedUpClicks,
        suggestedRightClicks: suggestedRightClicks,
      );
      await db.insert(_table, log.toMap());
      return id;
    } catch (e) {
      debugPrint('TargetSessionLogManager: failed to save session: $e');
      return null;
    }
  }

  /// Load all saved sessions, newest first.
  Future<List<TargetSessionLog>> loadSessions() async {
    try {
      final db = await LocalDatabaseService.instance.database;
      final rows = await db.query(
        _table,
        orderBy: 'createdAt DESC',
      );
      return rows.map(TargetSessionLog.fromMap).toList();
    } catch (e) {
      debugPrint('TargetSessionLogManager: failed to load sessions: $e');
      return const [];
    }
  }

  /// Delete a saved session by id.
  Future<bool> deleteSession(String id) async {
    try {
      final db = await LocalDatabaseService.instance.database;
      await db.delete(_table, where: 'id = ?', whereArgs: [id]);
      return true;
    } catch (e) {
      debugPrint('TargetSessionLogManager: failed to delete session: $e');
      return false;
    }
  }

  /// Generate a collision-resistant local id (timestamp + random suffix).
  static String _newId() {
    final ts = DateTime.now().toUtc().millisecondsSinceEpoch.toRadixString(36);
    final rand = (Object().hashCode & 0xffffff).toRadixString(36).padLeft(4, '0');
    return 'tsl_$ts$rand';
  }
}
