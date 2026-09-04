import { assertEquals, assertRejects } from "jsr:@std/assert";
import { authed, closeAll, makeFacility, makeOpenCourt, makeUser, resetCore, superuser } from "./_helpers.ts";

// §9 / §27 — public booking abuse controls (0065).
Deno.test("public booking: IP rate-limit window rejects a flood", async () => {
  const su = await superuser();
  await resetCore(su);
  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  const anon = await su; // record_and_check_* is SECURITY DEFINER; run as superuser

  const ipHash = "hash_of_one_ip";
  // limit is > 8 in 10 minutes → the 9th call raises.
  for (let i = 0; i < 8; i++) {
    await anon.queryArray({
      text: `select record_and_check_public_booking_attempt($1, $2, $3)`,
      args: [facilityId, ipHash, `90000000${i}`],
    });
  }
  await assertRejects(
    () =>
      anon.queryArray({
        text: `select record_and_check_public_booking_attempt($1, $2, $3)`,
        args: [facilityId, ipHash, "900000009"],
      }),
    Error,
    "Too many booking attempts",
  );
  await closeAll(su);
});

Deno.test("public booking: unpaid-booking cap rejects the 5th", async () => {
  const su = await superuser();
  await resetCore(su);
  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  const { courtId } = await makeOpenCourt(su, facilityId);
  const c = await authed(owner);

  const guestId = (await c.queryObject<{ id: string }>({
    text: `select (find_or_create_guest($1, 'Capped Guest', '9998887770')).id as id`,
    args: [facilityId],
  })).rows[0].id;

  // Four unpaid, future guest bookings already on the books.
  for (let h = 0; h < 4; h++) {
    const day = new Date();
    day.setUTCDate(day.getUTCDate() + 2 + h);
    const start = new Date(Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), 6, 0, 0));
    const end = new Date(start.getTime() + 3600_000);
    await su.queryArray({
      text: `insert into bookings
               (facility_id, court_id, member_id, start_time, end_time, status,
                customer_type, guest_name, guest_player_id, payment_status, currency, created_by)
             values ($1,$2,null,$3,$4,'confirmed','GUEST','Capped Guest',$5,'PENDING','INR',$6)`,
      args: [facilityId, courtId, start.toISOString(), end.toISOString(), guestId, owner],
    });
  }

  const day = new Date();
  day.setUTCDate(day.getUTCDate() + 20);
  const start = new Date(Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), 6, 0, 0));
  const end = new Date(start.getTime() + 3600_000);

  await assertRejects(
    () =>
      c.queryArray({
        text: `select public_create_guest_booking($1,$2,$3,$4,'Capped Guest','9998887770')`,
        args: [facilityId, courtId, start.toISOString(), end.toISOString()],
      }),
    Error,
    "unpaid bookings still pending",
  );

  await closeAll(su, c);
});
