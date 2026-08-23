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

  return new ServiceError("DATABASE_ERROR");
}