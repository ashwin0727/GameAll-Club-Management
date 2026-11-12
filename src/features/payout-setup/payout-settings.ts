"use client";

import { createClient } from "@/lib/supabase/client";

export type SettlementFrequency = "DAILY" | "WEEKLY" | "MONTHLY";

export interface PayoutSettings {
  frequency: SettlementFrequency;
  /** Whole rupees. */
  minimumPayoutInr: number;
  includeBookings: boolean;
  includeMemberships: boolean;
  includeCoaching: boolean;
  autoPayout: boolean;
  holdForReview: boolean;
}

export const DEFAULT_PAYOUT_SETTINGS: PayoutSettings = {
  frequency: "DAILY",
  minimumPayoutInr: 500,
  includeBookings: true,
  includeMemberships: true,
  includeCoaching: true,
  autoPayout: true,
  holdForReview: false,
};

export const FREQUENCY_OPTIONS: readonly { value: SettlementFrequency; label: string; note: string }[] = [
  { value: "DAILY", label: "Daily (T+1)", note: "T+1 means the amount will be settled the next working day after a successful booking." },
  { value: "WEEKLY", label: "Weekly", note: "Earnings are settled once a week, on the first working day, for the week before." },
  { value: "MONTHLY", label: "Monthly", note: "Earnings are settled once a month, on the first working day, for the month before." },
];

export const MAX_MINIMUM_PAYOUT = 1_000_000;

/** What is wrong with a settings draft, or null when it can be saved. */
export function validatePayoutSettings(s: PayoutSettings): string | null {
  if (!Number.isInteger(s.minimumPayoutInr) || s.minimumPayoutInr < 0 || s.minimumPayoutInr > MAX_MINIMUM_PAYOUT) {
    return `Enter a minimum payout between ₹0 and ₹${MAX_MINIMUM_PAYOUT.toLocaleString("en-IN")}.`;
  }
  if (!s.includeBookings && !s.includeMemberships && !s.includeCoaching) return "Choose at least one earning to include in your payouts.";
  return null;
}

type Row = Record<string, unknown>;

function toSettings(r: Row): PayoutSettings {
  return {
    frequency: (r.settlement_frequency as SettlementFrequency) ?? "DAILY",
    minimumPayoutInr: Number(r.minimum_payout_inr ?? 500),
    includeBookings: r.include_bookings !== false,
    includeMemberships: r.include_memberships !== false,
    includeCoaching: r.include_coaching !== false,
    autoPayout: r.auto_payout !== false,
    holdForReview: r.hold_for_review === true,
  };
}

// facility_payout_settings arrives with migration 0200 and is not in the generated types yet.
type UntypedTable = {
  select: (c: string) => { eq: (c: string, v: string) => { maybeSingle: () => Promise<{ data: Row | null; error: { message: string } | null }> } };
  upsert: (row: Row, o: { onConflict: string }) => Promise<{ error: { message: string } | null }>;
};
const table = () => (createClient() as unknown as { from: (t: string) => UntypedTable }).from("facility_payout_settings");

export async function loadPayoutSettings(facilityId: string): Promise<PayoutSettings> {
  const { data, error } = await table().select("*").eq("facility_id", facilityId).maybeSingle();
  if (error) throw new Error("Unable to load your payout settings.");
  return data ? toSettings(data) : DEFAULT_PAYOUT_SETTINGS;
}

export async function savePayoutSettings(facilityId: string, s: PayoutSettings): Promise<void> {
  const problem = validatePayoutSettings(s);
  if (problem) throw new Error(problem);
  const { error } = await table().upsert(
    {
      facility_id: facilityId,
      settlement_frequency: s.frequency,
      minimum_payout_inr: s.minimumPayoutInr,
      include_bookings: s.includeBookings,
      include_memberships: s.includeMemberships,
      include_coaching: s.includeCoaching,
      auto_payout: s.autoPayout,
      hold_for_review: s.holdForReview,
    },
    { onConflict: "facility_id" },
  );
  if (error) throw new Error("Could not save your payout settings. Please try again.");
}
