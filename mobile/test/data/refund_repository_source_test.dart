import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/payment.dart';
import 'package:gameall_club_mobile/data/models/refund.dart';

/// This repository has no fake/mock Supabase client set up anywhere in this
/// project (see test/data/payment_repository_source_test.dart for the
/// precedent this follows), so these are static, dependency-free checks on
/// the source itself rather than a call-through test. They mirror the cases
/// in src/services/refunds/supabase-refund.service.test.ts:
///   (a) each cancellation Edge Function is invoked with exactly the fields
///       the function accepts, and the returned booking/refund shapes are
///       parsed correctly (never a fabricated refund when `refund: null`).
///   (b) a gateway/network failure maps to a generic AppException, not a
///       leaked raw error.
///   (c) an Edge-Function `{ error: "..." }` response body's message is
///       surfaced to the caller verbatim.
///   (d) the thrown type is the app's own AppException, never a raw object.
///   (e) read RPCs (refundable_amount / list_refunds /
///       list_settlement_exceptions / get_effective_cancellation_policy /
///       upsert_cancellation_policy) are called with exactly their p_-prefixed
///       params.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/data/repositories/refund_repository.dart').readAsStringSync();
  });

  group('RefundRepository.cancelBooking', () {
    test('invokes the cancel-booking Edge Function by name', () {
      expect(source, contains("_invoke('cancel-booking',"));
    });

    test('sends exactly the cancellation fields the Edge Function accepts', () {
      final match = RegExp(r"'cancel-booking', \{([\s\S]*?)\}\);").firstMatch(source);
      expect(match, isNotNull, reason: 'expected an inline body map literal for cancel-booking');
      final fields = RegExp(r"'(\w+)':").allMatches(match!.group(1)!).map((m) => m.group(1)).toSet();
      expect(fields, {'bookingId', 'reason', 'refundOverridePercent', 'overrideReason'});
    });
  });

  group('RefundRepository.cancelMembershipSlot', () {
    test('invokes cancel-membership-slot with the booking id and refund override fields', () {
      expect(source, contains("_invoke('cancel-membership-slot',"));
      final match = RegExp(r"'cancel-membership-slot', \{([\s\S]*?)\}\);").firstMatch(source);
      expect(match, isNotNull);
      final fields = RegExp(r"'(\w+)':").allMatches(match!.group(1)!).map((m) => m.group(1)).toSet();
      expect(fields, {'bookingId', 'reason', 'refundOverridePercent', 'overrideReason'});
    });
  });

  group('RefundRepository.cancelMembership', () {
    test('invokes cancel-membership with an explicit refund amount field — never policy-derived', () {
      expect(source, contains("_invoke('cancel-membership',"));
      final match = RegExp(r"'cancel-membership', \{([\s\S]*?)\}\);").firstMatch(source);
      expect(match, isNotNull);
      final fields = RegExp(r"'(\w+)':").allMatches(match!.group(1)!).map((m) => m.group(1)).toSet();
      expect(fields, {'membershipId', 'reason', 'refundAmountMinor', 'overrideReason'});
    });
  });

  group('RefundRepository.initiateRefund', () {
    test('invokes create-razorpay-refund with exactly the manual/settlement-exception refund fields', () {
      expect(source, contains("_invoke('create-razorpay-refund',"));
      final match = RegExp(r"'create-razorpay-refund', \{([\s\S]*?)\}\);").firstMatch(source);
      expect(match, isNotNull);
      final fields = RegExp(r"'(\w+)':").allMatches(match!.group(1)!).map((m) => m.group(1)).toSet();
      expect(fields, {'paymentOrderId', 'settlementExceptionId', 'amountMinor', 'reason', 'overrideReason'});
    });
  });

  group('RefundRepository read RPCs', () {
    test('refundableAmount reads via refundable_amount', () {
      expect(source, contains("_client.rpc('refundable_amount', params: {'p_payment_order_id': paymentOrderId})"));
    });

    test('listRefunds reads via list_refunds', () {
      expect(source, contains("_client.rpc('list_refunds', params: {'p_facility_id': facilityId})"));
    });

    test('listSettlementExceptions defaults to OPEN and reads via list_settlement_exceptions', () {
      expect(source, contains("Future<List<SettlementException>> listSettlementExceptions(String facilityId, {String? status = 'OPEN'})"));
      expect(
        source,
        contains("_client.rpc('list_settlement_exceptions', params: {'p_facility_id': facilityId, 'p_status': status})"),
      );
    });

    test('getCancellationPolicy reads via get_effective_cancellation_policy', () {
      expect(source, contains("_client.rpc('get_effective_cancellation_policy', params: {'p_facility_id': facilityId})"));
    });

    test('upsertCancellationPolicy writes via upsert_cancellation_policy with exactly its p_-prefixed params', () {
      final match = RegExp(r"'upsert_cancellation_policy',\s*params: \{([\s\S]*?)\},\n\s*\);").firstMatch(source);
      expect(match, isNotNull, reason: 'expected an inline params: { ... } map literal for upsert_cancellation_policy');
      final fields = RegExp(r"'(p_\w+)':").allMatches(match!.group(1)!).map((m) => m.group(1)).toSet();
      expect(fields, {
        'p_facility_id',
        'p_full_refund_hours',
        'p_full_refund_percent',
        'p_partial_refund_hours',
        'p_partial_refund_percent',
      });
    });
  });

  group('RefundRepository error handling', () {
    test('a FunctionsHttpException body error is surfaced verbatim as paymentOrderError', () {
      expect(source, contains("throw AppException(AppErrorCode.paymentOrderError, details['error'] as String);"));
    });

    test('FunctionException (relay/fetch failure) maps to a generic paymentGatewayError, not a leaked raw error', () {
      expect(source, contains('on FunctionException {'));
      expect(source, contains('throw AppException(AppErrorCode.paymentGatewayError);'));
    });

    test('a PostgrestException from a read/write RPC maps to paymentOrderError with the server message', () {
      final postgrestThrows = RegExp(r"on PostgrestException catch \(e\) \{\s*throw AppException\(AppErrorCode\.paymentOrderError, e\.message\);").allMatches(source).length;
      expect(postgrestThrows, greaterThanOrEqualTo(5), reason: 'refundableAmount, listRefunds, listSettlementExceptions, getCancellationPolicy, upsertCancellationPolicy each catch PostgrestException');
    });

    test('every thrown error is the app\'s own AppException type, never a raw object', () {
      final throwStatements = RegExp(r'throw ([A-Za-z_][\w.]*)').allMatches(source).map((m) => m.group(1)).toSet();
      expect(throwStatements, {'AppException'});
    });
  });

  group('RefundStatus.toJson/fromJson mirrors refund_status exactly', () {
    test('round-trips every DB value', () {
      const values = {
        RefundStatus.requested: 'REQUESTED',
        RefundStatus.processing: 'PROCESSING',
        RefundStatus.pending: 'PENDING',
        RefundStatus.processed: 'PROCESSED',
        RefundStatus.failed: 'FAILED',
        RefundStatus.cancelled: 'CANCELLED',
      };
      for (final entry in values.entries) {
        expect(entry.key.toJson(), entry.value);
        expect(RefundStatus.fromJson(entry.value), entry.key);
      }
    });
  });

  group('RefundReason.toJson/fromJson mirrors refund_reason exactly', () {
    test('round-trips every DB value', () {
      const values = {
        RefundReason.customerCancellation: 'CUSTOMER_CANCELLATION',
        RefundReason.facilityCancellation: 'FACILITY_CANCELLATION',
        RefundReason.courtUnavailable: 'COURT_UNAVAILABLE',
        RefundReason.settlementException: 'SETTLEMENT_EXCEPTION',
        RefundReason.duplicatePayment: 'DUPLICATE_PAYMENT',
        RefundReason.ownerOverride: 'OWNER_OVERRIDE',
        RefundReason.other: 'OTHER',
      };
      for (final entry in values.entries) {
        expect(entry.key.toJson(), entry.value);
        expect(RefundReason.fromJson(entry.value), entry.key);
      }
    });
  });

  group('PaymentOrderStatus.fromJson mirrors the Phase 6 PARTIALLY_REFUNDED value, positioned right after REFUND_REQUESTED', () {
    test('PARTIALLY_REFUNDED parses and sits between REFUND_REQUESTED and REFUNDED', () {
      expect(PaymentOrderStatus.fromJson('PARTIALLY_REFUNDED'), PaymentOrderStatus.partiallyRefunded);
      final values = PaymentOrderStatus.values;
      final requestedIdx = values.indexOf(PaymentOrderStatus.refundRequested);
      final partialIdx = values.indexOf(PaymentOrderStatus.partiallyRefunded);
      final refundedIdx = values.indexOf(PaymentOrderStatus.refunded);
      expect(requestedIdx < partialIdx && partialIdx < refundedIdx, isTrue);
    });
  });

  group('RefundSubmission.fromJson', () {
    test('parses the normal submitRequestedRefund shape (refundId key)', () {
      final submission = RefundSubmission.fromJson({'refundId': 'r-1', 'status': 'PROCESSING', 'razorpayRefundId': 'rfnd_1'});
      expect(submission.id, 'r-1');
      expect(submission.status, RefundStatus.processing);
      expect(submission.razorpayRefundId, 'rfnd_1');
    });

    test('parses the no-Razorpay-configured fallback shape (id key, no razorpayRefundId)', () {
      final submission = RefundSubmission.fromJson({'id': 'r-2', 'status': 'REQUESTED'});
      expect(submission.id, 'r-2');
      expect(submission.status, RefundStatus.requested);
      expect(submission.razorpayRefundId, isNull);
    });
  });

  group('Refund.fromJson maps a raw refunds row (snake_case) to the camelCase model', () {
    test('parses list_refunds\' row shape', () {
      final refund = Refund.fromJson({
        'id': 'r-1',
        'facility_id': 'facility-1',
        'payment_order_id': 'po-1',
        'transaction_id': 'txn-1',
        'source_type': 'GUEST_BOOKING',
        'source_id': 'booking-1',
        'razorpay_payment_id': 'pay_1',
        'razorpay_refund_id': 'rfnd_1',
        'amount_minor': 80000,
        'currency': 'INR',
        'reason': 'CUSTOMER_CANCELLATION',
        'status': 'PROCESSED',
        'is_override': false,
        'override_reason': null,
        'policy_percent_applied': 100,
        'failure_reason': null,
        'initiated_by': 'user-1',
        'created_at': '2026-08-27T00:00:00Z',
        'updated_at': '2026-08-27T00:05:00Z',
        'processed_at': '2026-08-27T00:05:00Z',
      });

      expect(refund.id, 'r-1');
      expect(refund.policyPercentApplied, 100);
      expect(refund.razorpayRefundId, 'rfnd_1');
      expect(refund.status, RefundStatus.processed);
      expect(refund.sourceType, PaymentSourceType.guestBooking);
    });
  });

  group('CancellationPolicy.fromJson', () {
    test('reads the effective (configured-or-default) policy row', () {
      final policy = CancellationPolicy.fromJson({
        'id': 'cp-1',
        'facility_id': 'facility-1',
        'full_refund_hours': 24,
        'full_refund_percent': 100,
        'partial_refund_hours': 2,
        'partial_refund_percent': 50,
        'created_at': 'x',
        'updated_at': 'x',
      });

      expect(policy.facilityId, 'facility-1');
      expect(policy.fullRefundHours, 24);
      expect(policy.fullRefundPercent, 100);
      expect(policy.partialRefundHours, 2);
      expect(policy.partialRefundPercent, 50);
    });
  });
}