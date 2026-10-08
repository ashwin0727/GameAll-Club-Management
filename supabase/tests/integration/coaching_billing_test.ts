import { assert, assertEquals, assertRejects } from "jsr:@std/assert";
import { authed, closeAll, makeFacility, makeUser, resetCore, superuser } from "./_helpers.ts";

// Coaching online billing (migration 0110): the fee-type snapshot, the cycle
// count, and the webhook-facing RPCs that turn Razorpay events into payments.
// The webhook RPCs are service-role only — here the `superuser` connection
// stands in for the service role, and an `authed` user proves they are not
// reachable from a client.

type SU = Awaited<ReturnType<typeof superuser>>;

async function seed(su: SU) {
  await resetCore(su);
  await su.queryArray(
    `delete from coaching_enrollment_billing;
     delete from coaching_events;
     delete from coaching_session_students;
     delete from coaching_sessions;
     delete from coaching_enrollments;
     delete from coaching_programs;
     delete from members;`,
  );
  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  return { owner, facilityId };
}

async function makeMember(su: SU, facilityId: string): Promise<string> {
  const id = crypto.randomUUID();
  await su.queryArray({
    text: `insert into members (id, facility_id, full_name, phone) values ($1, $2, 'Arun Sharma', $3)`,
    args: [id, facilityId, `9${Math.floor(Math.random() * 1e9).toString().padStart(9, "0")}`],
  });
  return id;
}

async function makeProgram(
  su: SU,
  facilityId: string,
  opts: { feeType?: "ONE_TIME" | "MONTHLY"; start?: string | null; end?: string | null; price?: number } = {},
): Promise<string> {
  const id = crypto.randomUUID();
  await su.queryArray({
    text: `insert into coaching_programs (id, facility_id, name, default_price_minor, start_date, end_date)
           values ($1, $2, $3, $4, $5, $6)`,
    args: [id, facilityId, `Program ${id.slice(0, 6)}`, opts.price ?? 100000, opts.start ?? null, opts.end ?? null],
  });
  if (opts.feeType === "MONTHLY") {
    await su.queryArray({ text: `update coaching_programs set fee_type = 'MONTHLY' where id = $1`, args: [id] });
  }
  return id;
}

async function enroll(
  owner: Awaited<ReturnType<typeof authed>>,
  facilityId: string,
  memberId: string,
  programId: string,
  start: string,
  priceMinor: number,
): Promise<string> {
  return (
    await owner.queryObject<{ id: string }>({
      text: `select (create_coaching_enrollment($1, $2, $3, null, $4::date, null, null, $5, null, null)).id as id`,
      args: [facilityId, memberId, programId, start, priceMinor],
    })
  ).rows[0].id;
}

async function cycles(su: SU, start: string, end: string | null): Promise<number> {
  return (
    await su.queryObject<{ c: number }>({
      text: `select coaching_billing_cycles($1::date, $2::date) as c`,
      args: [start, end],
    })
  ).rows[0].c;
}

Deno.test("coaching_billing_cycles — one charge on the start date plus one per full month", async () => {
  const su = await superuser();
  assertEquals(await cycles(su, "2026-01-15", "2026-03-14"), 2);
  assertEquals(await cycles(su, "2026-01-15", "2026-03-15"), 3);
  assertEquals(await cycles(su, "2026-01-31", "2026-02-28"), 1);
  assertEquals(await cycles(su, "2026-01-01", "2026-12-31"), 12);
  assertEquals(await cycles(su, "2026-05-10", "2026-05-10"), 1);
  assertEquals(await cycles(su, "2026-05-10", null), 1); // no end date → a single charge
  assertEquals(await cycles(su, "2026-05-10", "2026-05-01"), 1); // end before start → clamp
  await closeAll(su);
});

Deno.test("a MONTHLY program needs both dates; an enrollment snapshots fee type and cycles", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const o = await authed(owner);
  const member = await makeMember(su, facilityId);

  // No dates → cannot be made monthly.
  const undated = await makeProgram(su, facilityId);
  await assertRejects(
    () => o.queryArray({ text: `select set_coaching_program_fee_type($1, 'MONTHLY')`, args: [undated] }),
    Error,
    "start and end date",
  );

  const monthly = await makeProgram(su, facilityId, { start: "2026-01-01", end: "2026-03-31", price: 50000 });
  await o.queryArray({ text: `select set_coaching_program_fee_type($1, 'MONTHLY')`, args: [monthly] });
  const eId = await enroll(o, facilityId, member, monthly, "2026-01-01", 150000);
  const row = (
    await su.queryObject<{ fee_type: string; billing_cycles: number; price_minor: number }>({
      text: `select fee_type, billing_cycles, price_minor from coaching_enrollments where id = $1`,
      args: [eId],
    })
  ).rows[0];
  assertEquals(row.fee_type, "MONTHLY");
  assertEquals(row.billing_cycles, 3);
  assertEquals(row.price_minor, 150000);

  // A one-time program keeps the defaults.
  const member2 = await makeMember(su, facilityId);
  const oneTime = await makeProgram(su, facilityId, { start: "2026-01-01", end: "2026-03-31" });
  const e2 = await enroll(o, facilityId, member2, oneTime, "2026-01-01", 100000);
  const row2 = (
    await su.queryObject<{ fee_type: string; billing_cycles: number }>({
      text: `select fee_type, billing_cycles from coaching_enrollments where id = $1`,
      args: [e2],
    })
  ).rows[0];
  assertEquals(row2.fee_type, "ONE_TIME");
  assertEquals(row2.billing_cycles, 1);
  await closeAll(su, o);
});

Deno.test("billing context is permission-gated and reports what is outstanding", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const o = await authed(owner);
  const stranger = await authed(await makeUser(su));
  const member = await makeMember(su, facilityId);
  const program = await makeProgram(su, facilityId);
  const eId = await enroll(o, facilityId, member, program, "2026-01-01", 100000);

  const ctx = (
    await o.queryObject<{ ctx: { outstandingMinor: number; feeType: string; billing: unknown } }>({
      text: `select get_coaching_billing_context($1) as ctx`,
      args: [eId],
    })
  ).rows[0].ctx;
  assertEquals(ctx.outstandingMinor, 100000);
  assertEquals(ctx.feeType, "ONE_TIME");
  assertEquals(ctx.billing, null);

  await assertRejects(
    () => stranger.queryArray({ text: `select get_coaching_billing_context($1)`, args: [eId] }),
    Error,
    "permission",
  );
  await closeAll(su, o, stranger);
});

Deno.test("payment_link.paid records ONE payment (idempotent), settles the obligation and flips the link to PAID", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const o = await authed(owner);
  const member = await makeMember(su, facilityId);
  const program = await makeProgram(su, facilityId);
  const eId = await enroll(o, facilityId, member, program, "2026-01-01", 100000);

  await o.queryArray({
    text: `select record_coaching_enrollment_billing($1, 'PAYMENT_LINK', 100000, 1, 'plink_1', null, null, 'https://rzp.io/i/x')`,
    args: [eId],
  });

  const args = { text: `select record_coaching_gateway_payment(null, 'plink_1', 100000, 'pay_AAA', now()) as ok` };
  assertEquals((await su.queryObject<{ ok: boolean }>(args)).rows[0].ok, true);
  assertEquals((await su.queryObject<{ ok: boolean }>(args)).rows[0].ok, true); // redelivered webhook

  const paid = (
    await su.queryObject<{ n: number; total: number }>({
      text: `select count(*)::int as n, coalesce(sum(amount_inr), 0)::int as total
               from payments where coaching_enrollment_id = $1 and status = 'paid'`,
      args: [eId],
    })
  ).rows[0];
  assertEquals(paid.n, 1);
  assertEquals(paid.total, 1000); // ₹1,000 = 100000 paise

  const status = (
    await su.queryObject<{ status: string }>({
      text: `select status from coaching_enrollment_billing where enrollment_id = $1`,
      args: [eId],
    })
  ).rows[0].status;
  assertEquals(status, "PAID");

  // The obligation is now fully collected — Record Payment must refuse a second one.
  await assertRejects(
    () =>
      o.queryArray({
        text: `select record_obligation_payment('COACHING_ENROLLMENT', $1, 100, 'Cash')`,
        args: [eId],
      }),
    Error,
    "already been paid",
  );
  await closeAll(su, o);
});

Deno.test("subscription: each distinct charge is a payment, a redelivery is not, status only moves forward", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const o = await authed(owner);
  const member = await makeMember(su, facilityId);
  const program = await makeProgram(su, facilityId, { start: "2026-01-01", end: "2026-03-31", price: 50000 });
  await o.queryArray({ text: `select set_coaching_program_fee_type($1, 'MONTHLY')`, args: [program] });
  const eId = await enroll(o, facilityId, member, program, "2026-01-01", 150000);

  await o.queryArray({
    text: `select record_coaching_enrollment_billing($1, 'SUBSCRIPTION', 50000, 3, null, 'plan_1', 'sub_1', 'https://rzp.io/i/s')`,
    args: [eId],
  });

  const charge = (id: string) =>
    su.queryArray({ text: `select record_coaching_gateway_payment('sub_1', null, 50000, $1, now())`, args: [id] });
  await charge("pay_1");
  await charge("pay_1"); // redelivery
  await charge("pay_2");

  const n = (
    await su.queryObject<{ n: number }>({
      text: `select count(*)::int as n from payments where coaching_enrollment_id = $1`,
      args: [eId],
    })
  ).rows[0].n;
  assertEquals(n, 2);

  const apply = (status: string, count: number | null = null) =>
    su.queryObject<{ ok: boolean }>({
      text: `select apply_coaching_billing_webhook('sub_1', null, $1, $2) as ok`,
      args: [status, count],
    });
  const current = async () =>
    (
      await su.queryObject<{ status: string; charge_count: number }>({
        text: `select status, charge_count from coaching_enrollment_billing where enrollment_id = $1`,
        args: [eId],
      })
    ).rows[0];

  await apply("ACTIVE", 2);
  assertEquals((await current()).status, "ACTIVE");
  assertEquals((await current()).charge_count, 2);

  await apply("HALTED");
  assertEquals((await current()).status, "HALTED");
  await apply("ACTIVE"); // a later successful charge recovers a halted mandate
  assertEquals((await current()).status, "ACTIVE");

  await apply("CANCELLED");
  await apply("ACTIVE"); // a stale event must not resurrect a terminal state
  assertEquals((await current()).status, "CANCELLED");
  await closeAll(su, o);
});

Deno.test("an id that is not a coaching enrollment's returns false so the webhook falls back to memberships", async () => {
  const su = await superuser();
  await seed(su);
  const apply = await su.queryObject<{ ok: boolean }>({
    text: `select apply_coaching_billing_webhook('sub_unknown', null, 'ACTIVE') as ok`,
  });
  assertEquals(apply.rows[0].ok, false);
  const rec = await su.queryObject<{ ok: boolean }>({
    text: `select record_coaching_gateway_payment('sub_unknown', null, 100, 'pay_z', now()) as ok`,
  });
  assertEquals(rec.rows[0].ok, false);
  await closeAll(su);
});

Deno.test("the webhook RPCs are not callable by a signed-in client", async () => {
  const su = await superuser();
  const { owner } = await seed(su);
  const o = await authed(owner);
  await assertRejects(
    () => o.queryArray({ text: `select record_coaching_gateway_payment('sub_1', null, 100, 'pay_hack', now())` }),
    Error,
    "permission denied",
  );
  await assertRejects(
    () => o.queryArray({ text: `select apply_coaching_billing_webhook('sub_1', null, 'CANCELLED')` }),
    Error,
    "permission denied",
  );
  assert(true);
  await closeAll(su, o);
});
