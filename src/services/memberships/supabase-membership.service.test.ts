import { describe, expect, it, vi } from "vitest";
import { MemberAlreadyExistsError, SupabaseMembershipService } from "@/services/memberships/supabase-membership.service";
import { ServiceError } from "@/services/shared/service-error";
import { fakeQueryBuilder } from "@/test/fakes/fake-supabase-query";

const MEMBER_ROW = {
  id: "member-1",
  facility_id: "facility-1",
  full_name: "Arun Kumar",
  phone: "9999999999",
  email: "arun@example.com",
  date_of_birth: null,
  gender: null,
  notes: null,
  status: "ACTIVE",
  user_id: null,
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

const MEMBERSHIP_ROW = {
  id: "membership-1",
  facility_id: "facility-1",
  member_id: "member-1",
  plan_id: "plan-1",
  status: "active",
  start_date: "2026-08-01",
  end_date: "2026-08-31",
  auto_renew: false,
  created_at: "2026-08-01T00:00:00.000Z",
};

describe("SupabaseMembershipService", () => {
  it("createMembership calls the create_membership RPC and maps the plan name back in", async () => {
    const rpc = vi.fn(async () => ({ data: MEMBERSHIP_ROW, error: null }));
    const from = vi.fn(() => fakeQueryBuilder({ data: { name: "Monthly" }, error: null }));
    const service = new SupabaseMembershipService({ rpc, from } as never);

    const membership = await service.createMembership({
      memberId: "member-1",
      facilityId: "facility-1",
      planId: "plan-1",
      startDate: "2026-08-01",
      paymentStatus: "paid",
    });

    expect(rpc).toHaveBeenCalledWith(
      "create_membership",
      expect.objectContaining({
        p_member_id: "member-1",
        p_facility_id: "facility-1",
        p_plan_id: "plan-1",
        p_start_date: "2026-08-01",
        p_payment_status: "paid",
      }),
    );
    expect(membership.id).toBe("membership-1");
    expect(membership.planName).toBe("Monthly");
    expect(membership.status).toBe("active");
  });

  it("createMembership surfaces a missing plan as MEMBERSHIP_PLAN_NOT_FOUND", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { code: "23503", message: "not found" } }));
    const service = new SupabaseMembershipService({ rpc } as never);

    await expect(
      service.createMembership({ memberId: "m", facilityId: "f", planId: "p", startDate: "2026-08-01" }),
    ).rejects.toMatchObject({ code: "MEMBERSHIP_PLAN_NOT_FOUND" });
  });

  it("cancelMembership calls the cancel_membership RPC and throws MEMBERSHIP_NOT_FOUND when nothing matched", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: null }));
    const service = new SupabaseMembershipService({ rpc } as never);

    await expect(service.cancelMembership("missing")).rejects.toThrow(ServiceError);
    expect(rpc).toHaveBeenCalledWith("cancel_membership", { p_membership_id: "missing" });
  });

  it("searchFacilityMembers maps every RPC row into a FacilityMemberRow", async () => {
    const rpc = vi.fn(async () => ({
      data: [
        {
          member_id: "member-1",
          full_name: "Asha Rao",
          phone: "9876543210",
          email: "asha@example.com",
          membership_id: "membership-1",
          plan_id: "plan-1",
          plan_name: "Monthly",
          start_date: "2026-08-01",
          end_date: "2026-08-31",
          status: "active",
        },
      ],
      error: null,
    }));
    const service = new SupabaseMembershipService({ rpc } as never);

    const rows = await service.searchFacilityMembers("facility-1", { query: "Asha" });

    expect(rpc).toHaveBeenCalledWith(
      "search_facility_members",
      expect.objectContaining({ p_facility_id: "facility-1", p_query: "Asha" }),
    );
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ memberId: "member-1", fullName: "Asha Rao", planName: "Monthly" });
  });

  it("getMemberStats defaults every field when the RPC returns no rows", async () => {
    const rpc = vi.fn(async () => ({ data: [], error: null }));
    const service = new SupabaseMembershipService({ rpc } as never);

    const stats = await service.getMemberStats("member-1", "facility-1");

    expect(stats).toEqual({
      totalVisits: 0,
      totalBookings: 0,
      lastVisit: null,
      totalAmountMinor: 0,
      pendingAmountMinor: 0,
      sports: [],
    });
  });

  it("createPlan inserts a facility-scoped row and maps it back", async () => {
    const planRow = {
      id: "plan-1",
      facility_id: "facility-1",
      name: "Monthly",
      price_inr: 1500,
      duration_days: 30,
      features: [],
      is_active: true,
      created_at: "2026-08-01T00:00:00.000Z",
    };
    const builder = fakeQueryBuilder({ data: planRow, error: null });
    const from = vi.fn(() => builder);
    const service = new SupabaseMembershipService({ from } as never);

    const plan = await service.createPlan({ facilityId: "facility-1", name: "Monthly", priceInr: 1500, durationDays: 30 });

    expect(plan.id).toBe("plan-1");
    expect(plan.priceInr).toBe(1500);
    const insertCall = (builder.insert as ReturnType<typeof vi.fn>).mock.calls[0]?.[0];
    expect(insertCall).toMatchObject({ facility_id: "facility-1", name: "Monthly", price_inr: 1500, duration_days: 30 });
  });

  describe("Member creation is a plain customer record — never a Supabase Auth account", () => {
    it("createMember with an email creates only a members row via the create_member RPC, never auth.signUp/admin.createUser", async () => {
      const rpc = vi.fn(async () => ({ data: MEMBER_ROW, error: null }));
      const from = vi.fn(() => fakeQueryBuilder({ data: null, error: null })); // duplicate pre-check: no existing row
      const auth = {
        signUp: vi.fn(),
        admin: { createUser: vi.fn(), inviteUserByEmail: vi.fn() },
      };
      const service = new SupabaseMembershipService({ rpc, from, auth } as never);

      const member = await service.createMember({
        facilityId: "facility-1",
        fullName: "Arun Kumar",
        phone: "9999999999",
        email: "arun@example.com",
      });

      expect(rpc).toHaveBeenCalledWith(
        "create_member",
        expect.objectContaining({ p_facility_id: "facility-1", p_full_name: "Arun Kumar", p_phone: "9999999999", p_email: "arun@example.com" }),
      );
      expect(member.id).toBe("member-1");
      expect(member.userId).toBeNull();
      expect(auth.signUp).not.toHaveBeenCalled();
      expect(auth.admin.createUser).not.toHaveBeenCalled();
      expect(auth.admin.inviteUserByEmail).not.toHaveBeenCalled();
    });

    it("createMember without an email still succeeds — email is optional contact info, not a login identifier", async () => {
      const rpc = vi.fn(async () => ({ data: { ...MEMBER_ROW, email: null }, error: null }));
      const from = vi.fn(() => fakeQueryBuilder({ data: null, error: null }));
      const service = new SupabaseMembershipService({ rpc, from } as never);

      const member = await service.createMember({ facilityId: "facility-1", fullName: "Arun Kumar", phone: "9999999999" });

      expect(member.email).toBeNull();
      expect(rpc).toHaveBeenCalledWith("create_member", expect.objectContaining({ p_email: null }));
    });

    it("createMember pre-checks by (facility, phone) and throws MemberAlreadyExistsError instead of inserting a duplicate", async () => {
      const from = vi.fn(() => fakeQueryBuilder({ data: { id: "existing-member" }, error: null }));
      const rpc = vi.fn();
      const service = new SupabaseMembershipService({ from, rpc } as never);

      await expect(
        service.createMember({ facilityId: "facility-1", fullName: "Duplicate", phone: "9999999999" }),
      ).rejects.toThrow(MemberAlreadyExistsError);
      expect(rpc).not.toHaveBeenCalled();
    });

    it("updateMember creates no auth account either — it only calls the update_member RPC", async () => {
      const from = vi.fn(() => fakeQueryBuilder({ data: MEMBER_ROW, error: null }));
      const rpc = vi.fn(async () => ({ data: { ...MEMBER_ROW, full_name: "Arun K." }, error: null }));
      const auth = { admin: { createUser: vi.fn() } };
      const service = new SupabaseMembershipService({ from, rpc, auth } as never);

      const member = await service.updateMember("member-1", { fullName: "Arun K." });

      expect(member.fullName).toBe("Arun K.");
      expect(auth.admin.createUser).not.toHaveBeenCalled();
    });

    it("searchMembers is facility-scoped and requires no membership plan to return a result", async () => {
      const rpc = vi.fn(async () => ({
        data: [{ id: "member-1", full_name: "Arun Kumar", phone: "9999999999", email: null }],
        error: null,
      }));
      const service = new SupabaseMembershipService({ rpc } as never);

      const results = await service.searchMembers("facility-1", "Arun");

      expect(rpc).toHaveBeenCalledWith("search_members", { p_facility_id: "facility-1", p_query: "Arun" });
      expect(results).toEqual([{ id: "member-1", fullName: "Arun Kumar", phone: "9999999999", email: null }]);
    });
  });
});