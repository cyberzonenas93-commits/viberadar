import 'dart:async';

/// Runs [tasks] concurrently with at most [maxConcurrent] in flight at once.
/// Results come back in the same order as [tasks], regardless of completion
/// order.
///
/// Semantics match `Future.wait` for error handling: the first exception
/// thrown (or first future to error) propagates to the caller. In-flight
/// tasks continue running until they complete on their own, but no new
/// tasks are started once an error has occurred, and subsequent results
/// are discarded.
///
/// Use this when you have a bounded, pre-computed list of tasks. For
/// lazy/streaming submission, use [ConcurrencyLimiter] instead.
Future<List<R>> runLimited<R>(
  Iterable<Future<R> Function()> tasks, {
  required int maxConcurrent,
}) async {
  if (maxConcurrent < 1) {
    throw ArgumentError.value(
        maxConcurrent, 'maxConcurrent', 'must be >= 1');
  }

  final list    = tasks.toList(growable: false);
  final total   = list.length;
  if (total == 0) return <R>[];

  final results = List<R?>.filled(total, null);
  var   next    = 0;
  Object?   firstError;
  StackTrace? firstStack;

  // Worker pool: each worker pulls the next index until exhausted or until
  // an earlier task has thrown (in which case we stop starting new work).
  Future<void> worker() async {
    while (true) {
      if (firstError != null) return;
      final i = next++;
      if (i >= total) return;
      try {
        results[i] = await list[i]();
      } catch (e, st) {
        firstError ??= e;
        firstStack ??= st;
        return;
      }
    }
  }

  final workerCount = total < maxConcurrent ? total : maxConcurrent;
  await Future.wait(List.generate(workerCount, (_) => worker()));

  if (firstError != null) {
    Error.throwWithStackTrace(firstError!, firstStack ?? StackTrace.current);
  }
  return results.cast<R>();
}

/// A semaphore-style concurrency limiter for lazy task submission.
///
/// Unlike [runLimited], this variant lets callers submit tasks one at a
/// time — useful when tasks are generated during iteration (e.g., a
/// directory walk) or when different call sites share a single budget.
///
/// At most [_maxConcurrent] calls to [run] are executing their [task]
/// bodies at any given moment. Additional submissions queue in FIFO order
/// and start as soon as a slot frees up.
class ConcurrencyLimiter {
  ConcurrencyLimiter({required int maxConcurrent})
      : _maxConcurrent = maxConcurrent {
    if (maxConcurrent < 1) {
      throw ArgumentError.value(
          maxConcurrent, 'maxConcurrent', 'must be >= 1');
    }
  }

  final int _maxConcurrent;
  final List<Completer<void>> _waiting = <Completer<void>>[];
  int _active = 0;

  /// Number of tasks currently executing their body.
  int get active => _active;

  /// Number of submissions waiting for a slot.
  int get queued => _waiting.length;

  /// Run [task] when a slot is available. Any error thrown by [task]
  /// propagates to the caller of [run]; the slot is always released.
  Future<R> run<R>(Future<R> Function() task) async {
    if (_active >= _maxConcurrent) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    _active++;
    try {
      return await task();
    } finally {
      _active--;
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      }
    }
  }
}
