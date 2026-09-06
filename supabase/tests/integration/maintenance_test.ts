import { assert, assertEquals, assertRejects } from "jsr:@std/assert";
import { authed, closeAll, makeFacility, makeOpenCourt, makeUser, resetCore, superuser } from "./_helpers.ts";

// Maintenance & Court Operations (migration 0068) — the spec's critical
// availability-integration and booking-conflict tests.

/** "h:m tomorrow, Asia/Kolkata (UTC+5:30)" -> a UTC ISO string. */
function ist(h: number, m = 0): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + 1);
  let utcH = h - 5;
  let utcM = m - 30;
  if (utcM < 0) {
    utcM += 60;
    utcH -= 1;
  }
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), utcH, utcM, 0)).toISOString();
}

async function seed(su: Awaited<ReturnType<typeof superuser>>) {
  await resetCore(su);
  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  const { courtId } = await makeOpenCourt(su, facilityId);
  const categoryId = (
    await su.queryObject<{ id: string }>(
      `select id from maintenance_issue_categories where facility_id is null and name = 'General Repair' limit 1`,
    )
  ).rows[0].id;
  return { owner, facilityId, courtId, categoryId };
}

Deno.test("booking 6-7pm IS affected by maintenance 6:30-8pm", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId } = await seed(su);
  const c = await authed(owner);
  await c.queryArray({
    text: `select create_booking($1,$2,$3,$4,'GUEST',null,'Neha',null,null,'PENDING',null,1,null)`,
    args: [facilityId, courtId, ist(18), ist(19)],
  });
  const affected = await c.queryObject<{ n: bigint }>({
    text: `select count(*)::bigint n from detect_maintenance_affected_bookings($1, $2, $3)`,
    args: [courtId, ist(18, 30), ist(20)],
  });
  assertEquals(Number(affected.rows[0].n), 1);
  await closeAll(su, c);
});

Deno.test("booking 6-7pm is NOT affected by maintenance 7-8pm (exclusive end boundary)", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId } = await seed(su);
  const c = await authed(owner);
  await c.queryArray({
    text: `select create_booking($1,$2,$3,$4,'GUEST',null,'Neha',null,null,'PENDING',null,1,null)`,
    args: [facilityId, courtId, ist(18), ist(19)],
  });
  const affected = await c.queryObject<{ n: bigint }>({
    text: `select count(*)::bigint n from detect_maintenance_affected_bookings($1, $2, $3)`,
    args: [courtId, ist(19), ist(20)],
  });
  assertEquals(Number(affected.rows[0].n), 0);
  await closeAll(su, c);
});

Deno.test("an ACTIVE maintenance block makes create_booking reject that window", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId, categoryId } = await seed(su);
  const c = await authed(owner);
  await c.queryArray({
    text: `select create_maintenance_ticket($1,$2,$3,'HIGH','Floor repair','Sanding the floor', $4, $5)`,
    args: [facilityId, courtId, categoryId, ist(16), ist(19)],
  });
  await assertRejects(
    () =>
      c.queryArray({
        text: `select create_booking($1,$2,$3,$4,'GUEST',null,'Racer',null,null,'PENDING',null,1,null)`,
        args: [facilityId, courtId, ist(17), ist(18)],
      }),
    Error,
    "under maintenance",
  );
  await closeAll(su, c);
});

Deno.test("resolving the ticket ends the block — the court reopens for booking", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId, categoryId } = await seed(su);
  const c = await authed(owner);
  const ticketId = (
    await c.queryObject<{ id: string }>({
      text: `select (create_maintenance_ticket($1,$2,$3,'HIGH','Floor repair','x', $4, $5)).id as id`,
      args: [facilityId, courtId, categoryId, ist(16), ist(19)],
    })
  ).rows[0].id;
  await c.queryArray({ text: `select start_maintenance_ticket($1)`, args: [ticketId] });
  await c.queryArray({ text: `select resolve_maintenance_ticket($1)`, args: [ticketId] });

  const blockStatus = (
    await su.queryObject<{ status: string }>({ text: `select status from maintenance_blocks where ticket_id = $1`, args: [ticketId] })
  ).rows[0].status;
  assertEquals(blockStatus, "ENDED");

  const booked = await c.queryArray({
    text: `select create_booking($1,$2,$3,$4,'GUEST',null,'AfterFix',null,null,'PENDING',null,1,null)`,
    args: [facilityId, courtId, ist(17), ist(18)],
  });
  assert(booked.rows.length === 1);
  await closeAll(su, c);
});

Deno.test("two tickets cannot schedule overlapping blocks on the same court", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId, categoryId } = await seed(su);
  const c = await authed(owner);
  const t1 = (
    await c.queryObject<{ id: string }>({ text: `select (create_maintenance_ticket($1,$2,$3,'HIGH','A','x')).id as id`, args: [facilityId, courtId, categoryId] })
  ).rows[0].id;
  const t2 = (
    await c.queryObject<{ id: string }>({ text: `select (create_maintenance_ticket($1,$2,$3,'HIGH','B','x')).id as id`, args: [facilityId, courtId, categoryId] })
  ).rows[0].id;
  await c.queryArray({ text: `select schedule_maintenance($1, $2, $3)`, args: [t1, ist(16), ist(19)] });
  await assertRejects(
    () => c.queryArray({ text: `select schedule_maintenance($1, $2, $3)`, args: [t2, ist(17), ist(20)] }),
    Error,
    "Another maintenance block already exists",
  );
  await closeAll(su, c);
});

Deno.test("facility A cannot read facility B's maintenance overview", async () => {
  const su = await superuser();
  await resetCore(su);
  const ownerA = await makeUser(su);
  const ownerB = await makeUser(su);
  await makeFacility(su, ownerA);
  const facilityB = await makeFacility(su, ownerB);
  const a = await authed(ownerA);
  await assertRejects(() => a.queryArray({ text: `select get_maintenance_overview($1)`, args: [facilityB] }), Error, "Not authorized");
  await closeAll(su, a);
});
