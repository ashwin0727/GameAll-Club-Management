import '../../data/models/booking.dart';

/// Port of src/features/bookings/operations.ts — owner-facing "what's
/// happening right now" counts and per-court live status.
class TodaysOperationsSummary {
  const TodaysOperationsSummary({
    required this.totalBookings,
    required this.upcoming,
    required this.currentlyOccupied,
  });

  final int totalBookings;
  final int upcoming;
  final int currentlyOccupied;
}

bool _isLive(Booking b) => b.status == BookingStatus.pending || b.status == BookingStatus.confirmed;

TodaysOperationsSummary computeTodaysOperations(List<Booking> bookings, DateTime now) {
  final live = bookings.where(_isLive).toList();
  final upcoming = live.where((b) => b.startTime.isAfter(now)).length;
  final occupied = live.where((b) => !b.startTime.isAfter(now) && now.isBefore(b.endTime)).length;
  return TodaysOperationsSummary(totalBookings: live.length, upcoming: upcoming, currentlyOccupied: occupied);
}

class CourtLiveStatus {
  const CourtLiveStatus({required this.isOccupied, this.booking});

  final bool isOccupied;
  final Booking? booking;
}

/// "What is happening on this court right now?" — one booking wins if
/// several overlap (shouldn't, given the DB exclusion constraint), earliest
/// start first.
CourtLiveStatus currentCourtStatus(String courtId, List<Booking> bookings, DateTime now) {
  final active = bookings.where((b) => b.courtId == courtId && _isLive(b)).where(
    (b) => !b.startTime.isAfter(now) && now.isBefore(b.endTime),
  ).toList()..sort((a, b) => a.startTime.compareTo(b.startTime));

  if (active.isNotEmpty) return CourtLiveStatus(isOccupied: true, booking: active.first);
  return const CourtLiveStatus(isOccupied: false);
}