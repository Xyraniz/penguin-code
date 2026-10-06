import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/services/bounded_parallel_runner.dart';

void main() {
  test('keeps result order and respects the concurrency limit', () async {
    var active = 0;
    var peak = 0;
    final futures = runBoundedParallel([0, 1, 2, 3, 4], maxConcurrent: 2,
        run: (value) async {
      active++;
      if (active > peak) peak = active;
      await Future<void>.delayed(Duration(milliseconds: 5 - value));
      active--;
      return value * 2;
    });

    expect(await Future.wait(futures), [0, 2, 4, 6, 8]);
    expect(peak, 2);
  });

  test('propagates an individual failure without stopping other work',
      () async {
    final futures =
        runBoundedParallel([0, 1, 2], maxConcurrent: 2, run: (value) async {
      if (value == 1) throw StateError('failed read');
      return value;
    });

    expect(await futures[0], 0);
    await expectLater(futures[1], throwsA(isA<StateError>()));
    expect(await futures[2], 2);
  });

  test('rejects an invalid concurrency limit', () {
    expect(
      () => runBoundedParallel([1], maxConcurrent: 0, run: (_) async => 1),
      throwsArgumentError,
    );
  });
}
