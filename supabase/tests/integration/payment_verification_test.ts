import { assertEquals, assertRejects } from "jsr:@std/assert";
import { authed, closeAll, makeFacility, makeOpenCourt, makeUser, resetCore, superuser, tomorrowSlot } from "./_helpers.ts";

// §27.5–7 — server-side payment verification is the authority.
Deno.test("apply_payment_verification: tamper rejected, capture idempotent", async (t) => {
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
  await su.queryArray({ text: `update bookings set amount_minor = 30000 where id = $1`, args: [bookingId] });

  const poId = (await su.queryObject<{ id: string }>({
    text: `insert into payment_orders
             (facility_id, source_type, booking_id, amount_minor, currency, status,
              razorpay_order_id, receipt, expires_at, created_by)
           values ($1,'GUEST_BOOKING',$2,30000,'INR','ORDER_CREATED','order_pv','RCPT',now()+interval '1 day',$3)
           returning id`,
    args: [facilityId, bookingId, owner],
  })).rows[0].id;

  await t.step("wrong amount is rejected", async () => {
    await assertRejects(() =>
      c.queryArray({
        text: `select apply_payment_verification($1,'order_pv','pay_1','CAPTURED', 999, 'INR', 'sig')`,
        args: [poId],
      })
    );
  });

  await t.step("wrong razorpay order id is rejected", async () => {
    await assertRejects(() =>
      c.queryArray({
        text: `select apply_payment_verification($1,'order_WRONG','pay_1','CAPTURED', 30000, 'INR', 'sig')`,
        args: [poId],
      })
    );
  });

  await t.step("a genuine CAPTURED, applied twice, yields exactly one payment row", async () => {
    for (let i = 0; i < 2; i++) {
      await c.queryArray({
        text: `select apply_payment_verification($1,'order_pv','pay_1','CAPTURED', 30000, 'INR', 'sig')`,
        args: [poId],
      });
    }
    const payments = await su.queryObject<{ n: bigint }>({
      text: `select count(*)::bigint n from payments where payment_order_id = $1`,
      args: [poId],
    });
    assertEquals(Number(payments.rows[0].n), 1);

    const po = await su.queryObject<{ status: string }>({
      text: `select status from payment_orders where id = $1`,
      args: [poId],
    });
    // CAPTURED → inline settle_payment → COMPLETED (booking still confirmable).
    assertEquals(po.rows[0].status, "COMPLETED");

    const booking = await su.queryObject<{ payment_status: string; status: string }>({
      text: `select payment_status, status from bookings where id = $1`,
      args: [bookingId],
    });
    assertEquals(booking.rows[0].payment_status, "PAID");
    assertEquals(booking.rows[0].status, "confirmed");
  });

  await t.step("a second, different payment id can never be substituted", async () => {
    await assertRejects(() =>
      c.queryArray({
        text: `select apply_payment_verification($1,'order_pv','pay_2','CAPTURED', 30000, 'INR', 'sig')`,
        args: [poId],
      })
    );
  });

  await closeAll(su, c);
});
