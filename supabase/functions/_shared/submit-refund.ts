// ═══════════════════════════════════════════════════════════════════════════
// submit-refund — shared "take a REQUESTED refund row to Razorpay" step,
// used by cancel-booking, cancel-membership-slot, cancel-membership, and
// create-razorpay-refund right after their DB-side refund RPC returns a
// refund id. Kept out of _shared/refunds.ts (which stays pure/DB-and-
// fetch-free for unit testing) since this one genuinely needs a Supabase
// client + a real Razorpay HTTP call.
//
// Concurrency: the REQUESTED → PROCESSING transition is claimed atomically
// in Postgres (claim_refund_for_submission, 0064) BEFORE the Razorpay call.
// Two concurrent invocations for the same refund id can never both reach
// createRazorpayRefund — exactly one wins the claim, the other returns the
// current status untouched.
// ═══════════════════════════════════════════════════════════════════════════

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { createRazorpayRefund } from "./razorpay.ts";

export interface SubmitRefundResult {
  refundId: string;
  status: string;
  razorpayRefundId?: string;
}

/**
 * Atomically claims a REQUESTED refund (REQUESTED → PROCESSING) and, if this
 * caller won the claim, submits it to Razorpay and records the refund id
 * (or marks it FAILED on error). A refund that is not REQUESTED — already
 * claimed by a concurrent call, already processed, or already failed — is
 * returned as-is, untouched, and Razorpay is never called.
 */
export async function submitRequestedRefund(
  supabase: SupabaseClient,
  refundId: string,
  keyId: string,
  keySecret: string,
): Promise<SubmitRefundResult> {
  const { data: claimed, error: claimError } = await supabase.rpc("claim_refund_for_submission", {
    p_refund_id: refundId,
  });
  if (claimError) {
    throw new Error(`Unable to claim refund ${refundId} for submission: ${claimError.message}`);
  }

  // NULL row back (no `id`) → lost the race, or the refund was already past
  // REQUESTED. Do NOT call Razorpay. Report whatever state it is actually in.
  if (!claimed?.id) {
    const { data: current } = await supabase.rpc("get_refund", { p_refund_id: refundId });
    return { refundId, status: current?.status ?? "PROCESSING" };
  }

  const reference = `GAMEALL-REFUND-${refundId.slice(0, 8).toUpperCase()}`;
  try {
    const razorpayRefund = await createRazorpayRefund(claimed.razorpay_payment_id, claimed.amount_minor, keyId, keySecret, reference);
    const { data: updated, error: markError } = await supabase.rpc("set_refund_razorpay_id", {
      p_refund_id: refundId,
      p_razorpay_refund_id: razorpayRefund.id,
    });
    if (markError) {
      // The Razorpay call succeeded; only the id write failed. The
      // refund.created / refund.processed webhook's fallback lookup by
      // razorpay_payment_id (apply_refund_webhook) still resolves this.
      console.error("[submit-refund] set_refund_razorpay_id failed after a successful Razorpay call", { refundId, message: markError.message });
    }
    return { refundId, status: updated?.status ?? "PROCESSING", razorpayRefundId: razorpayRefund.id };
  } catch (err) {
    console.error("[submit-refund] Razorpay refund call failed", { refundId, error: String(err) });
    const { data: failed } = await supabase.rpc("mark_refund_failed", { p_refund_id: refundId, p_error: String(err) });
    return { refundId, status: failed?.status ?? "FAILED" };
  }
}
