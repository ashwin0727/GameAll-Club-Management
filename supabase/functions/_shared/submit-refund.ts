// ═══════════════════════════════════════════════════════════════════════════
// submit-refund — shared "take a REQUESTED refund row to Razorpay" step,
// used by cancel-booking, cancel-membership-slot, and cancel-membership
// right after their DB-side cancellation RPC returns a refund id. Kept out
// of _shared/refunds.ts (which stays pure/DB-and-fetch-free for unit
// testing) since this one genuinely needs a Supabase client + a real
// Razorpay HTTP call.
// ═══════════════════════════════════════════════════════════════════════════

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { createRazorpayRefund } from "./razorpay.ts";

export interface SubmitRefundResult {
  refundId: string;
  status: string;
  razorpayRefundId?: string;
}

/** Loads a REQUESTED refund row and submits it to Razorpay; marks it PROCESSING on success or FAILED on error. A refund already past REQUESTED (a concurrent call beat this one to it) is returned as-is, untouched. */
export async function submitRequestedRefund(supabase: SupabaseClient, refundId: string, keyId: string, keySecret: string): Promise<SubmitRefundResult> {
  const { data: refund, error } = await supabase.rpc("get_refund", { p_refund_id: refundId });
  if (error || !refund) {
    throw new Error(`Unable to load refund ${refundId} before submitting to Razorpay: ${error?.message ?? "not found"}`);
  }
  if (refund.status !== "REQUESTED") {
    return { refundId, status: refund.status };
  }

  const reference = `GAMEALL-REFUND-${refundId.slice(0, 8).toUpperCase()}`;
  try {
    const razorpayRefund = await createRazorpayRefund(refund.razorpay_payment_id, refund.amount_minor, keyId, keySecret, reference);
    const { data: updated, error: markError } = await supabase.rpc("mark_refund_processing", { p_refund_id: refundId, p_razorpay_refund_id: razorpayRefund.id });
    if (markError) {
      console.error("[submit-refund] mark_refund_processing failed after a successful Razorpay call", { refundId, message: markError.message });
    }
    return { refundId, status: updated?.status ?? "PROCESSING", razorpayRefundId: razorpayRefund.id };
  } catch (err) {
    console.error("[submit-refund] Razorpay refund call failed", { refundId, error: String(err) });
    const { data: failed } = await supabase.rpc("mark_refund_failed", { p_refund_id: refundId, p_error: String(err) });
    return { refundId, status: failed?.status ?? "FAILED" };
  }
}