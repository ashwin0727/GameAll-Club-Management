/// What cancelling a court booking right now would do, as worked out by the database (migration 0188). The app never computes a
/// refund itself: it shows this.
class CancellationQuote {
  const CancellationQuote({
    required this.bookingId,
    required this.totalMinor,
    required this.paidMinor,
    required this.hoursUntilStart,
    required this.rule,
    required this.deductionPercent,
    required this.refundPercent,
    required this.deductionMinor,
    required this.refundMinor,
    required this.message,
    this.paymentOption,
  });

  factory CancellationQuote.fromJson(Map<String, dynamic> j) =>
      CancellationQuote(
        bookingId: (j['bookingId'] as String?) ?? '',
        totalMinor: (j['totalMinor'] as num?)?.toInt() ?? 0,
        paidMinor: (j['paidMinor'] as num?)?.toInt() ?? 0,
        hoursUntilStart: (j['hoursUntilStart'] as num?)?.toDouble() ?? 0,
        rule: (j['rule'] as String?) ?? 'UNPAID',
        deductionPercent: (j['deductionPercent'] as num?)?.toInt() ?? 0,
        refundPercent: (j['refundPercent'] as num?)?.toInt() ?? 0,
        deductionMinor: (j['deductionMinor'] as num?)?.toInt() ?? 0,
        refundMinor: (j['refundMinor'] as num?)?.toInt() ?? 0,
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

  /// The sentence the database wrote for the player.
  final String message;
  final String? paymentOption;

  int get paidInr => (paidMinor / 100).round();
  int get deductionInr => (deductionMinor / 100).round();
  int get refundInr => (refundMinor / 100).round();

  bool get hasRefund => refundMinor > 0;
  bool get nothingPaid => paidMinor <= 0;
}

/// What happened when the booking was cancelled.
class CancellationOutcome {
  const CancellationOutcome({required this.quote, this.refundsSent = 0});

  final CancellationQuote quote;

  /// How many refunds were handed to Razorpay.
  final int refundsSent;
}

/// The refund schedule for a fully paid booking, as shown to the player before they pay: (time left, % deducted).
const cancellationSchedule = <(String, int)>[
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
