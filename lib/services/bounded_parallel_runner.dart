import 'dart:async';

List<Future<R>> runBoundedParallel<T, R>(
  List<T> items, {
  required int maxConcurrent,
  required Future<R> Function(T) run,
}) {
  if (items.isEmpty) return const [];
  if (maxConcurrent < 1) {
    throw ArgumentError.value(maxConcurrent, 'maxConcurrent');
  }
  final results = List.generate(items.length, (_) => Completer<R>());
  var next = 0;

  Future<void> worker() async {
    while (next < items.length) {
      final index = next++;
      try {
        results[index].complete(await run(items[index]));
      } on Object catch (error, stackTrace) {
        results[index].completeError(error, stackTrace);
      }
    }
  }

  for (var workerIndex = 0;
      workerIndex < maxConcurrent && workerIndex < items.length;
      workerIndex++) {
    unawaited(worker());
  }
  return results.map((result) => result.future).toList(growable: false);
}
