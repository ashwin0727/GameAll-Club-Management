import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;

/// An HTTP client for Supabase that survives the usual hiccups under load: a dropped connection, a busy server (429 / 502 / 503 /
/// 504) and a request that hangs.
///
/// Only requests that are safe to repeat are retried:
///  * GET / HEAD, and
///  * POSTs to read-only database functions (list_*, get_*, my_*, ... see [_readRpc]), which only read.
/// Anything that writes (inserts, updates, payments, bookings, sign-in) is sent exactly once, so a slow response can never create a
/// duplicate. Every request, retried or not, gives up after [timeout] instead of hanging forever.
///
/// Retries wait 0.3 s, 0.6 s, 1.2 s plus a random pause (so many phones do not retry in step), and honour a Retry-After header.
class ResilientHttpClient extends http.BaseClient {
  ResilientHttpClient({
    http.Client? inner,
    this.timeout = const Duration(seconds: 30),
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 300),
    Random? random,
  })  : _inner = inner ?? http.Client(),
        _random = random ?? Random();

  final http.Client _inner;
  final Duration timeout;
  final int maxAttempts;
  final Duration baseDelay;
  final Random _random;

  static const _retryableStatus = {408, 425, 429, 500, 502, 503, 504};
  static final _readRpc = RegExp(r'^(list_|get_|my_|count_|search_|period_|is_|admin_list_|admin_get_|plan_has_|plan_includes_|public_facility_accepts_|effective_)');

  /// Whether sending this request again cannot change anything.
  static bool isSafeToRetry(http.BaseRequest request) {
    final method = request.method.toUpperCase();
    if (method == 'GET' || method == 'HEAD') return true;
    if (method == 'POST') {
      final match = RegExp(r'/rest/v1/rpc/([a-zA-Z0-9_]+)').firstMatch(request.url.path);
      return match != null && _readRpc.hasMatch(match.group(1)!);
    }
    return false;
  }

  Duration _delay(int attempt, http.BaseResponse? response) {
    final retryAfter = response?.headers['retry-after'];
    final seconds = retryAfter == null ? null : int.tryParse(retryAfter);
    if (seconds != null && seconds >= 0) return Duration(seconds: min(seconds, 5));
    return baseDelay * pow(2, attempt).toInt() + Duration(milliseconds: _random.nextInt(250));
  }

  /// A fresh copy of a request, because a sent request cannot be sent again. Null when it cannot be copied.
  http.BaseRequest? _copy(http.BaseRequest original) {
    if (original is http.Request) {
      return http.Request(original.method, original.url)
        ..headers.addAll(original.headers)
        ..bodyBytes = original.bodyBytes
        ..followRedirects = original.followRedirects
        ..maxRedirects = original.maxRedirects
        ..persistentConnection = original.persistentConnection;
    }
    return null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final retryable = isSafeToRetry(request);
    final attempts = retryable ? maxAttempts : 1;
    http.BaseRequest current = request;
    for (var attempt = 0;; attempt++) {
      final last = attempt >= attempts - 1;
      try {
        final response = await _inner.send(current).timeout(timeout);
        if (last || !_retryableStatus.contains(response.statusCode)) return response;
        // Drain the body so the connection is released before the next try.
        await response.stream.drain<void>();
        await Future<void>.delayed(_delay(attempt, response));
      } on Object {
        if (last) rethrow;
        await Future<void>.delayed(_delay(attempt, null));
      }
      final copy = _copy(request);
      if (copy == null) {
        // Cannot repeat a streamed body: send the original once more and let any failure surface.
        current = request;
        continue;
      }
      current = copy;
    }
  }

  @override
  void close() => _inner.close();
}
