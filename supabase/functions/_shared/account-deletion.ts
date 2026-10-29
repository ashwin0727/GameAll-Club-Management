// ═══════════════════════════════════════════════════════════════════════════
// Account deletion — shared by the delete-account function (the person asks) and the notification-worker (finishes closed
// accounts once their payments are settled). See migration 0163 for the database side.
//
//   • Everything is deleted — the facility and all its data, staff who only worked there, and the sign-in itself.
//   • EXCEPT while online payments of the club are still waiting to be settled: then the account is only CLOSED (sign-in
//     blocked, bookings stopped, recurring payments cancelled) and the records are kept until settlement is done.
//   • Recurring payments (Auto Pay) are always cancelled, so nobody keeps being charged for a club that is gone.
//   • The administrator account can never be deleted.
//
// Safe to run again after a partial failure: each step only acts on what is still there.
// ═══════════════════════════════════════════════════════════════════════════

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const ADMIN_EMAIL = "admin@gameall.co";
const PLACEHOLDER_EMAIL = "deleted-user@gameall.invalid";
const BAN_FOREVER = "876000h";

export type DeletionOutcome =
  | { status: "deleted" }
  | { status: "pending"; unsettledCount: number; unsettledInr: number };

interface DeletionPlan {
  facilities: string[];
  razorpaySubscriptions: string[];
  orphanStaff: string[];
}

/** Records the person wrote in other people's facilities are re-pointed at this stand-in account before their own is deleted. */
async function ensurePlaceholderUser(admin: SupabaseClient): Promise<string> {
  const { data } = await admin.from("platform_settings").select("value").eq("key", "deleted_user_id").maybeSingle();
  if (data?.value) return data.value as string;

  const created = await admin.auth.admin.createUser({
    email: PLACEHOLDER_EMAIL,
    password: crypto.randomUUID() + crypto.randomUUID(),
    email_confirm: true,
    user_metadata: { full_name: "Deleted user" },
    ban_duration: BAN_FOREVER,
  });
  let id = created.data.user?.id;
  if (!id) {
    // Already created by an earlier or concurrent run: find it.
    const list = await admin.auth.admin.listUsers({ perPage: 1000 });
    id = list.data.users.find((u) => u.email === PLACEHOLDER_EMAIL)?.id;
  }
  if (!id) throw new Error("Could not prepare the deletion placeholder account.");
  await admin.from("platform_settings").upsert({ key: "deleted_user_id", value: id });
  return id;
}

async function cancelRazorpaySubscriptions(ids: string[], keyId?: string, keySecret?: string): Promise<void> {
  if (!keyId || !keySecret) return;
  for (const id of ids) {
    try {
      await fetch(`https://api.razorpay.com/v1/subscriptions/${id}/cancel`, {
        method: "POST",
        headers: { Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`, "Content-Type": "application/json" },
        body: JSON.stringify({ cancel_at_cycle_end: 0 }),
      });
    } catch (err) {
      // Already cancelled or finished: nothing more to stop.
      console.warn("[account-deletion] could not cancel subscription", id, String(err));
    }
  }
}

async function rpc<T>(admin: SupabaseClient, fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await admin.rpc(fn, args);
  if (error) throw new Error(`${fn} failed: ${error.message}`);
  return data as T;
}

/** The final step, once nothing is waiting to be settled: delete the data, the orphaned staff and the sign-in. */
async function deleteEverything(admin: SupabaseClient, userId: string, plan: DeletionPlan): Promise<void> {
  const placeholder = await ensurePlaceholderUser(admin);

  await rpc(admin, "delete_owned_facilities", { p_user: userId });

  for (const staffId of plan.orphanStaff) {
    await rpc(admin, "reassign_user_references", { p_user: staffId, p_placeholder: placeholder });
    const { error } = await admin.auth.admin.deleteUser(staffId);
    if (error) throw new Error(`Could not delete staff account: ${error.message}`);
  }

  await rpc(admin, "reassign_user_references", { p_user: userId, p_placeholder: placeholder });
  const { error } = await admin.auth.admin.deleteUser(userId);
  if (error) throw new Error(`Could not delete the account: ${error.message}`);

  await admin.from("account_deletions").delete().eq("user_id", userId);
}

/** The person asked to delete their account: delete it, or close it if payments are still waiting to be settled. */
export async function closeOrDeleteAccount(
  admin: SupabaseClient,
  userId: string,
  keys: { keyId?: string; keySecret?: string },
): Promise<DeletionOutcome> {
  const { data: found, error: findError } = await admin.auth.admin.getUserById(userId);
  if (findError || !found.user) throw new Error("Account not found.");
  const email = found.user.email ?? "";
  if (email.toLowerCase() === ADMIN_EMAIL) throw new Error("The administrator account cannot be deleted.");

  const plan = await rpc<DeletionPlan>(admin, "account_deletion_plan", { p_user: userId });
  const blockers = await rpc<{ unsettledCount: number; unsettledInr: number }>(admin, "account_deletion_blockers", { p_user: userId });

  // Either way, stop charging the club's customers.
  await cancelRazorpaySubscriptions(plan.razorpaySubscriptions, keys.keyId, keys.keySecret);

  if (blockers.unsettledCount > 0) {
    await rpc(admin, "close_owned_facilities", { p_user: userId });
    await admin.from("account_deletions").upsert({ user_id: userId, email, status: "pending_settlement" });
    const { error } = await admin.auth.admin.updateUserById(userId, { ban_duration: BAN_FOREVER });
    if (error) throw new Error(`Could not close the account: ${error.message}`);
    return { status: "pending", unsettledCount: blockers.unsettledCount, unsettledInr: blockers.unsettledInr };
  }

  await deleteEverything(admin, userId, plan);
  return { status: "deleted" };
}

/** Run from the notification-worker: complete every closed account whose payments have now all been settled. */
export async function finishPendingDeletions(admin: SupabaseClient, keys: { keyId?: string; keySecret?: string }): Promise<number> {
  const { data: waiting } = await admin.from("account_deletions").select("user_id").eq("status", "pending_settlement").limit(20);
  let done = 0;
  for (const row of waiting ?? []) {
    try {
      const userId = row.user_id as string;
      const blockers = await rpc<{ unsettledCount: number }>(admin, "account_deletion_blockers", { p_user: userId });
      if (blockers.unsettledCount > 0) continue;
      const plan = await rpc<DeletionPlan>(admin, "account_deletion_plan", { p_user: userId });
      await cancelRazorpaySubscriptions(plan.razorpaySubscriptions, keys.keyId, keys.keySecret);
      await deleteEverything(admin, userId, plan);
      done++;
    } catch (err) {
      console.error("[account-deletion] could not finish", row.user_id, String(err));
    }
  }
  return done;
}
