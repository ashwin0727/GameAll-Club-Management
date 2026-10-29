import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/services/resilient_http_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Request _req(String method, String url, {String? body}) {
  final r = http.Request(method, Uri.parse(url));
  if (body != null) r.body = body;
  return r;
}

ResilientHttpClient _client(MockClient inner, {Duration timeout = const Duration(seconds: 5)}) =>
    ResilientHttpClient(inner: inner, timeout: timeout, baseDelay: const Duration(milliseconds: 1));

void main() {
  const base = 'https://x.supabase.co';

  group('isSafeToRetry', () {
    test('reads are safe', () {
      expect(ResilientHttpClient.isSafeToRetry(_req('GET', '$base/rest/v1/courts')), isTrue);
      expect(ResilientHttpClient.isSafeToRetry(_req('HEAD', '$base/rest/v1/courts')), isTrue);
      for (final fn in ['list_roles', 'get_session_bundle', 'my_facility_plan', 'period_revenue_inr', 'admin_list_facilities']) {
        expect(ResilientHttpClient.isSafeToRetry(_req('POST', '$base/rest/v1/rpc/$fn', body: '{}')), isTrue, reason: fn);
      }
    });

    test('anything that writes is never retried', () {
      for (final fn in ['create_booking', 'record_membership_payment', 'admin_mark_settled', 'mark_notifications_read', 'register_device_token']) {
        expect(ResilientHttpClient.isSafeToRetry(_req('POST', '$base/rest/v1/rpc/$fn', body: '{}')), isFalse, reason: fn);
      }
      expect(ResilientHttpClient.isSafeToRetry(_req('POST', '$base/rest/v1/payments', body: '{}')), isFalse);
      expect(ResilientHttpClient.isSafeToRetry(_req('PATCH', '$base/rest/v1/bookings?id=eq.1', body: '{}')), isFalse);
      expect(ResilientHttpClient.isSafeToRetry(_req('DELETE', '$base/rest/v1/bookings?id=eq.1')), isFalse);
      expect(ResilientHttpClient.isSafeToRetry(_req('POST', '$base/auth/v1/token?grant_type=password', body: '{}')), isFalse);
      expect(ResilientHttpClient.isSafeToRetry(_req('POST', '$base/functions/v1/delete-account', body: '{}')), isFalse);
    });
  });

  group('send', () {
    test('retries a busy server on a read and returns the first good answer', () async {
      var calls = 0;
      final client = _client(MockClient((_) async => ++calls < 3 ? http.Response('', 503) : http.Response('{}', 200)));
      final res = await client.send(_req('GET', '$base/rest/v1/courts'));
      expect(res.statusCode, 200);
      expect(calls, 3);
    });

    test('retries a read-only function with its body intact', () async {
      final bodies = <String>[];
      var calls = 0;
      final client = _client(MockClient((req) async {
        bodies.add(req.body);
        return ++calls < 2 ? http.Response('', 429, headers: {'retry-after': '0'}) : http.Response('[]', 200);
      }));
      final res = await client.send(_req('POST', '$base/rest/v1/rpc/list_roles', body: '{"p_facility_id":"f1"}'));
      expect(res.statusCode, 200);
      expect(bodies, ['{"p_facility_id":"f1"}', '{"p_facility_id":"f1"}']);
    });

    test('retries a dropped connection on a read', () async {
      var calls = 0;
      final client = _client(MockClient((_) async {
        if (++calls < 2) throw http.ClientException('connection reset');
        return http.Response('{}', 200);
      }));
      expect((await client.send(_req('GET', '$base/rest/v1/courts'))).statusCode, 200);
      expect(calls, 2);
    });

    test('stops after three attempts and returns the last response', () async {
      var calls = 0;
      final client = _client(MockClient((_) async {
        calls++;
        return http.Response('', 503);
      }));
      expect((await client.send(_req('GET', '$base/rest/v1/courts'))).statusCode, 503);
      expect(calls, 3);
    });

    test('sends a write exactly once, even when the server answers 503', () async {
      var calls = 0;
      final client = _client(MockClient((_) async {
        calls++;
        return http.Response('', 503);
      }));
      expect((await client.send(_req('POST', '$base/rest/v1/rpc/create_booking', body: '{}'))).statusCode, 503);
      expect(calls, 1);
    });

    test('does not retry a write whose connection dropped', () async {
      var calls = 0;
      final client = _client(MockClient((_) async {
        calls++;
        throw http.ClientException('reset');
      }));
      await expectLater(client.send(_req('POST', '$base/rest/v1/payments', body: '{}')), throwsA(isA<http.ClientException>()));
      expect(calls, 1);
    });

    test('does not retry client errors', () async {
      var calls = 0;
      final client = _client(MockClient((_) async {
        calls++;
        return http.Response('', 403);
      }));
      expect((await client.send(_req('POST', '$base/rest/v1/rpc/list_coaching_sessions', body: '{}'))).statusCode, 403);
      expect(calls, 1);
    });

    test('gives up on a request that hangs', () async {
      final client = _client(MockClient((_) => Completer<http.Response>().future), timeout: const Duration(milliseconds: 50));
      await expectLater(client.send(_req('POST', '$base/rest/v1/rpc/create_booking', body: '{}')), throwsA(isA<TimeoutException>()));
    });
  });
}
