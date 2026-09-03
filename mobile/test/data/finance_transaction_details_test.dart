import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/finance.dart';

/// Finance rework — Phase 12: Transaction Details, and a real PDF receipt.
///
/// Mirrors src/features/finance/types.ts (`TransactionDetails` /
/// `TransactionPaymentHistoryRow`) and the details half of
/// supabase-finance.service.ts. Backend: supabase/migrations/0055_transaction_
/// details.sql (`get_transaction_details`, camelCase jsonb) +
/// supabase/functions/download-transaction-receipt (PDF bytes).
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/data/repositories/finance_repository.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
  });

  group('TransactionDetails.fromJson (the RPC returns camelCase jsonb)', () {
    test('maps every field, including the payment-history rows', () {
      final details = TransactionDetails.fromJson({
        'id': 'txn-1',
        'reference': 'TXN-ABCD1234',
        'sourceType': 'GUEST_BOOKING',
        'category': 'Guest Booking Revenue',
        'type': 'INCOME',
        'amountMinor': 80000,
        'currency': 'INR',
        'status': 'paid',
        'paymentMethod': 'UPI',
        'occurredAt': '2026-08-20T10:15:00Z',
        'createdAt': '2026-08-20T10:14:30Z',
        'recordedBy': 'Asha Menon',
        'description': 'Guest booking payment for Court 2',
        'sourceReference': 'BOOK-AB12CD',
        'customerName': 'Rahul',
        'customerPhone': '9999999999',
        'facilityName': 'GameAll Arena',
        'facilityId': 'fac-1',
        'bookingId': 'book-1',
        'membershipId': null,
        'refundedMinor': 0,
        'netMinor': 80000,
        'history': [
          {
            'id': 'txn-0',
            'paidAt': '2026-08-10T09:00:00Z',
            'amountMinor': 30000,
            'paymentMethod': 'Cash',
            'reference': null,
            'status': 'paid',
            'isThisOne': false,
          },
          {
            'id': 'txn-1',
            'paidAt': '2026-08-20T10:15:00Z',
            'amountMinor': 50000,
            'paymentMethod': 'UPI',
            'reference': 'UPI-778',
            'status': 'paid',
            'isThisOne': true,
          },
        ],
      });

      expect(details.reference, 'TXN-ABCD1234');
      expect(details.sourceType, 'GUEST_BOOKING');
      expect(details.category, 'Guest Booking Revenue');
      expect(details.type, 'INCOME');
      expect(details.amountMinor, 80000);
      expect(details.status, 'paid');
      expect(details.paymentMethod, 'UPI');
      expect(details.occurredAt, DateTime.parse('2026-08-20T10:15:00Z'));
      expect(details.createdAt, DateTime.parse('2026-08-20T10:14:30Z'));
      expect(details.recordedBy, 'Asha Menon');
      expect(details.sourceReference, 'BOOK-AB12CD');
      expect(details.customerName, 'Rahul');
      expect(details.facilityName, 'GameAll Arena');
      expect(details.bookingId, 'book-1');
      expect(details.membershipId, isNull);
      expect(details.refundedMinor, 0);
      expect(details.netMinor, 80000);
      expect(details.history, hasLength(2));
      expect(details.history.first.amountMinor, 30000);
      expect(details.history.first.isThisOne, isFalse);
      expect(details.history.last.isThisOne, isTrue);
      expect(details.history.last.reference, 'UPI-778');
    });

    test('tolerates a null recordedBy / paymentMethod / sourceReference and an empty history', () {
      final details = TransactionDetails.fromJson({
        'id': 'txn-2',
        'reference': 'TXN-EEEE0000',
        'sourceType': 'MEMBERSHIP',
        'category': 'Membership Revenue',
        'type': 'INCOME',
        'amountMinor': 500000,
        'currency': 'INR',
        'status': 'paid',
        'paymentMethod': null,
        'occurredAt': '2026-09-01T00:00:00Z',
        'createdAt': '2026-09-01T00:00:00Z',
        'recordedBy': null,
        'description': 'Payment',
        'sourceReference': null,
        'customerName': null,
        'customerPhone': null,
        'facilityName': null,
        'facilityId': 'fac-1',
        'bookingId': null,
        'membershipId': 'mem-1',
        'refundedMinor': 0,
        'netMinor': 500000,
        'history': [],
      });

      expect(details.recordedBy, isNull);
      expect(details.paymentMethod, isNull);
      expect(details.sourceReference, isNull);
      expect(details.history, isEmpty);
      expect(details.membershipId, 'mem-1');
    });
  });

  group('FinanceRepository.getTransactionDetails', () {
    test('calls get_transaction_details with the transaction id', () {
      expect(source, contains("'get_transaction_details',"));
      expect(source, contains("'p_transaction_id': transactionId"));
    });

    test('parses the jsonb document, never a table row', () {
      expect(source, contains('TransactionDetails.fromJson('));
    });
  });

  group('FinanceRepository.downloadTransactionReceipt', () {
    test('invokes the download-transaction-receipt edge function with the transaction id', () {
      expect(source, contains("'download-transaction-receipt'"));
      expect(source, contains("'transactionId': transactionId"));
    });

    test('returns the PDF as bytes', () {
      expect(source, contains('Uint8List'));
    });

    test('the receipt is built server-side — no PDF library is imported here', () {
      expect(source, isNot(contains('pdf')));
    });
  });

  group('FinanceRepository still does no revenue math after Phase 12', () {
    test('the details methods add no fold/reduce/sum over amounts', () {
      for (final forbidden in const ['fold(', 'reduce(', '.sum', 'amountMinor +', 'netMinor +']) {
        expect(source, isNot(contains(forbidden)),
            reason: 'every total must come from a backend RPC field');
      }
    });

    test('every thrown error is still the app\'s own AppException, via _mapError', () {
      final thrown = RegExp(r'throw ([A-Za-z_][\w.]*)')
          .allMatches(source)
          .map((m) => m.group(1))
          .toSet();
      expect(thrown, {'AppException', '_mapError'});
    });
  });
}
