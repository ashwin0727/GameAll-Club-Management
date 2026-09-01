export interface MembershipBatch {
  id: string;
  facilityId: string;
  planId: string | null;
  facilitySportId: string;
  courtId: string;
  name: string;
  /** 0=Sunday..6=Saturday, matching JS Date#getDay(). */
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
  capacity: number;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface MembershipBatchInput {
  facilityId: string;
  planId: string;
  facilitySportId: string;
  courtId: string;
  name: string;
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
  capacity: number;
}

export interface MembershipBatchMember {
  id: string;
  batchId: string;
  memberId: string;
  membershipId: string | null;
  createdAt: string;
}

/**
 * One row in the Owner Availability View — a batch's occurrence on a
 * specific date, whether or not it has been materialized into an actual
 * `membership_sessions` row yet (sessionId is null until the first
 * booking/release/restore against that date).
 */
export interface MembershipSessionSlot {
  batchId: string;
  sessionId: string | null;
  batchName: string;
  courtId: string;
  courtName: string;
  facilitySportId: string;
  sportName: string;
  sessionDate: string;
  startTime: string;
  endTime: string;
  capacity: number;
  releasedCapacity: number;
  memberBookedCount: number;
  guestBookedCount: number;
}

/** Every count the capacity UI needs, derived live — never a maintained counter. */
export interface MembershipSessionCapacity {
  capacity: number;
  releasedCapacity: number;
  memberBookedCount: number;
  guestBookedCount: number;
  unusedCapacity: number;
  guestAvailableCapacity: number;
}

export interface MembershipSessionBooking {
  id: string;
  sessionId: string;
  facilityId: string;
  participantType: "MEMBER" | "GUEST";
  memberId: string | null;
  guestPlayerId: string | null;
  status: "CONFIRMED" | "CANCELLED";
  slotSource: "MEMBERSHIP" | "RELEASED";
  amountMinor: number | null;
  currency: string;
  createdBy: string;
  createdAt: string;
}
// ─────────────────────────────────────────────────────────────────────────
// Membership Sessions dashboard (Phase 9).
// ─────────────────────────────────────────────────────────────────────────

export interface MembershipSessionsSummary {
  totalSessions: number;
  activeSessions: number;
  todaysSessions: number;
  guestSlotsReleased: number;
  avgUtilizationPct: number;
}

export type MembershipSessionStatus = "active" | "paused" | "full";

export interface MembershipSessionListRow {
  batchId: string;
  name: string;
  courtId: string;
  courtName: string;
  facilitySportId: string;
  sportName: string;
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
  capacity: number;
  rosterCount: number;
  releasedToday: number;
  guestBookedToday: number;
  utilizationPct: number;
  status: MembershipSessionStatus;
  isActive: boolean;
}

export interface MembershipSessionListParams {
  search?: string;
  facilitySportId?: string;
  courtId?: string;
  status?: MembershipSessionStatus;
  day?: number;
  page: number;
  perPage: number;
}

export interface MembershipSessionListResult {
  rows: MembershipSessionListRow[];
  totalCount: number;
}

export interface MembershipSessionMemberRow {
  id: string;
  memberId: string;
  fullName: string;
  phone: string;
  status: string;
  addedOn: string;
}

export interface MembershipSessionDetail {
  batchId: string;
  facilityId: string;
  facilityName: string | null;
  facilityAddress: string | null;
  name: string;
  notes: string | null;
  courtId: string;
  courtName: string;
  facilitySportId: string;
  sportName: string;
  planName: string | null;
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
  capacity: number;
  isActive: boolean;
  createdByName: string | null;
  createdAt: string;
  updatedAt: string;
  rosterCount: number;
  guestsBookedToday: number;
  releasedToday: number;
  availableToRelease: number;
  runsToday: boolean;
  nextOccurrenceDate: string | null;
}

export interface MembershipSessionOccurrence {
  occurrenceDate: string;
  isBlocked: boolean;
  blockReason: string | null;
  materialized: boolean;
  memberCount: number;
  guestCount: number;
  releasedCapacity: number;
}

export interface MembershipSessionBookingRow {
  bookingId: string;
  sessionDate: string;
  participantType: "MEMBER" | "GUEST";
  participantName: string;
  slotSource: "MEMBERSHIP" | "RELEASED";
  status: "CONFIRMED" | "CANCELLED";
  amountMinor: number | null;
  createdAt: string;
}

export interface MembershipSessionActivity {
  kind: string;
  actor: string | null;
  detail: string;
  at: string;
}
