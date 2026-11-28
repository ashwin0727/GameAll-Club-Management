import { assert, assertEquals, assertRejects } from "jsr:@std/assert";
import { authed, closeAll, makeFacility, makeUser, resetCore, superuser } from "./_helpers.ts";

// Coach onboarding (migration 0211): draft creation, idempotent resume, payout validation + masking, the payouts
// permission gate and completion. Run with the rest of the DB suite (needs local Supabase).

type SU = Awaited<ReturnType<typeof superuser>>;

async function seed(su: SU) {
  await resetCore(su);
  await su.queryArray(
    `delete from coach_payout_details; delete from coach_profiles; delete from coach_availability; delete from coaches;`,
  );
  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  return { owner, facilityId };
}

async function staffMember(su: SU, facilityId: string): Promise<string> {
  const uid = await makeUser(su);
  await su.queryArray({
    text: `insert into facility_users (facility_id, user_id, role, status, is_primary, activated_at)
           values ($1, $2, 'staff', 'ACTIVE', false, now())`,
    args: [facilityId, uid],
  });
  return uid;
}

/** A custom role with exactly `keys`, assigned to a new user. */
async function userWithPerms(su: SU, facilityId: string, keys: string[]): Promise<string> {
  const uid = await makeUser(su);
  const roleId = crypto.randomUUID();
  await su.queryArray({
    text: `insert into roles (id, facility_id, key, base_role, name, is_system, is_template)
           values ($1, $2, null, 'staff', $3, false, false)`,
    args: [roleId, facilityId, `role-${roleId.slice(0, 8)}`],
  });
  for (const k of keys) {
    await su.queryArray({ text: `insert into role_permissions (role_id, permission_key) values ($1, $2)`, args: [roleId, k] });
  }
  await su.queryArray({
    text: `insert into facility_users (facility_id, user_id, role, role_id, status, is_primary, activated_at)
           values ($1, $2, 'staff', $3, 'ACTIVE', false, now())`,
    args: [facilityId, uid, roleId],
  });
  return uid;
}

const IDENTITY = { displayName: "Ravi Kumar", location: "Chennai", timezone: "Asia/Kolkata", languages: ["English", "Tamil"], shortBio: "Coach" };
const PAYOUT = {
  entityType: "INDIVIDUAL",
  taxId: "abcde 1234f",
  payoutMethod: "BANK_TRANSFER",
  accountHolderName: "Ravi Kumar",
  accountNumber: "123456781234",
  ifsc: "sbin 0001234",
  payoutFrequency: "MONTHLY",
};

Deno.test("onboarding: start creates an INACTIVE coach + DRAFT profile, and a second start returns the same id", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const u = await staffMember(su, facilityId);

  const first = (await c.queryObject<{ id: string }>({
    text: `select start_coach_onboarding($1, $2, $3::jsonb) as id`,
    args: [facilityId, u, JSON.stringify(IDENTITY)],
  })).rows[0].id;
  const again = (await c.queryObject<{ id: string }>({
    text: `select start_coach_onboarding($1, $2, $3::jsonb) as id`,
    args: [facilityId, u, JSON.stringify(IDENTITY)],
  })).rows[0].id;
  assertEquals(first, again);

  const row = (await su.queryObject<{ status: string; onboarding_status: string; current_step: number }>({
    text: `select c.status, cp.onboarding_status, cp.current_step from coaches c join coach_profiles cp on cp.coach_id = c.id where c.id = $1`,
    args: [first],
  })).rows[0];
  assertEquals(row.status, "INACTIVE");
  assertEquals(row.onboarding_status, "DRAFT");
  assertEquals(row.current_step, 2);
  await closeAll(su, c);
});

Deno.test("onboarding: payout validation, masking, normalisation and completion", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const u = await staffMember(su, facilityId);
  const id = (await c.queryObject<{ id: string }>({
    text: `select start_coach_onboarding($1, $2, $3::jsonb) as id`,
    args: [facilityId, u, JSON.stringify(IDENTITY)],
  })).rows[0].id;

  // Bad IFSC is rejected.
  await assertRejects(
    () => c.queryArray({ text: `select save_coach_onboarding_step($1, 4, $2::jsonb)`, args: [id, JSON.stringify({ ...PAYOUT, ifsc: "abc" })] }),
    Error,
    "IFSC",
  );
  // Lower-case / spaced PAN + IFSC are normalised and accepted.
  await c.queryArray({ text: `select save_coach_onboarding_step($1, 4, $2::jsonb)`, args: [id, JSON.stringify(PAYOUT)] });
  const got = (await c.queryObject<{ g: Record<string, any> }>({ text: `select get_coach_onboarding($1) as g`, args: [id] })).rows[0].g;
  assertEquals(got.payout.accountNumberMasked, "XXXXXXXX1234");
  assertEquals(got.payout.taxIdMasked, "XXXXXX234F");
  assertEquals(got.payout.ifsc, "SBIN0001234");
  assert(!JSON.stringify(got).includes("123456781234"), "raw account number must never be returned");
  assertEquals(got.payoutStatus, "COMPLETE");

  // Completion needs steps 1-3 and every agreement.
  await assertRejects(
    () => c.queryArray({ text: `select complete_coach_onboarding($1, '{"terms":true,"ethics":true,"privacy":true,"commission":true}'::jsonb)`, args: [id] }),
    Error,
    "steps 1 to 3",
  );
  await c.queryArray({
    text: `select save_coach_onboarding_step($1, 2, $2::jsonb)`,
    args: [id, JSON.stringify({ niche: "Badminton", experienceYears: 5, sportIds: [], expertiseLevels: ["Beginner"], certificates: [] })],
  });
  await c.queryArray({
    text: `select save_coach_onboarding_step($1, 3, $2::jsonb)`,
    args: [id, JSON.stringify({
      sessionFormats: ["ONE_TO_ONE"], sessionDurations: [60], perSessionRateMinor: 50000, weeklyRateMinor: 200000, monthlyRateMinor: 700000,
      availability: [{ dayOfWeek: 1, startTime: "09:00", endTime: "12:00" }],
    })],
  });
  const rates = (await su.queryObject<{ p: number; w: number; m: number }>({
    text: `select per_session_rate_minor p, weekly_rate_minor w, monthly_rate_minor m from coach_profiles where coach_id = $1`, args: [id],
  })).rows[0];
  assertEquals([rates.p, rates.w, rates.m], [50000, 200000, 700000]);
  await assertRejects(
    () => c.queryArray({ text: `select complete_coach_onboarding($1, '{"terms":true,"ethics":true,"privacy":true,"commission":false}'::jsonb)`, args: [id] }),
    Error,
    "agreements",
  );
  await c.queryArray({ text: `select complete_coach_onboarding($1, '{"terms":true,"ethics":true,"privacy":true,"commission":true}'::jsonb)`, args: [id] });
  const status = (await su.queryObject<{ status: string }>({ text: `select status from coaches where id = $1`, args: [id] })).rows[0].status;
  assertEquals(status, "ACTIVE");
  await closeAll(su, c);
});

Deno.test("onboarding: step 3 rejects a zero rate and a slot that ends before it starts", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const u = await staffMember(su, facilityId);
  const id = (await c.queryObject<{ id: string }>({
    text: `select start_coach_onboarding($1, $2, $3::jsonb) as id`,
    args: [facilityId, u, JSON.stringify(IDENTITY)],
  })).rows[0].id;
  const base = { sessionFormats: ["GROUP"], sessionDurations: [60], perSessionRateMinor: 50000, weeklyRateMinor: 200000, monthlyRateMinor: 700000 };
  for (const [key, word] of [["perSessionRateMinor", "per-session"], ["weeklyRateMinor", "weekly"], ["monthlyRateMinor", "monthly"]] as const) {
    await assertRejects(
      () => c.queryArray({ text: `select save_coach_onboarding_step($1, 3, $2::jsonb)`, args: [id, JSON.stringify({ ...base, [key]: 0 })] }),
      Error,
      word,
    );
  }
  await assertRejects(
    () => c.queryArray({
      text: `select save_coach_onboarding_step($1, 3, $2::jsonb)`,
      args: [id, JSON.stringify({ ...base, availability: [{ dayOfWeek: 1, startTime: "10:00", endTime: "09:00" }] })],
    }),
    Error,
    "end after",
  );
  // The same day twice / overlapping is rejected; back-to-back is accepted.
  const slot = (s: string, e: string) => ({ dayOfWeek: 1, startTime: s, endTime: e });
  await assertRejects(
    () => c.queryArray({ text: `select save_coach_onboarding_step($1, 3, $2::jsonb)`, args: [id, JSON.stringify({ ...base, availability: [slot("09:00", "12:00"), slot("09:00", "12:00")] })] }),
    Error,
    "overlap or repeat",
  );
  await assertRejects(
    () => c.queryArray({ text: `select save_coach_onboarding_step($1, 3, $2::jsonb)`, args: [id, JSON.stringify({ ...base, availability: [slot("09:00", "12:00"), slot("11:00", "13:00")] })] }),
    Error,
    "overlap or repeat",
  );
  await c.queryArray({ text: `select save_coach_onboarding_step($1, 3, $2::jsonb)`, args: [id, JSON.stringify({ ...base, availability: [slot("09:00", "12:00"), slot("12:00", "14:00")] })] });
  await closeAll(su, c);
});

Deno.test("onboarding: without the payouts permission step 4 is refused and payout is hidden", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const u = await staffMember(su, facilityId);
  const id = (await c.queryObject<{ id: string }>({
    text: `select start_coach_onboarding($1, $2, $3::jsonb) as id`,
    args: [facilityId, u, JSON.stringify(IDENTITY)],
  })).rows[0].id;
  await c.queryArray({ text: `select save_coach_onboarding_step($1, 4, $2::jsonb)`, args: [id, JSON.stringify(PAYOUT)] });

  const manager = await userWithPerms(su, facilityId, ["COACHING_VIEW", "COACHING_MANAGE_COACHES"]);
  const m = await authed(manager);
  const got = (await m.queryObject<{ g: Record<string, any> }>({ text: `select get_coach_onboarding($1) as g`, args: [id] })).rows[0].g;
  assertEquals(got.canManagePayouts, false);
  assertEquals(got.payout, null);
  await assertRejects(
    () => m.queryArray({ text: `select save_coach_onboarding_step($1, 4, $2::jsonb)`, args: [id, JSON.stringify(PAYOUT)] }),
    Error,
    "payout",
  );
  await closeAll(su, c, m);
});
