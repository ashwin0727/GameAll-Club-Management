"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { DEFAULT_NOTIFICATION_PREFS } from "@/features/profile/plan";
import type {
  FacilityPlan,
  NotificationPrefs,
  PayoutMethod,
  PayoutMethodInput,
  PlanInterval,
  ProfileStats,
  ProfileUpdate,
  SupportCategory,
  SupportStatus,
  SupportTicket,
  SupportTicketInput,
} from "@/features/profile/types";
import { getFinanceService } from "@/services/finance";
import type { ProfileService } from "@/services/profile/profile.service";
import { getReportsService } from "@/services/reports";
import { ServiceError } from "@/services/shared/service-error";

// The tables below arrive with migration 0148 and are not in the generated
// database types yet, so this service talks to an untyped client and maps the
// rows by hand.
type Row = Record<string, unknown>;

function fail(error: { code?: string; message?: string }, fallback: string): ServiceError {
  console.error("[profile-service]", error.code, error.message);
  if (error.code === "42501") return new ServiceError("UNAUTHORIZED");
  return new ServiceError("DATABASE_ERROR", fallback);
}

const toPlan = (r: Row): FacilityPlan => ({
  id: r.id as string,
  planName: r.plan_name as string,
  priceMinor: Number(r.price_minor),
  currency: (r.currency as string) ?? "INR",
  interval: r.billing_interval as PlanInterval,
  status: r.status as FacilityPlan["status"],
  validTill: r.valid_till as string,
  features: (r.features as string[] | null) ?? [],
  autoPay: Boolean(r.razorpay_subscription_id),
});

const toMethod = (r: Row): PayoutMethod => ({
  id: r.id as string,
  type: r.method_type as PayoutMethod["type"],
  accountHolderName: r.account_holder_name as string,
  bankName: (r.bank_name as string | null) ?? null,
  accountNumber: (r.account_number as string | null) ?? null,
  ifsc: (r.ifsc as string | null) ?? null,
  upiId: (r.upi_id as string | null) ?? null,
  isPrimary: Boolean(r.is_primary),
  verification: ((r.verification_status as string) ?? "PENDING") as PayoutMethod["verification"],
  verifiedAt: (r.verified_at as string | null) ?? null,
  verificationNote: (r.verification_note as string | null) ?? null,
  createdAt: r.created_at as string,
});

const toTicket = (r: Row): SupportTicket => ({
  id: r.id as string,
  category: r.category as SupportCategory,
  subject: r.subject as string,
  message: r.message as string,
  status: r.status as SupportStatus,
  createdAt: r.created_at as string,
});

export class SupabaseProfileService implements ProfileService {
  private readonly supabase: SupabaseClient;

  constructor(client?: SupabaseClient) {
    this.supabase = client ?? createClient();
  }

  private async userId(): Promise<string> {
    const { data } = await this.supabase.auth.getUser();
    if (!data.user) throw new ServiceError("UNAUTHENTICATED");
    return data.user.id;
  }

  async getPlan(facilityId: string): Promise<FacilityPlan | null> {
    const { data, error } = await this.supabase
      .from("facility_subscriptions")
      .select("*")
      .eq("facility_id", facilityId)
      .maybeSingle();
    if (error) throw fail(error, "Unable to load your GameAll plan.");
    return data ? toPlan(data as Row) : null;
  }

  async getStats(facilityId: string): Promise<ProfileStats> {
    // This month's totals. Bookings and revenue are the server's own figures, read through the same services the Reports and Finance pages
    // use, so this page can never disagree with them.
    const [overview, finance, members, courts] = await Promise.all([
      getReportsService().getAnalyticsOverview({ facilityId, preset: "THIS_MONTH" }),
      getFinanceService().getSummary(facilityId, { preset: "THIS_MONTH" }),
      this.supabase
        .from("members")
        .select("id", { count: "exact", head: true })
        .eq("facility_id", facilityId)
        .eq("status", "ACTIVE"),
      this.supabase.from("courts").select("id", { count: "exact", head: true }).eq("facility_id", facilityId).eq("archived", false),
    ]);
    return {
      totalBookings: overview.totalBookings,
      activeMembers: members.count ?? 0,
      courts: courts.count ?? 0,
      totalRevenueMinor: finance.grossRevenueMinor,
    };
  }

  async updateProfile(update: ProfileUpdate): Promise<void> {
    const id = await this.userId();
    const patch: Row = { full_name: update.fullName.trim(), phone: update.phone?.trim() || null };
    if (update.avatarUrl !== undefined) patch.avatar_url = update.avatarUrl;
    const { error } = await this.supabase.from("profiles").update(patch).eq("id", id);
    if (error) throw fail(error, "Could not save your profile. Please try again.");
  }

  async uploadAvatar(file: File): Promise<string> {
    const uid = await this.userId();
    const path = `${uid}/${crypto.randomUUID()}-${file.name.replace(/[^\w.-]/g, "_")}`;
    const { error } = await this.supabase.storage.from("avatars").upload(path, file, { contentType: file.type });
    if (error) throw fail(error, "Could not upload this photo. Please try again.");
    return this.supabase.storage.from("avatars").getPublicUrl(path).data.publicUrl;
  }

  async getNotificationPrefs(): Promise<NotificationPrefs> {
    const id = await this.userId();
    const { data, error } = await this.supabase.from("profiles").select("notification_prefs").eq("id", id).single();
    if (error) throw fail(error, "Unable to load your settings.");
    return { ...DEFAULT_NOTIFICATION_PREFS, ...((data as Row).notification_prefs as Partial<NotificationPrefs>) };
  }

  async saveNotificationPrefs(prefs: NotificationPrefs): Promise<void> {
    const id = await this.userId();
    const { error } = await this.supabase.from("profiles").update({ notification_prefs: prefs }).eq("id", id);
    if (error) throw fail(error, "Could not save your settings. Please try again.");
  }

  async listPayoutMethods(facilityId: string): Promise<PayoutMethod[]> {
    const { data, error } = await this.supabase
      .from("facility_payout_methods")
      .select("*")
      .eq("facility_id", facilityId)
      .order("is_primary", { ascending: false })
      .order("created_at", { ascending: true });
    if (error) throw fail(error, "Unable to load your payment methods.");
    return ((data ?? []) as Row[]).map(toMethod);
  }

  async addPayoutMethod(facilityId: string, input: PayoutMethodInput): Promise<PayoutMethod> {
    const existing = await this.supabase
      .from("facility_payout_methods")
      .select("id", { count: "exact", head: true })
      .eq("facility_id", facilityId);
    const row: Row = {
      facility_id: facilityId,
      method_type: input.type,
      account_holder_name: input.accountHolderName,
      // The first method added becomes the one payouts go to.
      is_primary: (existing.count ?? 0) === 0,
      ...(input.type === "BANK"
        ? { bank_name: input.bankName, account_number: input.accountNumber, ifsc: input.ifsc }
        : { upi_id: input.upiId }),
    };
    const { data, error } = await this.supabase.from("facility_payout_methods").insert(row).select("*").single();
    if (error) throw fail(error, "Could not save this payment method. Please try again.");
    return toMethod(data as Row);
  }

  async updatePayoutMethod(methodId: string, input: PayoutMethodInput): Promise<PayoutMethod> {
    // Editing the account details sends the method back for verification (the database enforces it).
    const { data, error } = await this.supabase
      .from("facility_payout_methods")
      .update({
        method_type: input.type,
        account_holder_name: input.accountHolderName,
        ...(input.type === "BANK"
          ? { bank_name: input.bankName, account_number: input.accountNumber, ifsc: input.ifsc, upi_id: null }
          : { upi_id: input.upiId, bank_name: null, account_number: null, ifsc: null }),
        updated_at: new Date().toISOString(),
      })
      .eq("id", methodId)
      .select("*")
      .single();
    if (error) throw fail(error, "Could not save this payment method. Please try again.");
    return toMethod(data as Row);
  }

  async setPrimaryPayoutMethod(methodId: string): Promise<void> {
    const { error } = await this.supabase.rpc("set_primary_payout_method", { p_method_id: methodId });
    if (error) throw fail(error, "Could not change the primary method. Please try again.");
  }

  async deletePayoutMethod(methodId: string): Promise<void> {
    const { error } = await this.supabase.from("facility_payout_methods").delete().eq("id", methodId);
    if (error) throw fail(error, "Could not remove this payment method. Please try again.");
  }

  async listSupportTickets(facilityId: string): Promise<SupportTicket[]> {
    const { data, error } = await this.supabase
      .from("support_tickets")
      .select("*")
      .eq("facility_id", facilityId)
      .order("created_at", { ascending: false })
      .limit(20);
    if (error) throw fail(error, "Unable to load your support requests.");
    return ((data ?? []) as Row[]).map(toTicket);
  }

  async createSupportTicket(facilityId: string, input: SupportTicketInput): Promise<SupportTicket> {
    const { data, error } = await this.supabase
      .from("support_tickets")
      .insert({
        facility_id: facilityId,
        category: input.category,
        subject: input.subject.trim(),
        message: input.message.trim(),
      })
      .select("*")
      .single();
    if (error) throw fail(error, "Could not send your request. Please try again.");
    return toTicket(data as Row);
  }
}
