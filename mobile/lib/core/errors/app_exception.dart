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