/// Guest Bookings dashboard models — mirrors src/features/bookings/types.ts
/// (GuestBookingsSummary / GuestBookingRow).
library;

class GuestBookingsSummary {
  const GuestBookingsSummary({
    required this.total,
    required this.confirmed,
    required this.completed,
    required this.cancelled,
    required this.pending,
    required this.totalRevenueMinor,
    required this.avgPerBookingMinor,
    required this.highestBookingMinor,
    this.totalChangePct,
    this.revenueChangePct,
    required this.trend,
  });

  final int total;
  final int confirmed;
  final int completed;
  final int cancelled;
  final int pending;
  final int totalRevenueMinor;
  final int avgPerBookingMinor;
  final int highestBookingMinor;
  final int? totalChangePct;
  final int? revenueChangePct;
  final List<int> trend;

  factory GuestBookingsSummary.fromJson(Map<String, dynamic> j) => GuestBookingsSummary(
        total: (j['total'] as num?)?.toInt() ?? 0,
        confirmed: (j['confirmed'] as num?)?.toInt() ?? 0,
        completed: (j['completed'] as num?)?.toInt() ?? 0,
        cancelled: (j['cancelled'] as num?)?.toInt() ?? 0,
        pending: (j['pending'] as num?)?.toInt() ?? 0,
        totalRevenueMinor: (j['totalRevenueMinor'] as num?)?.toInt() ?? 0,
        avgPerBookingMinor: (j['avgPerBookingMinor'] as num?)?.toInt() ?? 0,
        highestBookingMinor: (j['highestBookingMinor'] as num?)?.toInt() ?? 0,
        totalChangePct: (j['totalChangePct'] as num?)?.toInt(),
        revenueChangePct: (j['revenueChangePct'] as num?)?.toInt(),
        trend: ((j['trend'] as List<dynamic>?) ?? const [])
            .map((e) => ((e as Map<String, dynamic>)['amountMinor'] as num?)?.toInt() ?? 0)
            .toList(),
      );
}

/// Where a guest-bookings admin row comes from (migration 0043). A `SESSION`
/// row is a guest sitting in capacity released from a membership session — it
/// lives in `membership_session_bookings`, not `bookings`, so the court
/// actions (edit / reschedule / cancel / duplicate / delete) don't apply to
/// it. [bookingId] on such a row is the `membership_session_bookings` id.
enum GuestBookingSource {
  court,
  session;

  static GuestBookingSource fromJson(String? value) =>
      value == 'SESSION' ? GuestBookingSource.session : GuestBookingSource.court;
}

class GuestBookingRow {
  const GuestBookingRow({
    required this.bookingId,
    required this.code,
    required this.guestName,
    this.guestPhone,
    this.sportName,
    required this.courtName,
    required this.startTime,
    required this.endTime,
    required this.partySize,
    this.amountMinor,
    required this.currency,
    required this.paymentStatus,
    this.paymentMethod,
    required this.status,
    this.source = GuestBookingSource.court,
  });

  final String bookingId;
  final String code;
  final String guestName;
  final String? guestPhone;
  final String? sportName;
  final String courtName;
  final DateTime startTime;
  final DateTime endTime;
  final int partySize;
  final int? amountMinor;
  final String currency;
  final String paymentStatus; // PENDING | PAID | REFUNDED
  final String? paymentMethod;
  final String status; // pending | confirmed | cancelled | completed
  final GuestBookingSource source;

  bool get isSession => source == GuestBookingSource.session;

  factory GuestBookingRow.fromJson(Map<String, dynamic> j) => GuestBookingRow(
        bookingId: j['booking_id'] as String,
        code: j['code'] as String? ?? 'GBK',
        guestName: j['guest_name'] as String? ?? 'Guest',
        guestPhone: j['guest_phone'] as String?,
        sportName: j['sport_name'] as String?,
        courtName: j['court_name'] as String? ?? '',
        startTime: DateTime.parse(j['start_time'] as String),
        endTime: DateTime.parse(j['end_time'] as String),
        partySize: (j['party_size'] as num?)?.toInt() ?? 1,
        amountMinor: (j['amount_minor'] as num?)?.toInt(),
        currency: j['currency'] as String? ?? 'INR',
        paymentStatus: j['payment_status'] as String? ?? 'PENDING',
        paymentMethod: j['payment_method'] as String?,
        status: j['status'] as String? ?? 'confirmed',
        source: GuestBookingSource.fromJson(j['source'] as String?),
      );
}