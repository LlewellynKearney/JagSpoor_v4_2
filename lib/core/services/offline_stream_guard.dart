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
  ///
  /// The returned stream is a **broadcast** stream. Firestore `snapshots()`
  /// is single-subscription, and the consumers of this guard feed
  /// `StreamBuilder`s that can re-subscribe (listen -> cancel -> listen
  /// again) when their subtree is rebuilt or remounted (e.g. a `TabBarView`
  /// swapping tabs back to "Packages", a theme toggle rebuilding the app,
  /// or a parent tree restructure). A single-subscription
  /// `StreamController` here would throw
  /// `Bad state: Stream has already been listened to` on the second listen,
  /// crashing the host screen (e.g. the Package Marketplace). The broadcast
  /// controller tolerates multiple listeners and listen -> cancel ->
  /// re-listen without throwing.
  static Stream<T> offlineResilient<T>(
    Stream<T> source, {
    required T fallback,
    String? debugLabel,
  }) {
    final controller = StreamController<T>.broadcast();
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
