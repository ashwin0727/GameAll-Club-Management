import { assert, assertEquals, assertRejects } from "jsr:@std/assert";
import { authed, closeAll, makeFacility, makeOpenCourt, makeUser, resetCore, superuser, tomorrowSlot } from "./_helpers.ts";

// §27.10–13 + the P1 concurrent-refund fix (0064).
async function seedCompletedOrder(su: Awaited<ReturnType<typeof superuser>>, ownerId: string) {
  const facilityId = await makeFacility(su, ownerId);
  const { courtId } = await makeOpenCourt(su, facilityId);
  const { start, end } = tomorrowSlot();
  const c = await authed(ownerId);
  const bookingId = (await c.queryObject<{ id: string }>({
    text: `select (create_booking($1,$2,$3,$4,'GUEST',null,'Refundee',null,null,'PENDING',null,1,null)).id as id`,
    args: [facilityId, courtId, start, end],
  })).rows[0].id;
  const poId = (await su.queryObject<{ id: string }>({
    text: `insert into payment_orders
             (facility_id, source_type, booking_id, amount_minor, currency, status,
              razorpay_order_id, razorpay_payment_id, receipt, expires_at, created_by)
           values ($1,'GUEST_BOOKING',$2,30000,'INR','COMPLETED',
              'order_' || $3, 'pay_' || $3, 'RCPT', now() + interval '1 day', $4)
           returning id`,
    args: [facilityId, bookingId, crypto.randomUUID().slice(0, 8), ownerId],
  })).rows[0].id;
  await c.end();
  return { facilityId, bookingId, poId };
}

Deno.test("refund: over-refund is blocked", async () => {
  const su = await superuser();
  await resetCore(su);
  const owner = await makeUser(su);
  const { poId, bookingId } = await seedCompletedOrder(su, owner);
  const c = await authed(owner);

  await assertRejects(() =>
    c.queryArray({
      text: `select request_refund($1, 999999, 'CUSTOMER_CANCELLATION', 'GUEST_BOOKING', $2, false, null, null)`,
      args: [poId, bookingId],
    })
  );
  await closeAll(su, c);
});

Deno.test("refund: two concurrent submission claims — exactly one wins", async () => {
  const su = await superuser();
  await resetCore(su);
  const owner = await makeUser(su);
  const { poId, bookingId } = await seedCompletedOrder(su, owner);
  const c = await authed(owner);

  const refundId = (await c.queryObject<{ id: string }>({
    text: `select (request_refund($1, 30000, 'CUSTOMER_CANCELLATION', 'GUEST_BOOKING', $2, false, null, 100)).id as id`,
    args: [poId, bookingId],
  })).rows[0].id;

  // Pending refund never reads as PROCESSED.
  const pending = await c.queryObject<{ status: string }>({
    text: `select status from get_refund($1)`,
    args: [refundId],
  });
  assertEquals(pending.rows[0].status, "REQUESTED");

  const a = await authed(owner);
  const b = await authed(owner);
  const claims = await Promise.all([
    a.queryObject<{ id: string | null }>({ text: `select id from claim_refund_for_submission($1)`, args: [refundId] }),
    b.queryObject<{ id: string | null }>({ text: `select id from claim_refund_for_submission($1)`, args: [refundId] }),
  ]);
  const won = claims.filter((r) => r.rows[0]?.id).length;
  assertEquals(won, 1, "exactly one caller may claim the refund for a Razorpay call");

  await closeAll(su, c, a, b);
});

Deno.test("refund webhook: replay and out-of-order deliveries are no-ops", async () => {
  const su = await superuser();
  await resetCore(su);
  const owner = await makeUser(su);
  const { poId, bookingId } = await seedCompletedOrder(su, owner);
  const c = await authed(owner);

  const refundId = (await c.queryObject<{ id: string }>({
    text: `select (request_refund($1, 30000, 'CUSTOMER_CANCELLATION', 'GUEST_BOOKING', $2, false, null, 100)).id as id`,
    args: [poId, bookingId],
  })).rows[0].id;
  await c.queryArray({ text: `select claim_refund_for_submission($1)`, args: [refundId] });

  const rzpRefundId = "rfnd_test_1";
  const wh = (status: string) =>
    c.queryArray({
      text: `select apply_refund_webhook($1, $2, $3, 30000)`,
      args: [rzpRefundId, "pay_x", status],
    });

  await wh("processed");
  await wh("processed"); // duplicate
  await wh("created"); // stale, out of order
  await wh("failed"); // must not un-process

  const final = await c.queryObject<{ status: string }>({ text: `select status from get_refund($1)`, args: [refundId] });
  assertEquals(final.rows[0].status, "PROCESSED");

  const po = await c.queryObject<{ status: string }>({
    text: `select status from payment_orders where id = $1`,
    args: [poId],
  });
  assertEquals(po.rows[0].status, "REFUNDED");

  const processedRows = await su.queryObject<{ n: bigint }>({
    text: `select count(*)::bigint n from refunds where payment_order_id = $1 and status = 'PROCESSED'`,
    args: [poId],
  });
  assertEquals(Number(processedRows.rows[0].n), 1);

  await closeAll(su, c);
});
