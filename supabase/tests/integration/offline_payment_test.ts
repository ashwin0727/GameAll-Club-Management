import { assert, assertEquals } from "jsr:@std/assert";
import { authed, closeAll, makeFacility, makeOpenCourt, makeUser, resetCore, superuser, tomorrowSlot } from "./_helpers.ts";

// §27.14–15 — offline "Record Payment": idempotent, and concurrency-safe
// against the outstanding balance.
Deno.test("record_obligation_payment: idempotency key + concurrent last-balance", async (t) => {
  const su = await superuser();
  await resetCore(su);
  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  const { courtId } = await makeOpenCourt(su, facilityId);
  const { start, end } = tomorrowSlot();

  const c = await authed(owner);
  const bookingId = (await c.queryObject<{ id: string }>({
    text: `select (create_booking($1,$2,$3,$4,'GUEST',null,'Payer',null,null,'PENDING',null,1,null)).id as id`,
    args: [facilityId, courtId, start, end],
  })).rows[0].id;

  // amount_minor was resolved from the ₹300/hr rule → ₹300 obligation. Force
  // a known value so the test is independent of pricing config.
  await su.queryArray({ text: `update bookings set amount_minor = 30000 where id = $1`, args: [bookingId] });

  await t.step("same idempotency key does not take the money twice", async () => {
    const key = crypto.randomUUID();
    const first = await c.queryObject<{ record_obligation_payment: { duplicate: boolean } }>({
      text: `select record_obligation_payment('GUEST_BOOKING', $1, 10000, 'CASH', null, null, null, $2) as record_obligation_payment`,
      args: [bookingId, key],
    });
    assertEquals(first.rows[0].record_obligation_payment.duplicate, false);

    const second = await c.queryObject<{ record_obligation_payment: { duplicate: boolean } }>({
      text: `select record_obligation_payment('GUEST_BOOKING', $1, 10000, 'CASH', null, null, null, $2) as record_obligation_payment`,
      args: [bookingId, key],
    });
    assertEquals(second.rows[0].record_obligation_payment.duplicate, true);

    const rows = await su.queryObject<{ n: bigint }>({
      text: `select count(*)::bigint n from payments where booking_id = $1`,
      args: [bookingId],
    });
    assertEquals(Number(rows.rows[0].n), 1);
  });

  await t.step("two concurrent payments for the whole remaining balance — one wins", async () => {
    const a = await authed(owner);
    const b = await authed(owner);
    const pay = (client: typeof a) =>
      client.queryArray({
        text: `select record_obligation_payment('GUEST_BOOKING', $1, 20000, 'CASH', null, null, null, $2)`,
        args: [bookingId, crypto.randomUUID()],
      });
    const results = await Promise.allSettled([pay(a), pay(b)]);
    assertEquals(results.filter((r) => r.status === "fulfilled").length, 1);
    assertEquals(results.filter((r) => r.status === "rejected").length, 1);

    const paid = await su.queryObject<{ total: bigint }>({
      text: `select coalesce(sum(amount_inr),0)::bigint total from payments where booking_id = $1 and status = 'paid'`,
      args: [bookingId],
    });
    assertEquals(Number(paid.rows[0].total), 300); // ₹100 + ₹200, never ₹100 + ₹200 + ₹200

    const flag = await su.queryObject<{ payment_status: string }>({
      text: `select payment_status from bookings where id = $1`,
      args: [bookingId],
    });
    assertEquals(flag.rows[0].payment_status, "PAID");
    await closeAll(a, b);
  });

  assert(true);
  await closeAll(su, c);
});
