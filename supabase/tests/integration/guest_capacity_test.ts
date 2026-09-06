import { assert, assertEquals, assertRejects } from "jsr:@std/assert";
import { authed, closeAll, makeFacility, makeOpenCourt, makeUser, resetCore, superuser } from "./_helpers.ts";

// §27.2 / §27.3 / §27.4 — released membership capacity.
//   * a guest slot consumes ONLY released capacity, and two guests racing
//     for the last released seat cannot both win;
//   * release cannot exceed unused membership capacity;
//   * a released seat already taken by a guest cannot be restored.
Deno.test("membership guest-slot capacity: race, over-release, restore-after-book", async (t) => {
  const su = await superuser();
  await resetCore(su);

  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  const { facilitySportId, courtId } = await makeOpenCourt(su, facilityId);

  const c = await authed(owner);

  const planId = (await c.queryObject<{ id: string }>({
    text: `insert into membership_plans (facility_id, name, price_inr, duration_days)
           values ($1, 'Plan', 1000, 30) returning id`,
    args: [facilityId],
  })).rows[0].id;

  const batchId = (await c.queryObject<{ id: string }>({
    text: `select (create_membership_batch($1,$2,$3,$4,'Batch',$5::smallint[],'18:00','19:00',5)).id as id`,
    args: [facilityId, planId, facilitySportId, courtId, "{0,1,2,3,4,5,6}"],
  })).rows[0].id;

  const d = new Date();
  d.setUTCDate(d.getUTCDate() + 1);
  const sessionDate = d.toISOString().slice(0, 10);

  const guest = async (name: string) =>
    (await c.queryObject<{ id: string }>({
      text: `select (find_or_create_guest($1,$2,$3)).id as id`,
      args: [facilityId, name, `9${Math.floor(Math.random() * 1e9)}`],
    })).rows[0].id;

  await t.step("release cannot exceed unused capacity (5)", async () => {
    const session = (await c.queryObject<{ id: string }>({
      text: `select (get_or_create_membership_session($1,$2)).id as id`,
      args: [batchId, sessionDate],
    })).rows[0].id;

    await assertRejects(() =>
      c.queryArray({ text: `select release_membership_capacity($1, 6)`, args: [session] })
    );
    await c.queryArray({ text: `select release_membership_capacity($1, 1)`, args: [session] });
  });

  await t.step("two guests race for the one released seat — one wins", async () => {
    const a = await authed(owner);
    const b = await authed(owner);
    const g1 = await guest("Race One");
    const g2 = await guest("Race Two");

    const results = await Promise.allSettled([
      a.queryArray({ text: `select book_guest_slot($1,$2,$3)`, args: [batchId, sessionDate, g1] }),
      b.queryArray({ text: `select book_guest_slot($1,$2,$3)`, args: [batchId, sessionDate, g2] }),
    ]);
    assertEquals(results.filter((r) => r.status === "fulfilled").length, 1);
    assertEquals(results.filter((r) => r.status === "rejected").length, 1);

    const booked = await su.queryObject<{ n: bigint }>({
      text: `select count(*)::bigint n from membership_session_bookings b
             join membership_sessions s on s.id = b.session_id
             where s.batch_id = $1 and b.participant_type = 'GUEST' and b.status = 'CONFIRMED'`,
      args: [batchId],
    });
    assertEquals(Number(booked.rows[0].n), 1);
    await closeAll(a, b);
  });

  await t.step("cannot restore a released seat a guest already booked", async () => {
    const session = (await c.queryObject<{ id: string }>({
      text: `select id from membership_sessions where batch_id = $1 and session_date = $2`,
      args: [batchId, sessionDate],
    })).rows[0].id;
    await assertRejects(() =>
      c.queryArray({ text: `select restore_membership_capacity($1, 1)`, args: [session] })
    );
  });

  await t.step("guest capacity read is consistent", async () => {
    const cap = await c.queryObject<{ guest_available_capacity: number; guest_booked_count: number }>({
      text: `select * from get_membership_session_capacity(
               (select id from membership_sessions where batch_id = $1 and session_date = $2))`,
      args: [batchId, sessionDate],
    });
    assert(cap.rows[0].guest_available_capacity <= 0);
    assertEquals(cap.rows[0].guest_booked_count, 1);
  });

  await closeAll(su, c);
});
