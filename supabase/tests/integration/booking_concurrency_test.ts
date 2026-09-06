import { assertEquals } from "jsr:@std/assert";
import { authed, closeAll, makeFacility, makeOpenCourt, makeUser, resetCore, superuser, tomorrowSlot } from "./_helpers.ts";

// §27.1 — two users booking the same final slot simultaneously.
// Expected: exactly one confirmed, the other rejected as unavailable —
// enforced by the bookings_no_overlap GiST exclusion constraint, not app code.
Deno.test("two concurrent create_booking calls for one court/slot — exactly one wins", async () => {
  const su = await superuser();
  await resetCore(su);

  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  const { courtId } = await makeOpenCourt(su, facilityId);
  const { start, end } = tomorrowSlot();

  const a = await authed(owner);
  const b = await authed(owner);

  const book = (c: typeof a, who: string) =>
    c.queryObject({
      text: `select (create_booking($1,$2,$3,$4,'GUEST',null,$5,null,null,'PENDING',null,1,null)).id as id`,
      args: [facilityId, courtId, start, end, `Racer ${who}`],
    });

  const results = await Promise.allSettled([book(a, "A"), book(b, "B")]);

  const wins = results.filter((r) => r.status === "fulfilled").length;
  const losses = results.filter(
    (r) => r.status === "rejected" && String((r as PromiseRejectedResult).reason).match(/23P01|exclusion|overlap|not available/i),
  ).length;

  assertEquals(wins, 1, "exactly one booking should succeed");
  assertEquals(losses, 1, "the other should fail on the exclusion constraint");

  const count = await su.queryObject<{ n: bigint }>({
    text: `select count(*)::bigint n from bookings where court_id = $1 and status in ('pending','confirmed')`,
    args: [courtId],
  });
  assertEquals(Number(count.rows[0].n), 1);

  await closeAll(su, a, b);
});
