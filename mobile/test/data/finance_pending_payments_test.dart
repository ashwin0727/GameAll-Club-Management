import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/finance.dart';

/// Finance rework — Phase 10: Pending Payments.
///
/// Mirrors the pending-payments half of
/// src/services/finance/supabase-finance.service.ts (`listPendingPayments` /
/// `getPaymentObligation` / `getPendingPaymentsSummary`) and
/// src/features/finance/types.ts. Backend:
/// supabase/migrations/0052_pending_payments.sql + 0053_pending_payment_lookup.sql.
///
/// Nothing here derives what is owed — the database computes `outstanding_minor`
/// and `status` from what each booking/membership costs and what has been paid.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/data/repositories/finance_repository.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
  });

  group('Obligation enums round-trip the values the RPC emits and filters on', () {
    test('ObligationSource', () {
      const values = {
        ObligationSource.guestBooking: 'GUEST_BOOKING',
        ObligationSource.booking: 'BOOKING',
        ObligationSource.membership: 'MEMBERSHIP',
      };
      for (final e in values.entries) {
        expect(e.key.toJson(), e.value);
        expect(ObligationSource.fromJson(e.value), e.key);
      }
    });

    test('ObligationStatus', () {
      const values = {
        ObligationStatus.pending: 'PENDING',
        ObligationStatus.partiallyPaid: 'PARTIALLY_PAID',
        ObligationStatus.overdue: 'OVERDUE',
        ObligationStatus.paid: 'PAID',
      };
      for (final e in values.entries) {
        expect(e.key.toJson(), e.value);
        expect(ObligationStatus.fromJson(e.value), e.key);
      }
    });

    test('ObligationSort', () {
      expect(ObligationSort.dueDate.toJson(), 'DUE_DATE');
      expect(ObligationSort.amount.toJson(), 'AMOUNT');
      expect(ObligationSort.customer.toJson(), 'CUSTOMER');
      expect(ObligationSort.newest.toJson(), 'NEWEST');
    });

    test('the status filter has an ALL_OUTSTANDING option distinct from the four states', () {
      expect(PendingPaymentStatusFilter.allOutstanding.toJson(), 'ALL_OUTSTANDING');
      expect(PendingPaymentStatusFilter.overdue.toJson(), 'OVERDUE');
    });
  });

  group('PaymentObligation.fromJson', () {
    test('maps a booking obligation, keeping every server figure verbatim', () {
      final o = PaymentObligation.fromJson({
        'source_type': 'GUEST_BOOKING',
        'source_id': 'book-1',
        'reference': 'BOOK-AB12CD',
        'customer_name': 'Rahul',
        'customer_phone': '9999999999',
        'description': 'Court 2 • 14 Aug • 06:00 PM',
        'facility_name': 'GameAll Arena',
        'court_name': 'Court 2',
        'starts_at': '2026-08-14T12:30:00Z',
        'ends_at': '2026-08-14T13:30:00Z',
        'total_minor': 80000,
        'paid_minor': 30000,
        'outstanding_minor': 50000,
        'status': 'PARTIALLY_PAID',
        'payment_method': 'UPI',
        'due_on': '2026-08-14',
        'total_count': 7,
      });

      expect(o.sourceType, ObligationSource.guestBooking);
      expect(o.sourceId, 'book-1');
      expect(o.reference, 'BOOK-AB12CD');
      expect(o.customerName, 'Rahul');
      expect(o.customerPhone, '9999999999');
      expect(o.description, 'Court 2 • 14 Aug • 06:00 PM');
      expect(o.facilityName, 'GameAll Arena');
      expect(o.courtName, 'Court 2');
      expect(o.startsAt, DateTime.parse('2026-08-14T12:30:00Z'));
      expect(o.endsAt, DateTime.parse('2026-08-14T13:30:00Z'));
      expect(o.totalMinor, 80000);
      expect(o.paidMinor, 30000);
      expect(o.outstandingMinor, 50000);
      expect(o.status, ObligationStatus.partiallyPaid);
      expect(o.paymentMethod, 'UPI');
      expect(o.dueOn, '2026-08-14');
    });

    test('a membership obligation tolerates the null court/time fields', () {
      final o = PaymentObligation.fromJson({
        'source_type': 'MEMBERSHIP',
        'source_id': 'mem-1',
        'reference': 'MEM-99XX00',
        'customer_name': 'Priya',
        'customer_phone': null,
        'description': 'Gold Membership',
        'facility_name': 'GameAll Arena',
        'court_name': null,
        'starts_at': null,
        'ends_at': null,
        'total_minor': 500000,
        'paid_minor': 0,
        'outstanding_minor': 500000,
        'status': 'PENDING',
        'payment_method': null,
        'due_on': '2026-09-01',
      });

      expect(o.sourceType, ObligationSource.membership);
      expect(o.courtName, isNull);
      expect(o.startsAt, isNull);
      expect(o.endsAt, isNull);
      expect(o.customerPhone, isNull);
      expect(o.status, ObligationStatus.pending);
    });
  });

  group('PendingPaymentsPage / Summary', () {
    test('page totalCount is the server row\'s total_count, never obligations.length', () {
      final page = PendingPaymentsPage.fromRows([
        _row(totalCount: 12),
        _row(totalCount: 12),
      ]);
      expect(page.obligations.length, 2);
      expect(page.totalCount, 12);
    });

    test('an empty page is a real zero — never "all caught up" on a failed query', () {
      final page = PendingPaymentsPage.fromRows(const []);
      expect(page.obligations, isEmpty);
      expect(page.totalCount, 0);
    });

    test('summary maps the four server buckets and the count', () {
      final s = PendingPaymentsSummary.fromJson({
        'outstanding_minor': 900000,
        'pending_minor': 400000,
        'partially_paid_minor': 200000,
        'overdue_minor': 300000,
        'obligation_count': 9,
      });
      expect(s.outstandingMinor, 900000);
      expect(s.pendingMinor, 400000);
      expect(s.partiallyPaidMinor, 200000);
      expect(s.overdueMinor, 300000);
      expect(s.obligationCount, 9);
    });
  });

  group('FinanceRepository.listPendingPayments', () {
    test('calls list_pending_payments with every p_-prefixed argument', () {
      expect(source, contains("'list_pending_payments',"));
      for (final param in const [
        "'p_facility_id':",
        "'p_search':",
        "'p_source_type':",
        "'p_status':",
        "'p_from':",
        "'p_to':",
        "'p_sort':",
        "'p_source_id':",
      ]) {
        expect(source, contains(param), reason: 'list_pending_payments must send $param');
      }
      expect(source, contains("'p_limit': input.limit ?? 20"));
      expect(source, contains("'p_offset': input.offset ?? 0"));
    });

    test('defaults status to ALL_OUTSTANDING and sort to DUE_DATE, as the web service does', () {
      expect(source, contains("?? 'ALL_OUTSTANDING'"));
      expect(source, contains("?? 'DUE_DATE'"));
    });

    test('the page total is the server row\'s total_count, not the fetched length', () {
      expect(source, contains('PendingPaymentsPage.fromRows('));
      expect(source, isNot(contains('totalCount: obligations.length')));
    });
  });

  group('FinanceRepository.getPaymentObligation', () {
    test('is the same list, asked for one source id — never a second definition of "outstanding"', () {
      expect(source, contains('listPendingPayments('));
      expect(source, contains('sourceId:'));
    });
  });

  group('FinanceRepository.getPendingPaymentsSummary', () {
    test('calls get_pending_payments_summary with the facility id and optional window', () {
      expect(source, contains("'get_pending_payments_summary',"));
      expect(source, contains("'p_from':"));
      expect(source, contains("'p_to':"));
    });
  });

  group('FinanceRepository.recordObligationPayment', () {
    test('calls record_obligation_payment with every p_-prefixed argument', () {
      expect(source, contains("'record_obligation_payment',"));
      for (final param in const [
        "'p_source_type':",
        "'p_source_id':",
        "'p_amount_minor':",
        "'p_method':",
        "'p_paid_on':",
        "'p_reference':",
        "'p_notes':",
        "'p_idempotency_key':",
      ]) {
        expect(source, contains(param), reason: 'record_obligation_payment must send $param');
      }
    });

    test('passes the minor-unit amount straight through — no rupee arithmetic', () {
      expect(source, isNot(contains('* 100')));
      expect(source, isNot(contains('/ 100')));
    });

    test('surfaces the idempotency outcome from the server, never assumes success', () {
      expect(source, contains("map['duplicate'] == true"));
      expect(source, contains("map['outstandingMinor']"));
    });
  });

  group('FinanceRepository still does no revenue math after Phase 10', () {
    test('the pending-payments methods add no fold/reduce/sum over amounts', () {
      for (final forbidden in const ['fold(', 'reduce(', '.sum', 'outstandingMinor +', 'total_minor -']) {
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

Map<String, dynamic> _row({int totalCount = 1}) => {
      'source_type': 'BOOKING',
      'source_id': 'b',
      'reference': 'BOOK-1',
      'customer_name': 'A',
      'customer_phone': null,
      'description': 'x',
      'facility_name': 'F',
      'court_name': null,
      'starts_at': null,
      'ends_at': null,
      'total_minor': 1000,
      'paid_minor': 0,
      'outstanding_minor': 1000,
      'status': 'PENDING',
      'payment_method': null,
      'due_on': '2026-08-01',
      'total_count': totalCount,
    };
