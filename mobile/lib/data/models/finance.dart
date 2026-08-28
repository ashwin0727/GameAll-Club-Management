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
    required this.netRevenueMinor,
    required this.transactionCount,
    required this.successfulPaymentCount,
    required this.failedPaymentCount,
    required this.pendingPaymentCount,
    required this.pendingRefundCount,
    required this.settlementExceptionCount,
  });

  final int grossRevenueMinor;
  final int refundsMinor;
  final int netRevenueMinor;
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
      netRevenueMinor: (json['net_revenue_minor'] as num).toInt(),
      transactionCount: (json['transaction_count'] as num).toInt(),
      successfulPaymentCount: (json['successful_payment_count'] as num).toInt(),
      failedPaymentCount: (json['failed_payment_count'] as num).toInt(),
      pendingPaymentCount: (json['pending_payment_count'] as num).toInt(),
      pendingRefundCount: (json['pending_refund_count'] as num).toInt(),
      settlementExceptionCount: (json['settlement_exception_count'] as num).toInt(),
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