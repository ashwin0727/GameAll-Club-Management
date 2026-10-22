/** What is still ahead on a court (court_upcoming_usage, migration 0150). */
export interface CourtUsage {
  bookings: number;
  membershipBatches: number;
  membershipGuestSlots: number;
  coachingSessions: number;
  coachingBatches: number;
  total: number;
}

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

/** "2 upcoming bookings, 1 membership session batch" — what stands in the way of removing a court. */
export function describeCourtUsage(u: CourtUsage): string {
  return [
    u.bookings > 0 && plural(u.bookings, "upcoming booking", "upcoming bookings"),
    u.membershipBatches > 0 && plural(u.membershipBatches, "membership session batch", "membership session batches"),
    u.membershipGuestSlots > 0 && `${plural(u.membershipGuestSlots, "guest slot", "guest slots")} in membership sessions`,
    u.coachingSessions > 0 && plural(u.coachingSessions, "upcoming coaching session", "upcoming coaching sessions"),
    u.coachingBatches > 0 && `${plural(u.coachingBatches, "coaching batch", "coaching batches")} with students`,
  ]
    .filter(Boolean)
    .join(", ");
}
