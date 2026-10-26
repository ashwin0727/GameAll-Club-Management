export type PlanInterval = "month" | "quarter" | "year";

/** GameAll's own plan for a facility — what the owner pays GameAll (a membership fee, not a commission). */
export interface FacilityPlan {
  /** True for the placeholder shown until real plans are synced in. */
  isSample?: boolean;
  id: string;
  planName: string;
  priceMinor: number;
  currency: string;
  interval: PlanInterval;
  /** The stored status: "trialing" is the free trial before the first charge; "cancelled" is a plan the facility has ended. */
  status: "active" | "trialing" | "cancelled";
  /** yyyy-mm-dd — the last day the plan covers. */
  validTill: string;
  features: string[];
}

export type PayoutMethodType = "BANK" | "UPI";

/** GameAll checks every payout method by hand before sending money to it. */
export type PayoutVerification = "PENDING" | "VERIFIED" | "REJECTED";

export interface PayoutMethod {
  id: string;
  type: PayoutMethodType;
  accountHolderName: string;
  bankName: string | null;
  accountNumber: string | null;
  ifsc: string | null;
  upiId: string | null;
  isPrimary: boolean;
  verification: PayoutVerification;
  /** ISO timestamp of the manual check; null until verified. */
  verifiedAt: string | null;
  /** Why a method was rejected, written by GameAll. */
  verificationNote: string | null;
  createdAt: string;
}

export type PayoutMethodInput =
  | { type: "BANK"; accountHolderName: string; bankName: string; accountNumber: string; ifsc: string }
  | { type: "UPI"; accountHolderName: string; upiId: string };

export type SupportCategory = "GENERAL" | "BILLING" | "BOOKINGS" | "PAYMENTS" | "TECHNICAL" | "OTHER";
export type SupportStatus = "OPEN" | "IN_PROGRESS" | "RESOLVED" | "CLOSED";

export interface SupportTicket {
  id: string;
  category: SupportCategory;
  subject: string;
  message: string;
  status: SupportStatus;
  createdAt: string;
}

export interface SupportTicketInput {
  category: SupportCategory;
  subject: string;
  message: string;
}

/** The headline numbers on the profile page. */
export interface ProfileStats {
  /** This month. */
  totalBookings: number;
  activeMembers: number;
  courts: number;
  /** This month. */
  totalRevenueMinor: number;
}

export interface NotificationPrefs {
  bookings: boolean;
  payments: boolean;
  memberships: boolean;
  reports: boolean;
}

export interface ProfileUpdate {
  fullName: string;
  phone: string | null;
  avatarUrl?: string | null;
}
