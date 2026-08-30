import { createClient } from "@/lib/supabase/client";
import type {
  PublicSignupBatch,
  PublicSignupInfo,
  PublicSignupResult,
  MembershipSubscriptionInfo,
} from "@/features/memberships/types";

/** Public, unauthenticated: facility name + its active plans for the /join page. */
export async function getPublicSignupInfo(facilityId: string): Promise<PublicSignupInfo | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_public_membership_signup_info", { p_facility_id: facilityId });
  if (error || !data || !data.facilityId) return null;
  return {
    facilityId: data.facilityId,
    facilityName: data.facilityName,
    city: data.city,
    plans: data.plans ?? [],
  };
}

/** Public: time-slots (with a free seat) for the chosen plan. */
export async function getPublicSignupBatches(facilityId: string, planId: string): Promise<PublicSignupBatch[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_public_signup_batches", {
    p_facility_id: facilityId,
    p_plan_id: planId,
  });
  if (error || !Array.isArray(data)) return [];
  return data as PublicSignupBatch[];
}

/** Public: get-or-create the member and a pending self-registered membership. */
export async function startPublicSignup(input: {
  facilityId: string;
  fullName: string;
  phone: string;
  email: string;
  planId: string;
  batchId?: string | null;
}): Promise<PublicSignupResult> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("public_start_membership_signup", {
    p_facility_id: input.facilityId,
    p_full_name: input.fullName,
    p_phone: input.phone,
    p_email: input.email,
    p_plan_id: input.planId,
    p_batch_id: input.batchId ?? null,
  });
  if (error || !data?.membershipId) {
    throw new Error(error?.message ?? "Could not start your membership. Please try again.");
  }
  return { membershipId: data.membershipId, memberId: data.memberId, amountInr: data.amountInr };
}

/** Public: create the Razorpay Subscription and get the mandate authorisation URL. */
export async function startPublicSubscription(membershipId: string): Promise<MembershipSubscriptionInfo> {
  const supabase = createClient();
  const { data, error } = await supabase.functions.invoke<
    { subscriptionId: string; shortUrl: string | null; keyId: string } | { error: string }
  >("create-membership-subscription", { body: { membershipId } });
  if (error || !data || "error" in data) {
    throw new Error("Could not set up recurring payment. Please try again.");
  }
  return { subscriptionId: data.subscriptionId, shortUrl: data.shortUrl, keyId: data.keyId };
}