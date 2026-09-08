import { assertEquals, assertRejects } from "jsr:@std/assert";
import { authed, closeAll, makeFacility, makeUser, resetCore, superuser } from "./_helpers.ts";

// §27.18 — Facility A must not reach Facility B's financial data. Finance
// RPCs deny explicitly (42501), not just filter to zero.
Deno.test("facility A cannot read facility B finance / payments", async () => {
  const su = await superuser();
  await resetCore(su);

  const ownerA = await makeUser(su);
  const ownerB = await makeUser(su);
  const facilityA = await makeFacility(su, ownerA);
  const facilityB = await makeFacility(su, ownerB);

  // Real paid money in facility B.
  await su.queryArray({
    text: `insert into payments (facility_id, amount_inr, status, paid_at)
           values ($1, 5000, 'paid', now())`,
    args: [facilityB],
  });

  const a = await authed(ownerA);

  await assertRejects(
    () => a.queryArray({ text: `select * from get_finance_summary($1)`, args: [facilityB] }),
    Error,
    "Not authorized",
  );
  await assertRejects(
    () => a.queryArray({ text: `select * from list_pending_payments($1)`, args: [facilityB] }),
    Error,
    "Not authorized",
  );

  const leaked = await a.queryObject<{ n: bigint }>({
    text: `select count(*)::bigint n from payments where facility_id = $1`,
    args: [facilityB],
  });
  assertEquals(Number(leaked.rows[0].n), 0, "RLS must hide facility B payments");

  // Sanity: A can read its own.
  const ownSummary = await a.queryArray({ text: `select * from get_finance_summary($1)`, args: [facilityA] });
  assertEquals(ownSummary.rows.length, 1);

  await closeAll(su, a);
});
