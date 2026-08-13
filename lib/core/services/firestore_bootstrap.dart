import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Centralized Firestore initialization for global offline persistence.
///
/// Item #22 — every primary Firestore-backed screen (Marketplace, Firearms,
/// Permits, Processing Orders, Client Roster, Guided Hunt Logs) must keep
/// working when the network drops. With persistence enabled, Firestore's
/// `snapshots()` streams automatically serve cached data first and keep
/// emitting from cache while offline; writes are queued and flushed when the
/// link returns (the app already flushes a higher-level
/// `OfflineSyncQueue` on connectivity restore in `main.dart`).
///
/// This bootstrap:
///   * explicitly enables offline persistence with a bounded cache budget
///     (`cacheSizeBytes`) so the device never fills its storage with the
///     entire Firestore cache (defaults to ~40 MB, the Firestore-recommended
///     `CACHE_SIZE_UNLIMITED` alternative is opt-in by passing it);
///   * guards the settings assignment with a try/catch so the **web multi-tab
///     persistence exception** (`failed-precondition`: "IndexedDB: multiple
///     tabs open, persistence can only be enabled in one tab at a time") is
/// *handled gracefully* — on web, if a second tab already owns the IndexedDB
///     cache, this tab silently falls back to **in-memory persistence**
///     (`persistenceEnabled: false`) instead of crashing the app on startup.
///     Native (Android/iOS) builds are unaffected (they use a local SQLite
///     cache with no multi-tab constraint).
class FirestoreBootstrap {
  FirestoreBootstrap._();

  /// Configures global Firestore offline persistence. Call exactly once,
  /// after `Firebase.initializeApp()` and before any Firestore query.
  ///
  /// Returns `true` when disk/IndexedDB persistence was enabled, `false` when
  /// it fell back to in-memory (web multi-tab contention or a config error).
  static Future<bool> initialize({
    int cacheSizeBytes = 40 * 1024 * 1024, // 40 MB bounded cache
  }) async {
    final db = FirebaseFirestore.instance;

    // Preferred config: persistent cache so streams survive offline.
    final persistentSettings = Settings(
      persistenceEnabled: true,
      cacheSizeBytes: cacheSizeBytes,
    );

    try {
      db.settings = persistentSettings;
      return true;
    } catch (e) {
      // The classic web failure: a second browser tab already opened
      // IndexedDB persistence, so this tab cannot claim it. Firestore throws
      // a failed-precondition ("multiple tabs open, persistence can only be
      // enabled in one tab at a time"). Fall back to in-memory persistence
      // so this tab still works (offline cache is lost for this tab only).
      if (kIsWeb) {
        debugPrint(
          'FirestoreBootstrap: web persistence unavailable (multi-tab '
          'contention or config error: $e). Falling back to in-memory '
          'persistence for this tab.',
        );
      } else {
        // Native builds should not hit this, but guard anyway so a settings
        // assignment error never blocks app startup.
        debugPrint(
          'FirestoreBootstrap: persistence settings error ($e). '
          'Continuing with Firestore defaults.',
        );
      }
      try {
        db.settings = const Settings(persistenceEnabled: false);
      } catch (_) {
        // If even the fallback fails, leave Firestore on its defaults — the
        // app still runs (no offline cache, but no crash).
      }
      return false;
    }
  }
}
