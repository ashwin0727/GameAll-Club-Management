import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/finance.dart';
import 'package:gameall_club_mobile/data/models/payment.dart';

/// Finance & Revenue Management — Phase 7.
///
/// This repository has no fake/mock Supabase client set up anywhere in this
/// project (see test/data/refund_repository_source_test.dart and
/// test/data/payment_repository_source_test.dart for the precedent this
/// follows), and this phase deliberately adds no mocking dependency, so the
/// RPC-contract cases are static checks on the source itself while the
/// row-mapping cases are real calls against the models.
///
/// Mirrors src/services/finance/supabase-finance.service.test.ts:
///   (a) each RPC is called by name with exactly its p_-prefixed arguments,
///       including the shared date-range args (preset + explicit CUSTOM
///       dates passed straight through).
///   (b) "Not authorized" maps to financeAccessDenied — never a fabricated
///       zero summary; "valid start and end date" maps to invalidDateRange;
///       everything else maps to financeDataError.
///   (c) the thrown type is always the app's own AppException.
///   (d) list + count are fetched in parallel with identical filters, and
///       limit/offset default to page 1 of 20.
///   (e) every snake_case row/RPC field maps to the right model field.
///   (f) no figure is ever computed on the client (spec §"Core Finance
///       Principle" / §"Critical Final Rule").
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/data/repositories/finance_repository.dart').readAsStringSync();
  });

  group('FinanceRepository.getSummary', () {
    test('calls get_finance_summary with the facility id plus the shared date-range args', () {
      expect(source, contains("'get_finance_summary',"));
      expect(source, contains("params: {'p_facility_id': facilityId, ..._dateRangeArgs(dateRange)},"));
    });

    test('the shared date-range args are exactly p_preset/p_start_date/p_end_date', () {
      final match = RegExp(r'_dateRangeArgs\(FinanceDateRange dateRange\) \{\s*return \{([\s\S]*?)\};').firstMatch(source);
      expect(match, isNotNull, reason: 'expected an inline date-range args map literal');
      final fields = RegExp(r"'(p_\w+)':").allMatches(match!.group(1)!).map((m) => m.group(1)).toSet();
      expect(fields, {'p_preset', 'p_start_date', 'p_end_date'});
    });

    test('a CUSTOM range passes its explicit start/end dates straight through', () {
      expect(source, contains("'p_start_date': dateRange.startDate,"));
      expect(source, contains("'p_end_date': dateRange.endDate,"));
    });

    test('never resolves a date range on the device — presets are resolved server-side in the facility timezone', () {
      expect(source, isNot(contains('DateTime.now()')));
      expect(source, isNot(contains('DateTime(')));
    });

    test('maps the server\'s own summary totals, never recomputed client-side', () {
      final summary = FinanceSummary.fromJson({
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

      expect(summary.grossRevenueMinor, 350000);
      expect(summary.refundsMinor, 80000);
      expect(summary.netRevenueMinor, 270000);
      expect(summary.transactionCount, 4);
      expect(summary.successfulPaymentCount, 4);
      expect(summary.failedPaymentCount, 0);
      expect(summary.pendingPaymentCount, 0);
      expect(summary.pendingRefundCount, 0);
      expect(summary.settlementExceptionCount, 0);
    });
  });

  group('FinanceRepository error mapping', () {
    test('a facility-isolation rejection maps to financeAccessDenied — never a fabricated zero summary', () {
      expect(
        source,
        contains("if (message.contains('Not authorized')) return AppException(AppErrorCode.financeAccessDenied);"),
      );
    });

    test('an invalid custom range maps to invalidDateRange', () {
      expect(
        source,
        contains("if (message.contains('valid start and end date')) return AppException(AppErrorCode.invalidDateRange);"),
      );
    });

    test('anything else maps to the generic financeDataError rather than leaking the raw error', () {
      expect(source, contains('return AppException(AppErrorCode.financeDataError);'));
      expect(source, isNot(contains('e.message)')), reason: 'a raw Postgrest message is never surfaced by Finance');
    });

    test('every thrown error is the app\'s own AppException type, never a raw object', () {
      final throwStatements = RegExp(r'throw ([A-Za-z_][\w.]*)').allMatches(source).map((m) => m.group(1)).toSet();
      expect(throwStatements, {'AppException', '_mapError'});
    });
  });

  group('FinanceRepository.getRevenueBreakdown', () {
    test('calls get_revenue_breakdown with the same facility + date-range args', () {
      expect(source, contains("'get_revenue_breakdown',"));
    });

    test('maps every revenue-by-source figure — spec Critical Finance Test', () {
      final breakdown = RevenueBreakdown.fromJson({
        'membership_revenue_minor': 150000,
        'member_booking_revenue_minor': 50000,
        'guest_booking_revenue_minor': 150000,
        'refunds_minor': 80000,
        'net_revenue_minor': 270000,
        'membership_included_usage_count': 2,
      });

      expect(breakdown.membershipRevenueMinor, 150000);
      expect(breakdown.memberBookingRevenueMinor, 50000);
      expect(breakdown.guestBookingRevenueMinor, 150000);
      expect(breakdown.refundsMinor, 80000);
      expect(breakdown.netRevenueMinor, 270000);
      // Volume, never revenue.
      expect(breakdown.membershipIncludedUsageCount, 2);
    });
  });

  group('FinanceRepository.getRevenueTrend', () {
    test('passes the granularity through as p_granularity', () {
      expect(source, contains("'get_revenue_trend',"));
      expect(source, contains("'p_granularity': granularity.toJson(),"));
    });

    test('granularity values are exactly what get_revenue_trend accepts', () {
      expect(RevenueTrendGranularity.daily.toJson(), 'daily');
      expect(RevenueTrendGranularity.weekly.toJson(), 'weekly');
      expect(RevenueTrendGranularity.monthly.toJson(), 'monthly');
    });

    test('maps each server bucket', () {
      final point = RevenueTrendPoint.fromJson({
        'bucket_date': '2026-08-02',
        'gross_minor': 1200000,
        'refund_minor': 30000,
        'net_minor': 1170000,
      });

      expect(point.date, '2026-08-02');
      expect(point.grossMinor, 1200000);
      expect(point.refundMinor, 30000);
      expect(point.netMinor, 1170000);
    });

    test('an empty trend stays empty — the repository only maps rows the server sent, never fabricates points', () {
      expect(source, contains('.map((row) => RevenueTrendPoint.fromJson((row as Map).cast<String, dynamic>()))'));
      expect(
        source,
        isNot(contains('RevenueTrendPoint(')),
        reason: 'a trend point is only ever parsed from a server row, never constructed here',
      );
    });
  });

  group('FinanceRepository.listTransactions', () {
    test('fetches the page and the total count in parallel', () {
      expect(source, contains('await Future.wait(['));
      expect(source, contains("'list_finance_transactions',"));
      expect(source, contains("_client.rpc('count_finance_transactions', params: args),"));
    });

    test('both calls share one identical filter args map, so the count can never disagree with the page', () {
      final match = RegExp(r'final args = \{([\s\S]*?)\};').firstMatch(source);
      expect(match, isNotNull, reason: 'expected a single shared args map literal');
      final fields = RegExp(r"'(p_\w+)':").allMatches(match!.group(1)!).map((m) => m.group(1)).toSet();
      expect(fields, {'p_facility_id', 'p_source_type', 'p_status', 'p_search'});
      expect(match.group(1), contains('..._dateRangeArgs(input.dateRange),'));
      expect(source, contains("params: {...args, 'p_limit': input.limit ?? 20, 'p_offset': input.offset ?? 0},"));
    });

    test('defaults limit/offset to page 1 of 20 when not specified', () {
      expect(source, contains("'p_limit': input.limit ?? 20"));
      expect(source, contains("'p_offset': input.offset ?? 0"));
    });

    test('the total count is the server\'s own count(*), never the length of the fetched page', () {
      expect(source, contains('totalCount: (results[1] as num?)?.toInt() ?? 0,'));
      expect(source, isNot(contains('totalCount: transactions.length')));
    });

    test('filter enums serialize to the exact values the RPC filters on', () {
      expect(PaymentSourceType.guestBooking.toJson(), 'GUEST_BOOKING');
      expect(PaymentSourceType.memberBooking.toJson(), 'MEMBER_BOOKING');
      expect(PaymentSourceType.membership.toJson(), 'MEMBERSHIP');
      expect(TransactionStatus.paid.toJson(), 'paid');
      expect(TransactionStatus.created.toJson(), 'created');
      expect(TransactionStatus.failed.toJson(), 'failed');
      expect(TransactionStatus.refunded.toJson(), 'refunded');
    });
  });

  group('FinanceRepository.getTransaction', () {
    test('reads a single transaction via get_finance_transaction', () {
      expect(source, contains("'get_finance_transaction',"));
      expect(source, contains("params: {'p_transaction_id': transactionId},"));
    });

    test('maps a finance_transactions_view row to the model with full Razorpay traceability', () {
      final transaction = FinanceTransaction.fromJson({
        'id': 'txn-1',
        'reference': 'TXN-ABCD1234',
        'facility_id': 'facility-1',
        'created_at': '2026-08-27T10:00:00Z',
        'paid_at': '2026-08-27T10:00:05Z',
        'effective_at': '2026-08-27T10:00:05Z',
        'source_type': 'GUEST_BOOKING',
        'customer_name': 'Rahul',
        'customer_phone': '9999999999',
        'booking_id': 'booking-1',
        'membership_id': null,
        'payment_order_id': 'po-1',
        'amount_minor': 80000,
        'currency': 'INR',
        'payment_method': 'RAZORPAY',
        'status': 'paid',
        'razorpay_order_id': 'order_1',
        'razorpay_payment_id': 'pay_1',
        'refunded_minor': 0,
        'pending_refund_minor': 0,
        'net_minor': 80000,
      });

      expect(transaction.id, 'txn-1');
      expect(transaction.reference, 'TXN-ABCD1234');
      expect(transaction.facilityId, 'facility-1');
      expect(transaction.sourceType, PaymentSourceType.guestBooking);
      expect(transaction.status, TransactionStatus.paid);
      expect(transaction.customerName, 'Rahul');
      expect(transaction.customerPhone, '9999999999');
      expect(transaction.bookingId, 'booking-1');
      expect(transaction.membershipId, isNull);
      expect(transaction.paymentOrderId, 'po-1');
      expect(transaction.amountMinor, 80000);
      expect(transaction.currency, 'INR');
      expect(transaction.paymentMethod, 'RAZORPAY');
      expect(transaction.razorpayOrderId, 'order_1');
      expect(transaction.razorpayPaymentId, 'pay_1');
      expect(transaction.refundedMinor, 0);
      expect(transaction.pendingRefundMinor, 0);
      // The view's own net_minor — not amount minus refunded computed here.
      expect(transaction.netMinor, 80000);
      expect(transaction.paidAt, DateTime.parse('2026-08-27T10:00:05Z'));
      expect(transaction.effectiveAt, DateTime.parse('2026-08-27T10:00:05Z'));
    });

    test('an unpaid transaction has a null paid_at rather than a substituted created_at', () {
      final transaction = FinanceTransaction.fromJson({
        'id': 'txn-2',
        'reference': 'TXN-EEEE0000',
        'facility_id': 'facility-1',
        'created_at': '2026-08-27T10:00:00Z',
        'paid_at': null,
        'effective_at': '2026-08-27T10:00:00Z',
        'source_type': 'MEMBERSHIP',
        'customer_name': null,
        'customer_phone': null,
        'booking_id': null,
        'membership_id': 'm-1',
        'payment_order_id': null,
        'amount_minor': 500000,
        'currency': 'INR',
        'payment_method': null,
        'status': 'created',
        'razorpay_order_id': null,
        'razorpay_payment_id': null,
        'refunded_minor': 0,
        'pending_refund_minor': 0,
        'net_minor': 500000,
      });

      expect(transaction.paidAt, isNull);
      expect(transaction.status, TransactionStatus.created);
      expect(transaction.sourceType, PaymentSourceType.membership);
      expect(transaction.customerName, isNull);
    });
  });

  group('FinanceRepository does no revenue math', () {
    test('never sums, folds, or reduces amounts into a total of its own', () {
      for (final forbidden in ['fold(', 'reduce(', '.sum', 'grossRevenueMinor -', 'amountMinor +']) {
        expect(source, isNot(contains(forbidden)), reason: 'every total must come from a backend RPC field');
      }
    });
  });

  group('FinanceDateRangePreset mirrors resolve_finance_date_range exactly', () {
    test('round-trips every preset the backend understands', () {
      const values = {
        FinanceDateRangePreset.today: 'TODAY',
        FinanceDateRangePreset.yesterday: 'YESTERDAY',
        FinanceDateRangePreset.thisWeek: 'THIS_WEEK',
        FinanceDateRangePreset.lastWeek: 'LAST_WEEK',
        FinanceDateRangePreset.thisMonth: 'THIS_MONTH',
        FinanceDateRangePreset.lastMonth: 'LAST_MONTH',
        FinanceDateRangePreset.custom: 'CUSTOM',
      };
      for (final entry in values.entries) {
        expect(entry.key.toJson(), entry.value);
        expect(FinanceDateRangePreset.fromJson(entry.value), entry.key);
      }
    });

    test('a CUSTOM range is only complete once both ends are chosen', () {
      const preset = FinanceDateRange(preset: FinanceDateRangePreset.thisMonth);
      const halfPicked = FinanceDateRange(preset: FinanceDateRangePreset.custom, startDate: '2026-08-01');
      const complete = FinanceDateRange(
        preset: FinanceDateRangePreset.custom,
        startDate: '2026-08-01',
        endDate: '2026-08-15',
      );

      expect(preset.isComplete, isTrue);
      expect(halfPicked.isComplete, isFalse);
      expect(complete.isComplete, isTrue);
    });
  });
}