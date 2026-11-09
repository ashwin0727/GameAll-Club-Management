import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/network/resilient.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('isTransientError', () {
    test('a dropped network, a timeout and an overloaded server are worth another try', () {
      expect(isTransientError(const SocketException('x')), isTrue);
      expect(isTransientError(TimeoutException('x')), isTrue);
      expect(
        isTransientError(
          const PostgrestException(message: 'cancelled', code: '57014'),
        ),
        isTrue,
      );
      expect(
        isTransientError(
          const PostgrestException(message: 'busy', code: '53300'),
        ),
        isTrue,
      );
      expect(isTransientError(const FunctionException(status: 503)), isTrue);
      expect(isTransientError(const FunctionException(status: 429)), isTrue);
    });

    test('a real answer is not retried', () {
      expect(
        isTransientError(
          const PostgrestException(
            message: 'no such function',
            code: 'PGRST202',
          ),
        ),
        isFalse,
      );
      expect(
        isTransientError(
          const PostgrestException(message: 'denied', code: '42501'),
        ),
        isFalse,
      );
      expect(isTransientError(const FunctionException(status: 400)), isFalse);
      expect(isTransientError(const FunctionException(status: 401)), isFalse);
      expect(isTransientError(StateError('bug')), isFalse);
    });
  });

  group('retryTransient', () {
    test('returns the first answer without waiting', () async {
      var calls = 0;
      final waits = <Duration>[];
      final v = await retryTransient(
        () async => ++calls,
        sleep: (d) async => waits.add(d),
      );
      expect(v, 1);
      expect(waits, isEmpty);
    });

    test(
      'retries a transient failure and returns the answer that follows',
      () async {
        var calls = 0;
        final waits = <Duration>[];
        final v = await retryTransient(
          () async {
            if (++calls < 3) throw const SocketException('down');
            return 'ok';
          },
          sleep: (d) async => waits.add(d),
          random: math.Random(1),
        );
        expect(v, 'ok');
        expect(calls, 3);
        expect(waits, hasLength(2));
        expect(waits[1], greaterThan(waits[0]), reason: 'the waits grow');
        expect(waits[0].inMilliseconds, inInclusiveRange(400, 500));
        expect(waits[1].inMilliseconds, inInclusiveRange(800, 1000));
      },
    );

    test('gives up after the attempts and throws the last error', () async {
      var calls = 0;
      await expectLater(
        retryTransient<int>(() async {
          calls++;
          throw const SocketException('down');
        }, sleep: (_) async {}),
        throwsA(isA<SocketException>()),
      );
      expect(calls, 3);
    });

    test('never retries a real answer', () async {
      var calls = 0;
      await expectLater(
        retryTransient<int>(() async {
          calls++;
          throw const PostgrestException(message: 'denied', code: '42501');
        }, sleep: (_) async {}),
        throwsA(isA<PostgrestException>()),
      );
      expect(calls, 1);
    });

    test(
      'a call that hangs is cut off and counted as a transient failure',
      () async {
        var calls = 0;
        final v = await retryTransient(
          () {
            calls++;
            return calls == 1 ? Completer<int>().future : Future.value(7);
          },
          timeout: const Duration(milliseconds: 20),
          sleep: (_) async {},
        );
        expect(v, 7);
        expect(calls, 2);
      },
    );
  });

  group('InFlight', () {
    test('callers asking for the same thing at once share one call', () async {
      final f = InFlight();
      var calls = 0;
      final gate = Completer<int>();
      Future<int> op() {
        calls++;
        return gate.future;
      }

      final a = f.run('k', op);
      final b = f.run('k', op);
      gate.complete(5);
      expect(await a, 5);
      expect(await b, 5);
      expect(calls, 1);
    });

    test(
      'nothing is cached: the next call after it finishes runs again',
      () async {
        final f = InFlight();
        var calls = 0;
        Future<int> op() async => ++calls;
        expect(await f.run('k', op), 1);
        await Future<void>.delayed(Duration.zero);
        expect(await f.run('k', op), 2);
      },
    );

    test('different keys do not share', () async {
      final f = InFlight();
      var calls = 0;
      Future<int> op() async => ++calls;
      await Future.wait([f.run('a', op), f.run('b', op)]);
      expect(calls, 2);
    });
  });
}
