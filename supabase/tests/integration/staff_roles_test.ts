import { assert, assertEquals, assertRejects } from "jsr:@std/assert";
import { authed, closeAll, makeFacility, makeUser, resetCore, superuser } from "./_helpers.ts";

// Staff / Roles / Permissions (migrations 0072-0077) — the spec's required
// security tests (§46). Frontend permission checks are not security; these
// prove the database rejects the request regardless of the client.

type SU = Awaited<ReturnType<typeof superuser>>;

/** The three seeded system role ids. */
const ROLE = {
  owner: "00000000-0000-0000-0000-0000000000a1",
  manager: "00000000-0000-0000-0000-0000000000a2",
  staff: "00000000-0000-0000-0000-0000000000a3",
};

/** Add an existing user to a facility as `role`, ACTIVE, via the service role. */
async function addStaff(su: SU, facilityId: string, userId: string, role: "owner" | "manager" | "staff") {
  await su.queryArray({
    text: `insert into facility_users (facility_id, user_id, role, status, is_primary, activated_at)
           values ($1, $2, $3, 'ACTIVE', false, now())`,
    args: [facilityId, userId, role],
  });
}

async function seed(su: SU) {
  await resetCore(su);
  await su.queryArray(`delete from security_events; delete from roles where facility_id is not null;`);
  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  // makeFacility already inserts the owner as facility_users owner? check: no —
  // the finance helper's makeFacility inserts facility_users role 'owner'.
  return { owner, facilityId };
}

Deno.test("TEST 1 — a user with Facility A access cannot list Facility B staff", async () => {
  const su = await superuser();
  await resetCore(su);
  const ownerA = await makeUser(su);
  const ownerB = await makeUser(su);
  await makeFacility(su, ownerA);
  const facilityB = await makeFacility(su, ownerB);
  const a = await authed(ownerA);
  await assertRejects(
    () => a.queryArray({ text: `select list_staff($1)`, args: [facilityB] }),
    Error,
    "permission",
  );
  await closeAll(su, a);
});

Deno.test("TEST 2 — staff without FINANCE_REFUND cannot write a refund row", async () => {
  const su = await superuser();
  const { facilityId } = await seed(su);
  const staff = await makeUser(su);
  await addStaff(su, facilityId, staff, "staff"); // staff default: no FINANCE_REFUND
  const c = await authed(staff);
  const canRefund = await c.queryObject<{ ok: boolean }>({
    text: `select has_permission($1, 'FINANCE_REFUND') as ok`,
    args: [facilityId],
  });
  assertEquals(canRefund.rows[0].ok, false);
  // The refunds write policy is has_permission('FINANCE_REFUND'); a direct
  // insert as this user is filtered out by RLS.
  await assertRejects(
    () =>
      c.queryArray({
        text: `insert into refunds (facility_id, payment_order_id, source_type, razorpay_payment_id, amount_minor, reason, status)
               values ($1, gen_random_uuid(), 'MEMBER_BOOKING', 'pay_x', 100, 'CUSTOMER_REQUEST', 'REQUESTED')`,
        args: [facilityId],
      }),
    Error,
  );
  await closeAll(su, c);
});

Deno.test("TEST 3 — a manager without USERS_MANAGE_ROLES cannot change a role", async () => {
  const su = await superuser();
  const { facilityId } = await seed(su);
  const manager = await makeUser(su);
  const target = await makeUser(su);
  await addStaff(su, facilityId, manager, "manager"); // manager default excludes USERS_MANAGE_ROLES
  await addStaff(su, facilityId, target, "staff");
  const c = await authed(manager);
  assertEquals(
    (await c.queryObject<{ ok: boolean }>({ text: `select has_permission($1, 'USERS_MANAGE_ROLES') as ok`, args: [facilityId] }))
      .rows[0].ok,
    false,
  );
  await assertRejects(
    () => c.queryArray({ text: `select assign_staff_role($1, $2, $3)`, args: [facilityId, target, ROLE.manager] }),
    Error,
    "permission",
  );
  await closeAll(su, c);
});

Deno.test("TEST 4 — a deactivated staff member loses facility access everywhere", async () => {
  const su = await superuser();
  const { facilityId } = await seed(su);
  const staff = await makeUser(su);
  await addStaff(su, facilityId, staff, "staff");
  await su.queryArray({ text: `update facility_users set status = 'INACTIVE' where facility_id = $1 and user_id = $2`, args: [facilityId, staff] });
  const c = await authed(staff);
  assertEquals(
    (await c.queryObject<{ ok: boolean }>({ text: `select is_facility_member($1) as ok`, args: [facilityId] })).rows[0].ok,
    false,
  );
  assertEquals(
    (await c.queryObject<{ ok: boolean }>({ text: `select has_permission($1, 'BOOKINGS_VIEW') as ok`, args: [facilityId] })).rows[0].ok,
    false,
  );
  await closeAll(su, c);
});

Deno.test("TEST 5 — the same user has different permissions per facility", async () => {
  const su = await superuser();
  await resetCore(su);
  const person = await makeUser(su);
  const oA = await makeUser(su);
  const oB = await makeUser(su);
  const fA = await makeFacility(su, oA);
  const fB = await makeFacility(su, oB);
  await addStaff(su, fA, person, "manager");
  await addStaff(su, fB, person, "staff");
  const c = await authed(person);
  assertEquals((await c.queryObject<{ ok: boolean }>({ text: `select has_permission($1, 'FINANCE_MANAGE_EXPENSES') as ok`, args: [fA] })).rows[0].ok, true);
  assertEquals((await c.queryObject<{ ok: boolean }>({ text: `select has_permission($1, 'FINANCE_MANAGE_EXPENSES') as ok`, args: [fB] })).rows[0].ok, false);
  await closeAll(su, c);
});

Deno.test("TEST 6 — the last active owner cannot be removed or demoted", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  await assertRejects(
    () => c.queryArray({ text: `select set_staff_status($1, $2, 'INACTIVE')`, args: [facilityId, owner] }),
    Error,
    "last active owner",
  );
  await assertRejects(
    () => c.queryArray({ text: `select assign_staff_role($1, $2, $3)`, args: [facilityId, owner, ROLE.staff] }),
    Error,
    "last active owner",
  );
  await assertRejects(
    () => c.queryArray({ text: `select remove_facility_access($1, $2)`, args: [facilityId, owner] }),
    Error,
    "last active owner",
  );
  await closeAll(su, c);
});

Deno.test("TEST 7 — a role assigned to active staff cannot be deleted", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const staff = await makeUser(su);
  const c = await authed(owner);
  const roleId = (await c.queryObject<{ id: string }>({
    text: `select create_role($1, 'Front Desk', 'Desk', array['BOOKINGS_VIEW','BOOKINGS_CREATE']) as id`,
    args: [facilityId],
  })).rows[0].id;
  await su.queryArray({
    text: `insert into facility_users (facility_id, user_id, role, role_id, status, activated_at)
           values ($1, $2, 'staff', $3, 'ACTIVE', now())`,
    args: [facilityId, staff, roleId],
  });
  await assertRejects(
    () => c.queryArray({ text: `select delete_role($1, $2)`, args: [roleId, facilityId] }),
    Error,
    "assigned to staff",
  );
  await closeAll(su, c);
});

Deno.test("TEST 8 — adding an existing user as staff creates no second auth account", async () => {
  const su = await superuser();
  const { facilityId } = await seed(su);
  const person = await makeUser(su);
  const before = (await su.queryObject<{ n: bigint }>({ text: `select count(*)::bigint n from auth.users` })).rows[0].n;
  await su.queryArray({
    text: `insert into facility_users (facility_id, user_id, role, status, activated_at) values ($1, $2, 'staff', 'ACTIVE', now())`,
    args: [facilityId, person],
  });
  const after = (await su.queryObject<{ n: bigint }>({ text: `select count(*)::bigint n from auth.users` })).rows[0].n;
  assertEquals(Number(after), Number(before));
  await closeAll(su);
});

Deno.test("TEST 9 — deactivating a staff member keeps their created_by history", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const staff = await makeUser(su);
  await addStaff(su, facilityId, staff, "staff");
  // an expense recorded by staff
  const catId = (await su.queryObject<{ id: string }>({
    text: `select id from expense_categories where facility_id is null and name = 'Other' limit 1`,
  })).rows[0].id;
  await su.queryArray({
    text: `insert into expenses (facility_id, category_id, amount_minor, spent_on, created_by, updated_by, currency, amount_paid_minor, payment_status)
           values ($1, $2, 5000, current_date, $3, $3, 'INR', 5000, 'PAID')`,
    args: [facilityId, catId, staff],
  });
  const oc = await authed(owner);
  await oc.queryArray({ text: `select set_staff_status($1, $2, 'INACTIVE')`, args: [facilityId, staff] });
  const row = await su.queryObject<{ created_by: string }>({
    text: `select created_by from expenses where facility_id = $1 limit 1`,
    args: [facilityId],
  });
  assertEquals(row.rows[0].created_by, staff);
  await closeAll(su, oc);
});

Deno.test("TEST 10 — a non-owner cannot grant a permission they do not hold", async () => {
  const su = await superuser();
  const { facilityId } = await seed(su);
  // a custom-role admin who can manage roles but has NO finance permissions
  const roleAdmin = await makeUser(su);
  const su2 = su;
  const roleId = (await su2.queryObject<{ id: string }>({
    text: `insert into roles (facility_id, name, base_role, is_system) values ($1, 'Role Admin', 'staff', false) returning id`,
    args: [facilityId],
  })).rows[0].id;
  await su2.queryArray({ text: `insert into role_permissions (role_id, permission_key) values ($1, 'USERS_MANAGE_ROLES'), ($1, 'USERS_VIEW')`, args: [roleId] });
  await su2.queryArray({
    text: `insert into facility_users (facility_id, user_id, role, role_id, status, activated_at) values ($1, $2, 'staff', $3, 'ACTIVE', now())`,
    args: [facilityId, roleAdmin, roleId],
  });
  const c = await authed(roleAdmin);
  await assertRejects(
    () =>
      c.queryArray({
        text: `select create_role($1, 'Money Role', null, array['FINANCE_REFUND'])`,
        args: [facilityId],
      }),
    Error,
    "permissions you hold",
  );
  await closeAll(su, c);
});

Deno.test("system-role permissions are configurable per facility (copy-on-write)", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  // strip FINANCE_REFUND from this facility's Manager role
  const keys = ["DASHBOARD_VIEW", "BOOKINGS_VIEW"];
  await c.queryArray({
    text: `select update_role($1, $2, null, null, null, $3)`,
    args: [ROLE.manager, facilityId, keys],
  });
  const mgr = await makeUser(su);
  await addStaff(su, facilityId, mgr, "manager");
  const mc = await authed(mgr);
  assertEquals(
    (await mc.queryObject<{ ok: boolean }>({ text: `select has_permission($1, 'FINANCE_REFUND') as ok`, args: [facilityId] })).rows[0].ok,
    false,
  );
  await closeAll(su, c, mc);
});
