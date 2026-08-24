import type {
  MembershipBatch,
  MembershipBatchInput,
  MembershipBatchMember,
  MembershipSessionBooking,
  MembershipSessionCapacity,
  MembershipSessionSlot,
} from "@/features/membership-sessions/types";

export interface MembershipSessionService {
  getFacilityBatches(facilityId: string): Promise<MembershipBatch[]>;
  createBatch(input: MembershipBatchInput): Promise<MembershipBatch>;
  updateBatch(
    batchId: string,
    patch: Partial<Omit<MembershipBatchInput, "facilityId" | "planId" | "facilitySportId">> & { isActive?: boolean },
  ): Promise<MembershipBatch>;
  getBatchMembers(batchId: string): Promise<MembershipBatchMember[]>;
  assignBatchMember(batchId: string, memberId: string, membershipId?: string | null): Promise<MembershipBatchMember>;
  removeBatchMember(batchId: string, memberId: string): Promise<void>;
  /** The Owner Availability View's single read — every batch scheduled on this date, materialized or not. */
  listSessionsForDate(facilityId: string, date: string): Promise<MembershipSessionSlot[]>;
  /** Materializes the session occurrence row if it doesn't exist yet — needed before release/restore on a date nobody has booked against. */
  getOrCreateSession(batchId: string, sessionDate: string): Promise<string>;
  getSessionCapacity(sessionId: string): Promise<MembershipSessionCapacity>;
  bookMembershipSlot(batchId: string, sessionDate: string, memberId: string): Promise<MembershipSessionBooking>;
  releaseCapacity(sessionId: string, count: number): Promise<void>;
  restoreCapacity(sessionId: string, count: number): Promise<void>;
  bookGuestSlot(batchId: string, sessionDate: string, guestPlayerId: string): Promise<MembershipSessionBooking>;
  cancelSlotBooking(bookingId: string): Promise<void>;
}