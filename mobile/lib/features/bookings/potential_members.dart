import '../../data/models/guest_booking_dashboard.dart';

/// Potential Members: guests who book often and aren't members yet — a pure port of
/// src/features/bookings/potential-members.ts so the two apps always agree on who qualifies.
///
/// Built from a facility's whole guest-booking history. A guest is one phone number (last ten
/// digits); cancelled bookings never count; a guest whose phone matches a current member is a
/// member, not a potential one.

const _dayMs = 86400000;
const _monthDays = 30.4375;

/// The number of bookings that makes a guest a potential member.
const potentialMinBookings = 3;

/// The last ten digits of a phone number, or null when it is too short to be a real one.
String? phoneKey(String? phone) {
  final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length < 7) return null;
  return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
}

class GuestProfile {
  const GuestProfile({
    required this.key,
    required this.name,
    required this.phone,
    required this.bookings,
    required this.lastBookingAt,
    required this.totalSpentMinor,
    required this.preferredCourt,
    required this.isFrequent,
    required this.monthlySpendMinor,
    required this.isMember,
  });

  final String key;
  final String name;
  final String? phone;
  final int bookings;

  /// The most recent booking that has started (else the earliest one still to come).
  final DateTime lastBookingAt;

  /// Collected money across all their bookings, in minor units.
  final int totalSpentMinor;

  /// The court they book most (ties go to the one they booked most recently).
  final String preferredCourt;

  /// "Frequent" if they booked in the last 30 days, otherwise "Returning".
  final bool isFrequent;
  String get label => isFrequent ? 'Frequent' : 'Returning';

  /// What they pay in bookings per month: total spent over the months since their first booking
  /// (at least one).
  final int monthlySpendMinor;
  final bool isMember;
}

/// Money collected on one booking: the RPC's own paid figure, else the full amount when it is PAID.
int paidMinorOf(GuestBookingRow r) => r.paidMinor ?? (r.paymentStatus == 'PAID' ? (r.amountMinor ?? 0) : 0);

/// Every guest with a usable phone number, from live (non-cancelled) bookings.
List<GuestProfile> buildGuestProfiles(List<GuestBookingRow> rows, Set<String> memberKeys, DateTime now) {
  final byGuest = <String, List<GuestBookingRow>>{};
  for (final r in rows) {
    if (r.status == 'cancelled') continue;
    final key = phoneKey(r.guestPhone);
    if (key == null) continue;
    byGuest.putIfAbsent(key, () => []).add(r);
  }

  final nowMs = now.millisecondsSinceEpoch;
  final profiles = <GuestProfile>[];
  byGuest.forEach((key, list) {
    final newestFirst = [...list]..sort((a, b) => b.startTime.compareTo(a.startTime));
    final started = newestFirst.where((r) => r.startTime.millisecondsSinceEpoch <= nowMs).toList();
    final last = started.isNotEmpty ? started.first : newestFirst.last;
    final earliest = newestFirst.last;

    final perCourt = <String, int>{};
    for (final r in newestFirst) {
      perCourt[r.courtName] = (perCourt[r.courtName] ?? 0) + 1;
    }
    var preferred = newestFirst.first.courtName;
    for (final r in newestFirst) {
      if ((perCourt[r.courtName] ?? 0) > (perCourt[preferred] ?? 0)) preferred = r.courtName;
    }

    final totalSpent = list.fold<int>(0, (sum, r) => sum + paidMinorOf(r));
    final rawMonths = (nowMs - earliest.startTime.millisecondsSinceEpoch) / _dayMs / _monthDays;
    final months = rawMonths < 1 ? 1.0 : rawMonths;
    final lastMs = last.startTime.millisecondsSinceEpoch;
    profiles.add(GuestProfile(
      key: key,
      name: newestFirst.first.guestName,
      phone: newestFirst.first.guestPhone,
      bookings: list.length,
      lastBookingAt: last.startTime,
      totalSpentMinor: totalSpent,
      preferredCourt: preferred,
      isFrequent: lastMs <= nowMs && nowMs - lastMs <= 30 * _dayMs,
      monthlySpendMinor: (totalSpent / months).round(),
      isMember: memberKeys.contains(key),
    ));
  });
  return profiles;
}

class SegmentStats {
  const SegmentStats({required this.count, required this.monthlyRevenueMinor, required this.conversionPercent, required this.avgBookings});

  /// Potential members.
  final int count;

  /// What they would bring in a month, if each paid what they already spend on bookings.
  final int monthlyRevenueMinor;

  /// Potential members as a share of every frequent guest (3+ bookings), members included. 0–100.
  final double conversionPercent;

  /// Bookings per potential member.
  final double avgBookings;
}

List<GuestProfile> potentialMembers(List<GuestProfile> guests) =>
    guests.where((g) => !g.isMember && g.bookings >= potentialMinBookings).toList();

SegmentStats segmentStats(List<GuestProfile> guests) {
  final potential = potentialMembers(guests);
  final frequent = guests.where((g) => g.bookings >= potentialMinBookings).length;
  return SegmentStats(
    count: potential.length,
    monthlyRevenueMinor: potential.fold<int>(0, (sum, g) => sum + g.monthlySpendMinor),
    conversionPercent: frequent > 0 ? potential.length / frequent * 100 : 0,
    avgBookings: potential.isNotEmpty ? potential.fold<int>(0, (sum, g) => sum + g.bookings) / potential.length : 0,
  );
}

/// "any", "7", "30" or "90" — how recently the guest last booked.
class PotentialFilters {
  const PotentialFilters({this.search = '', this.court, this.minBookings = 3, this.lastBookingDays, this.minSpentMinor = 0});

  final String search;

  /// null = any court.
  final String? court;
  final int minBookings;

  /// null = any time.
  final int? lastBookingDays;

  /// Minor units; 0 = any amount.
  final int minSpentMinor;

  PotentialFilters copyWith({String? search, Object? court = _keep, int? minBookings, Object? lastBookingDays = _keep, int? minSpentMinor}) =>
      PotentialFilters(
        search: search ?? this.search,
        court: identical(court, _keep) ? this.court : court as String?,
        minBookings: minBookings ?? this.minBookings,
        lastBookingDays: identical(lastBookingDays, _keep) ? this.lastBookingDays : lastBookingDays as int?,
        minSpentMinor: minSpentMinor ?? this.minSpentMinor,
      );
}

const Object _keep = Object();

List<GuestProfile> filterPotential(List<GuestProfile> guests, PotentialFilters f, DateTime now) {
  final q = f.search.trim().toLowerCase();
  final qDigits = q.replaceAll(RegExp(r'\D'), '');
  final cutoff = f.lastBookingDays == null ? null : now.millisecondsSinceEpoch - f.lastBookingDays! * _dayMs;
  return guests.where((g) {
    if (g.bookings < f.minBookings) return false;
    if (f.court != null && g.preferredCourt != f.court) return false;
    if (g.totalSpentMinor < f.minSpentMinor) return false;
    if (cutoff != null && g.lastBookingAt.millisecondsSinceEpoch < cutoff) return false;
    if (q.isEmpty) return true;
    return g.name.toLowerCase().contains(q) || (qDigits.length >= 3 && (g.phone ?? '').replaceAll(RegExp(r'\D'), '').contains(qDigits));
  }).toList();
}

/// Most bookings first by default; ties go to whoever booked most recently.
List<GuestProfile> sortByBookings(List<GuestProfile> guests, {required bool descending}) {
  final sign = descending ? -1 : 1;
  return [...guests]..sort((a, b) {
      final byCount = sign * (a.bookings - b.bookings);
      return byCount != 0 ? byCount : b.lastBookingAt.compareTo(a.lastBookingAt);
    });
}
