import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/finance.dart';

/// Finance & Revenue Management — Phase 7 port, extended by the Phase 8+
/// finance rework. Mirrors src/services/finance/supabase-finance.service.ts.
///
/// This repository is a read layer over the finance aggregation RPCs (0024
/// onward: `get_finance_summary`, `get_revenue_breakdown`,
/// `get_revenue_trend`, `list_finance_transactions` /
/// `count_finance_transactions`, `get_finance_transaction`), plus the small
/// set of owner-entered writes finance genuinely needs — recording an expense
/// (`create_expense`), voiding one (`void_expense`), and, from Phase 11,
/// recording a payment against an obligation. Income is never written here: it
/// always arrives as a payment against a booking or membership, which is what
/// keeps the ledger traceable. Finance is NOT a new ledger — `payments`,
/// `refunds` and now `expenses` remain the source of truth, and every total
/// this class returns was computed by the server.
///
/// The one rule this file exists to enforce on the client side: **it never
/// does revenue math**. There is no method here that sums a transaction list
/// into a headline figure, and none of the callers can, because the only
/// totals available to them are RPC response fields (spec §"Core Finance
/// Principle" / §"Backend Aggregation" / §"Critical Final Rule").
///
/// Date ranges are likewise never resolved here: the client sends a preset
/// name (plus explicit dates for CUSTOM) and `resolve_finance_date_range`
/// turns it into real timestamps in the FACILITY's configured timezone —
/// a device clock set to another timezone can't shift what "Today" means.
class FinanceRepository {
  FinanceRepository(this._client);

  final SupabaseClient _client;

  /// The three date arguments every Finance RPC shares, built the same way
  /// for all of them so a summary, a breakdown, a trend and a transaction
  /// page for one range can never silently disagree about which range that
  /// is. Mirrors the web service's `dateRangeArgs` helper.
  Map<String, dynamic> _dateRangeArgs(FinanceDateRange dateRange) {
    return {
      'p_preset': dateRange.preset.toJson(),
      'p_start_date': dateRange.startDate,
      'p_end_date': dateRange.endDate,
    };
  }

  /// Mirrors the web service's `mapError`. A facility-isolation rejection is
  /// deliberately its own code rather than folding into a generic failure:
  /// the UI must show an explicit denial, never a fabricated ₹0 summary
  /// (spec §"Critical Facility Isolation Test" — "Expected: DENIED").
  AppException _mapError(Object error) {
    if (error is AppException) return error;
    final message = error is PostgrestException ? error.message : error.toString();
    if (message.contains('Not authorized')) return AppException(AppErrorCode.financeAccessDenied);
    if (message.contains('valid start and end date')) return AppException(AppErrorCode.invalidDateRange);
    return AppException(AppErrorCode.financeDataError);
  }

  /// `returns table (...)` RPCs come back as a list of rows; these single-row
  /// aggregates always have exactly one. An empty result means the call did
  /// not produce the summary it promised, which is an error rather than
  /// something to paper over with zeros.
  Map<String, dynamic> _firstRow(dynamic data) {
    if (data is List && data.isNotEmpty) {
      return (data.first as Map).cast<String, dynamic>();
    }
    throw AppException(AppErrorCode.financeDataError);
  }

  /// The dashboard's headline numbers — backend-aggregated, never summed
  /// from a paginated list.
  Future<FinanceSummary> getSummary(String facilityId, FinanceDateRange dateRange) async {
    try {
      final data = await _client.rpc(
        'get_finance_summary',
        params: {'p_facility_id': facilityId, ..._dateRangeArgs(dateRange)},
      );
      return FinanceSummary.fromJson(_firstRow(data));
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<RevenueBreakdown> getRevenueBreakdown(String facilityId, FinanceDateRange dateRange) async {
    try {
      final data = await _client.rpc(
        'get_revenue_breakdown',
        params: {'p_facility_id': facilityId, ..._dateRangeArgs(dateRange)},
      );
      return RevenueBreakdown.fromJson(_firstRow(data));
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// The chart's only data source. An empty range returns an empty list —
  /// never a fabricated set of zero points, which would draw a flat line
  /// that looks like real "no revenue" data for days the server never
  /// reported on.
  Future<List<RevenueTrendPoint>> getRevenueTrend(
    String facilityId,
    FinanceDateRange dateRange,
    RevenueTrendGranularity granularity,
  ) async {
    try {
      final rows = await _client.rpc(
        'get_revenue_trend',
        params: {
          'p_facility_id': facilityId,
          ..._dateRangeArgs(dateRange),
          'p_granularity': granularity.toJson(),
        },
      );
      return (rows as List<dynamic>)
          .map((row) => RevenueTrendPoint.fromJson((row as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// Server-side filtered, searched, and paginated. The page and its total
  /// count are fetched in parallel from two RPCs that share identical filter
  /// logic by construction, so the count can never disagree with the page —
  /// and the total is the server's `count(*)`, never `transactions.length`.
  Future<TransactionPage> listTransactions(ListTransactionsInput input) async {
    final args = {
      'p_facility_id': input.facilityId,
      ..._dateRangeArgs(input.dateRange),
      'p_source_type': input.sourceType?.toJson(),
      'p_status': input.status?.toJson(),
      'p_search': input.search,
    };
    try {
      final results = await Future.wait([
        _client.rpc(
          'list_finance_transactions',
          params: {...args, 'p_limit': input.limit ?? 20, 'p_offset': input.offset ?? 0},
        ),
        _client.rpc('count_finance_transactions', params: args),
      ]);
      final transactions = (results[0] as List<dynamic>)
          .map((row) => FinanceTransaction.fromJson((row as Map).cast<String, dynamic>()))
          .toList();
      return TransactionPage(
        transactions: transactions,
        totalCount: (results[1] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// The Transaction Details view's single read — full Razorpay traceability
  /// (transaction → payment order → Razorpay order/payment → booking or
  /// membership). A cross-facility lookup is denied by the RPC itself, not
  /// silently returned as empty.
  Future<FinanceTransaction> getTransaction(String transactionId) async {
    try {
      final data = await _client.rpc(
        'get_finance_transaction',
        params: {'p_transaction_id': transactionId},
      );
      if (data == null) throw AppException(AppErrorCode.financeDataError);
      return FinanceTransaction.fromJson((data as Map).cast<String, dynamic>());
    } catch (e) {
      throw _mapError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 8 — Expenses (the outgoing side).
  // Backend: supabase/migrations/0046_finance_expenses.sql.
  // ─────────────────────────────────────────────────────────────────────────

  /// The categories an expense can be filed under: the shared defaults (null
  /// `facility_id`) plus this facility's own. Read straight off the table —
  /// RLS decides which rows come back, exactly like the web service. Mirrors
  /// `SupabaseFinanceService.listExpenseCategories`.
  Future<List<ExpenseCategory>> listExpenseCategories(String facilityId) async {
    try {
      final rows = await _client
          .from('expense_categories')
          .select('id, name')
          .eq('is_active', true)
          .or('facility_id.is.null,facility_id.eq.$facilityId')
          .order('sort_order');
      return (rows as List<dynamic>)
          .map((row) => ExpenseCategory.fromJson((row as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// Expenses for a range, newest first, server-paginated. The page total is
  /// `list_expenses`' own `count(*) over ()` carried on every row — never the
  /// length of the page just fetched.
  Future<ExpensePage> listExpenses(ListExpensesInput input) async {
    try {
      final rows = await _client.rpc(
        'list_expenses',
        params: {
          'p_facility_id': input.facilityId,
          ..._dateRangeArgs(input.dateRange),
          'p_category_id': input.categoryId,
          'p_limit': input.limit ?? 25,
          'p_offset': input.offset ?? 0,
        },
      );
      return ExpensePage.fromRows(
        (rows as List<dynamic>).map((row) => (row as Map).cast<String, dynamic>()).toList(),
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// Records an expense. [amountMinor] is already in minor units — the caller
  /// converts from rupees, the repository passes it straight through and does
  /// no money arithmetic of its own. Requires an owner/manager role; the RPC
  /// enforces that and the category's facility scope.
  Future<void> createExpense({
    required String facilityId,
    required String categoryId,
    required int amountMinor,
    required String spentOn,
    String? paymentMethod,
    String? vendor,
    String? reference,
    String? notes,
  }) async {
    try {
      await _client.rpc(
        'create_expense',
        params: {
          'p_facility_id': facilityId,
          'p_category_id': categoryId,
          'p_amount_minor': amountMinor,
          'p_spent_on': spentOn,
          'p_payment_method': paymentMethod,
          'p_vendor': vendor,
          'p_reference': reference,
          'p_notes': notes,
        },
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// Voids an expense — never a delete. The row stays, marked `VOID` with who
  /// did it and an optional reason, so the books can still be explained.
  Future<void> voidExpense(String expenseId, {String? reason}) async {
    try {
      await _client.rpc(
        'void_expense',
        params: {'p_expense_id': expenseId, 'p_reason': reason},
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 9 — one ledger for the Transactions page.
  // Backend: supabase/migrations/0049_finance_ledger.sql.
  // ─────────────────────────────────────────────────────────────────────────

  /// Payments, refunds and expenses in one server-paged list. `list_finance_
  /// ledger` unions all three and filters/pages across them — the client never
  /// stitches three lists together. The page total is the RPC's own
  /// `count(*) over ()`, carried on every row.
  Future<LedgerPage> listLedger(ListLedgerInput input) async {
    final f = input.filters;
    try {
      final rows = await _client.rpc(
        'list_finance_ledger',
        params: {
          'p_facility_id': input.facilityId,
          ..._dateRangeArgs(input.dateRange),
          'p_txn_type': f.txnType?.toJson(),
          'p_category': f.category,
          'p_payment_method': f.paymentMethod,
          'p_status': f.status,
          'p_search': (f.search != null && f.search!.trim().isNotEmpty) ? f.search!.trim() : null,
          'p_limit': input.limit ?? 10,
          'p_offset': input.offset ?? 0,
        },
      );
      return LedgerPage.fromRows(
        (rows as List<dynamic>).map((row) => (row as Map).cast<String, dynamic>()).toList(),
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// The distinct payment methods actually present in this facility's payments
  /// and expenses — so the Transactions filter offers what exists, not a
  /// hardcoded list. Mirrors `SupabaseFinanceService.listPaymentMethods`.
  Future<List<String>> listPaymentMethods(String facilityId) async {
    try {
      final rows = await _client.rpc(
        'list_finance_payment_methods',
        params: {'p_facility_id': facilityId},
      );
      return (rows as List<dynamic>)
          .map((row) => (row as Map)['payment_method'] as String)
          .toList();
    } catch (e) {
      throw _mapError(e);
    }
  }
}