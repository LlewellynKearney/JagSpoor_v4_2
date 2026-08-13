import 'dart:async';

import 'package:flutter/foundation.dart';

/// Stream helpers for offline-resilient Firestore reads (Item #22).
///
/// With global offline persistence enabled (see `FirestoreBootstrap`),
/// Firestore `snapshots()` streams already serve cached data first and keep
/// emitting from cache when the network drops. The remaining failure mode is
/// a *hard* stream error that propagates to the `StreamBuilder` and crashes
/// the screen instead of falling back — e.g. a missing composite index, a
/// permissions change, or (on web with no persistence) an unrecoverable
/// network error with nothing in cache.
///
/// [offlineResilient] wraps a stream so any hard error is logged and replaced
/// with [fallback] (defaults to an empty emission). Firestore's own cache
/// already keeps the stream alive across brief network drops, so this is a
/// safety net for the cases where the stream errors outright (so the UI shows
/// a defined empty/error state instead of hanging or crashing).
class OfflineStreamGuard {
  OfflineStreamGuard._();

  /// Returns a stream that never errors: any error is logged and replaced
  /// with a single [fallback] emission, then the stream completes. Normal
  /// emissions pass through untouched.
  static Stream<T> offlineResilient<T>(
    Stream<T> source, {
    required T fallback,
    String? debugLabel,
  }) {
    final controller = StreamController<T>();
    source.listen(
      controller.add,
      onError: (error, stackTrace) {
        debugPrint(
          'OfflineStreamGuard${debugLabel == null ? '' : ' ($debugLabel)'}: '
          'stream error, serving fallback. $error',
        );
        controller.add(fallback);
        controller.close();
      },
      onDone: controller.close,
      cancelOnError: true,
    );
    return controller.stream;
  }
}
