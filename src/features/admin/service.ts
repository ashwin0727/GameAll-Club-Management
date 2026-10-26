import { createClient } from "@/lib/supabase/client";

// The admin RPCs (migration 0160) are newer than the generated database types, hence the casts. Every one of them refuses
// anyone but the platform admin on the server — nothing here is a security boundary.
type Rpc = (fn: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }>;

async function call<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const supabase = createClient();
  const { data, error } = await (supabase.rpc as unknown as Rpc).call(supabase, fn, args);
  if (error) throw new Error(error.message || "Something went wrong.");
  return data as T;
}

export interface AdminOverview {
  facilities: number;
  onboarded: number;
  inProgress: number;
  courts: number;
  sports: number;
  activeMemberships: number;
  activeStudents: number;
  payoutsPending: number;
  unsettledInr: number;
  settledInr: number;
}

export interface AdminFacilityRow {
  id: string;
  name: string;
  city: string | null;
  state: string | null;
  status: string;
  onboardingStep: string;
  createdAt: string;
  ownerName: string | null;
  ownerEmail: string | null;
  ownerPhone: string | null;
  sports: number;
  courts: number;
  activeMemberships: number;
  activeStudents: number;
  payoutVerified: number;
  payoutPending: number;
  planName: string | null;
}

export interface AdminFacilityDetail {
  facility: {
    id: string;
    name: string;
    type: string | null;
    status: string;
    onboardingStep: string;
    createdAt: string;
    onboardingCompletedAt: string | null;
    businessEmail: string | null;
    businessPhone: string | null;
    address: string;
    city: string | null;
    timezone: string | null;
    description: string | null;
  };
  owner: { name: string | null; email: string | null; phone: string | null };
  sports: { name: string; active: boolean; courts: number }[];
  courts: { name: string; sport: string | null; surface: string | null; hourlyRateInr: number; status: string; bookingEnabled: boolean }[];
  memberships: { plans: number; active: number; pending: number; members: number; collectedInr: number };
  coaching: { coaches: number; programs: number; activeStudents: number; collectedInr: number };
  payments: {
    onlineCount: number;
    onlineInr: number;
    offlineCount: number;
    offlineInr: number;
    refundedInr: number;
    settledInr: number;
    unsettledInr: number;
  };
  plan: { name: string; status: string; interval: string; priceMinor: number; validTill: string } | null;
  payoutMethods: { id: string; type: "BANK" | "UPI"; verification: PayoutVerification; primary: boolean }[];
}

export type PayoutVerification = "PENDING" | "VERIFIED" | "REJECTED";

export interface AdminPayoutFacility {
  id: string;
  name: string;
  city: string | null;
  ownerName: string | null;
  ownerEmail: string | null;
  total: number;
  pending: number;
  verified: number;
  rejected: number;
  updatedAt: string | null;
}

export interface AdminPayoutMethod {
  id: string;
  type: "BANK" | "UPI";
  accountHolderName: string;
  bankName: string | null;
  accountNumber: string | null;
  ifsc: string | null;
  upiId: string | null;
  primary: boolean;
  verification: PayoutVerification;
  verifiedAt: string | null;
  note: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface AdminPayoutDetail {
  facility: { id: string; name: string; city: string | null; ownerName: string | null; ownerEmail: string | null; ownerPhone: string | null } | null;
  methods: AdminPayoutMethod[];
}

export interface AdminTransactionFacility {
  id: string;
  name: string;
  city: string | null;
  recentCount: number;
  recentInr: number;
  settledCount: number;
  settledInr: number;
  lastAt: string | null;
}

export interface AdminTransaction {
  id: string;
  at: string;
  amountInr: number;
  status: "paid" | "refunded" | string;
  method: string;
  razorpayPaymentId: string;
  razorpayOrderId: string | null;
  source: "Booking" | "Membership" | "Coaching" | "Other";
  payer: string | null;
  settledAt: string | null;
  settledNote: string | null;
}

export type TransactionView = "recent" | "settled";

export const adminApi = {
  overview: () => call<AdminOverview>("admin_overview"),
  facilities: (search: string, limit: number, offset: number) =>
    call<{ total: number; rows: AdminFacilityRow[] }>("admin_list_facilities", { p_search: search || null, p_limit: limit, p_offset: offset }),
  facility: (id: string) => call<AdminFacilityDetail>("admin_get_facility", { p_facility_id: id }),
  payoutFacilities: () => call<AdminPayoutFacility[]>("admin_list_payout_facilities"),
  payoutMethods: (facilityId: string) => call<AdminPayoutDetail>("admin_list_payout_methods", { p_facility_id: facilityId }),
  reviewPayout: (methodId: string, status: PayoutVerification, note: string | null) =>
    call<void>("admin_review_payout_method", { p_method_id: methodId, p_status: status, p_note: note }),
  transactionFacilities: () => call<AdminTransactionFacility[]>("admin_list_transaction_facilities"),
  transactions: (facilityId: string, view: TransactionView, limit: number, offset: number) =>
    call<{ total: number; totalInr: number; rows: AdminTransaction[] }>("admin_list_transactions", {
      p_facility_id: facilityId,
      p_view: view,
      p_limit: limit,
      p_offset: offset,
    }),
  markSettled: (paymentIds: string[], note: string | null) => call<number>("admin_mark_settled", { p_payment_ids: paymentIds, p_note: note }),
  unsettle: (paymentId: string) => call<void>("admin_unsettle", { p_payment_id: paymentId }),
};
