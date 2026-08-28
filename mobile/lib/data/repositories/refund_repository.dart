import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/booking.dart';
import '../models/refund.dart';

/// Cancellation, Refund & Payment Recovery — Phase 6 port. Mirrors
/// src/services/refunds/supabase-refund.service.ts exactly: the single
/// write path for cancelling a booking/membership-slot/membership is its
/// dedicated Edge Function (cancel-booking / cancel-membership-slot /
/// cancel-membership) — cancellation and (when the source was paid) a
/// policy-derived refund happen together, in one server-side call, never as
/// a plain client-side status update. The owner's manual "Initiate Refund"
/// entry point (partial adjustment, or resolving a SETTLEMENT_EXCEPTION)
/// goes through create-razorpay-refund. See
/// supabase/migrations/0022_refund_enums.sql,
/// supabase/migrations/0023_cancellation_refunds.sql, and the four
/// supabase/functions/{cancel-booking,cancel-membership-slot,
/// cancel-membership,create-razorpay-refund}/index.ts Edge Functions for the
/// authoritative backend contract.
class RefundRepository {
  RefundRepository(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> _invoke(String name, Map<String, dynamic> body) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(name, body: body);
    } on FunctionsHttpException catch (e) {
      // The Edge Function itself responded (400/500/502) with a JSON
      // `{ error: string }` body — a specific, already-polished business-rule
      // or gateway message. Surfaced verbatim, mirroring the web service's
      // PAYMENT_ORDER_ERROR handling.
      final details = e.details;
      if (details is Map && details['error'] is String) {
        throw AppException(AppErrorCode.paymentOrderError, details['error'] as String);
      }
      throw AppException(AppErrorCode.paymentGatewayError);
    } on FunctionException {
      // FunctionsRelayException / FunctionsFetchException — nothing specific
      // to surface, map to a generic gateway error rather than leaking the
      // raw error.
      throw AppException(AppErrorCode.paymentGatewayError);
    }
    return (response.data as Map).cast<String, dynamic>();
  }

  RefundSubmission? _refundOrNull(Map<String, dynamic> data) {
    final refund = data['refund'];
    if (refund == null) return null;
    return RefundSubmission.fromJson((refund as Map).cast<String, dynamic>());
  }

  /// Cancels a `bookings` row (member or ad-hoc guest booking). Court
  /// availability releases for free (0001's exclusion constraint); if the
  /// booking was paid, a policy-derived refund is requested and submitted to
  /// Razorpay in the same call.
  Future<({Booking booking, RefundSubmission? refund})> cancelBooking(CancelBookingInput input) async {
    final data = await _invoke('cancel-booking', {
      'bookingId': input.bookingId,
      'reason': input.reason,
      'refundOverridePercent': input.refundOverridePercent,
      'overrideReason': input.overrideReason,
    });
    final booking = Booking.fromJson((data['booking'] as Map).cast<String, dynamic>());
    return (booking: booking, refund: _refundOrNull(data));
  }

  /// Cancels a released-capacity guest booking (membership_session_bookings
  /// row). Guest capacity releases for free.
  Future<({RefundSubmission? refund})> cancelMembershipSlot(CancelMembershipSlotInput input) async {
    final data = await _invoke('cancel-membership-slot', {
      'bookingId': input.bookingId,
      'reason': input.reason,
      'refundOverridePercent': input.refundOverridePercent,
      'overrideReason': input.overrideReason,
    });
    return (refund: _refundOrNull(data));
  }

  /// Cancels a membership. Refund amount (if any) is an explicit
  /// owner/manager decision — never policy/time-derived (spec §14/§15). The
  /// caller refetches membership state itself (same pattern as
  /// assign/renew — no fabricated object here).
  Future<({RefundSubmission? refund})> cancelMembership(CancelMembershipInput input) async {
    final data = await _invoke('cancel-membership', {
      'membershipId': input.membershipId,
      'reason': input.reason,
      'refundAmountMinor': input.refundAmountMinor,
      'overrideReason': input.overrideReason,
    });
    return (refund: _refundOrNull(data));
  }

  /// The owner's manual "Initiate Refund" entry point — a partial/manual
  /// refund on any settled payment, or resolving a SETTLEMENT_EXCEPTION with
  /// a full refund.
  Future<RefundSubmission> initiateRefund(InitiateRefundInput input) async {
    final data = await _invoke('create-razorpay-refund', {
      'paymentOrderId': input.paymentOrderId,
      'settlementExceptionId': input.settlementExceptionId,
      'amountMinor': input.amountMinor,
      'reason': input.reason?.toJson(),
      'overrideReason': input.overrideReason,
    });
    return RefundSubmission.fromJson(data);
  }

  /// Captured Amount − Processed Refunds − In-flight Refunds — the
  /// server-authoritative ceiling for any refund UI ever shows (spec §40).
  Future<int> refundableAmount(String paymentOrderId) async {
    try {
      final data = await _client.rpc('refundable_amount', params: {'p_payment_order_id': paymentOrderId});
      return (data as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      throw AppException(AppErrorCode.paymentOrderError, e.message);
    }
  }

  /// Phase 7 (0024_finance.sql) re-created `list_refunds` with status/source/
  /// date-range/pagination parameters for the Finance → Refunds filters. All
  /// of them default to "no filter" server-side, so `listRefunds(facilityId)`
  /// with an empty [filters] returns exactly what Phase 6 returned.
  Future<List<Refund>> listRefunds(String facilityId, {RefundListFilters filters = const RefundListFilters()}) async {
    try {
      final rows = await _client.rpc(
        'list_refunds',
        params: {
          'p_facility_id': facilityId,
          'p_status': filters.status?.toJson(),
          'p_source_type': filters.sourceType?.toJson(),
          'p_preset': filters.dateRange?.preset.toJson(),
          'p_start_date': filters.dateRange?.startDate,
          'p_end_date': filters.dateRange?.endDate,
          'p_limit': filters.limit ?? 100,
          'p_offset': filters.offset ?? 0,
        },
      );
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(Refund.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException(AppErrorCode.paymentOrderError, e.message);
    }
  }

  /// [SettlementExceptionListFilters.status] defaults to OPEN (matching the
  /// RPC's own default), mirroring the web service's `{ status: "OPEN" }`
  /// default. Pass `status: null` to see every status. Phase 7 added the
  /// source-type and date-range filters alongside it.
  Future<List<SettlementException>> listSettlementExceptions(
    String facilityId, {
    SettlementExceptionListFilters filters = const SettlementExceptionListFilters(),
  }) async {
    try {
      final rows = await _client.rpc(
        'list_settlement_exceptions',
        params: {
          'p_facility_id': facilityId,
          'p_status': filters.status?.toJson(),
          'p_source_type': filters.sourceType?.toJson(),
          'p_preset': filters.dateRange?.preset.toJson(),
          'p_start_date': filters.dateRange?.startDate,
          'p_end_date': filters.dateRange?.endDate,
        },
      );
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(SettlementException.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException(AppErrorCode.paymentOrderError, e.message);
    }
  }

  Future<CancellationPolicy> getCancellationPolicy(String facilityId) async {
    try {
      final data = await _client.rpc('get_effective_cancellation_policy', params: {'p_facility_id': facilityId});
      if (data == null) throw AppException(AppErrorCode.paymentOrderError);
      return CancellationPolicy.fromJson((data as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      throw AppException(AppErrorCode.paymentOrderError, e.message);
    }
  }

  Future<CancellationPolicy> upsertCancellationPolicy(UpsertCancellationPolicyInput input) async {
    try {
      final data = await _client.rpc(
        'upsert_cancellation_policy',
        params: {
          'p_facility_id': input.facilityId,
          'p_full_refund_hours': input.fullRefundHours,
          'p_full_refund_percent': input.fullRefundPercent,
          'p_partial_refund_hours': input.partialRefundHours,
          'p_partial_refund_percent': input.partialRefundPercent,
        },
      );
      if (data == null) throw AppException(AppErrorCode.paymentOrderError);
      return CancellationPolicy.fromJson((data as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      throw AppException(AppErrorCode.paymentOrderError, e.message);
    }
  }
}