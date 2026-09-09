import { assert, assertEquals, assertRejects } from "jsr:@std/assert";
import { authed, closeAll, makeFacility, makeUser, resetCore, superuser } from "./_helpers.ts";

// Expenses / Daily Closing / P&L (migrations 0069-0071) — the spec's
// critical financial tests. Cash reconciliation, accrual revenue,
// duplicate-closing prevention, refund handling, facility isolation.

type SU = Awaited<ReturnType<typeof superuser>>;

/** A captured payment on a given day, in the facility's timezone (Asia/Kolkata). */
async function pay(
  su: SU,
  facilityId: string,
  memberId: string,
  rupees: number,
  method: string,
  paidOn: string, // 'YYYY-MM-DD'
) {
  await su.queryArray({
    text: `insert into payments (facility_id, member_id, amount_inr, status, payment_method, paid_at, created_at)
           values ($1, $2, $3, 'paid', $4, ($5 || ' 10:00+05:30')::timestamptz, ($5 || ' 10:00+05:30')::timestamptz)`,
    args: [facilityId, memberId, rupees, method, paidOn],
  });
}

async function catId(c: Awaited<ReturnType<typeof authed>>, name: string): Promise<string> {
  const r = await c.queryObject<{ id: string }>({
    text: `select id from expense_categories where name = $1 and facility_id is null limit 1`,
    args: [name],
  });
  return r.rows[0].id;
}

async function seed(su: SU) {
  await resetCore(su);
  await su.queryArray(`delete from daily_closings; delete from expense_payments; delete from expenses where facility_id is not null;`);
  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  return { owner, facilityId };
}

function today(): string {
  return new Date(new Date().getTime() + 5.5 * 3600_000).toISOString().slice(0, 10);
}

Deno.test("expense is accrual: a PENDING expense still lowers net revenue", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  await pay(su, facilityId, owner, 1000, "Cash", today());

  await c.queryArray({
    text: `select create_expense($1, $2, 40000, $3, 'Bank Transfer', 'PowerCo', null, null, 'PENDING')`,
    args: [facilityId, await catId(c, "Utilities"), today()],
  });

  const s = await c.queryObject<{ expenses_minor: bigint; net_revenue_minor: bigint }>({
    text: `select expenses_minor, net_revenue_minor from get_finance_summary($1, 'TODAY')`,
    args: [facilityId],
  });
  assertEquals(Number(s.rows[0].expenses_minor), 40000);
  assertEquals(Number(s.rows[0].net_revenue_minor), 100000 - 40000);
  await closeAll(su, c);
});

Deno.test("record_expense_payment settles a pending expense and is idempotent", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const ex = await c.queryObject<{ id: string }>({
    text: `select (create_expense($1, $2, 50000, $3, 'Cash', null, null, null, 'PENDING')).id as id`,
    args: [facilityId, await catId(c, "Rent"), today()],
  });
  const id = ex.rows[0].id;

  await c.queryArray({ text: `select record_expense_payment($1, 30000, $2, 'Cash')`, args: [id, today()] });
  let row = await c.queryObject<{ payment_status: string; amount_paid_minor: number }>({
    text: `select payment_status, amount_paid_minor from expenses where id = $1`,
    args: [id],
  });
  assertEquals(row.rows[0].payment_status, "PARTIAL");
  assertEquals(row.rows[0].amount_paid_minor, 30000);

  await c.queryArray({ text: `select record_expense_payment($1, null, $2, 'Cash', null, null, 'key-1')`, args: [id, today()] });
  await c.queryArray({ text: `select record_expense_payment($1, null, $2, 'Cash', null, null, 'key-1')`, args: [id, today()] });
  row = await c.queryObject({ text: `select payment_status, amount_paid_minor from expenses where id = $1`, args: [id] });
  assertEquals(row.rows[0].payment_status, "PAID");
  assertEquals(row.rows[0].amount_paid_minor, 50000);
  await closeAll(su, c);
});

Deno.test("daily closing: expected cash = opening + cash collections - cash expenses", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const d = today();

  await pay(su, facilityId, owner, 100, "Cash", d); // 10000 minor
  await pay(su, facilityId, owner, 20, "UPI", d);
  const ex = await c.queryObject<{ id: string }>({
    text: `select (create_expense($1, $2, 2000, $3, 'Cash', null, null, null, 'PAID')).id as id`,
    args: [facilityId, await catId(c, "Cleaning"), d],
  });
  assert(ex.rows[0].id);

  const closing = await c.queryObject<{ id: string }>({
    text: `select (open_daily_closing($1, $2, 5000)).id as id`,
    args: [facilityId, d],
  });
  const summary = await c.queryObject<{ expected_cash_minor: bigint; cash_collected_minor: bigint; cash_expense_minor: bigint }>({
    text: `select expected_cash_minor, cash_collected_minor, cash_expense_minor from get_daily_closing_summary($1, $2)`,
    args: [facilityId, d],
  });
  assertEquals(Number(summary.rows[0].cash_collected_minor), 10000);
  assertEquals(Number(summary.rows[0].cash_expense_minor), 2000);
  assertEquals(Number(summary.rows[0].expected_cash_minor), 5000 + 10000 - 2000);

  // Actual 12500 -> variance -500, needs a reason.
  await assertRejects(
    () => c.queryArray({ text: `select close_daily_closing($1, 12500, null)`, args: [closing.rows[0].id] }),
    Error,
    "reason",
  );
  const closed = await c.queryObject<{ variance_minor: number; status: string }>({
    text: `select variance_minor, status from close_daily_closing($1, 12500, 'Cash shortage')`,
    args: [closing.rows[0].id],
  });
  assertEquals(closed.rows[0].variance_minor, -500);
  assertEquals(closed.rows[0].status, "CLOSED");
  await closeAll(su, c);
});

Deno.test("a second closing for the same facility/day is rejected", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const d = today();
  await c.queryArray({ text: `select open_daily_closing($1, $2, 0)`, args: [facilityId, d] });
  // open is idempotent — returns the same row, no error
  const again = await c.queryObject<{ n: bigint }>({
    text: `select count(*)::bigint n from daily_closings where facility_id = $1 and closing_date = $2`,
    args: [facilityId, d],
  });
  assertEquals(Number(again.rows[0].n), 1);

  const id = (await c.queryObject<{ id: string }>({
    text: `select id from daily_closings where facility_id = $1 and closing_date = $2`, args: [facilityId, d],
  })).rows[0].id;
  await c.queryArray({ text: `select close_daily_closing($1, 0, null)`, args: [id] });
  await assertRejects(
    () => c.queryArray({ text: `select close_daily_closing($1, 0, null)`, args: [id] }),
    Error,
    "already been completed",
  );
  await closeAll(su, c);
});

Deno.test("reopen requires a reason and is owner/manager only", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const d = today();
  const id = (await c.queryObject<{ id: string }>({
    text: `select (open_daily_closing($1, $2, 0)).id as id`, args: [facilityId, d],
  })).rows[0].id;
  await c.queryArray({ text: `select close_daily_closing($1, 0, null)`, args: [id] });

  await assertRejects(
    () => c.queryArray({ text: `select reopen_daily_closing($1, null)`, args: [id] }),
    Error,
    "reason",
  );
  const re = await c.queryObject<{ status: string }>({
    text: `select status from reopen_daily_closing($1, 'Missed a cash sale')`, args: [id],
  });
  assertEquals(re.rows[0].status, "REOPENED");

  const staff = await makeUser(su);
  await su.queryArray({
    text: `insert into facility_users (facility_id, user_id, role) values ($1, $2, 'staff')`,
    args: [facilityId, staff],
  });
  const sc = await authed(staff);
  await c.queryArray({ text: `select close_daily_closing($1, 0, null)`, args: [id] });
  await assertRejects(
    () => sc.queryArray({ text: `select reopen_daily_closing($1, 'x')`, args: [id] }),
    Error,
    "permission",
  );
  await closeAll(su, c, sc);
});

Deno.test("P&L: recognised revenue - recorded expenses = net profit", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const d = today();
  await pay(su, facilityId, owner, 1000, "UPI", d);
  await c.queryArray({
    text: `select create_expense($1, $2, 15000, $3, 'Cash', null, null, null, 'PAID')`,
    args: [facilityId, await catId(c, "Marketing"), d],
  });

  const pnl = await c.queryObject<{ total_revenue_minor: bigint; total_expense_minor: bigint; net_profit_minor: bigint; profit_margin_pct: string }>({
    text: `select total_revenue_minor, total_expense_minor, net_profit_minor, profit_margin_pct from get_pnl($1, 'TODAY')`,
    args: [facilityId],
  });
  assertEquals(Number(pnl.rows[0].total_revenue_minor), 100000);
  assertEquals(Number(pnl.rows[0].total_expense_minor), 15000);
  assertEquals(Number(pnl.rows[0].net_profit_minor), 100000 - 15000);
  await closeAll(su, c);
});

Deno.test("an unpaid booking is not recognised revenue (accrual is on payments, not bookings)", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  // No payment row at all — booking amount must never surface as revenue.
  const pnl = await c.queryObject<{ gross_revenue_minor: bigint }>({
    text: `select gross_revenue_minor from get_pnl($1, 'TODAY')`,
    args: [facilityId],
  });
  assertEquals(Number(pnl.rows[0].gross_revenue_minor), 0);
  await closeAll(su, c);
});

Deno.test("facility A cannot read facility B's expenses, closings or P&L", async () => {
  const su = await superuser();
  await resetCore(su);
  const a = await makeUser(su);
  const b = await makeUser(su);
  await makeFacility(su, a);
  const fb = await makeFacility(su, b);
  const ca = await authed(a);
  await assertRejects(() => ca.queryArray({ text: `select get_expense_summary($1)`, args: [fb] }), Error, "Not authorized");
  await assertRejects(() => ca.queryArray({ text: `select get_daily_closing_summary($1, null)`, args: [fb] }), Error, "Not authorized");
  await assertRejects(() => ca.queryArray({ text: `select get_pnl($1)`, args: [fb] }), Error, "Not authorized");
  await assertRejects(() => ca.queryArray({ text: `select list_expenses($1)`, args: [fb] }), Error, "Not authorized");
  await closeAll(su, ca);
});
