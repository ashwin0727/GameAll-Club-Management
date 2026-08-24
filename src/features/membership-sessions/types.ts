export interface MembershipBatch {
  id: string;
  facilityId: string;
  planId: string;
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