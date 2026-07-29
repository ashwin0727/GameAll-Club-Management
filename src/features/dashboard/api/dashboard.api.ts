import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database.types";
import type { DashboardStats } from "@/features/dashboard/types";

export async function getDashboardStats(
  supabase: SupabaseClient<Database>,
): Promise<DashboardStats> {
  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
  const startOfTomorrow = new Date(
    now.getFullYear(),
    now.getMonth(),
    now.getDate() + 1,
  ).toISOString();
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();

  const [membersRes, membershipsRes, bookingsRes, paymentsRes] = await Promise.all([
    supabase.from("profiles").select("id", { count: "exact", head: true }).eq("role", "member"),
    supabase
      .from("memberships")
      .select("id", { count: "exact", head: true })
      .eq("status", "active"),
    supabase
      .from("bookings")
      .select("id", { count: "exact", head: true })
      .gte("start_time", startOfToday)
      .lt("start_time", startOfTomorrow)
      .in("status", ["pending", "confirmed"]),
    supabase.from("payments").select("amount_inr").eq("status", "paid").gte("created_at", startOfMonth),
  ]);

  if (membersRes.error) throw new Error(membersRes.error.message);
  if (membershipsRes.error) throw new Error(membershipsRes.error.message);
  if (bookingsRes.error) throw new Error(bookingsRes.error.message);
  if (paymentsRes.error) throw new Error(paymentsRes.error.message);

  const revenueThisMonthInr = (paymentsRes.data ?? []).reduce(
    (sum, row) => sum + row.amount_inr,
    0,
  );

  return {
    totalMembers: membersRes.count ?? 0,
    activeMemberships: membershipsRes.count ?? 0,
    activeBookingsToday: bookingsRes.count ?? 0,
    revenueThisMonthInr,
  };
}