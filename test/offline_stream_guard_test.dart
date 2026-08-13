import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/services/offline_stream_guard.dart';

void main() {
  group('OfflineStreamGuard.offlineResilient', () {
    test('passes through normal emissions untouched', () async {
      final stream = OfflineStreamGuard.offlineResilient<int>(
        Stream.fromIterable([1, 2, 3]),
        fallback: -1,
        debugLabel: 'test',
      );
      final values = await stream.toList();
      expect(values, [1, 2, 3]);
    });

    test('replaces a stream error with the fallback emission', () async {
      final controller = StreamController<int>();
      final guarded = OfflineStreamGuard.offlineResilient<int>(
        controller.stream,
        fallback: 99,
      );
      final values = <int>[];
      final completer = Completer<void>();
      guarded.listen(
        values.add,
        onError: (e) => fail('guarded stream must not propagate errors'),
        onDone: completer.complete,
      );
      // Emit one normal value, then error.
      controller.add(1);
      controller.addError(StateError('network lost'));
      await completer.future;
      await controller.close();
      expect(values, [1, 99]);
    });

    test('does not emit fallback when stream completes without error',
        () async {
      final stream = OfflineStreamGuard.offlineResilient<String>(
        Stream.fromIterable(['a']),
        fallback: 'FALLBACK',
      );
      final values = await stream.toList();
      expect(values, ['a']);
    });

    test('handles a list fallback (typed) for cache-failure recovery',
        () async {
      final controller = StreamController<List<int>>();
      final guarded = OfflineStreamGuard.offlineResilient<List<int>>(
        controller.stream,
        fallback: const <int>[],
      );
      final values = <List<int>>[];
      final done = Completer<void>();
      guarded.listen(
        values.add,
        onError: (e) => fail('must not propagate'),
        onDone: done.complete,
      );
      controller.add([1, 2]);
      controller.addError(Exception('missing index'));
      await done.future;
      await controller.close();
      expect(values, [
        [1, 2],
        <int>[], // fallback
      ]);
    });

    test('completes after fallback emission (no hang)', () async {
      final controller = StreamController<int>();
      final guarded = OfflineStreamGuard.offlineResilient<int>(
        controller.stream,
        fallback: 0,
      );
      final done = guarded.isEmpty; // completes when stream closes with no data
      controller.addError(Exception('boom'));
      final isEmpty = await done;
      expect(isEmpty, isFalse); // fallback (0) was emitted, so not empty
      await controller.close();
    });
  });
}
