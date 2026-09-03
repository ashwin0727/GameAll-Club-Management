import type { PostgrestError } from "@supabase/supabase-js";

export type ServiceErrorCode =
  | "UNAUTHENTICATED"
  | "UNAUTHORIZED"
  | "FACILITY_NOT_FOUND"
  | "FACILITY_ACCESS_DENIED"
  | "SPORT_NOT_FOUND"
  | "FACILITY_SPORT_NOT_FOUND"
  | "DUPLICATE_FACILITY_SPORT"
  | "PLAYING_AREA_NOT_FOUND"
  | "DUPLICATE_PLAYING_AREA"
  | "INVALID_PLAYING_AREA"
  | "SETUP_INCOMPLETE"
  | "COURT_NOT_FOUND"
  | "BOOKING_NOT_FOUND"
  | "BOOKING_CONFLICT"
  | "INVALID_BOOKING"
  | "GUEST_NOT_FOUND"
  | "INVALID_GUEST"
  | "MEMBER_NOT_FOUND"
  | "MEMBER_ALREADY_EXISTS"
  | "INVALID_MEMBER"
  | "MEMBERSHIP_NOT_FOUND"
  | "MEMBERSHIP_PLAN_NOT_FOUND"
  | "INVALID_MEMBERSHIP"
  | "MEMBERSHIP_BATCH_NOT_FOUND"
  | "INVALID_MEMBERSHIP_BATCH"
  | "MEMBERSHIP_SESSION_NOT_FOUND"
  | "MEMBERSHIP_CAPACITY_ERROR"
  | "PAYMENT_ORDER_ERROR"
  | "PAYMENT_GATEWAY_ERROR"
  | "FINANCE_ACCESS_DENIED"
  | "INVALID_DATE_RANGE"
  | "FINANCE_DATA_ERROR"
  | "REPORTS_ACCESS_DENIED"
  | "REPORTS_DATA_ERROR"
  | "DATABASE_ERROR";

const FRIENDLY_MESSAGE: Record<ServiceErrorCode, string> = {
  UNAUTHENTICATED: "Please sign in and try again.",
  UNAUTHORIZED: "You don't have access to do that.",
  FACILITY_NOT_FOUND: "Facility not found.",
  FACILITY_ACCESS_DENIED: "You don't have access to this facility.",
  SPORT_NOT_FOUND: "That sport could not be found.",
  FACILITY_SPORT_NOT_FOUND: "That sport hasn't been added to this facility.",
  DUPLICATE_FACILITY_SPORT: "This sport has already been added to the facility.",
  PLAYING_AREA_NOT_FOUND: "Playing area not found.",
  DUPLICATE_PLAYING_AREA: "This name is already used for this sport.",
  INVALID_PLAYING_AREA: "That playing area isn't valid.",
  SETUP_INCOMPLETE: "Some required setup is still missing.",
  COURT_NOT_FOUND: "That court or turf could not be found.",
  BOOKING_NOT_FOUND: "That booking could not be found.",
  BOOKING_CONFLICT: "That time slot was just booked by someone else. Please pick another time.",
  INVALID_BOOKING: "That booking isn't valid. Check the time and try again.",
  GUEST_NOT_FOUND: "That guest could not be found.",
  INVALID_GUEST: "Enter a guest name to continue.",
  MEMBER_NOT_FOUND: "That member could not be found.",
  MEMBER_ALREADY_EXISTS: "A member with this mobile number already exists.",
  INVALID_MEMBER: "Enter the member's name and mobile number to continue.",
  MEMBERSHIP_NOT_FOUND: "That membership could not be found.",
  MEMBERSHIP_PLAN_NOT_FOUND: "That membership plan is not available for this facility.",
  INVALID_MEMBERSHIP: "That membership isn't valid. Check the plan and start date and try again.",
  MEMBERSHIP_BATCH_NOT_FOUND: "That membership batch could not be found.",
  INVALID_MEMBERSHIP_BATCH: "That membership batch isn't valid. Check the court, sport, and schedule and try again.",
  MEMBERSHIP_SESSION_NOT_FOUND: "That membership session could not be found.",
  // Overridden per-call with the specific rule that was broken (e.g. "No guest slots are currently available") — see supabase-membership-session.service.ts.
  MEMBERSHIP_CAPACITY_ERROR: "Unable to complete this action.",
  // Overridden per-call with the specific rule the RPC rejected the request for.
  PAYMENT_ORDER_ERROR: "Unable to start this payment.",
  PAYMENT_GATEWAY_ERROR: "Unable to reach the payment gateway. Please try again.",
  FINANCE_ACCESS_DENIED: "You don't have access to this facility's financial data.",
  INVALID_DATE_RANGE: "Please choose a valid date range.",
  FINANCE_DATA_ERROR: "Unable to load financial data. Please try again.",
  REPORTS_ACCESS_DENIED: "You don't have access to this facility's reports.",
  REPORTS_DATA_ERROR: "Unable to load this report. Please try again.",
  DATABASE_ERROR: "Something went wrong. Please try again.",
};

export class ServiceError extends Error {
  readonly code: ServiceErrorCode;

  constructor(code: ServiceErrorCode, message: string = FRIENDLY_MESSAGE[code]) {
    super(message);
    this.name = "ServiceError";
    this.code = code;
  }
}

/**
 * Translates a raw Postgres/PostgREST error into a typed ServiceError with a
 * user-safe message. The real error is logged here (server or browser
 * console, whichever runs this) and never reaches the UI.
 */
export function mapSupabaseError(
  error: PostgrestError,
  context: { duplicate?: ServiceErrorCode; notFound?: ServiceErrorCode; invalid?: ServiceErrorCode } = {},
): ServiceError {
  console.error("[service-error]", error.code, error.message, error.details);

  if (error.code === "23505" && context.duplicate) {
    return new ServiceError(context.duplicate);
  }
  if (error.code === "23503" && context.notFound) {
    return new ServiceError(context.notFound);
  }
  // Raised by our own trigger-level consistency checks (see 0002_onboarding_backend.sql).
  if (error.code === "23514" && context.invalid) {
    return new ServiceError(context.invalid);
  }
  // PostgREST surfaces an RLS-blocked write as a permission error.
  if (error.code === "42501") {
    return new ServiceError("UNAUTHORIZED");
  }
  // Raised by the bookings table's own exclusion constraint (0001_init.sql) —
  // two live bookings tried to claim the same court/time at once.
  if (error.code === "23P01") {
    return new ServiceError("BOOKING_CONFLICT");
  }

  return new ServiceError("DATABASE_ERROR");
}