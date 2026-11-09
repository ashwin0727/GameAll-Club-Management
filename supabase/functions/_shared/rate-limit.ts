// A shared, database-backed rate limit for the edge functions (migration 0185: check_rate_limit).
//
// The Player app polls and taps; the expensive things behind it (Razorpay calls, payment links, bookings) must not scale with how
// often a client chooses to call. A function asks `allowed(...)` first and, when it says no, answers from what it already knows (or 429)
// instead of doing the work again.
//
// It FAILS OPEN: if the limiter itself is unreachable the call goes ahead. The limiter protects capacity; it must never be the reason a
// player cannot pay.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export async function allowed(admin: SupabaseClient, bucket: string, limit: number, windowSeconds = 60): Promise<boolean> {
  try {
    const { data, error } = await admin.rpc("check_rate_limit", { p_bucket: bucket, p_limit: limit, p_window_seconds: windowSeconds });
    if (error) {
      console.error("[rate-limit] check failed, letting the call through", error.message);
      return true;
    }
    return data === true;
  } catch (err) {
    console.error("[rate-limit] check threw, letting the call through", String(err));
    return true;
  }
}
