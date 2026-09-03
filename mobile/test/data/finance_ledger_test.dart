import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/finance.dart';

/// Finance rework — Phase 9: one ledger for the Transactions page.
///
/// Mirrors the ledger half of src/services/finance/supabase-finance.service.ts
/// (`listLedger` / `listPaymentMethods`) and src/features/finance/types.ts
/// (`LedgerEntry` / `LedgerTxnType` / `LedgerFilters` / `LedgerPage`).
/// Backend: supabase/migrations/0049_finance_ledger.sql — payments, refunds
/// and expenses read into one shape, filtered and paged server-side.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/data/repositories/finance_repository.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
  });

  group('LedgerTxnType', () {
    test('round-trips the exact values list_finance_ledger emits and filters on', () {
      const values = {
        LedgerTxnType.income: 'INCOME',
        LedgerTxnType.expense: 'EXPENSE',
        LedgerTxnType.refund: 'REFUND',
      };
      for (final entry in values.entries) {
        expect(entry.key.toJson(), entry.value);
        expect(LedgerTxnType.fromJson(entry.value), entry.key);
      }
    });
  });

  group('LedgerEntry.fromJson', () {
    test('maps an INCOME row, keeping the server description and category verbatim', () {
      final entry = LedgerEntry.fromJson({
        'id': 'txn-1',
        'reference': 'TXN-ABCD1234',
        'occurred_at': '2026-08-20T10:15:00Z',
        'description': 'Guest Booking — Rahul',
        'category': 'Guest Booking Revenue',
        'txn_type': 'INCOME',
        'payment_method': 'UPI',
        'amount_minor': 80000,
        'currency': 'INR',
        'status': 'paid',
        'source_type': 'GUEST_BOOKING',
        'booking_id': 'booking-1',
        'membership_id': null,
        'expense_id': null,
        'total_count': 34,
      });

      expect(entry.id, 'txn-1');
      expect(entry.reference, 'TXN-ABCD1234');
      expect(entry.occurredAt, DateTime.parse('2026-08-20T10:15:00Z'));
      expect(entry.description, 'Guest Booking — Rahul');
      expect(entry.category, 'Guest Booking Revenue');
      expect(entry.txnType, LedgerTxnType.income);
      expect(entry.paymentMethod, 'UPI');
      expect(entry.amountMinor, 80000);
      expect(entry.currency, 'INR');
      expect(entry.status, 'paid');
      expect(entry.sourceType, 'GUEST_BOOKING');
      expect(entry.bookingId, 'booking-1');
      expect(entry.membershipId, isNull);
      expect(entry.expenseId, isNull);
    });

    test('maps an EXPENSE row — no payment method, an expense id, negative-in-meaning', () {
      final entry = LedgerEntry.fromJson({
        'id': 'exp-9',
        'reference': 'EXP-1A2B3C4D',
        'occurred_at': '2026-08-02T00:00:00Z',
        'description': 'State Electricity Board — August bill',
        'category': 'Utilities',
        'txn_type': 'EXPENSE',
        'payment_method': null,
        'amount_minor': 4000000,
        'currency': 'INR',
        'status': 'paid',
        'source_type': 'EXPENSE',
        'booking_id': null,
        'membership_id': null,
        'expense_id': 'exp-9',
        'total_count': 34,
      });

      expect(entry.txnType, LedgerTxnType.expense);
      expect(entry.paymentMethod, isNull);
      expect(entry.expenseId, 'exp-9');
      expect(entry.isIncome, isFalse);
    });

    test('isIncome tracks the server txn_type, never re-derived from the amount', () {
      expect(LedgerEntry.fromJson(_row('INCOME')).isIncome, isTrue);
      expect(LedgerEntry.fromJson(_row('REFUND')).isIncome, isFalse);
      expect(LedgerEntry.fromJson(_row('EXPENSE')).isIncome, isFalse);
    });
  });

  group('LedgerPage', () {
    test('totalCount is the server row\'s own total_count, never entries.length', () {
      final page = LedgerPage.fromRows([_row('INCOME', totalCount: 90), _row('EXPENSE', totalCount: 90)]);
      expect(page.entries.length, 2);
      expect(page.totalCount, 90);
    });

    test('an empty ledger is a real zero', () {
      final page = LedgerPage.fromRows(const []);
      expect(page.entries, isEmpty);
      expect(page.totalCount, 0);
    });
  });

  group('FinanceRepository.listLedger', () {
    test('calls list_finance_ledger with the shared date-range args plus every filter', () {
      expect(source, contains("'list_finance_ledger',"));
      expect(source, contains('..._dateRangeArgs('));
      for (final param in const [
        "'p_txn_type':",
        "'p_category':",
        "'p_payment_method':",
        "'p_status':",
        "'p_search':",
      ]) {
        expect(source, contains(param), reason: 'list_finance_ledger must send $param');
      }
      expect(source, contains("'p_limit': input.limit ?? 10"));
      expect(source, contains("'p_offset': input.offset ?? 0"));
    });

    test('the page total is the server row\'s total_count, not the fetched length', () {
      expect(source, contains('LedgerPage.fromRows('));
      expect(source, isNot(contains('totalCount: entries.length')));
    });
  });

  group('FinanceRepository.listPaymentMethods', () {
    test('calls list_finance_payment_methods and returns the bare method strings', () {
      expect(source, contains("'list_finance_payment_methods',"));
      expect(source, contains("'p_facility_id': facilityId"));
      expect(source, contains("['payment_method'] as String"));
    });
  });

  group('FinanceRepository still does no revenue math after Phase 9', () {
    test('the ledger methods add no fold/reduce/sum over amounts', () {
      for (final forbidden in const ['fold(', 'reduce(', '.sum', 'amountMinor +', 'amount_minor +']) {
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

Map<String, dynamic> _row(String txnType, {int totalCount = 1}) => {
      'id': 'row',
      'reference': 'REF-1',
      'occurred_at': '2026-08-01T00:00:00Z',
      'description': 'x',
      'category': 'Other Revenue',
      'txn_type': txnType,
      'payment_method': null,
      'amount_minor': 1000,
      'currency': 'INR',
      'status': 'paid',
      'source_type': txnType,
      'booking_id': null,
      'membership_id': null,
      'expense_id': null,
      'total_count': totalCount,
    };
