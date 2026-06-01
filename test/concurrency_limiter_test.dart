import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/core/utils/concurrency_limiter.dart';

void main() {
  group('runLimited', () {
    test('empty input produces empty output', () async {
      final result = await runLimited<int>(const [], maxConcurrent: 4);
      expect(result, isEmpty);
    });

    test('preserves input order regardless of completion order', () async {
      // Completers let us resolve tasks in reverse order, so we can verify
      // the returned list still matches input order.
      final completers = List.generate(5, (_) => Completer<int>());
      final future = runLimited<int>(
        List.generate(5, (i) => () => completers[i].future),
        maxConcurrent: 5,
      );

      // Resolve in reverse order.
      for (var i = 4; i >= 0; i--) {
        completers[i].complete(i * 10);
      }

      final result = await future;
      expect(result, <int>[0, 10, 20, 30, 40]);
    });

    test('never exceeds maxConcurrent tasks running at once', () async {
      const maxConcurrent = 3;
      const totalTasks = 12;

      var active = 0;
      var peak   = 0;
      final gates = List.generate(totalTasks, (_) => Completer<void>());

      final future = runLimited<int>(
        List.generate(totalTasks, (i) => () async {
          active++;
          if (active > peak) peak = active;
          await gates[i].future;
          active--;
          return i;
        }),
        maxConcurrent: maxConcurrent,
      );

      // Let the event loop schedule the first batch.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // First [maxConcurrent] tasks should be in flight.
      expect(active, maxConcurrent);
      expect(peak, maxConcurrent);

      // Complete them one at a time and verify the ceiling holds.
      for (var i = 0; i < totalTasks; i++) {
        gates[i].complete();
        await Future<void>.delayed(Duration.zero);
        expect(active, lessThanOrEqualTo(maxConcurrent));
        expect(peak, lessThanOrEqualTo(maxConcurrent));
      }

      final result = await future;
      expect(result.length, totalTasks);
      expect(peak, maxConcurrent);
    });

    test('first exception propagates (matching Future.wait semantics)',
        () async {
      final error = Exception('task 1 failed');
      final future = runLimited<int>(
        [
          () async => 0,
          () async => throw error,
          () async => 2,
        ],
        maxConcurrent: 2,
      );

      await expectLater(future, throwsA(same(error)));
    });

    test('rejects maxConcurrent < 1', () {
      expect(
        () => runLimited<int>([() async => 0], maxConcurrent: 0),
        throwsArgumentError,
      );
    });

    test('works when task count is smaller than maxConcurrent', () async {
      final result = await runLimited<int>(
        [() async => 1, () async => 2],
        maxConcurrent: 10,
      );
      expect(result, <int>[1, 2]);
    });
  });

  group('ConcurrencyLimiter', () {
    test('never exceeds maxConcurrent across concurrent run() calls',
        () async {
      const maxConcurrent = 2;
      const totalTasks = 8;

      final limiter = ConcurrencyLimiter(maxConcurrent: maxConcurrent);
      final gates = List.generate(totalTasks, (_) => Completer<void>());

      var active = 0;
      var peak   = 0;
      final futures = <Future<int>>[];
      for (var i = 0; i < totalTasks; i++) {
        futures.add(limiter.run<int>(() async {
          active++;
          if (active > peak) peak = active;
          await gates[i].future;
          active--;
          return i;
        }));
      }

      // Drain the event loop so the first batch gets scheduled.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(active, maxConcurrent);
      expect(limiter.active, maxConcurrent);
      expect(limiter.queued, totalTasks - maxConcurrent);

      for (var i = 0; i < totalTasks; i++) {
        gates[i].complete();
        await Future<void>.delayed(Duration.zero);
        expect(active, lessThanOrEqualTo(maxConcurrent));
      }

      final results = await Future.wait(futures);
      expect(results.length, totalTasks);
      expect(peak, maxConcurrent);
      expect(limiter.active, 0);
      expect(limiter.queued, 0);
    });

    test('run() propagates exceptions and releases slot', () async {
      final limiter = ConcurrencyLimiter(maxConcurrent: 1);
      final error = Exception('boom');

      await expectLater(
        limiter.run<int>(() async => throw error),
        throwsA(same(error)),
      );
      // Slot must be freed so the next submission can run.
      expect(limiter.active, 0);
      expect(limiter.queued, 0);

      final next = await limiter.run<int>(() async => 42);
      expect(next, 42);
    });

    test('queued tasks start in FIFO order', () async {
      final limiter = ConcurrencyLimiter(maxConcurrent: 1);
      final order = <int>[];

      final firstGate = Completer<void>();
      final first = limiter.run<void>(() async {
        order.add(0);
        await firstGate.future;
      });

      // Queue two more submissions while the first holds the slot.
      final second = limiter.run<void>(() async => order.add(1));
      final third  = limiter.run<void>(() async => order.add(2));

      await Future<void>.delayed(Duration.zero);
      expect(limiter.active, 1);
      expect(limiter.queued, 2);

      firstGate.complete();
      await Future.wait([first, second, third]);

      expect(order, <int>[0, 1, 2]);
    });

    test('rejects maxConcurrent < 1', () {
      expect(
        () => ConcurrencyLimiter(maxConcurrent: 0),
        throwsArgumentError,
      );
    });
  });
}
