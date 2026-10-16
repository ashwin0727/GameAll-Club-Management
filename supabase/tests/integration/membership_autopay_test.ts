import { assertEquals } from "jsr:@std/assert";
import { closeAll, makeFacility, makeUser, resetCore, superuser } from "./_helpers.ts";

// Migration 0119 — AutoPay runs in calendar months from the plan, settles the pending first payment, and
// keeps auto_renew in step with the subscription.

type SU = Awaited<ReturnType<typeof superuser>>;

const d = async (su: SU, sql: string, args: unknown[] = []) =>
  (await su.queryObject<{ v: string }>({ text: sql, args })).rows[0].v;

async function seed(su: SU, startDate: string, durationDays: number) {
  await resetCore(su);
  await su.queryArray(`delete from membership_subscriptions; delete from members;`);
  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  const memberId = crypto.randomUUID();
  await su.queryArray({
    text: `insert into members (id, facility_id, full_name, phone) values ($1, $2, 'Arun Sharma', '9876543210')`,
    args: [memberId, facilityId],
  });
  const membershipId = crypto.randomUUID();
  await su.queryArray({
    text: `insert into memberships (id, facility_id, member_id, status, start_date, end_date, name, duration_days,
                                   membership_fee_inr, registration_fee_inr, total_amount_inr, monthly_price_inr)
           values ($1, $2, $3, 'active', $4, $4, 'Monthly', $5, 2500, 200, 2700, 2500)`,
    args: [membershipId, facilityId, memberId, startDate, durationDays],
  });
  // The pending first payment created with the membership.
  await su.queryArray({
    text: `insert into payments (facility_id, member_id, membership_id, amount_inr, status)
           values ($1, $2, $3, 2700, 'created')`,
    args: [facilityId, memberId, membershipId],
  });
  await su.queryArray({
    text: `insert into membership_subscriptions (membership_id, facility_id, member_id, razorpay_plan_id,
                                                 razorpay_subscription_id, amount_inr, interval_months, one_time_inr)
           values ($1, $2, $3, 'plan_x', 'sub_x', 2500, $4, 200)`,
    args: [membershipId, facilityId, memberId, Math.max(Math.round(durationDays / 30), 1)],
  });
  return { facilityId, membershipId };
}

Deno.test("period maths: same day next month, 3-month and yearly plans, month-end clamp", async () => {
  const su = await superuser();
  assertEquals(await d(su, `select add_membership_period('2026-10-14', 30)::text as v`), "2026-11-14");
  assertEquals(await d(su, `select add_membership_period('2026-10-14', 90)::text as v`), "2027-01-14");
  assertEquals(await d(su, `select add_membership_period('2026-10-14', 365)::text as v`), "2027-10-14");
  assertEquals(await d(su, `select add_membership_period('2026-01-31', 30)::text as v`), "2026-02-28");
  assertEquals(await d(su, `select add_membership_period('2026-10-14', 10)::text as v`), "2026-10-24");
  await closeAll(su);
});

Deno.test("a membership created on the 14th is first due on the 14th of next month", async () => {
  const su = await superuser();
  const { membershipId } = await seed(su, "2026-10-14", 30);
  assertEquals(await d(su, `select end_date::text as v from memberships where id = $1`, [membershipId]), "2026-11-14");
  await closeAll(su);
});

Deno.test("AutoPay charges settle the first payment, then roll the due date: 14 Nov, 14 Dec, 14 Jan", async () => {
  const su = await superuser();
  const { membershipId } = await seed(su, "2026-10-14", 30);

  await su.queryArray(`select apply_subscription_webhook('sub_x', 'authenticated')`);
  assertEquals(await d(su, `select auto_renew::text as v from memberships where id = $1`, [membershipId]), "true");

  // First charge, paid on the 14th: settles the pending row (no duplicate) and next due is 14 Nov.
  await su.queryArray(`select record_subscription_charge('sub_x', 2700, 'pay_1', '2026-10-14T10:00:00+05:30')`);
  assertEquals(await d(su, `select count(*)::text as v from payments where membership_id = $1`, [membershipId]), "1");
  assertEquals(await d(su, `select status::text as v from payments where membership_id = $1`, [membershipId]), "paid");
  assertEquals(await d(su, `select end_date::text as v from memberships where id = $1`, [membershipId]), "2026-11-14");

  // Second and third charges: the 14th every month, whatever day the money lands.
  await su.queryArray(`select record_subscription_charge('sub_x', 2500, 'pay_2', '2026-11-14T10:00:00+05:30')`);
  assertEquals(await d(su, `select end_date::text as v from memberships where id = $1`, [membershipId]), "2026-12-14");
  await su.queryArray(`select record_subscription_charge('sub_x', 2500, 'pay_3', '2026-12-16T10:00:00+05:30')`);
  assertEquals(await d(su, `select end_date::text as v from memberships where id = $1`, [membershipId]), "2027-01-14");

  assertEquals(await d(su, `select charge_count::text as v from membership_subscriptions where razorpay_subscription_id = 'sub_x'`), "3");
  await closeAll(su);
});

Deno.test("a redelivered charge is not counted twice, and Razorpay's own date wins when it sends one", async () => {
  const su = await superuser();
  const { membershipId } = await seed(su, "2026-10-14", 30);
  await su.queryArray(`select apply_subscription_webhook('sub_x', 'active', 1, '2026-10-20', '2026-11-20')`);
  await su.queryArray(`select record_subscription_charge('sub_x', 2700, 'pay_1', '2026-10-20T10:00:00+05:30')`);
  await su.queryArray(`select record_subscription_charge('sub_x', 2700, 'pay_1', '2026-10-20T10:00:00+05:30')`);
  assertEquals(await d(su, `select count(*)::text as v from payments where membership_id = $1`, [membershipId]), "1");
  assertEquals(await d(su, `select end_date::text as v from memberships where id = $1`, [membershipId]), "2026-11-20");
  await closeAll(su);
});

Deno.test("auto_renew goes off when the subscription is cancelled", async () => {
  const su = await superuser();
  const { membershipId } = await seed(su, "2026-10-14", 30);
  await su.queryArray(`select apply_subscription_webhook('sub_x', 'active')`);
  assertEquals(await d(su, `select auto_renew::text as v from memberships where id = $1`, [membershipId]), "true");
  await su.queryArray(`select apply_subscription_webhook('sub_x', 'cancelled')`);
  assertEquals(await d(su, `select auto_renew::text as v from memberships where id = $1`, [membershipId]), "false");
  await closeAll(su);
});

Deno.test("a late 'authenticated' event cannot move a charging subscription back", async () => {
  const su = await superuser();
  await seed(su, "2026-10-14", 30);
  await su.queryArray(`select apply_subscription_webhook('sub_x', 'active', 1)`);
  await su.queryArray(`select apply_subscription_webhook('sub_x', 'authenticated')`); // arrives out of order
  assertEquals(await d(su, `select status::text as v from membership_subscriptions where razorpay_subscription_id = 'sub_x'`), "active");
  await closeAll(su);
});
