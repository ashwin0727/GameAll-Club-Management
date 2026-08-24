import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/booking.dart';
import 'package:gameall_club_mobile/features/bookings/booking_operations.dart';

final _now = DateTime(2026, 8, 23, 10, 0);

Booking _booking({
  String courtId = 'court-1',
  BookingStatus status = BookingStatus.confirmed,
  DateTime? startTime,
  DateTime? endTime,
}) {
  return Booking(
    id: 'b1',
    facilityId: 'f1',
    courtId: courtId,
    customerType: CustomerType.guest,
    guestName: 'Uma',
    startTime: startTime ?? DateTime(2026, 8, 23, 9, 0),
    endTime: endTime ?? DateTime(2026, 8, 23, 10, 0),
    status: status,
    currency: 'INR',
    paymentStatus: PaymentStatus.pending,
    createdBy: 'u1',
    createdAt: DateTime(2026, 8, 20),
    updatedAt: DateTime(2026, 8, 20),
  );
}

void main() {
  group('computeTodaysOperations', () {
    test('counts only live (pending/confirmed) bookings', () {
      final bookings = [_booking(status: BookingStatus.cancelled), _booking(status: BookingStatus.confirmed)];
      expect(computeTodaysOperations(bookings, _now).totalBookings, 1);
    });

    test('splits into upcoming vs currently occupied', () {
      final occupied = _booking(startTime: DateTime(2026, 8, 23, 9, 30), endTime: DateTime(2026, 8, 23, 10, 30));
      final upcoming = _booking(startTime: DateTime(2026, 8, 23, 11, 0), endTime: DateTime(2026, 8, 23, 12, 0));
      final past = _booking(startTime: DateTime(2026, 8, 23, 7, 0), endTime: DateTime(2026, 8, 23, 8, 0));
      final summary = computeTodaysOperations([occupied, upcoming, past], _now);
      expect(summary.currentlyOccupied, 1);
      expect(summary.upcoming, 1);
      expect(summary.totalBookings, 3);
    });
  });

  group('currentCourtStatus', () {
    test('is available when nothing occupies the court right now', () {
      expect(currentCourtStatus('court-1', const [], _now).isOccupied, isFalse);
    });

    test('is occupied when a live booking spans the current time', () {
      final b = _booking(startTime: DateTime(2026, 8, 23, 9, 30), endTime: DateTime(2026, 8, 23, 10, 30));
      final result = currentCourtStatus('court-1', [b], _now);
      expect(result.isOccupied, isTrue);
      expect(result.booking, b);
    });

    test('ignores a cancelled booking even if its window covers now', () {
      final b = _booking(
        status: BookingStatus.cancelled,
        startTime: DateTime(2026, 8, 23, 9, 30),
        endTime: DateTime(2026, 8, 23, 10, 30),
      );
      expect(currentCourtStatus('court-1', [b], _now).isOccupied, isFalse);
    });

    test('ignores bookings on a different court', () {
      final b = _booking(courtId: 'court-2', startTime: DateTime(2026, 8, 23, 9, 30), endTime: DateTime(2026, 8, 23, 10, 30));
      expect(currentCourtStatus('court-1', [b], _now).isOccupied, isFalse);
    });
  });
}