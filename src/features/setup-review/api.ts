import { createClient } from "@/lib/supabase/client";

export type ReviewStatus = "NOT_SUBMITTED" | "PENDING" | "APPROVED" | "REJECTED";

export interface MyReview {
  status: ReviewStatus;
  note: string | null;
  submittedAt: string | null;
  reviewedAt: string | null;
}

// Migration 0200 is newer than the generated database types.
type Rpc = (fn: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }>;
const rpc: Rpc = (fn, args) => {
  const supabase = createClient();
  return (supabase.rpc as unknown as Rpc).call(supabase, fn, args);
};

export async function fetchMyReview(facilityId: string): Promise<MyReview | null> {
  const { data, error } = await rpc("my_facility_review", { p_facility_id: facilityId });
  if (error) throw new Error("Unable to check the review status.");
  return (data as MyReview | null) ?? null;
}

/** After a rejection: sends the (edited) setup back to GameAll. Owner only; the database refuses anyone else. */
export async function resubmitForReview(facilityId: string): Promise<void> {
  const { error } = await rpc("resubmit_facility_for_review", { p_facility_id: facilityId });
  if (error) throw new Error(error.message || "Could not send your setup for review.");
}

/** Best effort: used right after "Complete Setup" on a facility GameAll had sent back, so editing + finishing re-submits it. */
export async function resubmitIfRejected(facilityId: string): Promise<void> {
  const review = await fetchMyReview(facilityId).catch(() => null);
  if (review?.status === "REJECTED") await resubmitForReview(facilityId);
}
