# Reports & Analytics — Phase 5: Overview — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use `- [ ]`.

> **Status: implemented (2026-09-04), pending user verification + commit.** Notes:
> - `changePct` + the delta component were lifted out of `booking-report.tsx` into `src/features/reports/components/kpi-delta.tsx` (`KpiDelta`), now imported by both `booking-report.tsx` and `reports-overview.tsx`.
> - `get_analytics_overview` composes `get_finance_summary` + `get_revenue_breakdown` + `get_booking_analytics` + `get_overall_utilization` via `select … into … from <rpc>(…)`. Nested `has_facility_role` checks re-run — harmless.
> - **`next build` not run** (standing rule). `tsc` + `next lint` + `vitest` (89 reports tests) + dev server compiles clean. Full suite **618/618**.

**Goal:** `/reports` (the Overview) — a one-screen business snapshot: headline KPI cards with vs-previous-period deltas and drill-down, a revenue-trend chart, a top-courts mini-table, and a peak-hours preview.

**Architecture:** One migration (`0062`) adds `get_analytics_overview`, which **composes** the Phase 2–4 RPCs (`get_finance_summary`, `get_revenue_breakdown`, `get_booking_analytics`, `get_overall_utilization`) into a single row, so the Overview makes one round trip for its headline numbers. Everything else (trend, top courts, peak hours) reuses existing reports-service methods. `<ReportsOverview>` replaces the Phase 1 stub, assembled from `<KpiStrip>`, `<RevenueTrendChart>`, `<DataTable>`, `<PeakHoursChart>`.

**Tech Stack:** PostgreSQL (Supabase), Next.js 15 / React 19, TypeScript, Recharts, Vitest.

**Spec:** `docs/superpowers/specs/2026-09-03-reports-analytics-design.md` §4, §5, §27, §28, §37, §43.

## Global Constraints

- Branch `feat/reports-analytics`. Phases 1–4 committed (`17bb3e1`, `5836b03`, `4e4ff7b`, `0d3f6f0`).
- **`get_analytics_overview` calls the existing analytics RPCs, it does not re-derive.** Every figure it returns equals what the dedicated report shows for the same filter. Its own `has_facility_role` check plus the nested checks in the composed RPCs are both fine (cheap, `stable` invoker).
- **Revenue figures are facility+date only** (`get_finance_summary` / `get_revenue_breakdown` take no sport/court). Booking counts and utilization in the overview row **do** honour `p_facility_sport_id` / `p_court_id`. The Overview page keeps the full filter bar; a sport/court selection narrows bookings + utilization + the top-courts table, and revenue stays facility-wide (same trade-off as Phase 4, no note needed on a snapshot page).
- **Comparison period** (§27): fetch a second `get_analytics_overview` for `previousPeriod(filter)`; show `±%` only where it resolves (TODAY/THIS_WEEK/THIS_MONTH → sibling). Suppress otherwise — "Do not show misleading comparisons when there is insufficient historical data."
- **Drill-down** (§28): each KPI card links to its report — Revenue → `/reports/revenue`, Bookings/Completed/Cancelled → `/reports/bookings`, Utilization → `/reports/court-utilization`, Outstanding → `/finance/pending-payments` — all carrying the current filter via `filterToSearchParams`.
- Migration `0062_analytics_overview.sql` — new file, immutable once shipped.
- `database.types.ts` — one `Functions` entry.
- No SQL harness — `0062` verified by the manual task (Task 4).
- Per phase: `npm run typecheck` (no *new* errors), `npx next lint --dir src`, `npx vitest run`. **No `next build` while `next dev` runs.**
- Commit only after verification + explicit user go-ahead.

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/0062_analytics_overview.sql` | **Create.** `get_analytics_overview`. |
| `src/types/database.types.ts` | **Modify.** One `Functions` entry. |
| `src/features/reports/types.ts` | **Modify.** `AnalyticsOverview`. |
| `src/services/reports/reports.service.ts` | **Modify.** `getAnalyticsOverview`. |
| `src/services/reports/supabase-reports.service.ts` | **Modify.** One RPC call. |
| `src/services/reports/supabase-reports.service.test.ts` | **Modify.** Contract test. |
| `src/test/fakes/fake-reports-service.ts` | **Modify.** One field + method. |
| `src/features/reports/components/reports-overview.tsx` | **Rewrite.** The assembled Overview. |
| `src/features/reports/components/reports-overview.test.tsx` | **Create.** |

No new chart/table components — all reused.

---

## Task 1: Migration `0062` — `get_analytics_overview`

**Files:** Create `supabase/migrations/0062_analytics_overview.sql`

**Interfaces — Produces:** `get_analytics_overview(p_facility_id uuid, p_preset text, p_start_date date, p_end_date date, p_facility_sport_id uuid, p_court_id uuid)` → `table (gross_revenue_minor bigint, booking_revenue_minor bigint, membership_revenue_minor bigint, expenses_minor bigint, net_revenue_minor bigint, outstanding_minor bigint, total_bookings bigint, completed_bookings bigint, cancelled_bookings bigint, overall_utilization_pct numeric)`. `has_facility_role` → `42501`; `grant execute … to authenticated`.

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 5: Overview.
--
-- One row, composed from the dedicated analytics RPCs so the Overview page
-- makes a single round trip and every headline figure equals the one the
-- detail report shows. Nothing is re-derived here.
--
-- Revenue (gross / expenses / net / outstanding / breakdown) is
-- facility+date only — get_finance_summary / get_revenue_breakdown take no
-- sport/court. Booking counts and utilisation honour the sport/court
-- filter.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_analytics_overview(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  gross_revenue_minor bigint,
  booking_revenue_minor bigint,
  membership_revenue_minor bigint,
  expenses_minor bigint,
  net_revenue_minor bigint,
  outstanding_minor bigint,
  total_bookings bigint,
  completed_bookings bigint,
  cancelled_bookings bigint,
  overall_utilization_pct numeric
)
language plpgsql
stable
as $$
declare
  v_gross bigint;
  v_exp bigint;
  v_net bigint;
  v_out bigint;
  v_membership bigint;
  v_member_book bigint;
  v_guest_book bigint;
  v_total bigint;
  v_completed bigint;
  v_cancelled bigint;
  v_util numeric;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  select s.gross_revenue_minor, s.expenses_minor, s.net_revenue_minor, s.outstanding_minor
    into v_gross, v_exp, v_net, v_out
    from get_finance_summary(p_facility_id, p_preset, p_start_date, p_end_date) s;

  select b.membership_revenue_minor, b.member_booking_revenue_minor, b.guest_booking_revenue_minor
    into v_membership, v_member_book, v_guest_book
    from get_revenue_breakdown(p_facility_id, p_preset, p_start_date, p_end_date) b;

  select a.total, a.completed, a.cancelled
    into v_total, v_completed, v_cancelled
    from get_booking_analytics(
      p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_id, p_court_id
    ) a;

  select u.utilization_pct
    into v_util
    from get_overall_utilization(
      p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_id, p_court_id
    ) u;

  return query select
    coalesce(v_gross, 0),
    (coalesce(v_member_book, 0) + coalesce(v_guest_book, 0))::bigint,
    coalesce(v_membership, 0),
    coalesce(v_exp, 0),
    coalesce(v_net, 0),
    coalesce(v_out, 0),
    coalesce(v_total, 0),
    coalesce(v_completed, 0),
    coalesce(v_cancelled, 0),
    coalesce(v_util, 0);
end;
$$;

grant execute on function get_analytics_overview(uuid, text, date, date, uuid, uuid) to authenticated;
```

- [ ] **Step 2: Parse-sanity** — `get_analytics_overview` present, `1` grant.

---

## Task 2: types + `database.types.ts` + service + fake

- [ ] **Step 1: `types.ts`** — append:

```ts
// ─── Phase 5: Overview ───────────────────────────────────────────────────

export interface AnalyticsOverview {
  grossRevenueMinor: number;
  bookingRevenueMinor: number;
  membershipRevenueMinor: number;
  expensesMinor: number;
  netRevenueMinor: number;
  outstandingMinor: number;
  totalBookings: number;
  completedBookings: number;
  cancelledBookings: number;
  overallUtilizationPct: number;
}
```

- [ ] **Step 2: `database.types.ts`** — after `get_revenue_by_court`, add `get_analytics_overview` with the standard six args and:
```ts
        Returns: {
          gross_revenue_minor: number;
          booking_revenue_minor: number;
          membership_revenue_minor: number;
          expenses_minor: number;
          net_revenue_minor: number;
          outstanding_minor: number;
          total_bookings: number;
          completed_bookings: number;
          cancelled_bookings: number;
          overall_utilization_pct: number;
        }[];
```

- [ ] **Step 3: `reports.service.ts`** — add to the interface:
```ts
  /** One-row business snapshot for the Overview page; composes the other RPCs. */
  getAnalyticsOverview(filter: AnalyticsFilter): Promise<AnalyticsOverview>;
```
(import `AnalyticsOverview` from `../types`.)

- [ ] **Step 4: `supabase-reports.service.ts`**:
```ts
async getAnalyticsOverview(filter: AnalyticsFilter): Promise<AnalyticsOverview> {
  const { data, error } = await this.supabase.rpc("get_analytics_overview", this.baseArgs(filter));
  if (error || !data?.[0]) throw this.mapError(error);
  const r = data[0];
  return {
    grossRevenueMinor: r.gross_revenue_minor,
    bookingRevenueMinor: r.booking_revenue_minor,
    membershipRevenueMinor: r.membership_revenue_minor,
    expensesMinor: r.expenses_minor,
    netRevenueMinor: r.net_revenue_minor,
    outstandingMinor: r.outstanding_minor,
    totalBookings: r.total_bookings,
    completedBookings: r.completed_bookings,
    cancelledBookings: r.cancelled_bookings,
    overallUtilizationPct: r.overall_utilization_pct,
  };
}
```

- [ ] **Step 5: `supabase-reports.service.test.ts`** — add:
```ts
describe("SupabaseReportsService.getAnalyticsOverview", () => {
  it("calls get_analytics_overview with the scoped args and maps the row", async () => {
    const rpc = vi.fn(async () => ({
      data: [{
        gross_revenue_minor: 12000000, booking_revenue_minor: 7000000, membership_revenue_minor: 5000000,
        expenses_minor: 3500000, net_revenue_minor: 8500000, outstanding_minor: 1850000,
        total_bookings: 205, completed_bookings: 120, cancelled_bookings: 20, overall_utilization_pct: 68,
      }],
      error: null,
    }));
    const service = new SupabaseReportsService({ rpc } as never);
    const r = await service.getAnalyticsOverview({ ...filter, courtId: "c1" });
    expect(rpc).toHaveBeenCalledWith("get_analytics_overview", expect.objectContaining({ p_facility_id: "fac-1", p_court_id: "c1" }));
    expect(r).toMatchObject({ grossRevenueMinor: 12000000, totalBookings: 205, overallUtilizationPct: 68 });
  });

  it("maps a denial to REPORTS_ACCESS_DENIED", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "Not authorized for this facility." } }));
    const service = new SupabaseReportsService({ rpc } as never);
    await expect(service.getAnalyticsOverview(filter)).rejects.toMatchObject({ code: "REPORTS_ACCESS_DENIED" });
  });
});
```

- [ ] **Step 6: `fake-reports-service.ts`** — add `analyticsOverview: AnalyticsOverview = { grossRevenueMinor: 0, bookingRevenueMinor: 0, membershipRevenueMinor: 0, expensesMinor: 0, netRevenueMinor: 0, outstandingMinor: 0, totalBookings: 0, completedBookings: 0, cancelledBookings: 0, overallUtilizationPct: 0 }` + `async getAnalyticsOverview(): Promise<AnalyticsOverview> { if (this.error) throw this.error; return this.analyticsOverview; }`.

- [ ] **Step 7:** `npx vitest run src/services/reports` + `npm run typecheck`.

---

## Task 3: `<ReportsOverview>`

**Files:** rewrite `reports-overview.tsx`; create `reports-overview.test.tsx`

**Behaviour:**
- `useAnalyticsFilter` → `load()` = `Promise.all([getAnalyticsOverview(filter), getRevenueTrend(filter, granularity), getCourtUtilization(filter), getPeakHours(filter)])` + a swallowed `getAnalyticsOverview(previousPeriod(filter))` for deltas.
- `status`: `loading` → `error` (`onRetry`) → `empty` when `overview.grossRevenueMinor === 0 && overview.totalBookings === 0` → `ready`.
- **Prominent KPI strip** (6, with deltas + drill-down href):
  - Total Revenue → `/reports/revenue` · Net Revenue → `/reports/revenue` · Total Expenses → `/finance/expenses` (external, keep filter off — just `/finance/expenses`) · Total Bookings → `/reports/bookings` · Court Utilization → `/reports/court-utilization` · Outstanding Payments → `/finance/pending-payments`
  - `Delta` component copied from `booking-report.tsx` (or lift to a shared `kpi-delta.tsx` — **do that**, `src/features/reports/components/kpi-delta.tsx`, and re-import in `booking-report.tsx`).
- **Secondary KPI strip** (4, no deltas): Booking Revenue → `/reports/revenue`, Membership Revenue → `/reports/memberships`, Completed Bookings → `/reports/bookings`, Cancelled Bookings → `/reports/bookings`.
- `<Card>` "Revenue Trend" → `<RevenueTrendChart points={trend} />`.
- `<div className="grid gap-4 lg:grid-cols-2">`:
  - `<Card>` "Top Courts" → `<DataTable caption="Top courts by utilization" columns=[Court, Utilization]>` of the top 5 `courtUtilization` rows sorted desc, `href` → `/reports/court-utilization?…&court=<id>`. "View all →" link to `/reports/court-utilization`.
  - `<Card>` "Peak Hours" → `<PeakHoursChart rows={peak} />` (or the top-5 hours if the full chart is too tall — use the full chart, it's already `h-64`). "View all →" link to `/reports/court-utilization`.
- `onExportCsv`: `toCsv` of the 10 overview KPIs (label,value) + top courts, filename `overview-<facilityId>-<preset>.csv`.
- Drill-down hrefs built with `filterToSearchParams(filter)` where the target is a `/reports/*` page; plain paths for `/finance/*`.

- [ ] **Step 1: create `kpi-delta.tsx`** (lift from `booking-report.tsx`):

```tsx
"use client";

import { TrendingDown, TrendingUp } from "lucide-react";

/** Percent change vs the preceding window of equal length, or null. */
export function changePct(current: number, previous: number | null): number | null {
  if (previous === null || previous === 0) return null;
  return Math.round(((current - previous) / Math.abs(previous)) * 1000) / 10;
}

export function KpiDelta({ pct, invert }: { pct: number | null; invert?: boolean }) {
  if (pct === null) return <span className="text-muted-foreground">vs last period</span>;
  const good = invert ? pct <= 0 : pct >= 0;
  const Icon = pct >= 0 ? TrendingUp : TrendingDown;
  return (
    <span className={`inline-flex items-center gap-0.5 font-medium ${good ? "text-success" : "text-destructive"}`}>
      <Icon className="h-3 w-3" aria-hidden />
      {pct > 0 ? "+" : ""}
      {pct}%
    </span>
  );
}
```
Then in `booking-report.tsx` replace the local `changePct` + `Delta` with `import { KpiDelta, changePct } from "./kpi-delta"` and swap `<Delta` → `<KpiDelta`. Re-run `booking-report.test.tsx`.

- [ ] **Step 2: `reports-overview.test.tsx`**

```tsx
import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { ReportsOverview } from "./reports-overview";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";
import { installFakeReportsService } from "@/test/fakes/fake-reports-service";

const SLOW = { timeout: 4000 } as const;

function setup() {
  installFakeReportsFilterDeps();
  return installFakeReportsService();
}

describe("ReportsOverview", () => {
  it("shows the empty state when there is no activity", async () => {
    setup();
    render(<ReportsOverview />);
    expect(await screen.findByText(/no activity for this period/i, {}, SLOW)).toBeInTheDocument();
  });

  it("renders headline KPIs with drill-down links and the trend + top-courts", async () => {
    const reports = setup();
    reports.analyticsOverview = {
      grossRevenueMinor: 12_000_000, bookingRevenueMinor: 7_000_000, membershipRevenueMinor: 5_000_000,
      expensesMinor: 3_500_000, netRevenueMinor: 8_500_000, outstandingMinor: 1_850_000,
      totalBookings: 205, completedBookings: 120, cancelledBookings: 20, overallUtilizationPct: 68,
    };
    reports.revenueTrend = [{ date: "2026-09-01", grossMinor: 800000, refundMinor: 0, netMinor: 800000 }];
    reports.courtUtilization = [
      { courtId: "c1", courtName: "Court 1", facilitySportId: "fs1", sportName: "Badminton", openMinutes: 3000, bookedMinutes: 2460, utilizationPct: 82 },
    ];
    reports.peakHours = [{ hour: 18, openMinutes: 300, bookedMinutes: 270, demandPct: 90 }];

    render(<ReportsOverview />);

    expect(await screen.findByText("205", {}, SLOW)).toBeInTheDocument(); // total bookings
    expect(screen.getByRole("link", { name: /total revenue/i })).toHaveAttribute(
      "href",
      expect.stringContaining("/reports/revenue"),
    );
    expect(screen.getByRole("table", { name: /top courts/i })).toBeInTheDocument();
  });
});
```

- [ ] **Step 3: run — fails.**

- [ ] **Step 4: write `reports-overview.tsx`** per Behaviour.

- [ ] **Step 5: run — passes.**

- [ ] **Step 6:** `npx vitest run src/features/reports src/services/reports` + `npm run typecheck` + `npx next lint --dir src` + full `npx vitest run`.

---

## Task 4: manual DB verification (reviewer, against linked Supabase)

Apply `0056`–`0060` + `0062`. Using the §50 fixture (Champz Turf, 03 Sep 2026):

```sql
select * from get_analytics_overview('<champz>', 'CUSTOM', '2026-09-03', '2026-09-03', null, null);
-- gross_revenue_minor = 600000, booking_revenue_minor = 100000, membership_revenue_minor = 500000,
-- expenses_minor = 100000, net_revenue_minor = 500000, outstanding_minor = 80000,
-- total_bookings = 3, completed_bookings = 0, cancelled_bookings = 0

-- equals the dedicated reports for the same range:
select gross_revenue_minor from get_finance_summary('<champz>', 'CUSTOM', '2026-09-03', '2026-09-03');   -- 600000
select total from get_booking_analytics('<champz>', 'CUSTOM', '2026-09-03', '2026-09-03', null, null);   -- 3
select utilization_pct from get_overall_utilization('<champz>', 'CUSTOM', '2026-09-03', '2026-09-03', null, null);

-- facility isolation
select * from get_analytics_overview('<other>', 'THIS_MONTH', null, null, null, null);  -- raises "Not authorized"
```

Confirm §5 KPI definitions: the ₹800 pending booking is in `outstanding_minor`, never in `gross_revenue_minor` or `booking_revenue_minor`.

---

## Self-Review

**Spec coverage:** §4 KPI cards (prominent 6 + secondary 4) → `<KpiStrip>` ×2. §5 KPI definitions → `get_analytics_overview` composes the already-defined RPCs; nothing re-derived. §27 comparison period → `previousPeriod` + `<KpiDelta>`, suppressed when unavailable. §28 drill-down → every card is a `<Link>`. §37 desktop layout (filter bar, KPI cards, trend, then two-up top-courts + peak-hours) → the component structure. §43 empty state → `<ReportShell>`.

**Placeholder scan:** Task 3 Step 4 "write per Behaviour" — the whole component is `<KpiStrip>` / `<RevenueTrendChart>` / `<DataTable>` / `<PeakHoursChart>` in `<ReportShell>`, with the `load` + status + `previousPeriod` pattern from `booking-report.tsx`. `<KpiDelta>` is fully written in Step 1. Acceptable.

**Type consistency:** `AnalyticsOverview` field names (`grossRevenueMinor`, `overallUtilizationPct`, …) identical across `types.ts`, service, fake, component. SQL `gross_revenue_minor` → `grossRevenueMinor` mapping matches the pattern of every prior phase. `changePct`/`KpiDelta` moved to `kpi-delta.tsx` and imported in both `booking-report.tsx` and `reports-overview.tsx` — one definition.
