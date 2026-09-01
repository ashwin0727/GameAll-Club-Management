/// Mirrors src/features/bookings/types.ts — same shape, same
/// MEMBER/GUEST customer split.
enum BookingStatus { pending, confirmed, cancelled, completed }
enum CustomerType { member, guest }
enum PaymentStatus { pending, paid, refunded }

PaymentStatus _paymentStatusFromDb(String value) {
  switch (value) {
    case 'PAID':
      return PaymentStatus.paid;
    case 'REFUNDED':
      return PaymentStatus.refunded;
    default:
      return PaymentStatus.pending;
  }
}

String paymentStatusToDb(PaymentStatus status) {
  switch (status) {
    case PaymentStatus.paid:
      return 'PAID';
    case PaymentStatus.refunded:
      return 'REFUNDED';
    case PaymentStatus.pending:
      return 'PENDING';
  }
}

BookingStatus _statusFromDb(String value) {
  switch (value) {
    case 'confirmed':
      return BookingStatus.confirmed;
    case 'cancelled':
      return BookingStatus.cancelled;
    case 'completed':
      return BookingStatus.completed;
    default:
      return BookingStatus.pending;
  }
}

CustomerType _customerTypeFromDb(String value) => value == 'GUEST' ? CustomerType.guest : CustomerType.member;

String customerTypeToDb(CustomerType type) => type == CustomerType.guest ? 'GUEST' : 'MEMBER';

class Booking {
  const Booking({
    required this.id,
    required this.facilityId,
    required this.courtId,
    this.facilitySportId,
    this.memberId,
    required this.customerType,
    this.guestPlayerId,
    this.guestName,
    this.guestPhone,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.amountMinor,
    required this.currency,
    required this.paymentStatus,
    this.cancellationReason,
    this.notes,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String facilityId;
  final String courtId;
  final String? facilitySportId;
  final String? memberId;
  final CustomerType customerType;
  final String? guestPlayerId;
  final String? guestName;
  final String? guestPhone;
  final DateTime startTime;
  final DateTime endTime;
  final BookingStatus status;
  final int? amountMinor;
  final String currency;
  final PaymentStatus paymentStatus;
  final String? cancellationReason;
  final String? notes;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: json['id'] as String,
      facilityId: json['facility_id'] as String,
      courtId: json['court_id'] as String,
      facilitySportId: json['facility_sport_id'] as String?,
      memberId: json['member_id'] as String?,
      customerType: _customerTypeFromDb(json['customer_type'] as String? ?? 'MEMBER'),
      guestPlayerId: json['guest_player_id'] as String?,
      guestName: json['guest_name'] as String?,
      guestPhone: json['guest_phone'] as String?,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      status: _statusFromDb(json['status'] as String? ?? 'pending'),
      amountMinor: json['amount_minor'] as int?,
      currency: json['currency'] as String? ?? 'INR',
      paymentStatus: _paymentStatusFromDb(json['payment_status'] as String? ?? 'PENDING'),
      cancellationReason: json['cancellation_reason'] as String?,
      notes: json['notes'] as String?,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Booking copyWith({BookingStatus? status, String? cancellationReason, PaymentStatus? paymentStatus}) {
    return Booking(
      id: id,
      facilityId: facilityId,
      courtId: courtId,
      facilitySportId: facilitySportId,
      memberId: memberId,
      customerType: customerType,
      guestPlayerId: guestPlayerId,
      guestName: guestName,
      guestPhone: guestPhone,
      startTime: startTime,
      endTime: endTime,
      status: status ?? this.status,
      amountMinor: amountMinor,
      currency: currency,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      notes: notes,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class NewBookingInput {
  const NewBookingInput({
    required this.facilityId,
    required this.courtId,
    required this.startTime,
    required this.endTime,
    required this.customerType,
    this.memberId,
    this.guestPlayerId,
    this.guestName,
    this.guestPhone,
    this.notes,
    this.paymentStatus = PaymentStatus.pending,
    this.partySize = 1,
    this.paymentMethod,
  });

  final String facilityId;
  final String courtId;
  final DateTime startTime;
  final DateTime endTime;
  final CustomerType customerType;
  final String? memberId;
  final String? guestPlayerId;
  final String? guestName;
  final String? guestPhone;
  final String? notes;
  final PaymentStatus paymentStatus;
  final int partySize;
  final String? paymentMethod;
}

class RescheduleBookingInput {
  const RescheduleBookingInput({
    required this.bookingId,
    required this.courtId,
    required this.startTime,
    required this.endTime,
  });

  final String bookingId;
  final String courtId;
  final DateTime startTime;
  final DateTime endTime;
}

/// One bookable window on the picked date, for the "pick a slot" UI.
class BookingTimeSlot {
  const BookingTimeSlot({required this.startTime, required this.endTime, required this.available});

  final DateTime startTime;
  final DateTime endTime;
  final bool available;
}

/// Mirrors `search_members`'s return columns — a facility-scoped, ACTIVE-only
/// member lookup used by the Booking → Member picker. `phone` is always
/// present (members.phone is not-null); `email` is optional.
class MemberSearchResult {
  const MemberSearchResult({required this.id, required this.fullName, required this.phone, this.email});

  final String id;
  final String fullName;
  final String phone;
  final String? email;

  factory MemberSearchResult.fromJson(Map<String, dynamic> json) {
    return MemberSearchResult(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
    );
  }
}