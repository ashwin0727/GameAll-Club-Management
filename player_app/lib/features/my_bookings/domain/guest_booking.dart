/// One guest court booking of the player's, as the Guest Booking page shows it. Read from `get_my_guest_bookings` (migration 0184).
class GuestBooking {
  const GuestBooking({
    required this.id,
    required this.ref,
    required this.status,
    required this.start,
    required this.end,
    required this.venue,
    this.sport,
    this.court,
    this.players = 1,
    this.totalInr = 0,
    this.paidInr = 0,
    this.payState = 'PENDING',
  });

  factory GuestBooking.fromJson(Map<String, dynamic> j) {
    final v = j['venue'] is Map
        ? (j['venue'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return GuestBooking(
      id: j['id'] as String,
      ref: (j['ref'] as String?) ?? '',
      status: (j['status'] as String?) ?? 'confirmed',
      start: DateTime.parse(j['startTime'] as String).toLocal(),
      end: DateTime.parse(j['endTime'] as String).toLocal(),
      sport: _clean(j['sport'] as String?),
      court: _clean(j['court'] as String?),
      players: (j['players'] as num?)?.toInt() ?? 1,
      totalInr: (j['totalInr'] as num?)?.toInt() ?? 0,
      paidInr: (j['paidInr'] as num?)?.toInt() ?? 0,
      payState: (j['payState'] as String?) ?? 'PENDING',
      venue: BookingVenue(
        id: (v['id'] as String?) ?? '',
        name: (v['name'] as String?) ?? '',
        area: _clean(v['area'] as String?),
        city: _clean(v['city'] as String?),
        phone: _clean(v['phone'] as String?),
        imageUrl: _clean(v['imageUrl'] as String?),
      ),
    );
  }

  final String id;

  /// "GBK-CHZ-1A2B3".
  final String ref;

  /// confirmed, pending (waiting on its advance), completed or cancelled.
  final String status;
  final DateTime start;
  final DateTime end;
  final BookingVenue venue;
  final String? sport;
  final String? court;
  final int players;
  final int totalInr;
  final int paidInr;

  /// PAID, PARTIAL or PENDING.
  final String payState;

  bool get isUpcoming => status == 'confirmed' || status == 'pending';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  int get balanceInr => (totalInr - paidInr).clamp(0, totalInr);

  /// "1 Hour", "1.5 Hours", "2 Hours".
  String get durationLabel {
    final mins = end.difference(start).inMinutes;
    final h = mins / 60;
    final text = h == h.roundToDouble() ? '${h.round()}' : h.toStringAsFixed(1);
    return '$text ${h == 1 ? 'Hour' : 'Hours'}';
  }
}

class BookingVenue {
  const BookingVenue({
    required this.id,
    required this.name,
    this.area,
    this.city,
    this.phone,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String? area;
  final String? city;
  final String? phone;
  final String? imageUrl;

  /// "Iyyapanthangal, Chennai".
  String get place {
    final a = area;
    final c = city;
    if (a != null && c != null && a.toLowerCase() == c.toLowerCase()) return c;
    return [?a, ?c].join(', ');
  }
}

/// The three tabs of the page.
class GuestBookings {
  const GuestBookings({
    this.upcoming = const [],
    this.completed = const [],
    this.cancelled = const [],
    this.completedCount = 0,
    this.cancelledCount = 0,
  });

  factory GuestBookings.fromJson(Map<String, dynamic> j) {
    List<GuestBooking> list(Object? v) => [
      for (final e in (v as List<dynamic>? ?? const []))
        if (e is Map) GuestBooking.fromJson(e.cast<String, dynamic>()),
    ];
    final completed = list(j['completed']);
    final cancelled = list(j['cancelled']);
    return GuestBookings(
      upcoming: list(j['upcoming']),
      completed: completed,
      cancelled: cancelled,
      completedCount:
          (j['completedCount'] as num?)?.toInt() ?? completed.length,
      cancelledCount:
          (j['cancelledCount'] as num?)?.toInt() ?? cancelled.length,
    );
  }

  final List<GuestBooking> upcoming;
  final List<GuestBooking> completed;
  final List<GuestBooking> cancelled;
  final int completedCount;
  final int cancelledCount;

  bool get isEmpty =>
      upcoming.isEmpty && completed.isEmpty && cancelled.isEmpty;

  /// The most recent two past (completed) bookings, shown under the upcoming ones.
  List<GuestBooking> get lastPast => completed.take(2).toList();
}

String? _clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
