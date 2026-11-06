import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../domain/player_dashboard_models.dart';

/// Why a payment page could not be opened, in words for the player.
class PaymentLinkException implements Exception {
  const PaymentLinkException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Turns an unpaid membership, coaching enrolment or booking into a Razorpay page the player can pay on. The Supabase version is the
/// real one; tests supply a fake.
abstract class PendingPaymentRepository {
  /// The page to pay on, or null when it turns out to be paid already.
  Future<Uri?> paymentLink(PendingPayment payment);
}

class SupabasePendingPaymentRepository implements PendingPaymentRepository {
  SupabasePendingPaymentRepository([SupabaseClient? client])
    : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient? get _client =>
      _injected ?? (AppConfig.isConfigured ? Supabase.instance.client : null);

  @override
  Future<Uri?> paymentLink(PendingPayment payment) async {
    final client = _client;
    if (client == null) {
      throw const PaymentLinkException('Please sign in to pay.');
    }
    // Each edge function reads the amount from the database and checks the item is the player's own; the app sends only the id.
    final (function, field) = switch (payment.kind) {
      PendingPaymentKind.membership => (
        'create-membership-subscription',
        'membershipId',
      ),
      PendingPaymentKind.coaching => (
        'create-player-coaching-billing',
        'enrollmentId',
      ),
      PendingPaymentKind.booking => (
        'create-player-booking-payment-link',
        'bookingId',
      ),
    };
    try {
      final res = await client.functions.invoke(
        function,
        body: {field: payment.id},
      );
      final data = res.data;
      if (data is Map && data['paid'] == true) return null;
      final url = data is Map ? data['shortUrl'] as String? : null;
      if (url == null || url.isEmpty) {
        throw const PaymentLinkException(
          "We couldn't open the payment page. Please try again.",
        );
      }
      return Uri.parse(url);
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map ? details['error'] as String? : null;
      throw PaymentLinkException(
        msg ?? "We couldn't open the payment page. Please try again.",
      );
    }
  }
}
