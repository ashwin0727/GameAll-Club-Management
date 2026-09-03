import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/finance.dart';

/// Finance rework — Phase 13: the dashboard rebuild.
///
/// `get_finance_summary` gained `expenses_minor` and `outstanding_minor`
/// (migration 0046); `get_payment_method_breakdown` is new (0047). Mirrors
/// src/services/finance/supabase-finance.service.ts.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/data/repositories/finance_repository.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
  });

  group('FinanceSummary.fromJson gains the outgoing side', () {
    test('maps expenses_minor and outstanding_minor when present', () {
      final s = FinanceSummary.fromJson({
        'gross_revenue_minor': 350000,
        'refunds_minor': 80000,
        'expenses_minor': 40000,
        'net_revenue_minor': 230000,
        'outstanding_minor': 125000,
        'transaction_count': 4,
        'successful_payment_count': 4,
        'failed_payment_count': 0,
        'pending_payment_count': 0,
        'pending_refund_count': 0,
        'settlement_exception_count': 0,
      });

      expect(s.expensesMinor, 40000);
      expect(s.outstandingMinor, 125000);
      expect(s.netRevenueMinor, 230000);
    });

    test('defaults the two new fields to zero when the row omits them', () {
      // A summary row from before 0046 (and the existing repo test fixture)
      // has neither key — it must read as 0, never throw.
      final s = FinanceSummary.fromJson({
        'gross_revenue_minor': 350000,
        'refunds_minor': 80000,
        'net_revenue_minor': 270000,
        'transaction_count': 4,
        'successful_payment_count': 4,
        'failed_payment_count': 0,
        'pending_payment_count': 0,
        'pending_refund_count': 0,
        'settlement_exception_count': 0,
      });

      expect(s.expensesMinor, 0);
      expect(s.outstandingMinor, 0);
    });
  });

  group('PaymentMethodSlice.fromJson', () {
    test('maps the method, its captured total and its payment count', () {
      final slice = PaymentMethodSlice.fromJson({
        'payment_method': 'UPI',
        'amount_minor': 240000,
        'payment_count': 6,
      });
      expect(slice.paymentMethod, 'UPI');
      expect(slice.amountMinor, 240000);
      expect(slice.paymentCount, 6);
    });
  });

  group('FinanceRepository.getPaymentMethodBreakdown', () {
    test('calls get_payment_method_breakdown with the facility id and the shared date-range args', () {
      expect(source, contains("'get_payment_method_breakdown',"));
      expect(source, contains('..._dateRangeArgs('));
    });

    test('maps rows straight from the server — never summed from a transaction list', () {
      expect(source, contains('PaymentMethodSlice.fromJson('));
      for (final forbidden in const ['fold(', 'reduce(', '.sum', 'amount_minor +']) {
        expect(source, isNot(contains(forbidden)),
            reason: 'the method split is a backend aggregate, never client math');
      }
    });
  });
}
