import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/finance.dart';

/// Finance rework — Expenses payment status (0069), Daily Closing (0070) and
/// Profit & Loss (0071). Mirrors the model + repository-contract shape of the
/// web's src/features/finance/types.ts and supabase-finance.service.ts.
///
/// Same house style as finance_expenses_test.dart: model cases are real calls
/// against the fromJson factories; RPC-contract cases are static checks on the
/// repository source (this project has no fake Supabase client).
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/data/repositories/finance_repository.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
  });

  group('ExpenseRow payment status', () {
    test('maps amount_paid_minor + payment_status and derives outstanding', () {
      final row = ExpenseRow.fromJson({
        'id': 'e1',
        'category_id': 'c1',
        'category_name': 'Rent',
        'amount_minor': 5000000,
        'amount_paid_minor': 3000000,
        'currency': 'INR',
        'payment_method': 'Bank Transfer',
        'payment_status': 'PARTIAL',
        'spent_on': '2026-09-01',
        'due_on': '2026-09-10',
        'vendor': 'Landlord',
        'reference': null,
        'notes': null,
        'receipt_path': null,
        'status': 'RECORDED',
        'created_by_name': 'Arun',
        'total_count': 1,
      });
      expect(row.paymentStatus, ExpensePaymentStatus.partial);
      expect(row.amountPaidMinor, 3000000);
      expect(row.outstandingMinor, 2000000);
      expect(row.createdByName, 'Arun');
    });

    test('a legacy row with no payment fields defaults to PAID / fully paid', () {
      final row = ExpenseRow.fromJson({
        'id': 'e2',
        'category_id': 'c1',
        'category_name': 'Other',
        'amount_minor': 1000,
        'currency': 'INR',
        'payment_method': null,
        'spent_on': '2026-08-01',
        'vendor': null,
        'reference': null,
        'notes': null,
        'status': 'RECORDED',
        'total_count': 1,
      });
      expect(row.paymentStatus, ExpensePaymentStatus.paid);
      expect(row.amountPaidMinor, 0);
    });
  });

  group('DailyClosingSummary.fromJson', () {
    test('maps every collection bucket and the closing row fields', () {
      final s = DailyClosingSummary.fromJson({
        'closing_date': '2026-09-09',
        'opening_cash_minor': 500000,
        'cash_collected_minor': 1000000,
        'upi_collected_minor': 850000,
        'card_collected_minor': 0,
        'online_collected_minor': 0,
        'bank_transfer_collected_minor': 0,
        'other_collected_minor': 0,
        'total_collected_minor': 1850000,
        'cash_expense_minor': 200000,
        'other_expense_minor': 0,
        'total_expense_minor': 200000,
        'expected_cash_minor': 1300000,
        'payment_count': 3,
        'expense_count': 1,
        'pending_payment_count': 0,
        'closing_id': 'dc1',
        'status': 'OPEN',
        'actual_cash_minor': null,
        'variance_minor': null,
        'variance_reason': null,
        'closed_at': null,
      });
      expect(s.status, DailyClosingStatus.open);
      expect(s.expectedCashMinor, 1300000);
      expect(s.cashCollectedMinor, 1000000);
      expect(s.closingId, 'dc1');
    });

    test('a day with no closing row reads as NOT_STARTED', () {
      final s = DailyClosingSummary.fromJson({
        'closing_date': '2026-09-09',
        'opening_cash_minor': 0,
        'cash_collected_minor': 0,
        'upi_collected_minor': 0,
        'card_collected_minor': 0,
        'online_collected_minor': 0,
        'bank_transfer_collected_minor': 0,
        'other_collected_minor': 0,
        'total_collected_minor': 0,
        'cash_expense_minor': 0,
        'other_expense_minor': 0,
        'total_expense_minor': 0,
        'expected_cash_minor': 0,
        'payment_count': 0,
        'expense_count': 0,
        'pending_payment_count': 0,
        'closing_id': null,
        'status': 'NOT_STARTED',
        'actual_cash_minor': null,
        'variance_minor': null,
        'variance_reason': null,
        'closed_at': null,
      });
      expect(s.status, DailyClosingStatus.notStarted);
      expect(s.closingId, isNull);
    });
  });

  group('ProfitAndLoss.fromJson', () {
    test('maps the revenue split, totals, margin and category breakdown', () {
      final p = ProfitAndLoss.fromJson({
        'booking_revenue_minor': 6000000,
        'membership_revenue_minor': 3000000,
        'guest_booking_revenue_minor': 1000000,
        'other_revenue_minor': 0,
        'gross_revenue_minor': 10000000,
        'refunds_minor': 500000,
        'total_revenue_minor': 9500000,
        'total_expense_minor': 1500000,
        'net_profit_minor': 8000000,
        'profit_margin_pct': 84.2,
        'expense_by_category': [
          {'categoryId': 'c1', 'category': 'Rent', 'amountMinor': 1500000},
        ],
      });
      expect(p.netProfitMinor, 8000000);
      expect(p.profitMarginPct, 84.2);
      expect(p.expenseByCategory.single.category, 'Rent');
    });
  });

  group('FinanceRepository — closing & P&L RPC contract', () {
    test('daily-closing methods call the 0070 RPCs by name', () {
      for (final rpc in const [
        "'get_daily_closing_summary'",
        "'open_daily_closing'",
        "'close_daily_closing'",
        "'reopen_daily_closing'",
        "'list_daily_closings'",
      ]) {
        expect(source, contains(rpc), reason: 'missing $rpc');
      }
    });

    test('close sends actual cash + optional reason; reopen sends a required reason', () {
      expect(source, contains("'p_actual_cash_minor': actualCashMinor"));
      expect(source, contains("'p_variance_reason': varianceReason"));
      expect(source, contains("'p_reason': reason"));
    });

    test('P&L reads get_pnl / get_pnl_trend and still does no money math', () {
      expect(source, contains("'get_pnl'"));
      expect(source, contains("'get_pnl_trend'"));
      for (final forbidden in const ['fold(', 'reduce(', 'amountMinor +', 'amount_minor +']) {
        expect(source, isNot(contains(forbidden)));
      }
    });

    test('record_expense_payment forwards an idempotency key', () {
      expect(source, contains("'record_expense_payment'"));
      expect(source, contains("'p_idempotency_key': idempotencyKey"));
    });
  });
}
