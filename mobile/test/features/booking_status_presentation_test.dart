import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/booking.dart';
import 'package:gameall_club_mobile/features/bookings/booking_status_presentation.dart';
import 'package:gameall_club_mobile/shared/widgets/misc.dart';

void main() {
  group('bookingStatusTone', () {
    test('maps every status to a distinct, non-neutral tone where meaningful', () {
      expect(bookingStatusTone(BookingStatus.pending), StatusTone.warning);
      expect(bookingStatusTone(BookingStatus.confirmed), StatusTone.info);
      expect(bookingStatusTone(BookingStatus.cancelled), StatusTone.danger);
      expect(bookingStatusTone(BookingStatus.completed), StatusTone.success);
    });
  });

  group('bookingStatusLabel', () {
    test('never returns the raw enum name (e.g. no lowercase "confirmed")', () {
      for (final status in BookingStatus.values) {
        expect(bookingStatusLabel(status), isNot(status.name));
      }
    });
  });

  group('paymentStatusTone', () {
    test('maps every payment status to its semantic tone', () {
      expect(paymentStatusTone(PaymentStatus.pending), StatusTone.warning);
      expect(paymentStatusTone(PaymentStatus.paid), StatusTone.success);
      expect(paymentStatusTone(PaymentStatus.refunded), StatusTone.neutral);
    });
  });

  group('paymentStatusLabel', () {
    test('never returns the raw enum name', () {
      for (final status in PaymentStatus.values) {
        expect(paymentStatusLabel(status), isNot(status.name));
      }
    });
  });
}