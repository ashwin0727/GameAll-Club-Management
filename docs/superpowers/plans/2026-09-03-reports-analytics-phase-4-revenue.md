# Reports & Analytics — Phase 4: Revenue Report — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use `- [ ]`.

> **Status: implemented (2026-09-04), pending user verification + commit.** Notes:
> - `<RevenueReport>` reuses `<RevenueTrendChart>` and `<Donut>` verbatim; `segmentsFrom` copied from `finance-dashboard.tsx`. `getRevenueTrend`/`Summary`/`Breakdown`/`PaymentMethodBreakdown` in `SupabaseReportsService` call the **Finance RPCs directly** with `dateRangeArgs(filter)` — no `FinanceDateRange` type coupling, and `THIS_QUARTER`/`THIS_YEAR` resolve fine at runtime via 0056.
> - `refunds` added to `KpiKey` + `KPI_DEFINITIONS`.
> - **`next build` not run** (standing rule). Verified: `tsc --noEmit` (whole project) + `next lint` + `vitest` (85 reports tests) + dev server compiles cleanly. Full suite **614/614** this run.

**Goal:** `/reports/revenue` — revenue trend, breakdown by source, payment-method split, and revenue by sport / by court (with drill-down). Numbers reconcile exactly with Finance.

**Architecture:** The trend, breakdown, method-split and headline totals are the **existing Finance RPCs** (`get_finance_summary`, `get_revenue_trend`, `get_revenue_breakdown`, `get_payment_method_breakdown`) — called straight from `SupabaseReportsService` via `this.supabase.rpc(...)` with `AnalyticsFilter`-derived args, so Reports revenue == Finance revenue by construction. Only two genuinely new cuts need a migration: `get_revenue_by_sport` / `get_revenue_by_court` (`0060`), court-attributable paid revenue. Reuses the existing `<RevenueTrendChart>` and `<Donut>` components.

**Tech Stack:** PostgreSQL (Supabase), Next.js 15 / React 19, TypeScript, Recharts, Vitest.

**Spec:** `docs/superpowers/specs/2026-09-03-reports-analytics-design.md` §6, §7, §8, §28, §34, §42, §43.

## Global Constraints

- Branch `feat/reports-analytics`. Phases 1–3 committed (`17bb3e1`, `5836b03`, `4e4ff7b`).
- **Reuse Finance RPCs unchanged** for trend / breakdown / method / totals — do not add sport/court params to them, do not touch their SQL. Data consistency §34: with no sport/court filter, every revenue figure on this page equals the same figure in Finance.
- **Sport / court filter scope:** the Finance RPCs are facility+date only. So the Revenue page behaves in two modes:
  - **No sport/court filter** → full report: trend + breakdown donut + method donut + by-sport table + by-court table.
  - **Sport or court filter set** → scoped report: by-sport + by-court tables only (both narrowed), plus a one-line note that trend/breakdown are facility-wide and a "Clear sport/court" link. Drilling "Revenue by Sport → Badminton" (spec §28) lands here with `?sport=<fsId>`.
- **Court-attributable revenue** (`0060`) = paid `payments` whose booking's court, or whose released-seat session's court, resolves to a sport. Membership payments (no booking/session) are **not** sport/court attributed — the UI shows `get_revenue_breakdown.membership_revenue_minor` as its own "Memberships" line, and by-sport + membership + any residual reconcile to `gross_revenue_minor`.
- Paid revenue base identical to Finance: `payments p where p.facility_id = … and p.status = 'paid' and range_ @> coalesce(p.paid_at, p.created_at)`; `amount_minor = p.amount_inr * 100`.
- Migration `0060_analytics_revenue.sql` — new file, immutable once shipped.
- `database.types.ts` — add entries for `get_revenue_by_sport` / `get_revenue_by_court` only (the Finance RPCs are already typed).
- No SQL harness — `0060` verified by the manual task (Task 5).
- Per phase: `npm run typecheck` (no *new* errors), `npx next lint --dir src`, `npx vitest run`. **No `next build` while `next dev` runs.**
- Commit only after verification + explicit user go-ahead.

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/0060_analytics_revenue.sql` | **Create.** `get_revenue_by_sport`, `get_revenue_by_court`. |
| `src/types/database.types.ts` | **Modify.** Two `Functions` entries. |
| `src/features/reports/types.ts` | **Modify.** `RevenueSummary`, `RevenueBreakdown`, `PaymentMethodSlice`, `RevenueBySportRow`, `RevenueByCourtRow`. |
| `src/services/reports/reports.service.ts` | **Modify.** Six methods. |
| `src/services/reports/supabase-reports.service.ts` | **Modify.** Four Finance-RPC wrappers + two `0060` calls. |
| `src/services/reports/supabase-reports.service.test.ts` | **Modify.** Contract tests. |
| `src/test/fakes/fake-reports-service.ts` | **Modify.** Six fields + methods. |
| `src/features/reports/components/revenue-report.tsx` | **Rewrite.** The assembled report. |
| `src/features/reports/components/revenue-report.test.tsx` | **Create.** |

No new chart components — `@/features/finance/components/revenue-trend-chart` (`RevenueTrendChart`) and `@/components/shared/donut` (`Donut`, `DonutSegment`) are reused.

---

## Task 1: Migration `0060` — revenue by sport / court

**Files:** Create `supabase/migrations/0060_analytics_revenue.sql`

**Interfaces — Produces** (args `p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_id, p_court_id`; `has_facility_role` → `42501`; `resolve_finance_date_range`; `grant execute … to authenticated`):
- `get_revenue_by_sport(…)` → `table (facility_sport_id uuid, sport_name text, revenue_minor bigint)` — one row per active facility sport in scope (0-revenue sports included), highest first.
- `get_revenue_by_court(…)` → `table (court_id uuid, court_name text, facility_sport_id uuid, sport_name text, revenue_minor bigint)` — one row per non-archived court in scope, highest first.

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 4: Revenue by sport / court.
--
-- The only revenue cuts Finance does not already expose. Court-attributable
-- paid revenue only: a payment is attributed to a sport/court through its
-- booking's court, or through its released-seat session's court. Membership
-- payments (no booking, no session) are NOT attributed here — the UI shows
-- membership revenue as its own line from get_revenue_breakdown.
--
-- Paid base identical to get_finance_summary:
--   payments.status = 'paid' AND range @> coalesce(paid_at, created_at)
-- so with no sport/court filter these totals reconcile to gross revenue
-- (minus the unattributed membership + other slice).
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_revenue_by_sport(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  facility_sport_id uuid,
  sport_name text,
  revenue_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with rev as (
    select
      coalesce(bc.facility_sport_id, ms.facility_sport_id) as fs_id,
      (p.amount_inr * 100)::bigint as amount_minor
    from payments p
    left join bookings b on b.id = p.booking_id
    left join courts bc on bc.id = b.court_id
    left join membership_session_bookings msb on msb.id = p.membership_session_booking_id
    left join membership_sessions ms on ms.id = msb.session_id
    where p.facility_id = p_facility_id
      and p.status = 'paid'
      and range_ @> coalesce(p.paid_at, p.created_at)
      and coalesce(bc.facility_sport_id, ms.facility_sport_id) is not null
      and (p_court_id is null or coalesce(b.court_id, ms.court_id) = p_court_id)
  )
  select
    fs.id,
    coalesce(fs.custom_sport_name, sp.name),
    coalesce(sum(rev.amount_minor), 0)::bigint
  from facility_sports fs
  join sports sp on sp.id = fs.sport_id
  left join rev on rev.fs_id = fs.id
  where fs.facility_id = p_facility_id
    and fs.is_active
    and (p_facility_sport_id is null or fs.id = p_facility_sport_id)
  group by fs.id, coalesce(fs.custom_sport_name, sp.name)
  order by coalesce(sum(rev.amount_minor), 0) desc, 2;
end;
$$;

grant execute on function get_revenue_by_sport(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_revenue_by_court(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  court_id uuid,
  court_name text,
  facility_sport_id uuid,
  sport_name text,
  revenue_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with rev as (
    select
      coalesce(b.court_id, ms.court_id) as court_id,
      (p.amount_inr * 100)::bigint as amount_minor
    from payments p
    left join bookings b on b.id = p.booking_id
    left join membership_session_bookings msb on msb.id = p.membership_session_booking_id
    left join membership_sessions ms on ms.id = msb.session_id
    where p.facility_id = p_facility_id
      and p.status = 'paid'
      and range_ @> coalesce(p.paid_at, p.created_at)
      and coalesce(b.court_id, ms.court_id) is not null
  )
  select
    c.id,
    c.name,
    c.facility_sport_id,
    coalesce(fs.custom_sport_name, sp.name),
    coalesce(sum(rev.amount_minor), 0)::bigint
  from courts c
  join facility_sports fs on fs.id = c.facility_sport_id
  join sports sp on sp.id = fs.sport_id
  left join rev on rev.court_id = c.id
  where c.facility_id = p_facility_id
    and not c.archived
    and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
    and (p_court_id is null or c.id = p_court_id)
  group by c.id, c.name, c.facility_sport_id, coalesce(fs.custom_sport_name, sp.name)
  order by coalesce(sum(rev.amount_minor), 0) desc, c.name;
end;
$$;

grant execute on function get_revenue_by_court(uuid, text, date, date, uuid, uuid) to authenticated;
```

- [ ] **Step 2: Parse-sanity** — both function names present.

---

## Task 2: types + `database.types.ts`

- [ ] **Step 1: `types.ts`** — append:

```ts
// ─── Phase 4: Revenue ────────────────────────────────────────────────────

export interface RevenueSummary {
  grossMinor: number;
  refundsMinor: number;
  expensesMinor: number;
  netMinor: number;
  outstandingMinor: number;
}

export interface RevenueBreakdown {
  membershipMinor: number;
  memberBookingMinor: number;
  guestBookingMinor: number;
  refundsMinor: number;
  netMinor: number;
}

export interface PaymentMethodSlice {
  method: string;
  amountMinor: number;
  count: number;
}

export interface RevenueBySportRow {
  facilitySportId: string;
  sportName: string;
  revenueMinor: number;
}

export interface RevenueByCourtRow {
  courtId: string;
  courtName: string;
  facilitySportId: string;
  sportName: string;
  revenueMinor: number;
}
```

- [ ] **Step 2: `database.types.ts`** — after `get_demand_heatmap`, add:

```ts
      get_revenue_by_sport: {
        Args: { p_facility_id: string; p_preset?: string; p_start_date?: string | null; p_end_date?: string | null; p_facility_sport_id?: string | null; p_court_id?: string | null };
        Returns: { facility_sport_id: string; sport_name: string; revenue_minor: number }[];
      };
      get_revenue_by_court: {
        Args: { p_facility_id: string; p_preset?: string; p_start_date?: string | null; p_end_date?: string | null; p_facility_sport_id?: string | null; p_court_id?: string | null };
        Returns: { court_id: string; court_name: string; facility_sport_id: string; sport_name: string; revenue_minor: number }[];
      };
```

- [ ] **Step 3:** `npm run typecheck`.

---

## Task 3: service + fake + tests

**Interfaces — Produces** on `ReportsService`:
```ts
getRevenueSummary(filter: AnalyticsFilter): Promise<RevenueSummary>;
getRevenueTrend(filter: AnalyticsFilter, granularity: AnalyticsGranularity): Promise<RevenueTrendPoint[]>;  // from @/features/finance/types
getRevenueBreakdown(filter: AnalyticsFilter): Promise<RevenueBreakdown>;
getPaymentMethodBreakdown(filter: AnalyticsFilter): Promise<PaymentMethodSlice[]>;
getRevenueBySport(filter: AnalyticsFilter): Promise<RevenueBySportRow[]>;
getRevenueByCourt(filter: AnalyticsFilter): Promise<RevenueByCourtRow[]>;
```

Note: `getRevenueTrend` **overloads/shadows** the Phase 2 `getBookingTrend` name? No — Phase 2's method is `getBookingTrend`. This is a new `getRevenueTrend`. Import `RevenueTrendPoint` from `@/features/finance/types` (the `<RevenueTrendChart>` this feeds is the finance one).

- [ ] **Step 1: `reports.service.ts`** — add the six signatures with a doc line each; add the `RevenueTrendPoint` import from `@/features/finance/types`, the new types from `../types`... wait, service imports from `@/features/reports/types`. Add `RevenueSummary, RevenueBreakdown, PaymentMethodSlice, RevenueBySportRow, RevenueByCourtRow` there and `import type { RevenueTrendPoint } from "@/features/finance/types"`.

- [ ] **Step 2: `supabase-reports.service.ts`** — implementations:

```ts
async getRevenueSummary(filter: AnalyticsFilter): Promise<RevenueSummary> {
  const { data, error } = await this.supabase.rpc("get_finance_summary", {
    p_facility_id: filter.facilityId,
    ...dateRangeArgs(filter),
  });
  if (error || !data?.[0]) throw this.mapError(error);
  const r = data[0];
  return {
    grossMinor: r.gross_revenue_minor,
    refundsMinor: r.refunds_minor,
    expensesMinor: r.expenses_minor ?? 0,
    netMinor: r.net_revenue_minor,
    outstandingMinor: r.outstanding_minor ?? 0,
  };
}

async getRevenueTrend(filter: AnalyticsFilter, granularity: AnalyticsGranularity): Promise<RevenueTrendPoint[]> {
  const { data, error } = await this.supabase.rpc("get_revenue_trend", {
    p_facility_id: filter.facilityId,
    ...dateRangeArgs(filter),
    p_granularity: granularity,
  });
  if (error) throw this.mapError(error);
  return (data ?? []).map((r) => ({
    date: r.bucket_date,
    grossMinor: r.gross_minor,
    refundMinor: r.refund_minor,
    netMinor: r.net_minor,
  }));
}

async getRevenueBreakdown(filter: AnalyticsFilter): Promise<RevenueBreakdown> {
  const { data, error } = await this.supabase.rpc("get_revenue_breakdown", {
    p_facility_id: filter.facilityId,
    ...dateRangeArgs(filter),
  });
  if (error || !data?.[0]) throw this.mapError(error);
  const r = data[0];
  return {
    membershipMinor: r.membership_revenue_minor,
    memberBookingMinor: r.member_booking_revenue_minor,
    guestBookingMinor: r.guest_booking_revenue_minor,
    refundsMinor: r.refunds_minor,
    netMinor: r.net_revenue_minor,
  };
}

async getPaymentMethodBreakdown(filter: AnalyticsFilter): Promise<PaymentMethodSlice[]> {
  const { data, error } = await this.supabase.rpc("get_payment_method_breakdown", {
    p_facility_id: filter.facilityId,
    ...dateRangeArgs(filter),
  });
  if (error) throw this.mapError(error);
  return (data ?? []).map((r) => ({ method: r.payment_method, amountMinor: r.amount_minor, count: r.payment_count }));
}

async getRevenueBySport(filter: AnalyticsFilter): Promise<RevenueBySportRow[]> {
  const { data, error } = await this.supabase.rpc("get_revenue_by_sport", this.baseArgs(filter));
  if (error) throw this.mapError(error);
  return (data ?? []).map((r) => ({ facilitySportId: r.facility_sport_id, sportName: r.sport_name, revenueMinor: r.revenue_minor }));
}

async getRevenueByCourt(filter: AnalyticsFilter): Promise<RevenueByCourtRow[]> {
  const { data, error } = await this.supabase.rpc("get_revenue_by_court", this.baseArgs(filter));
  if (error) throw this.mapError(error);
  return (data ?? []).map((r) => ({ courtId: r.court_id, courtName: r.court_name, facilitySportId: r.facility_sport_id, sportName: r.sport_name, revenueMinor: r.revenue_minor }));
}
```

- [ ] **Step 3: `supabase-reports.service.test.ts`** — add a `describe("SupabaseReportsService revenue")`:
  - `getRevenueSummary` calls `get_finance_summary` with `{ p_facility_id, p_preset, p_start_date, p_end_date }` (**no** sport/court args), maps `gross_revenue_minor`→`grossMinor` etc., `expenses_minor`/`outstanding_minor` default 0 when absent.
  - `getRevenueTrend` passes `p_granularity`, maps to `{ date, grossMinor, refundMinor, netMinor }`.
  - `getRevenueBreakdown` maps the five fields.
  - `getPaymentMethodBreakdown` maps `payment_method`→`method`.
  - `getRevenueBySport` calls `get_revenue_by_sport` with full `baseArgs` (incl. sport/court), maps rows.
  - `getRevenueByCourt` maps rows.
  - one `REPORTS_ACCESS_DENIED` case via `getRevenueSummary`.

- [ ] **Step 4: `fake-reports-service.ts`** — add fields: `revenueSummary: RevenueSummary = { grossMinor: 0, refundsMinor: 0, expensesMinor: 0, netMinor: 0, outstandingMinor: 0 }`, `revenueTrend: RevenueTrendPoint[] = []`, `revenueBreakdown: RevenueBreakdown = { membershipMinor: 0, memberBookingMinor: 0, guestBookingMinor: 0, refundsMinor: 0, netMinor: 0 }`, `paymentMethods: PaymentMethodSlice[] = []`, `revenueBySport: RevenueBySportRow[] = []`, `revenueByCourt: RevenueByCourtRow[] = []`; six param-less methods.

- [ ] **Step 5:** `npx vitest run src/services/reports` + `npm run typecheck`.

---

## Task 4: `<RevenueReport>`

**Files:** rewrite `revenue-report.tsx`; create `revenue-report.test.tsx`

**Behaviour:**
- `useAnalyticsFilter` → `scoped = Boolean(filter.facilitySportId || filter.courtId)`.
- `load()`:
  - always: `getRevenueBySport(filter)`, `getRevenueByCourt(filter)`
  - when **not** scoped, also: `getRevenueSummary`, `getRevenueTrend(filter, pickGranularityForDays(filterSpanDays(filter)))`, `getRevenueBreakdown`, `getPaymentMethodBreakdown`
- `status`: `loading` → `error` (`onRetry`) → `empty` when (`scoped` ? by-sport all zero : `summary.grossMinor === 0`) → `ready`.
- **Not scoped** layout:
  - KPI strip: Total Revenue (`grossMinor`), Net Revenue (`netMinor`), Refunds (`refundsMinor`), Expenses (`expensesMinor`) — keys `totalRevenue`/`netRevenue`/… (add `refunds` to `KpiKey` + definition, or reuse — actually add `refunds` key + definition "Money returned to customers in the range (Finance).").
  - `<Card>` "Revenue Trend" → `<RevenueTrendChart points={trend} />` + `<DataTable caption="Revenue over time" columns=[Date, Gross, Refunds, Net]>` (format each with `formatCurrency(v, "INR")` — pass strings into the table).
  - `<div className="grid gap-4 lg:grid-cols-2">`:
    - `<Card>` "Revenue Breakdown" → `<Donut segments={…} centreValue={formatCurrency(total)} centreLabel="Total" />` from `[{label:"Guest Bookings", value: guestBookingMinor, color:"#FFB020"}, {label:"Memberships", value: membershipMinor, color:"#8B5CF6"}, {label:"Member Bookings", value: memberBookingMinor, color:"#00D084"}]` (drop zero slices — copy `segmentsFrom` from `finance-dashboard.tsx`) + `<DataTable>`.
    - `<Card>` "Payment Methods" → `<Donut>` of `paymentMethods` + `<DataTable>`.
- **Both modes** — `<Card>` "Revenue by Sport" (`<ReportBarList>` colour `#00D084`, `caption = formatCurrency(revenueMinor)`) + `<DataTable caption="Revenue by sport" columns=[Sport, Revenue]>` `href` → `/reports/revenue?…&sport=<fsId>`. Plus, when not scoped, a "Memberships" row appended showing `breakdown.membershipMinor` (not sport-attributed) so the table reconciles.
- **Both modes** — `<Card>` "Revenue by Court" similarly, `href` → `…&court=<id>`.
- When `scoped`: a `<p className="text-xs text-muted-foreground">` — "Trend, breakdown and payment methods show the whole facility." + a `<Link>` to `/reports/revenue?facility=<id>&preset=<preset>` labelled "Clear sport & court".
- `onExportCsv`: `toCsv` of by-sport + by-court (+ trend when present), filename `revenue-<facilityId>-<preset>.csv`.

- [ ] **Step 1: add `refunds` to `KpiKey` + `KPI_DEFINITIONS`** in `definitions.ts`:
```ts
  refunds: "Money returned to customers in the range (Finance). Reduces net revenue.",
```
(and the union). Update `definitions.test.ts` count threshold if it asserts an exact length — it asserts `>= 20`, fine.

- [ ] **Step 2: `revenue-report.test.tsx`**

```tsx
import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { RevenueReport } from "./revenue-report";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";
import { installFakeReportsService } from "@/test/fakes/fake-reports-service";

const SLOW = { timeout: 4000 } as const;

function setup() {
  installFakeReportsFilterDeps();
  return installFakeReportsService();
}

describe("RevenueReport", () => {
  it("shows the empty state when there is no revenue", async () => {
    setup();
    render(<RevenueReport />);
    expect(await screen.findByText("No revenue data for this period.", {}, SLOW)).toBeInTheDocument();
  });

  it("renders totals, the trend table and the by-sport table (unscoped)", async () => {
    const reports = setup();
    reports.revenueSummary = { grossMinor: 1_10_000_00, refundsMinor: 0, expensesMinor: 35_000_00, netMinor: 75_000_00, outstandingMinor: 0 };
    reports.revenueTrend = [{ date: "2026-09-01", grossMinor: 800000, refundMinor: 0, netMinor: 800000 }];
    reports.revenueBreakdown = { membershipMinor: 60_000_00, memberBookingMinor: 5_000_00, guestBookingMinor: 45_000_00, refundsMinor: 0, netMinor: 1_10_000_00 };
    reports.paymentMethods = [{ method: "UPI", amountMinor: 50_000_00, count: 20 }];
    reports.revenueBySport = [{ facilitySportId: "fs1", sportName: "Badminton", revenueMinor: 45_000_00 }];
    reports.revenueByCourt = [{ courtId: "c1", courtName: "Court 1", facilitySportId: "fs1", sportName: "Badminton", revenueMinor: 30_000_00 }];

    render(<RevenueReport />);

    expect(await screen.findByText("Total Revenue", {}, SLOW)).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /revenue over time/i })).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /revenue by sport/i })).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /revenue by court/i })).toBeInTheDocument();
  });
});
```

- [ ] **Step 3: run — fails.**

- [ ] **Step 4: write `revenue-report.tsx`** per Behaviour. `segmentsFrom` helper copied from `finance-dashboard.tsx` (drops zero slices, assigns colour + `caption`). `formatCurrency` from `@/features/pricing/money`.

- [ ] **Step 5: run — passes.**

- [ ] **Step 6:** `npx vitest run src/features/reports src/services/reports` + `npm run typecheck` + `npx next lint --dir src` + full `npx vitest run` (only known flakes may fail).

---

## Task 5: manual DB verification (reviewer, against linked Supabase)

Apply `0056`–`0060`. Using the §50 fixture (Champz Turf, 03 Sep 2026: guest ₹400 paid + ₹600 paid + ₹800 pending; membership ₹5,000 paid; maintenance expense ₹1,000):

```sql
-- reconciliation: by-sport + membership + residual == gross
select sum(revenue_minor) from get_revenue_by_sport('<champz>', 'CUSTOM', '2026-09-03', '2026-09-03', null, null);
-- = 100000  (₹400 + ₹600 paid guest bookings, in paise) — the ₹800 pending is NOT here
select membership_revenue_minor from get_revenue_breakdown('<champz>', 'CUSTOM', '2026-09-03', '2026-09-03');
-- = 500000  (₹5,000)
select gross_revenue_minor from get_finance_summary('<champz>', 'CUSTOM', '2026-09-03', '2026-09-03');
-- = 600000  — matches 100000 (by-sport) + 500000 (membership) + 0 residual

select * from get_revenue_by_court('<champz>', 'CUSTOM', '2026-09-03', '2026-09-03', null, null);
-- the booked court carries 100000; other courts 0

-- facility isolation
select * from get_revenue_by_sport('<other>', 'THIS_MONTH', null, null, null, null);  -- raises "Not authorized"
```

Confirm §34: `get_finance_summary` and the Reports revenue page show the **same** Total Revenue for the same range with no sport/court filter.

---

## Self-Review

**Spec coverage:** §6 trend (Finance RPC, granularity auto) → `getRevenueTrend` + `<RevenueTrendChart>`. §7 breakdown by source (Finance classification) → `getRevenueBreakdown` + `<Donut>` + table. §8 payment methods (Finance RPC, pending not counted — the RPC already only sums paid) → `getPaymentMethodBreakdown` + `<Donut>` + table. §28 drill-down → `DataTable href` on by-sport + by-court, scoped mode. §34 data consistency → Reports calls the Finance RPCs verbatim; manual task confirms equality. §42 tables under charts → every card. §43 empty state → `<ReportShell>`.

**Placeholder scan:** Task 4 Step 4 "write per Behaviour" — every widget is either a reused component (`RevenueTrendChart`, `Donut`, `ReportBarList`, `DataTable`, `KpiStrip`, `ReportShell`) or the `load`/status pattern identical to `booking-report.tsx` / `court-utilization-report.tsx`. `segmentsFrom` is named with its source file. Acceptable.

**Type consistency:** `revenue_minor` (SQL) ↔ `revenueMinor` (TS) across `0060`, service, fake, component. `RevenueTrendPoint` imported from `@/features/finance/types` in both the service and the component (same shape the reused `<RevenueTrendChart>` expects). `PaymentMethodSlice` here is `{ method, amountMinor, count }` — deliberately *not* the finance one (`{ paymentMethod, amountMinor, paymentCount }`); the mapping in the service bridges the RPC's snake_case to this shape.
