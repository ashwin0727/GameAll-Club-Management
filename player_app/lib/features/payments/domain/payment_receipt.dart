/// What a payment is for.
enum PaymentKind {
  membership('membership'),
  coaching('coaching'),
  booking('booking');

  const PaymentKind(this.wire);

  /// The value the database function expects.
  final String wire;
}

/// Where a payment stands. The same words as Home's prompts.
enum PaymentState { paid, pending, failed }

/// A membership, coaching enrolment or booking of the player's, with what has been paid for it and everything the "Payment Successful"
/// page and its PDF receipt show. Read from `get_my_payment_receipt` (migration 0181).
class PaymentReceipt {
  const PaymentReceipt({
    required this.kind,
    required this.id,
    required this.state,
    required this.title,
    required this.venueName,
    this.venueId,
    this.venuePlace,
    this.venuePhone,
    this.totalInr = 0,
    this.paidInr = 0,
    this.amountInr = 0,
    this.receiptNo = '',
    this.method,
    this.reference,
    this.paidAt,
    this.autopay = false,
    this.details = const {},
  });

  factory PaymentReceipt.fromJson(Map<String, dynamic> j) {
    final venue = j['venue'] is Map
        ? (j['venue'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final area = _clean(venue['area'] as String?);
    final city = _clean(venue['city'] as String?);
    final showArea =
        area != null && area.toLowerCase() != (city ?? '').toLowerCase();
    return PaymentReceipt(
      kind: switch (j['kind']) {
        'coaching' => PaymentKind.coaching,
        'booking' => PaymentKind.booking,
        _ => PaymentKind.membership,
      },
      id: (j['id'] as String?) ?? '',
      state: switch (j['state']) {
        'PAID' => PaymentState.paid,
        'FAILED' => PaymentState.failed,
        _ => PaymentState.pending,
      },
      title: (j['title'] as String?) ?? '',
      venueName: (venue['name'] as String?) ?? '',
      venueId: _clean(venue['id'] as String?),
      venuePlace: [if (showArea) area, ?city].join(', '),
      venuePhone: _clean(venue['phone'] as String?),
      totalInr: (j['totalInr'] as num?)?.toInt() ?? 0,
      paidInr: (j['paidInr'] as num?)?.toInt() ?? 0,
      amountInr: (j['amountInr'] as num?)?.toInt() ?? 0,
      receiptNo: (j['receiptNo'] as String?) ?? '',
      method: _clean(j['method'] as String?),
      reference: _clean(j['reference'] as String?),
      paidAt: j['paidAt'] is String
          ? DateTime.tryParse(j['paidAt'] as String)?.toLocal()
          : null,
      autopay: j['autopay'] == true,
      details: j['details'] is Map
          ? (j['details'] as Map).cast<String, dynamic>()
          : const {},
    );
  }

  final PaymentKind kind;
  final String id;
  final PaymentState state;

  /// The plan, programme or booking: "Court Time Membership", "Beginner Program", "Badminton booking".
  final String title;
  final String venueName;
  final String? venueId;
  final String? venuePlace;
  final String? venuePhone;
  final int totalInr;
  final int paidInr;

  /// What this receipt is for: what has been paid, or the amount agreed for an AutoPay that is approved but not charged yet.
  final int amountInr;

  /// "RCP-1A2B3C4D"
  final String receiptNo;
  final String? method;
  final String? reference;
  final DateTime? paidAt;
  final bool autopay;

  /// The kind's own details: plan / slot / dates for a membership, programme / coach / batch for coaching, court / time for a booking.
  final Map<String, dynamic> details;

  bool get isPaid => state == PaymentState.paid;

  String? str(String key) => _clean(details[key] as String?);

  DateTime? date(String key) {
    final v = details[key];
    return v is String ? DateTime.tryParse(v)?.toLocal() : null;
  }

  Map<String, dynamic>? map(String key) => details[key] is Map
      ? (details[key] as Map).cast<String, dynamic>()
      : null;

  /// "Online (UPI)", "UPI AutoPay"… or null.
  String? get methodLabel {
    final m = (method ?? '').trim();
    if (m.isEmpty) return autopay ? 'UPI AutoPay' : null;
    switch (m.toLowerCase()) {
      case 'upi':
        return 'Online (UPI)';
      case 'card':
        return 'Online (Card)';
      case 'online':
      case 'razorpay':
        return 'Online';
      case 'cash':
        return 'Cash at the club';
      default:
        return m;
    }
  }

  /// A short word for the page: "Membership", "Coaching", "Booking".
  String get kindLabel => switch (kind) {
    PaymentKind.membership => 'Membership',
    PaymentKind.coaching => 'Coaching',
    PaymentKind.booking => 'Court booking',
  };
}

String? _clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
