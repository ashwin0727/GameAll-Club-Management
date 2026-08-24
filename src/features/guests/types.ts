export type GuestStatus = "ACTIVE" | "INACTIVE";

export interface GuestPlayer {
  id: string;
  facilityId: string;
  name: string;
  phone: string | null;
  email: string | null;
  notes: string | null;
  status: GuestStatus;
  createdAt: string;
  updatedAt: string;
}

export interface GuestInput {
  facilityId: string;
  name: string;
  phone?: string | null;
  email?: string | null;
  notes?: string | null;
}

export interface GuestSportPlayed {
  sportId: string;
  sportName: string;
}

/** Everything on the Guest Profile screen — derived live from real bookings, never a maintained counter. */
export interface GuestStats {
  totalVisits: number;
  totalBookings: number;
  /** ISO timestamp of the most recent confirmed/completed booking, or null if the guest has never visited. */
  lastVisit: string | null;
  totalAmountMinor: number;
  pendingAmountMinor: number;
  sports: GuestSportPlayed[];
}