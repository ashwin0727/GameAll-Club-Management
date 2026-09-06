"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type { FacilityStaffOption, MaintenanceService } from "@/services/maintenance/maintenance.service";
import { ServiceError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";
import type {
  AffectedBooking,
  AffectedSession,
  CreateMaintenanceTicketInput,
  MaintenanceActivityEntry,
  MaintenanceAttachment,
  MaintenanceIssueCategory,
  MaintenanceOverview,
  MaintenanceTicketDetail,
  MaintenanceTicketFilters,
  MaintenanceTicketPage,
} from "@/features/maintenance/types";

const BUCKET = "maintenance-attachments";

/** Custom RPC exception text (0068) is user-actionable by design — surfaced verbatim, same pattern as refunds/settlement. */
function toServiceError(error: { code?: string; message?: string }, fallback: "MAINTENANCE_RULE_ERROR" | "MAINTENANCE_DATA_ERROR" = "MAINTENANCE_RULE_ERROR"): ServiceError {
  console.error("[maintenance-service]", error.code, error.message);
  if (error.code === "42501") return new ServiceError("MAINTENANCE_ACCESS_DENIED");
  if (error.code === "P0002") return new ServiceError("MAINTENANCE_NOT_FOUND", error.message);
  if (error.code === "23514" || error.code === "23503" || error.code === "23P01") {
    return new ServiceError(fallback, error.message ?? undefined);
  }
  return new ServiceError("MAINTENANCE_DATA_ERROR");
}

export class SupabaseMaintenanceService implements MaintenanceService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async listAssignableStaff(facilityId: string): Promise<FacilityStaffOption[]> {
    const { data, error } = await this.supabase.rpc("list_facility_staff", { p_facility_id: facilityId });
    if (error) throw toServiceError(error, "MAINTENANCE_DATA_ERROR");
    return (data ?? []).map((r) => ({ userId: r.user_id, fullName: r.full_name, role: r.role }));
  }

  async getOverview(facilityId: string): Promise<MaintenanceOverview> {
    const { data, error } = await this.supabase.rpc("get_maintenance_overview", { p_facility_id: facilityId });
    if (error) throw toServiceError(error, "MAINTENANCE_DATA_ERROR");
    const o = data as Record<string, unknown>;
    return {
      openIssues: Number(o.openIssues ?? 0),
      inProgress: Number(o.inProgress ?? 0),
      scheduled: Number(o.scheduled ?? 0),
      resolvedThisMonth: Number(o.resolvedThisMonth ?? 0),
      courtsBlocked: Number(o.courtsBlocked ?? 0),
      repairCostThisMonthMinor: Number(o.repairCostThisMonthMinor ?? 0),
      courtStatus: (o.courtStatus as MaintenanceOverview["courtStatus"]) ?? [],
      recentTickets: (o.recentTickets as MaintenanceOverview["recentTickets"]) ?? [],
      upcomingSchedule: (o.upcomingSchedule as MaintenanceOverview["upcomingSchedule"]) ?? [],
      recentActivity: (o.recentActivity as MaintenanceOverview["recentActivity"]) ?? [],
    };
  }

  async listIssueCategories(facilityId: string, includeInactive = true): Promise<MaintenanceIssueCategory[]> {
    const { data, error } = await this.supabase.rpc("list_maintenance_issue_categories", {
      p_facility_id: facilityId,
      p_include_inactive: includeInactive,
    });
    if (error) throw toServiceError(error, "MAINTENANCE_DATA_ERROR");
    return (data ?? []).map((r) => ({
      id: r.id,
      facilityId: r.facility_id,
      name: r.name,
      icon: r.icon,
      description: r.description,
      isActive: r.is_active,
      sortOrder: r.sort_order,
      issueCount: r.issue_count,
      isShared: r.is_shared,
    }));
  }

  async createIssueCategory(input: { facilityId: string; name: string; icon: string; description?: string | null; sortOrder?: number }): Promise<MaintenanceIssueCategory> {
    const { data, error } = await this.supabase.rpc("create_maintenance_issue_category", {
      p_facility_id: input.facilityId,
      p_name: input.name,
      p_icon: input.icon,
      p_description: input.description ?? null,
      p_sort_order: input.sortOrder ?? 0,
    });
    if (error) throw toServiceError(error);
    return {
      id: data.id,
      facilityId: data.facility_id,
      name: data.name,
      icon: data.icon,
      description: data.description,
      isActive: data.is_active,
      sortOrder: data.sort_order,
      issueCount: 0,
      isShared: data.facility_id === null,
    };
  }

  async updateIssueCategory(input: { categoryId: string; name: string; icon: string; description?: string | null; sortOrder?: number; isActive?: boolean }): Promise<MaintenanceIssueCategory> {
    const { data, error } = await this.supabase.rpc("update_maintenance_issue_category", {
      p_category_id: input.categoryId,
      p_name: input.name,
      p_icon: input.icon,
      p_description: input.description ?? null,
      p_sort_order: input.sortOrder ?? 0,
      p_is_active: input.isActive ?? true,
    });
    if (error) throw toServiceError(error);
    return {
      id: data.id,
      facilityId: data.facility_id,
      name: data.name,
      icon: data.icon,
      description: data.description,
      isActive: data.is_active,
      sortOrder: data.sort_order,
      issueCount: 0,
      isShared: data.facility_id === null,
    };
  }

  async listTickets(facilityId: string, filters: MaintenanceTicketFilters, limit: number, offset: number): Promise<MaintenanceTicketPage> {
    const { data, error } = await this.supabase.rpc("list_maintenance_tickets", {
      p_facility_id: facilityId,
      p_search: filters.search || null,
      p_status: filters.status ?? null,
      p_priority: filters.priority ?? null,
      p_court_id: filters.courtId ?? null,
      p_facility_sport_id: filters.facilitySportId ?? null,
      p_issue_category_id: filters.issueCategoryId ?? null,
      p_assigned_to: filters.assignedTo ?? null,
      p_from: filters.from ?? null,
      p_to: filters.to ?? null,
      p_sort: filters.sort ?? "NEWEST",
      p_limit: limit,
      p_offset: offset,
    });
    if (error) throw toServiceError(error, "MAINTENANCE_DATA_ERROR");
    const rows = data ?? [];
    return {
      totalCount: rows[0]?.total_count ?? 0,
      tickets: rows.map((r) => ({
        ticketId: r.ticket_id,
        code: r.code,
        courtId: r.court_id,
        courtName: r.court_name,
        sportName: r.sport_name,
        issueCategoryId: r.issue_category_id,
        categoryName: r.category_name,
        title: r.title,
        priority: r.priority,
        status: r.status,
        reportedByName: r.reported_by_name,
        assignedToName: r.assigned_to_name,
        scheduledStart: r.scheduled_start,
        reportedAt: r.reported_at,
        actualCostMinor: r.actual_cost_minor,
        estimatedCostMinor: r.estimated_cost_minor,
      })),
    };
  }

  async getTicketDetail(ticketId: string): Promise<MaintenanceTicketDetail> {
    const { data, error } = await this.supabase.rpc("get_maintenance_ticket_detail", { p_ticket_id: ticketId });
    if (error) throw toServiceError(error);
    return mapDetail(data as Record<string, unknown>);
  }

  async createTicket(input: CreateMaintenanceTicketInput): Promise<MaintenanceTicketDetail> {
    const { data, error } = await this.supabase.rpc("create_maintenance_ticket", {
      p_facility_id: input.facilityId,
      p_court_id: input.courtId,
      p_issue_category_id: input.issueCategoryId,
      p_priority: input.priority,
      p_title: input.title,
      p_description: input.description,
      p_scheduled_start: input.scheduledStart ?? null,
      p_scheduled_end: input.scheduledEnd ?? null,
      p_assigned_to: input.assignedTo ?? null,
      p_estimated_cost_minor: input.estimatedCostMinor ?? null,
      p_notes: input.notes ?? null,
    });
    if (error) throw toServiceError(error);
    return this.getTicketDetail(data.id);
  }

  async updateTicket(input: { ticketId: string; title: string; description: string; issueCategoryId: string; priority: string; notes?: string | null }): Promise<void> {
    const { error } = await this.supabase.rpc("update_maintenance_ticket", {
      p_ticket_id: input.ticketId,
      p_title: input.title,
      p_description: input.description,
      p_issue_category_id: input.issueCategoryId,
      p_priority: input.priority as CreateMaintenanceTicketInput["priority"],
      p_notes: input.notes ?? null,
    });
    if (error) throw toServiceError(error);
  }

  async assignTicket(ticketId: string, assignedTo: string): Promise<void> {
    const { error } = await this.supabase.rpc("assign_maintenance_ticket", { p_ticket_id: ticketId, p_assigned_to: assignedTo });
    if (error) throw toServiceError(error);
  }

  async scheduleMaintenance(ticketId: string, start: string, end: string): Promise<void> {
    const { error } = await this.supabase.rpc("schedule_maintenance", { p_ticket_id: ticketId, p_start: start, p_end: end });
    if (error) throw toServiceError(error);
  }

  async startMaintenance(ticketId: string): Promise<void> {
    const { error } = await this.supabase.rpc("start_maintenance_ticket", { p_ticket_id: ticketId });
    if (error) throw toServiceError(error);
  }

  async addNote(ticketId: string, note: string): Promise<void> {
    const { error } = await this.supabase.rpc("add_maintenance_note", { p_ticket_id: ticketId, p_note: note });
    if (error) throw toServiceError(error);
  }

  async updateCost(input: {
    ticketId: string;
    estimatedCostMinor?: number | null;
    actualCostMinor?: number | null;
    postToExpenses?: boolean;
    expenseCategoryId?: string | null;
    paymentMethod?: string | null;
    vendor?: string | null;
  }): Promise<void> {
    const { error } = await this.supabase.rpc("update_maintenance_cost", {
      p_ticket_id: input.ticketId,
      p_estimated_cost_minor: input.estimatedCostMinor ?? null,
      p_actual_cost_minor: input.actualCostMinor ?? null,
      p_post_to_expenses: input.postToExpenses ?? false,
      p_expense_category_id: input.expenseCategoryId ?? null,
      p_payment_method: input.paymentMethod ?? null,
      p_vendor: input.vendor ?? null,
    });
    if (error) throw toServiceError(error);
  }

  async resolveTicket(ticketId: string, actualEnd?: string | null): Promise<void> {
    const { error } = await this.supabase.rpc("resolve_maintenance_ticket", { p_ticket_id: ticketId, p_actual_end: actualEnd ?? null });
    if (error) throw toServiceError(error);
  }

  async reopenTicket(ticketId: string): Promise<void> {
    const { error } = await this.supabase.rpc("reopen_maintenance_ticket", { p_ticket_id: ticketId });
    if (error) throw toServiceError(error);
  }

  async closeTicket(ticketId: string, reason?: string | null): Promise<void> {
    const { error } = await this.supabase.rpc("close_maintenance_ticket", { p_ticket_id: ticketId, p_reason: reason ?? null });
    if (error) throw toServiceError(error);
  }

  async detectAffectedBookings(courtId: string, start: string, end: string, excludeTicketId?: string | null): Promise<AffectedBooking[]> {
    const { data, error } = await this.supabase.rpc("detect_maintenance_affected_bookings", {
      p_court_id: courtId,
      p_start: start,
      p_end: end,
      p_exclude_ticket_id: excludeTicketId ?? null,
    });
    if (error) throw toServiceError(error, "MAINTENANCE_DATA_ERROR");
    return (data ?? []).map((b) => ({
      bookingId: b.booking_id,
      customerType: b.customer_type,
      guestName: b.guest_name,
      memberId: b.member_id,
      startTime: b.start_time,
      endTime: b.end_time,
      status: b.status,
      paymentStatus: b.payment_status,
      amountMinor: b.amount_minor,
    }));
  }

  async detectAffectedSessions(courtId: string, start: string, end: string): Promise<AffectedSession[]> {
    const { data, error } = await this.supabase.rpc("detect_maintenance_affected_membership_sessions", {
      p_court_id: courtId,
      p_start: start,
      p_end: end,
    });
    if (error) throw toServiceError(error, "MAINTENANCE_DATA_ERROR");
    return (data ?? []).map((s) => ({
      batchId: s.batch_id,
      batchName: s.batch_name,
      sessionDate: s.session_date,
      startTime: s.start_time,
      endTime: s.end_time,
      memberBookedCount: s.member_booked_count,
      guestBookedCount: s.guest_booked_count,
    }));
  }

  async addAttachment(ticketId: string, storagePath: string, fileName: string, contentType?: string | null, sizeBytes?: number | null): Promise<void> {
    const { error } = await this.supabase.rpc("add_maintenance_attachment", {
      p_ticket_id: ticketId,
      p_storage_path: storagePath,
      p_file_name: fileName,
      p_content_type: contentType ?? null,
      p_size_bytes: sizeBytes ?? null,
    });
    if (error) throw toServiceError(error);
  }

  async uploadAttachment(facilityId: string, ticketId: string, file: File): Promise<{ storagePath: string; signedUrl: string | null }> {
    const path = `${facilityId}/${ticketId}/${crypto.randomUUID()}-${file.name}`;
    const { error: uploadError } = await this.supabase.storage.from(BUCKET).upload(path, file, { contentType: file.type });
    if (uploadError) {
      console.error("[maintenance-service] attachment upload failed", uploadError.message);
      throw new ServiceError("MAINTENANCE_DATA_ERROR", "Could not upload this file. Please try again.");
    }
    await this.addAttachment(ticketId, path, file.name, file.type, file.size);
    const signedUrl = await this.getAttachmentUrl(path);
    return { storagePath: path, signedUrl };
  }

  async getAttachmentUrl(storagePath: string): Promise<string | null> {
    const { data, error } = await this.supabase.storage.from(BUCKET).createSignedUrl(storagePath, 3600);
    if (error) return null;
    return data?.signedUrl ?? null;
  }
}

function mapDetail(d: Record<string, unknown>): MaintenanceTicketDetail {
  return {
    id: d.id as string,
    code: d.code as string,
    facilityId: d.facilityId as string,
    court: d.court as MaintenanceTicketDetail["court"],
    sportName: (d.sportName as string) ?? null,
    category: d.category as MaintenanceTicketDetail["category"],
    title: d.title as string,
    description: d.description as string,
    priority: d.priority as MaintenanceTicketDetail["priority"],
    status: d.status as MaintenanceTicketDetail["status"],
    reportedBy: d.reportedBy as MaintenanceTicketDetail["reportedBy"],
    reportedAt: d.reportedAt as string,
    assignedTo: (d.assignedTo as MaintenanceTicketDetail["assignedTo"]) ?? null,
    scheduledStart: (d.scheduledStart as string) ?? null,
    scheduledEnd: (d.scheduledEnd as string) ?? null,
    actualStart: (d.actualStart as string) ?? null,
    actualEnd: (d.actualEnd as string) ?? null,
    estimatedCostMinor: (d.estimatedCostMinor as number) ?? null,
    actualCostMinor: (d.actualCostMinor as number) ?? null,
    expenseId: (d.expenseId as string) ?? null,
    notes: (d.notes as string) ?? null,
    currency: (d.currency as string) ?? "INR",
    activeBlock: (d.activeBlock as MaintenanceTicketDetail["activeBlock"]) ?? null,
    attachments: (d.attachments as MaintenanceAttachment[]) ?? [],
    activity: (d.activity as MaintenanceActivityEntry[]) ?? [],
    affectedBookings: (d.affectedBookings as AffectedBooking[]) ?? [],
    affectedSessions: (d.affectedSessions as AffectedSession[]) ?? [],
  };
}
