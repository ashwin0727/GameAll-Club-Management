import { describe, expect, it, vi } from "vitest";
import { SupabaseStaffService } from "@/services/staff/supabase-staff.service";
import { ServiceError } from "@/services/shared/service-error";

describe("SupabaseStaffService", () => {
  it("listStaff maps rows and carries the server's total_count", async () => {
    const row = {
      assignment_id: "a1",
      user_id: "u1",
      full_name: "Priya Sharma",
      email: "priya@x.com",
      phone: null,
      avatar_url: null,
      role_id: null,
      role_name: "Manager",
      base_role: "manager",
      status: "ACTIVE",
      is_primary: true,
      title: null,
      facility_count: 2,
      last_login_at: null,
      joined_at: "2024-03-05",
      total_count: 12,
    };
    const rpc = vi.fn(async () => ({ data: [row], error: null }));
    const service = new SupabaseStaffService({ rpc } as never);
    const page = await service.listStaff({ facilityId: "f1", filters: { status: "ACTIVE" } });
    expect(rpc).toHaveBeenCalledWith("list_staff", {
      p_facility_id: "f1",
      p_search: null,
      p_status: "ACTIVE",
      p_role_id: null,
      p_limit: 20,
      p_offset: 0,
    });
    expect(page.totalCount).toBe(12);
    expect(page.staff[0]?.fullName).toBe("Priya Sharma");
    expect(page.staff[0]?.facilityCount).toBe(2);
  });

  it("assignRole forwards the role id and maps a permission rejection", async () => {
    const okRpc = vi.fn(async () => ({ error: null }));
    await new SupabaseStaffService({ rpc: okRpc } as never).assignRole("f1", "u1", "r1");
    expect(okRpc).toHaveBeenCalledWith("assign_staff_role", { p_facility_id: "f1", p_user_id: "u1", p_role_id: "r1" });

    const denyRpc = vi.fn(async () => ({ error: { message: "You don't have permission to manage roles." } }));
    await expect(new SupabaseStaffService({ rpc: denyRpc } as never).assignRole("f1", "u1", "r1")).rejects.toMatchObject({
      code: "STAFF_ACCESS_DENIED",
    });
  });

  it("maps a concurrent role edit to STAFF_CONCURRENT_UPDATE", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "Another administrator updated this role. Refresh and try again." } }));
    await expect(
      new SupabaseStaffService({ rpc } as never).updateRole({ roleId: "r1", facilityId: "f1", expectedVersion: 1 }),
    ).rejects.toMatchObject({ code: "STAFF_CONCURRENT_UPDATE" });
  });

  it("maps the last-owner guard to STAFF_LAST_OWNER", async () => {
    const rpc = vi.fn(async () => ({ error: { message: "You can't deactivate the last active owner." } }));
    await expect(
      new SupabaseStaffService({ rpc } as never).setStatus("f1", "u1", "INACTIVE"),
    ).rejects.toMatchObject({ code: "STAFF_LAST_OWNER" });
  });

  it("createRole returns the new role id and passes the permission keys", async () => {
    const rpc = vi.fn(async () => ({ data: "new-role-id", error: null }));
    const service = new SupabaseStaffService({ rpc } as never);
    const id = await service.createRole({ facilityId: "f1", name: "Front Desk", permissionKeys: ["BOOKINGS_VIEW"] });
    expect(id).toBe("new-role-id");
    expect(rpc).toHaveBeenCalledWith("create_role", {
      p_facility_id: "f1",
      p_name: "Front Desk",
      p_description: null,
      p_permission_keys: ["BOOKINGS_VIEW"],
      p_from_template_id: null,
    });
  });

  it("throws a ServiceError (not a raw object) from a failed RPC", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "boom" } }));
    await expect(new SupabaseStaffService({ rpc } as never).listRoles("f1")).rejects.toThrow(ServiceError);
  });
});
