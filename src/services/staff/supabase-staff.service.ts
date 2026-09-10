"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { ServiceError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";
import type {
  CreateStaffInput,
  CreateStaffResult,
  Permission,
  RoleDetail,
  RoleRow,
  RoleTemplate,
  SecurityEventFilters,
  SecurityEventPage,
  StaffDetail,
  StaffFilters,
  StaffPage,
} from "@/features/staff/types";

function mapError(error: unknown): ServiceError {
  console.error("[staff-service] request failed", error);
  const message = (error as { message?: string } | null)?.message ?? "";
  if (message.includes("permission")) return new ServiceError("STAFF_ACCESS_DENIED", message);
  if (message.includes("Another administrator")) return new ServiceError("STAFF_CONCURRENT_UPDATE", message);
  if (message.includes("last active owner")) return new ServiceError("STAFF_LAST_OWNER", message);
  if (message.includes("assigned to")) return new ServiceError("STAFF_ROLE_IN_USE", message);
  if (message.includes("already has access")) return new ServiceError("STAFF_DUPLICATE", message);
  return new ServiceError("STAFF_DATA_ERROR", message || undefined);
}

export class SupabaseStaffService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async listStaff(input: {
    facilityId: string;
    filters?: StaffFilters;
    limit?: number;
    offset?: number;
  }): Promise<StaffPage> {
    const f = input.filters ?? {};
    const { data, error } = await this.supabase.rpc("list_staff", {
      p_facility_id: input.facilityId,
      p_search: f.search?.trim() || null,
      p_status: f.status ?? null,
      p_role_id: f.roleId ?? null,
      p_limit: input.limit ?? 20,
      p_offset: input.offset ?? 0,
    });
    if (error) throw mapError(error);
    return {
      staff: (data ?? []).map((r) => ({
        assignmentId: r.assignment_id,
        userId: r.user_id,
        fullName: r.full_name,
        email: r.email,
        phone: r.phone,
        avatarUrl: r.avatar_url,
        roleId: r.role_id,
        roleName: r.role_name,
        baseRole: r.base_role,
        status: r.status,
        isPrimary: r.is_primary,
        title: r.title,
        facilityCount: r.facility_count,
        lastLoginAt: r.last_login_at,
        joinedAt: r.joined_at,
      })),
      totalCount: data?.[0]?.total_count ?? 0,
    };
  }

  async getStaff(facilityId: string, userId: string): Promise<StaffDetail> {
    const { data, error } = await this.supabase.rpc("get_staff", {
      p_facility_id: facilityId,
      p_user_id: userId,
    });
    if (error || !data) throw mapError(error);
    return data as unknown as StaffDetail;
  }

  async createStaff(input: CreateStaffInput): Promise<CreateStaffResult> {
    const { data, error } = await this.supabase.functions.invoke("create-staff", {
      body: {
        facilityId: input.facilityId,
        fullName: input.fullName,
        email: input.email,
        phone: input.phone ?? undefined,
        roleId: input.roleId,
        isPrimary: input.isPrimary ?? false,
        title: input.title ?? undefined,
        notes: input.notes ?? undefined,
        avatarUrl: input.avatarUrl ?? undefined,
      },
    });
    if (error) {
      // The edge function returns a JSON { error } body with the real message.
      const body = (error as { context?: { body?: unknown } }).context?.body;
      const msg = typeof body === "string" ? body : (body as { error?: string } | undefined)?.error;
      throw new ServiceError("STAFF_INVITE_FAILED", msg || "Could not add the staff member.");
    }
    return {
      userId: data.userId,
      linked: Boolean(data.linked),
      temporaryPassword: data.temporaryPassword ?? null,
    };
  }

  async assignRole(facilityId: string, userId: string, roleId: string): Promise<void> {
    const { error } = await this.supabase.rpc("assign_staff_role", {
      p_facility_id: facilityId,
      p_user_id: userId,
      p_role_id: roleId,
    });
    if (error) throw mapError(error);
  }

  async setStatus(facilityId: string, userId: string, status: "ACTIVE" | "INACTIVE"): Promise<void> {
    const { error } = await this.supabase.rpc("set_staff_status", {
      p_facility_id: facilityId,
      p_user_id: userId,
      p_status: status,
    });
    if (error) throw mapError(error);
  }

  async updateProfile(facilityId: string, userId: string, patch: { title?: string | null; notes?: string | null }): Promise<void> {
    const { error } = await this.supabase.rpc("update_staff_profile", {
      p_facility_id: facilityId,
      p_user_id: userId,
      p_title: patch.title ?? null,
      p_notes: patch.notes ?? null,
    });
    if (error) throw mapError(error);
  }

  async addFacilityAccess(facilityId: string, userId: string, roleId: string, isPrimary: boolean): Promise<void> {
    const { error } = await this.supabase.rpc("add_facility_access", {
      p_facility_id: facilityId,
      p_user_id: userId,
      p_role_id: roleId,
      p_is_primary: isPrimary,
    });
    if (error) throw mapError(error);
  }

  async removeFacilityAccess(facilityId: string, userId: string): Promise<void> {
    const { error } = await this.supabase.rpc("remove_facility_access", {
      p_facility_id: facilityId,
      p_user_id: userId,
    });
    if (error) throw mapError(error);
  }

  async listRoles(facilityId: string): Promise<RoleRow[]> {
    const { data, error } = await this.supabase.rpc("list_roles", { p_facility_id: facilityId });
    if (error) throw mapError(error);
    return (data ?? []).map((r) => ({
      id: r.id,
      key: r.key,
      name: r.name,
      description: r.description,
      isSystem: r.is_system,
      isCustom: r.is_custom,
      isActive: r.is_active,
      version: r.version,
      staffCount: r.staff_count,
      permissionCount: r.permission_count,
    }));
  }

  async getRole(roleId: string): Promise<RoleDetail> {
    const { data, error } = await this.supabase.rpc("get_role", { p_role_id: roleId });
    if (error || !data) throw mapError(error);
    return data as unknown as RoleDetail;
  }

  async listRoleTemplates(): Promise<RoleTemplate[]> {
    const { data, error } = await this.supabase.rpc("list_role_templates");
    if (error) throw mapError(error);
    return (data ?? []).map((t) => ({
      id: t.id,
      name: t.name,
      description: t.description,
      permissionKeys: t.permission_keys ?? [],
    }));
  }

  async listPermissions(): Promise<Permission[]> {
    const { data, error } = await this.supabase.rpc("list_permissions");
    if (error) throw mapError(error);
    return (data ?? []).map((p) => ({
      key: p.key,
      module: p.module,
      action: p.action,
      label: p.label,
      description: p.description,
      isDangerous: p.is_dangerous,
      sortOrder: p.sort_order,
    }));
  }

  async createRole(input: {
    facilityId: string;
    name: string;
    description?: string | null;
    permissionKeys: string[];
    fromTemplateId?: string | null;
  }): Promise<string> {
    const { data, error } = await this.supabase.rpc("create_role", {
      p_facility_id: input.facilityId,
      p_name: input.name,
      p_description: input.description ?? null,
      p_permission_keys: input.permissionKeys,
      p_from_template_id: input.fromTemplateId ?? null,
    });
    if (error || !data) throw mapError(error);
    return data;
  }

  async updateRole(input: {
    roleId: string;
    facilityId: string;
    name?: string | null;
    description?: string | null;
    isActive?: boolean | null;
    permissionKeys?: string[] | null;
    expectedVersion?: number | null;
  }): Promise<string> {
    const { data, error } = await this.supabase.rpc("update_role", {
      p_role_id: input.roleId,
      p_facility_id: input.facilityId,
      p_name: input.name ?? null,
      p_description: input.description ?? null,
      p_is_active: input.isActive ?? null,
      p_permission_keys: input.permissionKeys ?? null,
      p_expected_version: input.expectedVersion ?? null,
    });
    if (error || !data) throw mapError(error);
    return data;
  }

  async deleteRole(roleId: string, facilityId: string): Promise<void> {
    const { error } = await this.supabase.rpc("delete_role", { p_role_id: roleId, p_facility_id: facilityId });
    if (error) throw mapError(error);
  }

  async listSecurityEvents(input: {
    facilityId: string;
    filters?: SecurityEventFilters;
    limit?: number;
    offset?: number;
  }): Promise<SecurityEventPage> {
    const f = input.filters ?? {};
    const { data, error } = await this.supabase.rpc("list_security_events", {
      p_facility_id: input.facilityId,
      p_event: f.event ?? null,
      p_target_user_id: f.targetUserId ?? null,
      p_from: f.from ?? null,
      p_to: f.to ?? null,
      p_limit: input.limit ?? 25,
      p_offset: input.offset ?? 0,
    });
    if (error) throw mapError(error);
    return {
      events: (data ?? []).map((e) => ({
        id: e.id,
        event: e.event,
        summary: e.summary,
        actorName: e.actor_name,
        targetName: e.target_name,
        detail: e.detail,
        createdAt: e.created_at,
      })),
      totalCount: data?.[0]?.total_count ?? 0,
    };
  }
}
