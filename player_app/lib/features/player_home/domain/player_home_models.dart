import 'player_dashboard_models.dart';

/// What the Player Home page knows about the signed-in player. Built from the `get_my_player_home` database function, which only
/// ever returns the caller's own data.
class PlayerHomeData {
  const PlayerHomeData({
    required this.fullName,
    required this.unreadNotifications,
    required this.hasActiveMembership,
    required this.hasActiveCoaching,
    required this.hasBookingHistory,
    required this.upcomingBookings,
    this.signedIn = false,
    this.phone,
    this.email,
    this.memberships = const [],
    this.coaching = const [],
    this.guestBookings = const GuestBookingSummary(),
    this.schedule = const [],
    this.courtsToday = const [],
  });

  /// A visitor who is not signed in (or a brand-new player): nothing enrolled, nothing booked.
  const PlayerHomeData.guest({this.fullName})
    : unreadNotifications = 0,
      hasActiveMembership = false,
      hasActiveCoaching = false,
      hasBookingHistory = false,
      upcomingBookings = const [],
      signedIn = false,
      phone = null,
      email = null,
      memberships = const [],
      coaching = const [],
      guestBookings = const GuestBookingSummary(),
      schedule = const [],
      courtsToday = const [];

  factory PlayerHomeData.fromJson(Map<String, dynamic> json) {
    final bookings = (json['upcomingBookings'] as List<dynamic>? ?? const [])
        .map(
          (b) => UpcomingBooking.fromJson((b as Map).cast<String, dynamic>()),
        )
        .toList();
    return PlayerHomeData(
      fullName: json['fullName'] as String?,
      unreadNotifications: (json['unreadNotifications'] as num?)?.toInt() ?? 0,
      hasActiveMembership: json['hasActiveMembership'] == true,
      hasActiveCoaching: json['hasActiveCoaching'] == true,
      hasBookingHistory: json['hasBookingHistory'] == true,
      upcomingBookings: bookings,
      // The dashboard function only answers for a signed-in player with a profile; a name means that happened.
      signedIn: json['fullName'] != null,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      memberships: _list(json['memberships'], ActiveMembership.fromJson),
      coaching: _list(json['coaching'], ActiveCoaching.fromJson),
      guestBookings: GuestBookingSummary.fromJson(json['guestBookings'] is Map ? (json['guestBookings'] as Map).cast<String, dynamic>() : null),
      schedule: _list(json['schedule'], ScheduleItem.fromJson),
      courtsToday: _list(json['courtsToday'], ScheduleItem.fromJson),
    );
  }

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) make) =>
      [for (final e in (raw as List<dynamic>? ?? const [])) make((e as Map).cast<String, dynamic>())];

  /// True when the player is signed in with a profile (so the personal Home is shown rather than the visitor's).
  final bool signedIn;
  final String? phone;
  final String? email;

  /// Every active membership and coaching enrolment, at every club (a player can have several of each).
  final List<ActiveMembership> memberships;
  final List<ActiveCoaching> coaching;
  final GuestBookingSummary guestBookings;

  /// The next seven days across memberships, coaching and bookings, soonest first.
  final List<ScheduleItem> schedule;

  /// What is happening today (on a court).
  final List<ScheduleItem> courtsToday;

  final String? fullName;
  final int unreadNotifications;
  final bool hasActiveMembership;
  final bool hasActiveCoaching;
  final bool hasBookingHistory;
  final List<UpcomingBooking> upcomingBookings;

  /// The first word of the name ("Alex Kumar" -> "Alex"), or "there" when the name is not known.
  String get firstName {
    final name = fullName?.trim() ?? '';
    if (name.isEmpty) return 'there';
    return name.split(RegExp(r'\s+')).first;
  }
}

class UpcomingBooking {
  const UpcomingBooking({
    required this.id,
    required this.venueName,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.sportName,
    this.courtName,
    this.venueLogoUrl,
  });

  factory UpcomingBooking.fromJson(Map<String, dynamic> json) =>
      UpcomingBooking(
        id: json['id'] as String,
        venueName: (json['venueName'] as String?) ?? 'Your venue',
        sportName: json['sportName'] as String?,
        courtName: json['courtName'] as String?,
        venueLogoUrl: json['venueLogo'] as String?,
        startTime: DateTime.parse(json['startTime'] as String).toLocal(),
        endTime: DateTime.parse(json['endTime'] as String).toLocal(),
        status: (json['status'] as String?) ?? 'confirmed',
      );

  final String id;
  final String venueName;
  final String? sportName;
  final String? courtName;
  final String? venueLogoUrl;
  final DateTime startTime;
  final DateTime endTime;
  final String status;

  bool get isConfirmed => status.toLowerCase() == 'confirmed';
}

/// Which "Your Next Game" panel to show.
enum NextGameKind {
  /// A confirmed booking that has not finished: show it.
  upcoming,

  /// Nothing coming up, but the player has booked before: "Ready for your next game?"
  readyForNext,

  /// A brand-new player: "No bookings yet."
  empty,
}

/// The booking to feature and the panel to show, decided in one place so the page never calculates it itself.
class NextGame {
  const NextGame(this.kind, this.booking, this.moreCount);

  final NextGameKind kind;

  /// The nearest valid booking (only when [kind] is [NextGameKind.upcoming]).
  final UpcomingBooking? booking;

  /// How many further upcoming bookings there are, for "View All".
  final int moreCount;
}

/// Picks the next game. Only confirmed bookings that have not finished count (a cancelled booking is never shown as confirmed);
/// when [sportName] is given, only that sport's bookings are considered.
NextGame resolveNextGame(
  PlayerHomeData data,
  DateTime now, {
  String? sportName,
}) {
  final valid =
      data.upcomingBookings
          .where((b) => b.isConfirmed && b.endTime.isAfter(now))
          .where(
            (b) =>
                sportName == null ||
                (b.sportName ?? '').toLowerCase() == sportName.toLowerCase(),
          )
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
  if (valid.isNotEmpty) {
    return NextGame(NextGameKind.upcoming, valid.first, valid.length - 1);
  }
  return NextGame(
    data.hasBookingHistory ? NextGameKind.readyForNext : NextGameKind.empty,
    null,
    0,
  );
}
