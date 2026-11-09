import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/resilient.dart';
import '../domain/payment_receipt.dart';

/// Where the payment progress and success pages get their data. The Supabase version is the real one; tests supply a fake.
abstract class PaymentReceiptRepository {
  /// The membership / enrolment / booking and what has been paid for it, or null when it is not the player's own (or not there).
  Future<PaymentReceipt?> receipt(PaymentKind kind, String id);

  /// Ask Razorpay for the real state of a membership or coaching payment and save it (the webhook may be late or not set up), then
  /// return what the database now says. Never throws on the sync: when the function is not deployed it just reads [receipt].
  Future<PaymentReceipt?> sync(PaymentKind kind, String id);
}

class SupabasePaymentReceiptRepository implements PaymentReceiptRepository {
  SupabasePaymentReceiptRepository([SupabaseClient? client])
    : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient? get _client =>
      _injected ?? (AppConfig.isConfigured ? Supabase.instance.client : null);

  @override
  Future<PaymentReceipt?> receipt(PaymentKind kind, String id) async {
    final client = _client;
    if (client == null) return null;
    final res = await retryTransient(
      () => client.rpc(
        'get_my_payment_receipt',
        params: {'p_kind': kind.wire, 'p_id': id},
      ),
    );
    return res is Map
        ? PaymentReceipt.fromJson(res.cast<String, dynamic>())
        : null;
  }

  @override
  Future<PaymentReceipt?> sync(PaymentKind kind, String id) async {
    final client = _client;
    if (client == null) return null;
    // The webhook is the primary way a payment is recorded; this asks Razorpay directly in case it is late or not set up.
    try {
      await client.functions.invoke(
        'sync-player-payment',
        body: {'kind': kind.wire, 'id': id},
      );
    } catch (_) {
      // not deployed yet, offline or Razorpay slow: the database read below still tells the truth it has
    }
    return receipt(kind, id);
  }
}
