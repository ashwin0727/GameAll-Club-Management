import 'dart:async';
import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether [error] is the kind of failure a second try can fix: the network dropped, the server timed out or was briefly overloaded.
/// A real answer ("not signed in", "no such function", a validation message) is NOT transient and is never retried.
bool isTransientError(Object error) {
  // SocketException is matched by name: dart:io does not exist on the web build
  if (error is TimeoutException ||
      error.runtimeType.toString() == 'SocketException')
    return true;
  if (error is PostgrestException) {
    final code = error.code ?? '';
    // 57014 = the database cancelled the call (statement_timeout); 53300 = too many connections; 08xxx = connection problems
    return code == '57014' ||
        code == '53300' ||
        code.startsWith('08') ||
        code == '503' ||
        code == '502' ||
        code == '504' ||
        code == '429';
  }
  if (error is FunctionException) {
    return error.status == 429 ||
        error.status == 502 ||
        error.status == 503 ||
        error.status == 504;
  }
  final text = error.toString().toLowerCase();
  return text.contains('failed host lookup') ||
      text.contains('connection closed') ||
      text.contains('connection reset') ||
      text.contains('clientexception');
}

/// Runs [op], and tries again (with growing, jittered waits) when it fails for a transient reason.
///
/// Meant for READS only: repeating a read changes nothing, while repeating a payment or a booking could. Each attempt is also cut off
/// after [timeout], so a hung connection turns into an error the page can show instead of an endless spinner. Waits are
/// baseDelay, 2x, 4x … plus up to 25 % random jitter, so a crowd of clients that failed together does not retry together.
Future<T> retryTransient<T>(
  Future<T> Function() op, {
  int maxAttempts = 3,
  Duration timeout = const Duration(seconds: 15),
  Duration baseDelay = const Duration(milliseconds: 400),
  bool Function(Object error)? isTransient,
  Future<void> Function(Duration)? sleep,
  math.Random? random,
}) async {
  final transient = isTransient ?? isTransientError;
  final wait = sleep ?? (d) => Future<void>.delayed(d);
  final rng = random ?? math.Random();
  Object? last;
  StackTrace? lastTrace;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await op().timeout(timeout);
    } catch (e, st) {
      last = e;
      lastTrace = st;
      if (attempt == maxAttempts || !transient(e)) break;
      final ms = baseDelay.inMilliseconds * (1 << (attempt - 1));
      await wait(
        Duration(milliseconds: ms + (ms * 0.25 * rng.nextDouble()).round()),
      );
    }
  }
  Error.throwWithStackTrace(last!, lastTrace!);
}

/// Shares one running call between everyone who asks for the same thing at the same time (a page opening while another page already
/// asked for the same data). The map is keyed by [key]; the entry is gone as soon as the call finishes, so nothing is cached.
class InFlight {
  final _running = <String, Future<Object?>>{};

  Future<T> run<T>(String key, Future<T> Function() op) {
    final existing = _running[key];
    if (existing != null) return existing as Future<T>;
    final future = op();
    _running[key] = future;
    future.whenComplete(() => _running.remove(key)).ignore();
    return future;
  }
}
