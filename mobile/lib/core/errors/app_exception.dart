import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors the web app's `ServiceError` (see src/services/shared/service-error.ts)
/// so both clients speak the same error vocabulary against the same backend.
enum AppErrorCode {
  unauthenticated,
  unauthorized,
  facilityNotFound,
  facilityAccessDenied,
  sportNotFound,
  facilitySportNotFound,
  duplicateFacilitySport,
  playingAreaNotFound,
  duplicatePlayingArea,
  invalidPlayingArea,
  setupIncomplete,
  courtNotFound,
  bookingNotFound,
  bookingConflict,
  invalidBooking,
  guestNotFound,
  invalidGuest,
  membershipPlanNotFound,
  invalidMembership,
  membershipNotFound,
  memberNotFound,
  memberAlreadyExists,
  invalidMember,
  membershipBatchNotFound,
  membershipSessionNotFound,
  invalidMembershipBatch,
  membershipCapacityError,
  paymentGatewayError,
  paymentOrderError,
  // Finance & Revenue Management — Phase 7. Deliberately distinct from
  // `unauthorized`/`databaseError`: a facility-isolation rejection on a
  // Finance read must never degrade into a silent ₹0 (spec §"Critical
  // Facility Isolation Test": the expected result is DENIED, not zero).
  financeAccessDenied,
  invalidDateRange,
  financeDataError,
  network,
  databaseError,
}

const Map<AppErrorCode, String> _friendlyMessage = {
  AppErrorCode.unauthenticated: 'Please sign in and try again.',
  AppErrorCode.unauthorized: "You don't have access to do that.",
  AppErrorCode.facilityNotFound: 'Facility not found.',
  AppErrorCode.facilityAccessDenied: "You don't have access to this facility.",
  AppErrorCode.sportNotFound: 'That sport could not be found.',
  AppErrorCode.facilitySportNotFound: "That sport hasn't been added to this facility.",
  AppErrorCode.duplicateFacilitySport: 'This sport has already been added to the facility.',
  AppErrorCode.playingAreaNotFound: 'Playing area not found.',
  AppErrorCode.duplicatePlayingArea: 'This name is already used for this sport.',
  AppErrorCode.invalidPlayingArea: "That value isn't valid.",
  AppErrorCode.setupIncomplete: 'Some required setup is still missing.',
  AppErrorCode.courtNotFound: 'That court or turf could not be found.',
  AppErrorCode.bookingNotFound: 'That booking could not be found.',
  AppErrorCode.bookingConflict: 'That time slot was just booked by someone else. Please pick another time.',
  AppErrorCode.invalidBooking: "That booking isn't valid. Check the time and try again.",
  AppErrorCode.guestNotFound: 'That guest could not be found.',
  AppErrorCode.invalidGuest: 'Enter a guest name to continue.',
  AppErrorCode.membershipPlanNotFound: 'That membership plan could not be found.',
  AppErrorCode.invalidMembership: "That membership isn't valid. Check the plan and start date and try again.",
  AppErrorCode.membershipNotFound: 'That membership could not be found.',
  AppErrorCode.memberNotFound: 'That member could not be found.',
  AppErrorCode.memberAlreadyExists: 'A member with this email already exists.',
  AppErrorCode.invalidMember: "That value isn't valid. Check the member's details and try again.",
  AppErrorCode.membershipBatchNotFound: 'That membership batch could not be found.',
  AppErrorCode.membershipSessionNotFound: 'That membership session could not be found.',
  AppErrorCode.invalidMembershipBatch: 'That court does not belong to this facility/sport.',
  AppErrorCode.membershipCapacityError: 'Unable to complete this action.',
  AppErrorCode.paymentGatewayError: 'Unable to reach the payment gateway. Please try again.',
  AppErrorCode.paymentOrderError: 'Unable to start this payment.',
  AppErrorCode.financeAccessDenied: "You don't have access to this facility's financial data.",
  AppErrorCode.invalidDateRange: 'Please choose a valid date range.',
  AppErrorCode.financeDataError: 'Unable to load financial data. Please try again.',
  AppErrorCode.network: 'Network error. Check your connection and try again.',
  AppErrorCode.databaseError: 'Something went wrong. Please try again.',
};

class AppException implements Exception {
  AppException(this.code, [String? message])
    : message = message ?? _friendlyMessage[code]!;

  final AppErrorCode code;
  final String message;

  @override
  String toString() => message;
}

/// Converts a raw Supabase/Postgrest/network error into an [AppException]
/// with a user-safe message. The real error is left in the caught
/// exception's `toString()` for debug logging, never surfaced to the UI.
AppException mapSupabaseError(
  Object error, {
  AppErrorCode? duplicate,
  AppErrorCode? notFound,
  AppErrorCode? invalid,
}) {
  if (error is AppException) return error;

  if (error is AuthException) {
    return AppException(AppErrorCode.unauthenticated, error.message);
  }

  if (error is PostgrestException) {
    final code = error.code;
    if (code == '23505' && duplicate != null) return AppException(duplicate);
    if (code == '23503' && notFound != null) return AppException(notFound);
    if (code == '23514' && invalid != null) return AppException(invalid);
    if (code == '42501') return AppException(AppErrorCode.unauthorized);
    if (code == '23P01') return AppException(AppErrorCode.bookingConflict);
    return AppException(AppErrorCode.databaseError);
  }

  return AppException(AppErrorCode.network);
}