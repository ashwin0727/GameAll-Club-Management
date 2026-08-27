import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/payment.dart';

/// This repository has no fake/mock Supabase client set up anywhere in this
/// project (see test/data/membership_session_repository_source_test.dart for
/// the precedent this follows), so these are static, dependency-free checks
/// on the source itself rather than a call-through test. They mirror the 4
/// cases in src/services/payments/supabase-payment.service.test.ts:
///   (a) the request body sends exactly the source fields and NEVER an
///       amount field — the single most important guarantee here, since
///       supabase/migrations/0016_payment_orders.sql's create_payment_order
///       RPC never accepts a client-supplied amount either.
///   (b) a gateway/network failure maps to a generic AppException, not a
///       leaked raw error.
///   (c) an Edge-Function `{ error: "..." }` response body's message is
///       surfaced to the caller verbatim.
///   (d) the thrown type is the app's own AppException, never a raw object.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/data/repositories/payment_repository.dart').readAsStringSync();
  });

  group('PaymentRepository.createPaymentOrder', () {
    test('invokes the create-razorpay-order Edge Function by name', () {
      expect(source, contains("_client.functions.invoke(\n        'create-razorpay-order'"));
    });

    test('the request body never includes an amount field', () {
      expect(source, isNot(contains("'amount'")));
      expect(source, isNot(contains('amount:')));
    });

    test('the request body sends exactly the source fields the RPC/Edge Function accept', () {
      final bodyMatch = RegExp(r'body: \{([\s\S]*?)\},\n\s*\);').firstMatch(source);
      expect(bodyMatch, isNotNull, reason: 'expected an inline body: { ... } map literal');
      final bodyFields = RegExp(r"'(\w+)':").allMatches(bodyMatch!.group(1)!).map((m) => m.group(1)).toSet();
      expect(bodyFields, {'facilityId', 'sourceType', 'bookingId', 'membershipSessionBookingId', 'memberId', 'planId'});
    });

    test('a FunctionsHttpException body error is surfaced verbatim as paymentOrderError', () {
      expect(source, contains("throw AppException(AppErrorCode.paymentOrderError, details['error'] as String);"));
    });

    test('FunctionsRelayException/FunctionsFetchException map to a generic paymentGatewayError, not a leaked raw error', () {
      expect(source, contains('on FunctionException {'));
      // Both the FunctionsHttpException-without-a-usable-body branch and the
      // catch-all FunctionException branch throw the same generic code. This
      // same try/catch shape is repeated for verifyPaymentOrder,
      // reconcilePaymentOrder (Phase 4), and settlePaymentOrder (Phase 5), so
      // across the whole file there are 2 occurrences per method x 4 methods
      // = 8.
      final gatewayThrows = RegExp(r'throw AppException\(AppErrorCode\.paymentGatewayError\);').allMatches(source).length;
      expect(gatewayThrows, 8);
    });

    test('every thrown error is the app\'s own AppException type, never a raw object', () {
      final throwStatements = RegExp(r'throw ([A-Za-z_][\w.]*)').allMatches(source).map((m) => m.group(1)).toSet();
      expect(throwStatements, {'AppException'});
    });
  });

  group('PaymentSourceType.toJson mirrors payment_source_type exactly', () {
    test('MEMBERSHIP / MEMBER_BOOKING / GUEST_BOOKING', () {
      expect(PaymentSourceType.membership.toJson(), 'MEMBERSHIP');
      expect(PaymentSourceType.memberBooking.toJson(), 'MEMBER_BOOKING');
      expect(PaymentSourceType.guestBooking.toJson(), 'GUEST_BOOKING');
    });
  });

  group('PaymentOrderCheckoutInfo.fromJson', () {
    test('parses the Edge Function success shape exactly, amount as minor units', () {
      final info = PaymentOrderCheckoutInfo.fromJson({
        'keyId': 'rzp_test_fake_for_unit_test',
        'razorpayOrderId': 'order_fake',
        'amount': 50000,
        'currency': 'INR',
        'paymentOrderId': 'po-1',
        'receipt': 'GAMEALL-MEMBERBOOKING-abc',
      });

      expect(info.keyId, 'rzp_test_fake_for_unit_test');
      expect(info.razorpayOrderId, 'order_fake');
      expect(info.amount, 50000);
      expect(info.currency, 'INR');
      expect(info.paymentOrderId, 'po-1');
      expect(info.receipt, 'GAMEALL-MEMBERBOOKING-abc');
    });
  });

  group('PaymentOrderStatus.fromJson mirrors payment_order_status exactly, including the new Phase 4 values', () {
    test('PAYMENT_VERIFICATION_PENDING / PAYMENT_VERIFIED parse, positioned between PAYMENT_ATTEMPTED and AUTHORIZED', () {
      expect(PaymentOrderStatus.fromJson('PAYMENT_VERIFICATION_PENDING'), PaymentOrderStatus.paymentVerificationPending);
      expect(PaymentOrderStatus.fromJson('PAYMENT_VERIFIED'), PaymentOrderStatus.paymentVerified);
      final values = PaymentOrderStatus.values;
      final attemptedIdx = values.indexOf(PaymentOrderStatus.paymentAttempted);
      final pendingIdx = values.indexOf(PaymentOrderStatus.paymentVerificationPending);
      final verifiedIdx = values.indexOf(PaymentOrderStatus.paymentVerified);
      final authorizedIdx = values.indexOf(PaymentOrderStatus.authorized);
      expect(attemptedIdx < pendingIdx && pendingIdx < verifiedIdx && verifiedIdx < authorizedIdx, isTrue);
    });

    test('CAPTURED and COMPLETED both parse (the only two statuses toCheckoutResult treats as captured)', () {
      expect(PaymentOrderStatus.fromJson('CAPTURED'), PaymentOrderStatus.captured);
      expect(PaymentOrderStatus.fromJson('COMPLETED'), PaymentOrderStatus.completed);
    });
  });

  group('PaymentVerificationResult.fromJson', () {
    test('parses the paymentOrderId/status shape verify-razorpay-payment and reconcile-razorpay-payment share', () {
      final result = PaymentVerificationResult.fromJson({'paymentOrderId': 'po-1', 'status': 'CAPTURED'});
      expect(result.paymentOrderId, 'po-1');
      expect(result.status, PaymentOrderStatus.captured);
    });
  });

  group('PaymentRepository.verifyPaymentOrder', () {
    test('invokes verify-razorpay-payment by name', () {
      expect(source, contains("_client.functions.invoke(\n        'verify-razorpay-payment'"));
    });

    test('the request body sends exactly the four required fields', () {
      final match = RegExp(r"verify-razorpay-payment'[\s\S]*?body: \{([\s\S]*?)\},\n\s*\);").firstMatch(source);
      expect(match, isNotNull, reason: 'expected an inline body: { ... } map literal for verify-razorpay-payment');
      final fields = RegExp(r"'(\w+)':").allMatches(match!.group(1)!).map((m) => m.group(1)).toSet();
      expect(fields, {'paymentOrderId', 'razorpayOrderId', 'razorpayPaymentId', 'razorpaySignature'});
    });
  });

  group('PaymentRepository.reconcilePaymentOrder', () {
    test('invokes reconcile-razorpay-payment by name with just the payment order id', () {
      expect(source, contains("_client.functions.invoke(\n        'reconcile-razorpay-payment'"));
      final match = RegExp(r"reconcile-razorpay-payment'[\s\S]*?body: \{([\s\S]*?)\},\n\s*\);").firstMatch(source);
      expect(match, isNotNull, reason: 'expected an inline body: { ... } map literal for reconcile-razorpay-payment');
      final fields = RegExp(r"'(\w+)':").allMatches(match!.group(1)!).map((m) => m.group(1)).toSet();
      expect(fields, {'paymentOrderId'});
    });
  });

  group('PaymentRepository.settlePaymentOrder', () {
    test('invokes settle-payment with just the payment order id', () {
      expect(source, contains("_client.functions.invoke(\n        'settle-payment'"));
      final match = RegExp(r"settle-payment'[\s\S]*?body: \{([\s\S]*?)\},\n\s*\);").firstMatch(source);
      expect(match, isNotNull, reason: 'expected an inline body: { ... } map literal for settle-payment');
      final fields = RegExp(r"'(\w+)':").allMatches(match!.group(1)!).map((m) => m.group(1)).toSet();
      expect(fields, {'paymentOrderId'});
    });
  });

  group('PaymentOrderStatus.fromJson mirrors the Phase 5 SETTLEMENT_EXCEPTION value, positioned right after COMPLETED', () {
    test('SETTLEMENT_EXCEPTION parses and sits between COMPLETED and FAILED', () {
      expect(PaymentOrderStatus.fromJson('SETTLEMENT_EXCEPTION'), PaymentOrderStatus.settlementException);
      final values = PaymentOrderStatus.values;
      final completedIdx = values.indexOf(PaymentOrderStatus.completed);
      final exceptionIdx = values.indexOf(PaymentOrderStatus.settlementException);
      final failedIdx = values.indexOf(PaymentOrderStatus.failed);
      expect(completedIdx < exceptionIdx && exceptionIdx < failedIdx, isTrue);
    });
  });

  group('PaymentRepository.getPaymentOrderStatus', () {
    test('reads status via the existing RLS-scoped get_payment_order RPC — never a new privileged read path', () {
      expect(source, contains("_client.rpc('get_payment_order', params: {'p_payment_order_id': paymentOrderId})"));
    });
  });

  group('verify/reconcile error handling mirrors createPaymentOrder — every thrown error is the app\'s own AppException type', () {
    test('every thrown error across the whole file is AppException, never a raw object', () {
      final throwStatements = RegExp(r'throw ([A-Za-z_][\w.]*)').allMatches(source).map((m) => m.group(1)).toSet();
      expect(throwStatements, {'AppException'});
    });
  });
}