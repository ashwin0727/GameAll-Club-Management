import '../../data/models/booking.dart';
import '../../shared/widgets/misc.dart';

/// Pure status→(label,tone) mapping so a status is never communicated by
/// color alone (spec §42) — every badge pairs a tone with explicit text.
/// Kept out of widgets so the mapping itself is independently unit-testable.

String bookingStatusLabel(BookingStatus status) {
  switch (status) {
    case BookingStatus.pending:
      return 'Pending';
    case BookingStatus.confirmed:
      return 'Confirmed';
    case BookingStatus.cancelled:
      return 'Cancelled';
    case BookingStatus.completed:
      return 'Completed';
  }
}

StatusTone bookingStatusTone(BookingStatus status) {
  switch (status) {
    case BookingStatus.pending:
      return StatusTone.warning;
    case BookingStatus.confirmed:
      return StatusTone.info;
    case BookingStatus.cancelled:
      return StatusTone.danger;
    case BookingStatus.completed:
      return StatusTone.success;
  }
}

String paymentStatusLabel(PaymentStatus status) {
  switch (status) {
    case PaymentStatus.pending:
      return 'Pending';
    case PaymentStatus.paid:
      return 'Paid';
    case PaymentStatus.refunded:
      return 'Refunded';
  }
}

StatusTone paymentStatusTone(PaymentStatus status) {
  switch (status) {
    case PaymentStatus.pending:
      return StatusTone.warning;
    case PaymentStatus.paid:
      return StatusTone.success;
    case PaymentStatus.refunded:
      return StatusTone.neutral;
  }
}

/// AVAILABLE/BOOKED for a single booking slot — the state the reusable
/// BookingSlotChip renders (spec §17).
enum SlotVisualState { available, selected, booked }