import { assertEquals } from "jsr:@std/assert";
import { authed, closeAll, makeFacility, makeUser, resetCore, superuser } from "./_helpers.ts";

// Migration 0118 — profiles.role = 'admin' (what every owner signup gets) must not widen access to
// another business's information. Both owners below are 'admin'; each may only see their own facility.
Deno.test("an 'admin' owner cannot see or touch another owner's facility, profile or permissions", async () => {
  const su = await superuser();
  await resetCore(su);

  const ownerA = await makeUser(su);
  const ownerB = await makeUser(su);
  await su.queryArray({ text: `update profiles set role = 'admin' where id = any($1)`, args: [[ownerA, ownerB]] });
  const facilityA = await makeFacility(su, ownerA);
  const facilityB = await makeFacility(su, ownerB);

  const a = await authed(ownerA);

  // Facilities: only their own.
  const facilities = await a.queryObject<{ id: string }>(`select id from facilities`);
  assertEquals(facilities.rows.map((r) => r.id), [facilityA]);

  // Profiles: their own, never the other owner's.
  const otherProfile = await a.queryObject<{ id: string }>({ text: `select id from profiles where id = $1`, args: [ownerB] });
  assertEquals(otherProfile.rows.length, 0);
  const changed = await a.queryArray({ text: `update profiles set full_name = 'hijacked' where id = $1 returning id`, args: [ownerB] });
  assertEquals(changed.rows.length, 0);

  // Permissions: full in their own facility, none in the other.
  const own = await a.queryObject<{ ok: boolean }>({ text: `select has_permission($1, 'COACHING_VIEW') as ok`, args: [facilityA] });
  const other = await a.queryObject<{ ok: boolean }>({ text: `select has_permission($1, 'COACHING_VIEW') as ok`, args: [facilityB] });
  assertEquals(own.rows[0].ok, true);
  assertEquals(other.rows[0].ok, false);

  await closeAll(a, su);
});
