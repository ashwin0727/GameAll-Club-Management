/// Finance & Revenue Management — Phase 7 port.
///
/// Mirrors src/features/finance/types.ts 1:1. Every figure in this file is
/// server-computed (supabase/migrations/0024_finance.sql) — these classes only
/// ever describe the SHAPE of what the backend returns. Nothing here computes,
/// sums, or derives a monetary total (spec §"Core Finance Principle" /
/// §"Critical Final Rule"), which is why there is deliberately no
/// `grossMinor - refundsMinor` convenience getter anywhere below: net revenue
/// is a field the server sends, never arithmetic the client performs.
library;

import 'payment.dart';

/// Every preset `resolve_finance_date_range` understands. The client only ever
/// picks one of these (or CUSTOM plus explicit dates) — it never computes
/// "today"/"this week" boundaries itself, because those are resolved against
/// the FACILITY's configured timezone on the server, not the device clock
/// (spec §"Date Range" / §"Date/Time").
enum FinanceDateRangePreset {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  custom;

  String toJson() {
    switch (this) {
      case FinanceDateRangePreset.today:
        return 'TODAY';
      case FinanceDateRangePreset.yesterday:
        return 'YESTERDAY';
      case FinanceDateRangePreset.thisWeek:
        return 'THIS_WEEK';
      case FinanceDateRangePreset.lastWeek:
        return 'LAST_WEEK';
      case FinanceDateRangePreset.thisMonth:
        return 'THIS_MONTH';
      case FinanceDateRangePreset.lastMonth:
        return 'LAST_MONTH';
      case FinanceDateRangePreset.custom:
        return 'CUSTOM';
    }
  }

  static FinanceDateRangePreset fromJson(String value) {
    switch (value) {
      case 'TODAY':
        return FinanceDateRangePreset.today;
      case 'YESTERDAY':
        return FinanceDateRangePreset.yesterday;
      case 'THIS_WEEK':
        return FinanceDateRangePreset.thisWeek;
      case 'LAST_WEEK':
        return FinanceDateRangePreset.lastWeek;
      case 'THIS_MONTH':
        return FinanceDateRangePreset.thisMonth;
      case 'LAST_MONTH':
        return FinanceDateRangePreset.lastMonth;
      case 'CUSTOM':
        return FinanceDateRangePreset.custom;
      default:
        throw ArgumentError('Unknown FinanceDateRangePreset: $value');
    }
  }

  /// Display label — mirrors PRESET_LABELS in date-range-picker.tsx.
  String get label {
    switch (this) {
      case FinanceDateRangePreset.today:
        return 'Today';
      case FinanceDateRangePreset.yesterday:
        return 'Yesterday';
      case FinanceDateRangePreset.thisWeek:
        return 'This Week';
      case FinanceDateRangePreset.lastWeek:
        return 'Last Week';
      case FinanceDateRangePreset.thisMonth:
        return 'This Month';
      case FinanceDateRangePreset.lastMonth:
        return 'Last Month';
      case FinanceDateRangePreset.custom:
        return 'Custom Range';
    }
  }
}

/// [startDate]/[endDate] are `yyyy-MM-dd` strings (Postgres `date` literals) —
/// required, and only used, when [preset] is CUSTOM.
class FinanceDateRange {
  const FinanceDateRange({required this.preset, this.startDate, this.endDate});

  final FinanceDateRangePreset preset;
  final String? startDate;
  final String? endDate;

  /// A CUSTOM range with a missing end of the range is not yet askable —
  /// the server would reject it with "valid start and end date". Callers use
  /// this to hold off the fetch while the owner is still picking dates,
  /// exactly like the web dashboard's `if (preset === "CUSTOM" && ...) return`.
  bool get isComplete =>
      preset != FinanceDateRangePreset.custom || (startDate != null && endDate != null);

  FinanceDateRange copyWith({
    FinanceDateRangePreset? preset,
    String? startDate,
    String? endDate,
  }) {
    return FinanceDateRange(
      preset: preset ?? this.preset,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FinanceDateRange &&
      other.preset == preset &&
      other.startDate == startDate &&
      other.endDate == endDate;

  @override
  int get hashCode => Object.hash(preset, startDate, endDate);
}

/// The dashboard's headline numbers, straight off `get_finance_summary`.
///
/// [pendingRefundCount] and [settlementExceptionCount] are deliberately NOT
/// date-filtered by the backend — they're a current, actionable queue ("what
/// needs my attention right now"), not a historical figure for the selected
/// range (spec §"Dashboard Metrics").
class FinanceSummary {
  const FinanceSummary({
    required this.grossRevenueMinor,
    required this.refundsMinor,
    required this.expensesMinor,
    required this.netRevenueMinor,
    required this.outstandingMinor,
    required this.transactionCount,
    required this.successfulPaymentCount,
    required this.failedPaymentCount,
    required this.pendingPaymentCount,
    required this.pendingRefundCount,
    required this.settlementExceptionCount,
  });

  final int grossRevenueMinor;
  final int refundsMinor;

  /// What the facility spent in the range — recorded expenses, voids excluded
  /// (migration 0046). Absent on a pre-0046 row, in which case it reads 0.
  final int expensesMinor;

  /// Gross, less refunds, less expenses — the server's own figure.
  final int netRevenueMinor;

  /// Money owed on bookings and memberships that have not been paid for.
  /// Absent on a pre-0046 row, in which case it reads 0.
  final int outstandingMinor;
  final int transactionCount;
  final int successfulPaymentCount;
  final int failedPaymentCount;
  final int pendingPaymentCount;
  final int pendingRefundCount;
  final int settlementExceptionCount;

  factory FinanceSummary.fromJson(Map<String, dynamic> json) {
    return FinanceSummary(
      grossRevenueMinor: (json['gross_revenue_minor'] as num).toInt(),
      refundsMinor: (json['refunds_minor'] as num).toInt(),
      expensesMinor: (json['expenses_minor'] as num?)?.toInt() ?? 0,
      netRevenueMinor: (json['net_revenue_minor'] as num).toInt(),
      outstandingMinor: (json['outstanding_minor'] as num?)?.toInt() ?? 0,
      transactionCount: (json['transaction_count'] as num).toInt(),
      successfulPaymentCount: (json['successful_payment_count'] as num).toInt(),
      failedPaymentCount: (json['failed_payment_count'] as num).toInt(),
      pendingPaymentCount: (json['pending_payment_count'] as num).toInt(),
      pendingRefundCount: (json['pending_refund_count'] as num).toInt(),
      settlementExceptionCount: (json['settlement_exception_count'] as num).toInt(),
    );
  }
}

/// One payment method's share of captured revenue in the selected range —
/// straight off `get_payment_method_breakdown` (0047), never summed from a
/// transaction list.
class PaymentMethodSlice {
  const PaymentMethodSlice({
    required this.paymentMethod,
    required this.amountMinor,
    required this.paymentCount,
  });

  final String paymentMethod;
  final int amountMinor;
  final int paymentCount;

  factory PaymentMethodSlice.fromJson(Map<String, dynamic> json) {
    return PaymentMethodSlice(
      paymentMethod: json['payment_method'] as String,
      amountMinor: (json['amount_minor'] as num).toInt(),
      paymentCount: (json['payment_count'] as num).toInt(),
    );
  }
}

/// Revenue by source, straight off `get_revenue_breakdown`.
///
/// [membershipIncludedUsageCount] is a volume/operational figure, never
/// revenue — a member's included session has no `payments` row at all
/// (spec §"Membership Included Usage").
class RevenueBreakdown {
  const RevenueBreakdown({
    required this.membershipRevenueMinor,
    required this.memberBookingRevenueMinor,
    required this.guestBookingRevenueMinor,
    required this.refundsMinor,
    required this.netRevenueMinor,
    required this.membershipIncludedUsageCount,
  });

  final int membershipRevenueMinor;
  final int memberBookingRevenueMinor;
  final int guestBookingRevenueMinor;
  final int refundsMinor;
  final int netRevenueMinor;
  final int membershipIncludedUsageCount;

  factory RevenueBreakdown.fromJson(Map<String, dynamic> json) {
    return RevenueBreakdown(
      membershipRevenueMinor: (json['membership_revenue_minor'] as num).toInt(),
      memberBookingRevenueMinor: (json['member_booking_revenue_minor'] as num).toInt(),
      guestBookingRevenueMinor: (json['guest_booking_revenue_minor'] as num).toInt(),
      refundsMinor: (json['refunds_minor'] as num).toInt(),
      netRevenueMinor: (json['net_revenue_minor'] as num).toInt(),
      membershipIncludedUsageCount: (json['membership_included_usage_count'] as num).toInt(),
    );
  }
}

enum RevenueTrendGranularity {
  daily,
  weekly,
  monthly;

  /// Lowercase on the wire — `get_revenue_trend` raises on anything else.
  String toJson() => name;

  static RevenueTrendGranularity fromJson(String value) {
    switch (value) {
      case 'daily':
        return RevenueTrendGranularity.daily;
      case 'weekly':
        return RevenueTrendGranularity.weekly;
      case 'monthly':
        return RevenueTrendGranularity.monthly;
      default:
        throw ArgumentError('Unknown RevenueTrendGranularity: $value');
    }
  }
}

/// One bucket of the revenue trend. [date] is the bucket's `yyyy-MM-dd`
/// start, already truncated in the facility's own timezone by the server.
class RevenueTrendPoint {
  const RevenueTrendPoint({
    required this.date,
    required this.grossMinor,
    required this.refundMinor,
    required this.netMinor,
  });

  final String date;
  final int grossMinor;
  final int refundMinor;
  final int netMinor;

  factory RevenueTrendPoint.fromJson(Map<String, dynamic> json) {
    return RevenueTrendPoint(
      date: json['bucket_date'] as String,
      grossMinor: (json['gross_minor'] as num).toInt(),
      refundMinor: (json['refund_minor'] as num).toInt(),
      netMinor: (json['net_minor'] as num).toInt(),
    );
  }
}

/// Mirrors `payments.status` as exposed by `finance_transactions_view`.
/// Lowercase on the wire — these are the DB enum's literal values.
enum TransactionStatus {
  created,
  paid,
  failed,
  refunded;

  String toJson() => name;

  static TransactionStatus fromJson(String value) {
    switch (value) {
      case 'created':
        return TransactionStatus.created;
      case 'paid':
        return TransactionStatus.paid;
      case 'failed':
        return TransactionStatus.failed;
      case 'refunded':
        return TransactionStatus.refunded;
      default:
        throw ArgumentError('Unknown TransactionStatus: $value');
    }
  }
}

/// One enriched row of `finance_transactions_view`.
///
/// Every money field is in minor units (paise) — the view normalizes
/// `payments.amount_inr` (whole rupees) to minor units so Finance is
/// internally consistent with payment_orders/refunds. [netMinor] and
/// [refundedMinor] are computed by the view, not by this client.
class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.reference,
    required this.facilityId,
    required this.createdAt,
    required this.paidAt,
    required this.effectiveAt,
    required this.sourceType,
    required this.customerName,
    required this.customerPhone,
    required this.bookingId,
    required this.membershipId,
    required this.paymentOrderId,
    required this.amountMinor,
    required this.currency,
    required this.paymentMethod,
    required this.status,
    required this.razorpayOrderId,
    required this.razorpayPaymentId,
    required this.refundedMinor,
    required this.pendingRefundMinor,
    required this.netMinor,
  });

  final String id;
  final String reference;
  final String facilityId;
  final DateTime createdAt;
  final DateTime? paidAt;
  final DateTime effectiveAt;
  final PaymentSourceType sourceType;
  final String? customerName;
  final String? customerPhone;
  final String? bookingId;
  final String? membershipId;
  final String? paymentOrderId;
  final int amountMinor;
  final String currency;
  final String? paymentMethod;
  final TransactionStatus status;
  final String? razorpayOrderId;
  final String? razorpayPaymentId;
  final int refundedMinor;
  final int pendingRefundMinor;
  final int netMinor;

  factory FinanceTransaction.fromJson(Map<String, dynamic> json) {
    return FinanceTransaction(
      id: json['id'] as String,
      reference: json['reference'] as String,
      facilityId: json['facility_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      paidAt: json['paid_at'] == null ? null : DateTime.parse(json['paid_at'] as String),
      effectiveAt: DateTime.parse(json['effective_at'] as String),
      sourceType: PaymentSourceType.fromJson(json['source_type'] as String),
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      bookingId: json['booking_id'] as String?,
      membershipId: json['membership_id'] as String?,
      paymentOrderId: json['payment_order_id'] as String?,
      amountMinor: (json['amount_minor'] as num).toInt(),
      currency: json['currency'] as String,
      paymentMethod: json['payment_method'] as String?,
      status: TransactionStatus.fromJson(json['status'] as String),
      razorpayOrderId: json['razorpay_order_id'] as String?,
      razorpayPaymentId: json['razorpay_payment_id'] as String?,
      refundedMinor: (json['refunded_minor'] as num).toInt(),
      pendingRefundMinor: (json['pending_refund_minor'] as num).toInt(),
      netMinor: (json['net_minor'] as num).toInt(),
    );
  }
}

/// Server-side filters — every one of these is applied inside
/// `list_finance_transactions`/`count_finance_transactions`, never by
/// filtering an already-fetched list (spec §"Transaction Pagination").
class TransactionFilters {
  const TransactionFilters({this.sourceType, this.status, this.search});

  final PaymentSourceType? sourceType;
  final TransactionStatus? status;
  final String? search;
}

class ListTransactionsInput {
  const ListTransactionsInput({
    required this.facilityId,
    required this.dateRange,
    this.sourceType,
    this.status,
    this.search,
    this.limit,
    this.offset,
  });

  final String facilityId;
  final FinanceDateRange dateRange;
  final PaymentSourceType? sourceType;
  final TransactionStatus? status;
  final String? search;
  final int? limit;
  final int? offset;
}

/// [totalCount] is `count_finance_transactions`' own answer for the SAME
/// filters — never `transactions.length`, which is only the current page.
class TransactionPage {
  const TransactionPage({required this.transactions, required this.totalCount});

  final List<FinanceTransaction> transactions;
  final int totalCount;
}

// ═══════════════════════════════════════════════════════════════════════════
// Finance rework — Phase 8: the outgoing side (Expenses).
//
// Mirrors src/features/finance/types.ts (`ExpenseCategory` / `ExpenseRow` /
// `ExpensePage`). Backend: supabase/migrations/0046_finance_expenses.sql.
// Income is never typed in by hand — it always arrives as a payment against a
// booking or membership. An expense is the one transaction an owner records
// directly, which is why it has its own small write path.
// ═══════════════════════════════════════════════════════════════════════════

/// One row of `expense_categories` a facility may file an expense under —
/// either a shared default (null `facility_id`) or the facility's own.
class ExpenseCategory {
  const ExpenseCategory({required this.id, required this.name});

  final String id;
  final String name;

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }
}

/// One row of `list_expenses`. [amountMinor] is minor units, like every other
/// amount in the ledger. [spentOn] is a `yyyy-MM-dd` date string (Postgres
/// `date`), not a timestamp — an expense is filed against a day, not an
/// instant. [status] is the backend's own vocabulary (`RECORDED` / `VOID`)
/// verbatim; a voided expense is never removed, only marked.
class ExpenseRow {
  const ExpenseRow({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.amountMinor,
    required this.currency,
    required this.paymentMethod,
    required this.spentOn,
    required this.vendor,
    required this.reference,
    required this.notes,
    required this.status,
  });

  final String id;
  final String categoryId;
  final String categoryName;
  final int amountMinor;
  final String currency;
  final String? paymentMethod;
  final String spentOn;
  final String? vendor;
  final String? reference;
  final String? notes;
  final String status;

  bool get isVoid => status == 'VOID';

  factory ExpenseRow.fromJson(Map<String, dynamic> json) {
    return ExpenseRow(
      id: json['id'] as String,
      categoryId: json['category_id'] as String,
      categoryName: json['category_name'] as String,
      amountMinor: (json['amount_minor'] as num).toInt(),
      currency: json['currency'] as String,
      paymentMethod: json['payment_method'] as String?,
      spentOn: json['spent_on'] as String,
      vendor: json['vendor'] as String?,
      reference: json['reference'] as String?,
      notes: json['notes'] as String?,
      status: json['status'] as String,
    );
  }
}

/// A page of expenses plus the server's own count for the same filters.
/// [totalCount] is `list_expenses`' in-row `total_count` (a window count over
/// the full match, `count(*) over ()`), never `expenses.length`.
class ExpensePage {
  const ExpensePage({required this.expenses, required this.totalCount});

  final List<ExpenseRow> expenses;
  final int totalCount;

  /// `list_expenses` returns each row with a `total_count` column repeated on
  /// every row; an empty result therefore has no count row and means zero.
  factory ExpensePage.fromRows(List<Map<String, dynamic>> rows) {
    return ExpensePage(
      expenses: rows.map(ExpenseRow.fromJson).toList(),
      totalCount: rows.isEmpty ? 0 : (rows.first['total_count'] as num).toInt(),
    );
  }
}

/// The arguments `list_expenses` takes, kept together so a page and its count
/// can never be requested for different filters.
class ListExpensesInput {
  const ListExpensesInput({
    required this.facilityId,
    required this.dateRange,
    this.categoryId,
    this.limit,
    this.offset,
  });

  final String facilityId;
  final FinanceDateRange dateRange;
  final String? categoryId;
  final int? limit;
  final int? offset;
}

// ═══════════════════════════════════════════════════════════════════════════
// Finance rework — Phase 9: one ledger for the Transactions page.
//
// Mirrors src/features/finance/types.ts (`LedgerEntry` / `LedgerTxnType` /
// `LedgerFilters` / `LedgerPage`). Backend: 0049_finance_ledger.sql reads
// payments, refunds and expenses into one shape — this is NOT a ledger table,
// the three underlying records stay authoritative.
// ═══════════════════════════════════════════════════════════════════════════

/// Which side of the books a ledger line is. Uppercase on the wire — these are
/// exactly the values `list_finance_ledger` emits and filters on.
enum LedgerTxnType {
  income,
  expense,
  refund;

  String toJson() {
    switch (this) {
      case LedgerTxnType.income:
        return 'INCOME';
      case LedgerTxnType.expense:
        return 'EXPENSE';
      case LedgerTxnType.refund:
        return 'REFUND';
    }
  }

  static LedgerTxnType fromJson(String value) {
    switch (value) {
      case 'INCOME':
        return LedgerTxnType.income;
      case 'EXPENSE':
        return LedgerTxnType.expense;
      case 'REFUND':
        return LedgerTxnType.refund;
      default:
        throw ArgumentError('Unknown LedgerTxnType: $value');
    }
  }

  /// Title-cased for a filter menu ("Income").
  String get label => toJson()[0] + toJson().substring(1).toLowerCase();
}

/// One line of financial activity — a payment, a refund, or an expense —
/// already shaped and described by `list_finance_ledger`. [amountMinor] is the
/// magnitude only; whether it adds to or subtracts from the books is
/// [txnType], never inferred from a sign here. [description] and [category]
/// are the server's words, rendered as-is.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.reference,
    required this.occurredAt,
    required this.description,
    required this.category,
    required this.txnType,
    required this.paymentMethod,
    required this.amountMinor,
    required this.currency,
    required this.status,
    required this.sourceType,
    required this.bookingId,
    required this.membershipId,
    required this.expenseId,
  });

  final String id;
  final String reference;
  final DateTime occurredAt;
  final String description;
  final String category;
  final LedgerTxnType txnType;
  final String? paymentMethod;
  final int amountMinor;
  final String currency;
  final String status;
  final String sourceType;
  final String? bookingId;
  final String? membershipId;
  final String? expenseId;

  /// Only a payment has a Transaction Details page — an expense and a refund
  /// are the row already in view.
  bool get isIncome => txnType == LedgerTxnType.income;

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    return LedgerEntry(
      id: json['id'] as String,
      reference: json['reference'] as String,
      occurredAt: DateTime.parse(json['occurred_at'] as String),
      description: json['description'] as String,
      category: json['category'] as String,
      txnType: LedgerTxnType.fromJson(json['txn_type'] as String),
      paymentMethod: json['payment_method'] as String?,
      amountMinor: (json['amount_minor'] as num).toInt(),
      currency: json['currency'] as String,
      status: json['status'] as String,
      sourceType: json['source_type'] as String,
      bookingId: json['booking_id'] as String?,
      membershipId: json['membership_id'] as String?,
      expenseId: json['expense_id'] as String?,
    );
  }
}

/// Server-side ledger filters — every one is applied inside
/// `list_finance_ledger`, never by filtering an already-fetched list.
class LedgerFilters {
  const LedgerFilters({
    this.txnType,
    this.category,
    this.paymentMethod,
    this.status,
    this.search,
  });

  final LedgerTxnType? txnType;
  final String? category;
  final String? paymentMethod;
  final String? status;
  final String? search;
}

/// A page of ledger entries plus the server's own count for the same filters —
/// `list_finance_ledger`'s in-row `total_count` (`count(*) over ()`), never
/// `entries.length`.
class LedgerPage {
  const LedgerPage({required this.entries, required this.totalCount});

  final List<LedgerEntry> entries;
  final int totalCount;

  factory LedgerPage.fromRows(List<Map<String, dynamic>> rows) {
    return LedgerPage(
      entries: rows.map(LedgerEntry.fromJson).toList(),
      totalCount: rows.isEmpty ? 0 : (rows.first['total_count'] as num).toInt(),
    );
  }
}

/// The arguments `list_finance_ledger` takes, kept together.
class ListLedgerInput {
  const ListLedgerInput({
    required this.facilityId,
    required this.dateRange,
    this.filters = const LedgerFilters(),
    this.limit,
    this.offset,
  });

  final String facilityId;
  final FinanceDateRange dateRange;
  final LedgerFilters filters;
  final int? limit;
  final int? offset;
}

// ═══════════════════════════════════════════════════════════════════════════
// Finance rework — Phase 10: Pending Payments.
//
// Mirrors src/features/finance/types.ts. Backend:
// 0052_pending_payments.sql + 0053_pending_payment_lookup.sql. Money still
// owed on one booking or membership, derived in the database from what the
// thing costs and what has been collected against it — never stored, so it
// cannot drift from the payments it is computed from.
// ═══════════════════════════════════════════════════════════════════════════

/// What an obligation is owed against. Distinct from [PaymentSourceType]
/// (`MEMBERSHIP` / `MEMBER_BOOKING` / `GUEST_BOOKING`) — the ledger and
/// obligations split bookings by customer, not by member-vs-guest pricing.
enum ObligationSource {
  guestBooking,
  booking,
  membership;

  String toJson() {
    switch (this) {
      case ObligationSource.guestBooking:
        return 'GUEST_BOOKING';
      case ObligationSource.booking:
        return 'BOOKING';
      case ObligationSource.membership:
        return 'MEMBERSHIP';
    }
  }

  static ObligationSource fromJson(String value) {
    switch (value) {
      case 'GUEST_BOOKING':
        return ObligationSource.guestBooking;
      case 'BOOKING':
        return ObligationSource.booking;
      case 'MEMBERSHIP':
        return ObligationSource.membership;
      default:
        throw ArgumentError('Unknown ObligationSource: $value');
    }
  }

  String get label {
    switch (this) {
      case ObligationSource.guestBooking:
        return 'Guest Booking';
      case ObligationSource.booking:
        return 'Court Booking';
      case ObligationSource.membership:
        return 'Membership';
    }
  }
}

/// How an obligation reads — server-derived. `OVERDUE` is a view of unpaid
/// debt whose due date has passed, not a state stored anywhere.
enum ObligationStatus {
  pending,
  partiallyPaid,
  overdue,
  paid;

  String toJson() {
    switch (this) {
      case ObligationStatus.pending:
        return 'PENDING';
      case ObligationStatus.partiallyPaid:
        return 'PARTIALLY_PAID';
      case ObligationStatus.overdue:
        return 'OVERDUE';
      case ObligationStatus.paid:
        return 'PAID';
    }
  }

  static ObligationStatus fromJson(String value) {
    switch (value) {
      case 'PENDING':
        return ObligationStatus.pending;
      case 'PARTIALLY_PAID':
        return ObligationStatus.partiallyPaid;
      case 'OVERDUE':
        return ObligationStatus.overdue;
      case 'PAID':
        return ObligationStatus.paid;
      default:
        throw ArgumentError('Unknown ObligationStatus: $value');
    }
  }

  String get label {
    switch (this) {
      case ObligationStatus.pending:
        return 'Pending';
      case ObligationStatus.partiallyPaid:
        return 'Partially Paid';
      case ObligationStatus.overdue:
        return 'Overdue';
      case ObligationStatus.paid:
        return 'Paid';
    }
  }
}

/// Sort order for the Pending Payments list — exactly the values
/// `list_pending_payments`' `p_sort` understands.
enum ObligationSort {
  dueDate,
  amount,
  customer,
  newest;

  String toJson() {
    switch (this) {
      case ObligationSort.dueDate:
        return 'DUE_DATE';
      case ObligationSort.amount:
        return 'AMOUNT';
      case ObligationSort.customer:
        return 'CUSTOMER';
      case ObligationSort.newest:
        return 'NEWEST';
    }
  }

  String get label {
    switch (this) {
      case ObligationSort.dueDate:
        return 'Oldest first';
      case ObligationSort.amount:
        return 'Largest';
      case ObligationSort.customer:
        return 'Customer';
      case ObligationSort.newest:
        return 'Newest';
    }
  }
}

/// The Pending Payments status filter. `ALL_OUTSTANDING` (the default) is
/// everything not fully paid — a filter value, not one of the four states an
/// individual obligation can be in.
enum PendingPaymentStatusFilter {
  allOutstanding,
  pending,
  partiallyPaid,
  overdue,
  paid;

  String toJson() {
    switch (this) {
      case PendingPaymentStatusFilter.allOutstanding:
        return 'ALL_OUTSTANDING';
      case PendingPaymentStatusFilter.pending:
        return 'PENDING';
      case PendingPaymentStatusFilter.partiallyPaid:
        return 'PARTIALLY_PAID';
      case PendingPaymentStatusFilter.overdue:
        return 'OVERDUE';
      case PendingPaymentStatusFilter.paid:
        return 'PAID';
    }
  }

  String get label {
    switch (this) {
      case PendingPaymentStatusFilter.allOutstanding:
        return 'All Outstanding';
      case PendingPaymentStatusFilter.pending:
        return 'Pending';
      case PendingPaymentStatusFilter.partiallyPaid:
        return 'Partially Paid';
      case PendingPaymentStatusFilter.overdue:
        return 'Overdue';
      case PendingPaymentStatusFilter.paid:
        return 'Paid';
    }
  }
}

/// One booking or membership with money still owed. Every figure is
/// database-derived; this class only describes the shape.
class PaymentObligation {
  const PaymentObligation({
    required this.sourceType,
    required this.sourceId,
    required this.reference,
    required this.customerName,
    required this.customerPhone,
    required this.description,
    required this.facilityName,
    required this.courtName,
    required this.startsAt,
    required this.endsAt,
    required this.totalMinor,
    required this.paidMinor,
    required this.outstandingMinor,
    required this.status,
    required this.paymentMethod,
    required this.dueOn,
  });

  final ObligationSource sourceType;
  final String sourceId;
  final String reference;
  final String customerName;
  final String? customerPhone;
  final String description;
  final String? facilityName;
  final String? courtName;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int totalMinor;
  final int paidMinor;
  final int outstandingMinor;
  final ObligationStatus status;
  final String? paymentMethod;

  /// Booking date, or membership start date — one meaning per source.
  /// `yyyy-MM-dd` date string.
  final String dueOn;

  bool get isSettled => outstandingMinor <= 0;

  factory PaymentObligation.fromJson(Map<String, dynamic> json) {
    return PaymentObligation(
      sourceType: ObligationSource.fromJson(json['source_type'] as String),
      sourceId: json['source_id'] as String,
      reference: json['reference'] as String,
      customerName: json['customer_name'] as String,
      customerPhone: json['customer_phone'] as String?,
      description: json['description'] as String,
      facilityName: json['facility_name'] as String?,
      courtName: json['court_name'] as String?,
      startsAt: json['starts_at'] == null ? null : DateTime.parse(json['starts_at'] as String),
      endsAt: json['ends_at'] == null ? null : DateTime.parse(json['ends_at'] as String),
      totalMinor: (json['total_minor'] as num).toInt(),
      paidMinor: (json['paid_minor'] as num).toInt(),
      outstandingMinor: (json['outstanding_minor'] as num).toInt(),
      status: ObligationStatus.fromJson(json['status'] as String),
      paymentMethod: json['payment_method'] as String?,
      dueOn: json['due_on'] as String,
    );
  }
}

/// Filters for `list_pending_payments`. [status] and [sort] are nullable; the
/// repository supplies the wire defaults (`ALL_OUTSTANDING` / `DUE_DATE`),
/// exactly as the web service does.
class PendingPaymentFilters {
  const PendingPaymentFilters({
    this.search,
    this.sourceType,
    this.status,
    this.from,
    this.to,
    this.sort,
  });

  final String? search;
  final ObligationSource? sourceType;
  final PendingPaymentStatusFilter? status;
  final String? from;
  final String? to;
  final ObligationSort? sort;
}

/// A page of obligations plus the server's own count for the same filters —
/// `list_pending_payments`' in-row `total_count`, never `obligations.length`.
class PendingPaymentsPage {
  const PendingPaymentsPage({required this.obligations, required this.totalCount});

  final List<PaymentObligation> obligations;
  final int totalCount;

  factory PendingPaymentsPage.fromRows(List<Map<String, dynamic>> rows) {
    return PendingPaymentsPage(
      obligations: rows.map(PaymentObligation.fromJson).toList(),
      totalCount: rows.isEmpty ? 0 : (rows.first['total_count'] as num).toInt(),
    );
  }
}

/// The Pending Payments KPI row, straight off `get_pending_payments_summary`.
class PendingPaymentsSummary {
  const PendingPaymentsSummary({
    required this.outstandingMinor,
    required this.pendingMinor,
    required this.partiallyPaidMinor,
    required this.overdueMinor,
    required this.obligationCount,
  });

  final int outstandingMinor;
  final int pendingMinor;
  final int partiallyPaidMinor;
  final int overdueMinor;
  final int obligationCount;

  factory PendingPaymentsSummary.fromJson(Map<String, dynamic> json) {
    return PendingPaymentsSummary(
      outstandingMinor: (json['outstanding_minor'] as num).toInt(),
      pendingMinor: (json['pending_minor'] as num).toInt(),
      partiallyPaidMinor: (json['partially_paid_minor'] as num).toInt(),
      overdueMinor: (json['overdue_minor'] as num).toInt(),
      obligationCount: (json['obligation_count'] as num).toInt(),
    );
  }
}

/// What `record_obligation_payment` hands back. [duplicate] is true when an
/// earlier request with the same idempotency key already recorded this
/// payment — the money was taken once, not twice. [outstandingMinor] is what
/// remains after this payment (absent on the duplicate path).
class RecordObligationPaymentResult {
  const RecordObligationPaymentResult({required this.duplicate, this.outstandingMinor});

  final bool duplicate;
  final int? outstandingMinor;
}

/// The arguments `list_pending_payments` takes. [sourceId] switches it to
/// single-obligation mode — returns just that one, whatever its status.
class ListPendingPaymentsInput {
  const ListPendingPaymentsInput({
    required this.facilityId,
    this.filters = const PendingPaymentFilters(),
    this.limit,
    this.offset,
    this.sourceId,
  });

  final String facilityId;
  final PendingPaymentFilters filters;
  final int? limit;
  final int? offset;
  final String? sourceId;
}

// ═══════════════════════════════════════════════════════════════════════════
// Finance rework — Phase 12: Transaction Details, and a real PDF receipt.
//
// Mirrors src/features/finance/types.ts (`TransactionDetails` /
// `TransactionPaymentHistoryRow`). Backend: 0055_transaction_details.sql.
// NOTE: `get_transaction_details` returns a camelCase jsonb document (the web
// does `data as unknown as TransactionDetails`), so these `fromJson` readers
// use camelCase keys — unlike every other model in this file.
// ═══════════════════════════════════════════════════════════════════════════

/// One payment against the same booking or membership as the transaction being
/// viewed. [isThisOne] marks the payment this details page is actually about,
/// among its siblings.
class TransactionPaymentHistoryRow {
  const TransactionPaymentHistoryRow({
    required this.id,
    required this.paidAt,
    required this.amountMinor,
    required this.paymentMethod,
    required this.reference,
    required this.status,
    required this.isThisOne,
  });

  final String id;
  final DateTime paidAt;
  final int amountMinor;
  final String? paymentMethod;
  final String? reference;
  final String status;
  final bool isThisOne;

  factory TransactionPaymentHistoryRow.fromJson(Map<String, dynamic> json) {
    return TransactionPaymentHistoryRow(
      id: json['id'] as String,
      paidAt: DateTime.parse(json['paidAt'] as String),
      amountMinor: (json['amountMinor'] as num).toInt(),
      paymentMethod: json['paymentMethod'] as String?,
      reference: json['reference'] as String?,
      status: json['status'] as String,
      isThisOne: json['isThisOne'] as bool? ?? false,
    );
  }
}

/// Everything the Transaction Details page and its receipt render — one
/// `get_transaction_details` read. Every figure is server-computed.
class TransactionDetails {
  const TransactionDetails({
    required this.id,
    required this.reference,
    required this.sourceType,
    required this.category,
    required this.type,
    required this.amountMinor,
    required this.currency,
    required this.status,
    required this.paymentMethod,
    required this.occurredAt,
    required this.createdAt,
    required this.recordedBy,
    required this.description,
    required this.sourceReference,
    required this.customerName,
    required this.customerPhone,
    required this.facilityName,
    required this.facilityId,
    required this.bookingId,
    required this.membershipId,
    required this.refundedMinor,
    required this.netMinor,
    required this.history,
  });

  final String id;
  final String reference;
  final String sourceType;
  final String category;

  /// Always `INCOME` — a receipt is only ever raised for money coming in.
  final String type;
  final int amountMinor;
  final String currency;
  final String status;
  final String? paymentMethod;
  final DateTime occurredAt;
  final DateTime createdAt;
  final String? recordedBy;
  final String description;
  final String? sourceReference;
  final String? customerName;
  final String? customerPhone;
  final String? facilityName;
  final String facilityId;
  final String? bookingId;
  final String? membershipId;
  final int refundedMinor;
  final int netMinor;
  final List<TransactionPaymentHistoryRow> history;

  factory TransactionDetails.fromJson(Map<String, dynamic> json) {
    return TransactionDetails(
      id: json['id'] as String,
      reference: json['reference'] as String,
      sourceType: json['sourceType'] as String,
      category: json['category'] as String,
      type: json['type'] as String? ?? 'INCOME',
      amountMinor: (json['amountMinor'] as num).toInt(),
      currency: json['currency'] as String,
      status: json['status'] as String,
      paymentMethod: json['paymentMethod'] as String?,
      occurredAt: DateTime.parse(json['occurredAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      recordedBy: json['recordedBy'] as String?,
      description: json['description'] as String,
      sourceReference: json['sourceReference'] as String?,
      customerName: json['customerName'] as String?,
      customerPhone: json['customerPhone'] as String?,
      facilityName: json['facilityName'] as String?,
      facilityId: json['facilityId'] as String,
      bookingId: json['bookingId'] as String?,
      membershipId: json['membershipId'] as String?,
      refundedMinor: (json['refundedMinor'] as num?)?.toInt() ?? 0,
      netMinor: (json['netMinor'] as num?)?.toInt() ?? 0,
      history: ((json['history'] as List<dynamic>?) ?? const [])
          .map((row) => TransactionPaymentHistoryRow.fromJson((row as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}