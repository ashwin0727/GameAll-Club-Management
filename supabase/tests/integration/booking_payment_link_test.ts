import { assertEquals, assertRejects } from "jsr:@std/assert";
import { authed, closeAll, makeFacility, makeOpenCourt, makeUser, resetCore, superuser, tomorrowSlot } from "./_helpers.ts";

// Migration 0124 — a guest booking's "Pay Online" payment link settles through the same gate as a checkout
// payment, and can only ever settle the booking it was made for.
Deno.test("apply_booking_payment_link_event: paid link confirms the booking, safely and once", async (t) => {
  const su = await superuser();
  await resetCore(su);
  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  const { courtId } = await makeOpenCourt(su, facilityId);
  const { start, end } = tomorrowSlot();

  const c = await authed(owner);
  const bookingId = (await c.queryObject<{ id: string }>({
    text: `select (create_booking($1,$2,$3,$4,'GUEST',null,'Buyer',null,null,'PENDING',null,1,null)).id as id`,
    args: [facilityId, courtId, start, end],
  })).rows[0].id;
  await su.queryArray({ text: `update bookings set amount_minor = 80000 where id = $1`, args: [bookingId] });

  const poId = (await su.queryObject<{ id: string }>({
    text: `insert into payment_orders
             (facility_id, source_type, booking_id, amount_minor, currency, status, receipt, expires_at, created_by,
              razorpay_payment_link_id, payment_link_url, payment_link_status)
           values ($1,'GUEST_BOOKING',$2,80000,'INR','ORDER_CREATED','RCPT-LINK',now()+interval '1 day',$3,
                   'plink_1','https://rzp.io/i/x','CREATED')
           returning id`,
    args: [facilityId, bookingId, owner],
  })).rows[0].id;

  const event = (link: string, name: string, order: string | null, pay: string | null, amount: number | null) =>
    su.queryObject<{ handled: boolean }>({
      text: `select apply_booking_payment_link_event($1,$2,$3,$4,$5,'INR') as handled`,
      args: [link, name, order, pay, amount],
    });

  await t.step("a link that is not ours is reported as not handled", async () => {
    assertEquals((await event("plink_other", "paid", "order_x", "pay_x", 80000)).rows[0].handled, false);
  });

  await t.step("a wrong amount is rejected and the booking stays pending", async () => {
    await assertRejects(() => event("plink_1", "paid", "order_L", "pay_1", 999));
    const b = await su.queryObject<{ payment_status: string }>({ text: `select payment_status from bookings where id = $1`, args: [bookingId] });
    assertEquals(b.rows[0].payment_status, "PENDING");
  });

  await t.step("the real payment confirms and pays the booking, once even if delivered twice", async () => {
    for (let i = 0; i < 2; i++) assertEquals((await event("plink_1", "paid", "order_L", "pay_1", 80000)).rows[0].handled, true);
    const b = await su.queryObject<{ payment_status: string; status: string }>({ text: `select payment_status, status from bookings where id = $1`, args: [bookingId] });
    assertEquals(b.rows[0].payment_status, "PAID");
    assertEquals(b.rows[0].status, "confirmed");
    const n = await su.queryObject<{ n: bigint }>({ text: `select count(*)::bigint n from payments where payment_order_id = $1`, args: [poId] });
    assertEquals(Number(n.rows[0].n), 1);
    const po = await su.queryObject<{ payment_link_status: string; status: string }>({ text: `select payment_link_status, status from payment_orders where id = $1`, args: [poId] });
    assertEquals(po.rows[0].payment_link_status, "PAID");
    assertEquals(po.rows[0].status, "COMPLETED");
  });

  await t.step("a different payment can never be substituted afterwards", async () => {
    await assertRejects(() => event("plink_1", "paid", "order_L", "pay_2", 80000));
  });

  await t.step("a paid link is never downgraded by a late expired / cancelled event", async () => {
    await event("plink_1", "expired", null, null, null);
    const po = await su.queryObject<{ payment_link_status: string }>({ text: `select payment_link_status from payment_orders where id = $1`, args: [poId] });
    assertEquals(po.rows[0].payment_link_status, "PAID");
  });

  await t.step("only the service role may call it", async () => {
    await assertRejects(() => c.queryArray({ text: `select apply_booking_payment_link_event('plink_1','paid','order_L','pay_1',80000,'INR')` }));
  });

  await closeAll(su, c);
});

Deno.test("apply_booking_payment_link_event: a cancelled link is recorded", async () => {
  const su = await superuser();
  await resetCore(su);
  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  const { courtId } = await makeOpenCourt(su, facilityId);
  const { start, end } = tomorrowSlot();
  const c = await authed(owner);
  const bookingId = (await c.queryObject<{ id: string }>({
    text: `select (create_booking($1,$2,$3,$4,'GUEST',null,'Buyer',null,null,'PENDING',null,1,null)).id as id`,
    args: [facilityId, courtId, start, end],
  })).rows[0].id;
  await su.queryArray({ text: `update bookings set amount_minor = 80000 where id = $1`, args: [bookingId] });
  const poId = (await su.queryObject<{ id: string }>({
    text: `insert into payment_orders
             (facility_id, source_type, booking_id, amount_minor, currency, status, receipt, expires_at, created_by,
              razorpay_payment_link_id, payment_link_url, payment_link_status)
           values ($1,'GUEST_BOOKING',$2,80000,'INR','ORDER_CREATED','RCPT-LINK2',now()+interval '1 day',$3,'plink_2','https://rzp.io/i/y','CREATED')
           returning id`,
    args: [facilityId, bookingId, owner],
  })).rows[0].id;
  await su.queryArray({ text: `select apply_booking_payment_link_event('plink_2','cancelled')` });
  const po = await su.queryObject<{ payment_link_status: string }>({ text: `select payment_link_status from payment_orders where id = $1`, args: [poId] });
  assertEquals(po.rows[0].payment_link_status, "CANCELLED");
  await closeAll(su, c);
});
