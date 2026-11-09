/// What cancelling a court booking right now would do, as worked out by the database (migration 0188,
/// `staff_booking_cancellation_quote`). Mirrors `BookingCancellationQuote` in src/features/refunds/types.ts. The app never works out a
/// refund itself: it shows this. Amounts are in minor units (paise).
class BookingCancellationQuote {
  const BookingCancellationQuote({
    required this.bookingId,
    required this.totalMinor,
    required this.paidMinor,
    required this.hoursUntilStart,
    required this.rule,
    required this.deductionPercent,
    required this.refundPercent,
    required this.deductionMinor,
    required this.refundMinor,
    required this.onlineRefundMinor,
    required this.offlineRefundDueMinor,
    required this.isOverride,
    required this.message,
    this.paymentOption,
  });

  factory BookingCancellationQuote.fromJson(Map<String, dynamic> j) => BookingCancellationQuote(
    bookingId: (j['bookingId'] as String?) ?? '',
    totalMinor: (j['totalMinor'] as num?)?.toInt() ?? 0,
    paidMinor: (j['paidMinor'] as num?)?.toInt() ?? 0,
    hoursUntilStart: (j['hoursUntilStart'] as num?)?.toDouble() ?? 0,
    rule: (j['rule'] as String?) ?? 'UNPAID',
    deductionPercent: (j['deductionPercent'] as num?)?.toInt() ?? 0,
    refundPercent: (j['refundPercent'] as num?)?.toInt() ?? 0,
    deductionMinor: (j['deductionMinor'] as num?)?.toInt() ?? 0,
    refundMinor: (j['refundMinor'] as num?)?.toInt() ?? 0,
    onlineRefundMinor: (j['onlineRefundMinor'] as num?)?.toInt() ?? 0,
    offlineRefundDueMinor: (j['offlineRefundDueMinor'] as num?)?.toInt() ?? 0,
    isOverride: j['isOverride'] == true,
    message: (j['message'] as String?) ?? '',
    paymentOption: j['paymentOption'] as String?,
  );

  final String bookingId;
  final int totalMinor;
  final int paidMinor;
  final double hoursUntilStart;

  /// UNPAID | ADVANCE_ONLY | FULL | STARTED
  final String rule;
  final int deductionPercent;
  final int refundPercent;
  final int deductionMinor;
  final int refundMinor;

  /// Goes back through Razorpay.
  final int onlineRefundMinor;

  /// Cash the club took at the desk: the club hands this back itself.
  final int offlineRefundDueMinor;
  final bool isOverride;

  /// The sentence to show: how long is left, the % deducted and the refund.
  final String message;
  final String? paymentOption;

  int get paidInr => (paidMinor / 100).round();
  int get deductionInr => (deductionMinor / 100).round();
  int get refundInr => (refundMinor / 100).round();
  int get onlineRefundInr => (onlineRefundMinor / 100).round();
  int get offlineRefundDueInr => (offlineRefundDueMinor / 100).round();
}

/// The fixed refund schedule for a fully paid booking: (time left, % deducted).
const bookingCancellationSchedule = <(String, int)>[
  ('12 hours or more', 5),
  ('11 – 12 hours', 10),
  ('10 – 11 hours', 15),
  ('9 – 10 hours', 20),
  ('8 – 9 hours', 30),
  ('7 – 8 hours', 40),
  ('6 – 7 hours', 45),
  ('5 – 6 hours', 50),
  ('4 – 5 hours', 70),
  ('3 – 4 hours', 75),
  ('2 – 3 hours', 80),
  ('1 – 2 hours', 90),
  ('Under 1 hour', 100),
];
