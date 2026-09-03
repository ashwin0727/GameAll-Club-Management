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

/// The actions a guest-bookings admin row can offer. Mirrors the action set in
/// src/features/bookings/components/guest-booking-actions.tsx.
enum GuestBookingAction {
  complete,
  cancel,
  sendReceipt,
  duplicate,
  invoice,
  delete,

  /// Offline payment for a released membership seat — `record_session_guest_
  /// payment`, not the court-booking recorder.
  recordSessionPayment,
}

/// Which actions apply to a guest-bookings row, given where it came from and
/// its current state.
///
/// A `SESSION` row has no `bookings` record behind it, so only Record Payment
/// and Invoice apply — exactly as the web hides the court action set for
/// `isSession` rows. A court row keeps the full set, minus Complete once it is
/// completed/cancelled and minus Cancel once cancelled.
List<GuestBookingAction> guestBookingActions({
  required bool isSession,
  required String status,
  required String paymentStatus,
}) {
  if (isSession) {
    final canRecord = paymentStatus != 'PAID' && status != 'cancelled';
    return [
      if (canRecord) GuestBookingAction.recordSessionPayment,
      GuestBookingAction.invoice,
    ];
  }

  return [
    if (status != 'completed' && status != 'cancelled') GuestBookingAction.complete,
    if (status != 'cancelled') GuestBookingAction.cancel,
    GuestBookingAction.sendReceipt,
    GuestBookingAction.duplicate,
    GuestBookingAction.invoice,
    GuestBookingAction.delete,
  ];
}