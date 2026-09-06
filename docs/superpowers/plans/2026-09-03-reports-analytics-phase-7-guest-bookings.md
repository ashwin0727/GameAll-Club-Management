# Reports & Analytics — Phase 7: Guest Booking Report — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use `- [ ]`.

> **Status: implemented (2026-09-04), pending user verification + commit.** Notes:
> - Built on Phase 6 (`dcd8609`). `guestBookingCollectionRate` added to `KpiKey` + `KPI_DEFINITIONS`.
> - Peak guest hours is a `<ReportBarList>` of volume-by-hour (no chart, no %) — §21 shows no percentage.
> - **`next build` not run** (standing rule). `tsc` + `next lint` + `vitest` (101 reports tests) + dev server compiles clean. Full suite **630/630**. All six web report pages are now real.

**Goal:** `/reports/guest-bookings` — guest booking volume & status, guest revenue, average booking value, payment collection rate, popular sports & courts, and peak guest hours.

**Architecture:** One migration (`0063`) adds four RPCs, all filtered to `bookings.customer_type = 'GUEST'` (ad-hoc guest bookings — released-seat session guests are covered by the Membership report, spec §11). `<GuestBookingReport>` follows the established assembly pattern; no new components.

**Tech Stack:** PostgreSQL (Supabase), Next.js 15 / React 19, TypeScript, Vitest.

**Spec:** `docs/superpowers/specs/2026-09-03-reports-analytics-design.md` §21, §22, §23, §42, §43.

## Global Constraints

- Branch `feat/reports-analytics`. HEAD is Phase 5 (`cedcd97`); **Phase 6 is uncommitted** — this phase stacks on it.
- **Guest bookings = `bookings WHERE customer_type = 'GUEST'`** in the range (by `start_time`), sport/court filtered. Released-seat session guests are **not** here.
- **Guest revenue = collected** (paid `payments` for those bookings) — realised, cash basis, subset of Finance's `guest_booking_revenue_minor`.
- **Average Booking Value** (§22) = total captured `amount_minor` of **paid** (`payment_status = 'PAID'`), **non-cancelled** guest bookings ÷ their count — identical to the `averageBookingValue` definition set in Phase 4 and to `get_booking_analytics.avg_guest_booking_value_minor`.
- **Payment Collection Rate** (§23) = `collected ÷ (collected + outstanding)`, over non-cancelled guest bookings. Outstanding = `Σ greatest(amount_minor − collected, 0)`. Pending ≠ collected.
- **Peak guest hours** = a volume count by local hour-of-day (not a utilisation %) — "which hours do guests book". No availability primitives needed.
- Booking status enum verbatim: `pending | confirmed | cancelled | completed`.
- Migration `0063_analytics_guest_bookings.sql` — new file, immutable once shipped.
- `database.types.ts` — four `Functions` entries.
- No SQL harness — `0063` verified by the manual task (Task 4). §50 fixture becomes a check.
- Per phase: `npm run typecheck` (no *new* errors), `npx next lint --dir src`, `npx vitest run`. **No `next build` while `next dev` runs.**
- Commit only after verification + explicit user go-ahead.

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/0063_analytics_guest_bookings.sql` | **Create.** `get_guest_booking_analytics`, `get_guest_bookings_by_sport`, `get_guest_bookings_by_court`, `get_guest_peak_hours`. |
| `src/types/database.types.ts` | **Modify.** Four `Functions` entries. |
| `src/features/reports/types.ts` | **Modify.** `GuestBookingAnalytics`, `GuestBookingsBySportRow`, `GuestBookingsByCourtRow`, `GuestPeakHourRow`. |
| `src/features/reports/definitions.ts` | **Modify.** Add `guestBookingsTotal` / `guestBookingCollectionRate` keys (or reuse). |
| `src/services/reports/reports.service.ts` | **Modify.** Four methods. |
| `src/services/reports/supabase-reports.service.ts` | **Modify.** Four RPC calls. |
| `src/services/reports/supabase-reports.service.test.ts` | **Modify.** Contract tests. |
| `src/test/fakes/fake-reports-service.ts` | **Modify.** Four fields + methods. |
| `src/features/reports/components/guest-booking-report.tsx` | **Rewrite.** The assembled report. |
| `src/features/reports/components/guest-booking-report.test.tsx` | **Create.** |

---

## Task 1: Migration `0063`

**Files:** Create `supabase/migrations/0063_analytics_guest_bookings.sql`

**Interfaces — Produces** (all: standard six args; `has_facility_role` → `42501`; `resolve_finance_date_range`; `grant execute … to authenticated`):
- `get_guest_booking_analytics(…)` → `table (total bigint, completed bigint, confirmed bigint, pending bigint, cancelled bigint, revenue_minor bigint, avg_booking_value_minor bigint, collected_minor bigint, outstanding_minor bigint, collection_rate_pct numeric)`
- `get_guest_bookings_by_sport(…)` → `table (facility_sport_id uuid, sport_name text, booking_count bigint, revenue_minor bigint)` — active facility sports in scope, busiest first.
- `get_guest_bookings_by_court(…)` → `table (court_id uuid, court_name text, sport_name text, booking_count bigint, revenue_minor bigint)` — non-archived courts in scope, busiest first.
- `get_guest_peak_hours(…)` → `table (hour smallint, booking_count bigint)` — one row per hour that has ≥1 guest booking, ordered by hour.

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 7: Guest bookings.
--
-- Ad-hoc guest bookings only (bookings.customer_type = 'GUEST'). Released-
-- seat session guests are in the Membership report. Revenue is collected
-- (paid payments), cash basis. Average booking value and collection rate
-- per spec §22 / §23 — cancelled and unpaid excluded from the divisors.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_guest_booking_analytics(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  total bigint,
  completed bigint,
  confirmed bigint,
  pending bigint,
  cancelled bigint,
  revenue_minor bigint,
  avg_booking_value_minor bigint,
  collected_minor bigint,
  outstanding_minor bigint,
  collection_rate_pct numeric
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
  with gb as (
    select
      b.id,
      b.status::text as status,
      coalesce(b.amount_minor, 0) as amount_minor,
      b.payment_status,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p where p.booking_id = b.id and p.status = 'paid'
      ), 0)::bigint as collected_minor
    from bookings b
    where b.facility_id = p_facility_id
      and b.customer_type = 'GUEST'
      and range_ @> b.start_time
      and (p_facility_sport_id is null or b.facility_sport_id = p_facility_sport_id)
      and (p_court_id is null or b.court_id = p_court_id)
  ),
  agg as (
    select
      count(*) as total,
      count(*) filter (where status = 'completed') as completed,
      count(*) filter (where status = 'confirmed') as confirmed,
      count(*) filter (where status = 'pending') as pending,
      count(*) filter (where status = 'cancelled') as cancelled,
      coalesce(sum(collected_minor), 0) as collected,
      coalesce(sum(amount_minor) filter (
        where payment_status = 'PAID' and status <> 'cancelled'
      ), 0) as paid_value,
      count(*) filter (where payment_status = 'PAID' and status <> 'cancelled') as paid_count,
      coalesce(sum(greatest(amount_minor - collected_minor, 0)) filter (where status <> 'cancelled'), 0) as outstanding
    from gb
  )
  select
    total::bigint,
    completed::bigint,
    confirmed::bigint,
    pending::bigint,
    cancelled::bigint,
    collected::bigint,
    case when paid_count > 0 then round(paid_value / paid_count)::bigint else 0 end,
    collected::bigint,
    outstanding::bigint,
    case when (collected + outstanding) > 0
      then round((collected::numeric / (collected + outstanding)) * 100, 1)
      else 0 end
  from agg;
end;
$$;

grant execute on function get_guest_booking_analytics(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_guest_bookings_by_sport(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  facility_sport_id uuid,
  sport_name text,
  booking_count bigint,
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
  with gb as (
    select
      b.facility_sport_id,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p where p.booking_id = b.id and p.status = 'paid'
      ), 0)::bigint as collected_minor
    from bookings b
    where b.facility_id = p_facility_id
      and b.customer_type = 'GUEST'
      and range_ @> b.start_time
      and (p_court_id is null or b.court_id = p_court_id)
  )
  select
    fs.id,
    coalesce(fs.custom_sport_name, sp.name),
    count(gb.facility_sport_id)::bigint,
    coalesce(sum(gb.collected_minor), 0)::bigint
  from facility_sports fs
  join sports sp on sp.id = fs.sport_id
  left join gb on gb.facility_sport_id = fs.id
  where fs.facility_id = p_facility_id
    and fs.is_active
    and (p_facility_sport_id is null or fs.id = p_facility_sport_id)
  group by fs.id, coalesce(fs.custom_sport_name, sp.name)
  order by count(gb.facility_sport_id) desc, 2;
end;
$$;

grant execute on function get_guest_bookings_by_sport(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_guest_bookings_by_court(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  court_id uuid,
  court_name text,
  sport_name text,
  booking_count bigint,
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
  with gb as (
    select
      b.court_id,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p where p.booking_id = b.id and p.status = 'paid'
      ), 0)::bigint as collected_minor
    from bookings b
    where b.facility_id = p_facility_id
      and b.customer_type = 'GUEST'
      and range_ @> b.start_time
  )
  select
    c.id,
    c.name,
    coalesce(fs.custom_sport_name, sp.name),
    count(gb.court_id)::bigint,
    coalesce(sum(gb.collected_minor), 0)::bigint
  from courts c
  join facility_sports fs on fs.id = c.facility_sport_id
  join sports sp on sp.id = fs.sport_id
  left join gb on gb.court_id = c.id
  where c.facility_id = p_facility_id
    and not c.archived
    and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
    and (p_court_id is null or c.id = p_court_id)
  group by c.id, c.name, coalesce(fs.custom_sport_name, sp.name)
  order by count(gb.court_id) desc, c.name;
end;
$$;

grant execute on function get_guest_bookings_by_court(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_guest_peak_hours(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  hour smallint,
  booking_count bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  select coalesce(timezone, 'Asia/Kolkata') into tz from facilities where id = p_facility_id;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  select
    extract(hour from b.start_time at time zone tz)::smallint as hour,
    count(*)::bigint
  from bookings b
  where b.facility_id = p_facility_id
    and b.customer_type = 'GUEST'
    and b.status <> 'cancelled'
    and range_ @> b.start_time
    and (p_facility_sport_id is null or b.facility_sport_id = p_facility_sport_id)
    and (p_court_id is null or b.court_id = p_court_id)
  group by 1
  order by 1;
end;
$$;

grant execute on function get_guest_peak_hours(uuid, text, date, date, uuid, uuid) to authenticated;
```

- [ ] **Step 2: Parse-sanity** — the four function names present.

---

## Task 2: types + `database.types.ts` + service + fake

- [ ] **Step 1: `types.ts`** — append:

```ts
// ─── Phase 7: Guest Bookings ─────────────────────────────────────────────

export interface GuestBookingAnalytics {
  total: number;
  completed: number;
  confirmed: number;
  pending: number;
  cancelled: number;
  revenueMinor: number;
  avgBookingValueMinor: number;
  collectedMinor: number;
  outstandingMinor: number;
  collectionRatePct: number;
}

export interface GuestBookingsBySportRow {
  facilitySportId: string;
  sportName: string;
  bookingCount: number;
  revenueMinor: number;
}

export interface GuestBookingsByCourtRow {
  courtId: string;
  courtName: string;
  sportName: string;
  bookingCount: number;
  revenueMinor: number;
}

export interface GuestPeakHourRow {
  hour: number;
  bookingCount: number;
}
```

- [ ] **Step 2: `database.types.ts`** — after `get_guest_release_analytics`, add the four entries (standard six-arg `Args`; snake_case `Returns` matching the SQL tables, all fields `number` except uuid/text).

- [ ] **Step 3: `reports.service.ts`** — add signatures + import the four types:
```ts
  getGuestBookingAnalytics(filter: AnalyticsFilter): Promise<GuestBookingAnalytics>;
  getGuestBookingsBySport(filter: AnalyticsFilter): Promise<GuestBookingsBySportRow[]>;
  getGuestBookingsByCourt(filter: AnalyticsFilter): Promise<GuestBookingsByCourtRow[]>;
  getGuestPeakHours(filter: AnalyticsFilter): Promise<GuestPeakHourRow[]>;
```

- [ ] **Step 4: `supabase-reports.service.ts`** — four methods, `this.baseArgs(filter)`, snake→camel. `getGuestBookingAnalytics` reads `data?.[0]` and throws `mapError` if absent.

- [ ] **Step 5: `supabase-reports.service.test.ts`** — `describe("SupabaseReportsService guest bookings")`: `getGuestBookingAnalytics` (RPC name, `baseArgs`, mapping incl. `collectionRatePct`, one `REPORTS_ACCESS_DENIED`), `getGuestBookingsBySport` / `_byCourt` / `getGuestPeakHours` (mapping).

- [ ] **Step 6: `fake-reports-service.ts`** — four fields (zeroed) + four param-less methods.

- [ ] **Step 7:** `npx vitest run src/services/reports` + `npm run typecheck`.

---

## Task 3: `<GuestBookingReport>`

**Files:** rewrite `guest-booking-report.tsx`; create `guest-booking-report.test.tsx`

**Behaviour** (pattern per `booking-report.tsx`):
- `load()` = `Promise.all([getGuestBookingAnalytics, getGuestBookingsBySport, getGuestBookingsByCourt, getGuestPeakHours])`. No previous-period.
- `status`: `loading` → `error` (`onRetry`) → `empty` when `analytics.total === 0` → `ready`.
- **KPI strip** (6): Total Guest Bookings, Completed, Cancelled, Guest Revenue (`formatCurrency(revenueMinor)`), Avg Booking Value (`formatCurrency(avgBookingValueMinor)`), Collection Rate (`${collectionRatePct}%`).
- **`<Card>` "Guest Bookings by Sport"** — `<ReportBarList>` (value `bookingCount`, caption `<count> · <formatCurrency(revenueMinor)>`) + `<DataTable caption="Guest bookings by sport" columns=[Sport, Bookings, Revenue]>` with `href` → `/reports/guest-bookings?…&sport=<fsId>`.
- **`<Card>` "Guest Bookings by Court"** — same, `href` → `…&court=<id>`.
- **`<Card>` "Peak Guest Hours"** — `<ReportBarList>` of `get_guest_peak_hours` (label `formatHourLabel(hour)`, value `bookingCount`) + `<DataTable caption="Peak guest hours" columns=[Hour, Bookings]>`. (No chart — a simple bar list; §21 shows no %.)
- **`<Card>` "Payment Collection"** — a `<DataTable caption="Guest payment collection">` rows `[{metric:"Collected", value: formatCurrency(collectedMinor)}, {metric:"Outstanding", value: formatCurrency(outstandingMinor)}, {metric:"Collection rate", value: `${collectionRatePct}%`}]` + a "Collect →" `<Link href="/finance/pending-payments">`.
- `onExportCsv`: KPIs + by-sport + by-court + peak hours, filename `guest-bookings-<facilityId>-<preset>.csv`.

- [ ] **Step 1: `definitions.ts`** — add `guestBookingCollectionRate: "Collected guest-booking payments divided by (collected + outstanding), over non-cancelled guest bookings in the range."` + the `KpiKey` entry. (`guestBookingRevenue` already exists.)

- [ ] **Step 2: `guest-booking-report.test.tsx`**

```tsx
import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { GuestBookingReport } from "./guest-booking-report";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";
import { installFakeReportsService } from "@/test/fakes/fake-reports-service";

const SLOW = { timeout: 4000 } as const;

function setup() {
  installFakeReportsFilterDeps();
  return installFakeReportsService();
}

describe("GuestBookingReport", () => {
  it("shows the empty state with no guest bookings", async () => {
    setup();
    render(<GuestBookingReport />);
    expect(await screen.findByText(/no guest bookings for this period/i, {}, SLOW)).toBeInTheDocument();
  });

  it("renders KPIs and the by-sport table", async () => {
    const reports = setup();
    reports.guestBookingAnalytics = {
      total: 120, completed: 90, confirmed: 20, pending: 3, cancelled: 7,
      revenueMinor: 45_000_00, avgBookingValueMinor: 500_00, collectedMinor: 45_000_00,
      outstandingMinor: 5_000_00, collectionRatePct: 90,
    };
    reports.guestBookingsBySport = [
      { facilitySportId: "fs1", sportName: "Badminton", bookingCount: 80, revenueMinor: 30_000_00 },
    ];
    reports.guestBookingsByCourt = [
      { courtId: "c1", courtName: "Court 1", sportName: "Badminton", bookingCount: 50, revenueMinor: 20_000_00 },
    ];
    reports.guestPeakHours = [{ hour: 18, bookingCount: 30 }];

    render(<GuestBookingReport />);

    expect(await screen.findByText("120", {}, SLOW)).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /guest bookings by sport/i })).toBeInTheDocument();
    expect(screen.getByText("90%")).toBeInTheDocument(); // collection rate KPI
  });
});
```

- [ ] **Step 3: run — fails.**

- [ ] **Step 4: write `guest-booking-report.tsx`** per Behaviour. `formatHourLabel` local (copy from `court-utilization-report.tsx` or `peak-hours-chart.tsx`).

- [ ] **Step 5: run — passes.**

- [ ] **Step 6:** `npx vitest run src/features/reports src/services/reports` + `npm run typecheck` + `npx next lint --dir src` + full `npx vitest run`.

---

## Task 4: manual DB verification (reviewer, against linked Supabase)

Apply `0056`–`0063`. §50 fixture (Champz Turf, 03 Sep 2026: guest bookings ₹400 paid, ₹600 paid, ₹800 pending — all confirmed, none cancelled):

```sql
select * from get_guest_booking_analytics('<champz>', 'CUSTOM', '2026-09-03', '2026-09-03', null, null);
-- total 3, confirmed 3, completed 0, cancelled 0
-- revenue_minor / collected_minor = 100000  (₹400 + ₹600 — the ₹800 is not paid)
-- avg_booking_value_minor = 50000  (avg captured value of the 2 PAID: (40000+60000)/2)
-- outstanding_minor = 80000  (the ₹800)
-- collection_rate_pct = round(100000 / 180000 * 100, 1) = 55.6

select * from get_guest_bookings_by_sport('<champz>', 'CUSTOM', '2026-09-03', '2026-09-03', null, null);
-- the sport of the booked court: booking_count 3, revenue_minor 100000; other sports 0

select * from get_guest_peak_hours('<champz>', 'CUSTOM', '2026-09-03', '2026-09-03', null, null);
-- one row per hour that has a guest booking

select * from get_guest_booking_analytics('<other>', 'THIS_MONTH', null, null, null, null);  -- raises "Not authorized"
```

Confirms §22 (avg over paid, non-cancelled only) and §23 (collection rate = collected / (collected + outstanding), the ₹800 pending never counted as collected).

---

## Self-Review

**Spec coverage:** §21 total / completed / cancelled guest bookings → `get_guest_booking_analytics`. §21 guest revenue → `revenue_minor` (collected). §22 average booking value (documented, paid + non-cancelled only) → `avg_booking_value_minor`, matching the Phase 4 definition. §21 popular sports / courts → `get_guest_bookings_by_sport` / `_by_court`. §21 peak guest hours → `get_guest_peak_hours` (volume by hour). §23 collection rate → `collection_rate_pct`, pending not counted. §28 drill-down → `DataTable href` on sport + court. §42 tables → every card. §43 empty state → `<ReportShell>`.

**Placeholder scan:** Task 3 Step 4 "write per Behaviour" — `<KpiStrip>` + four `<Card>`s of `<ReportBarList>` / `<DataTable>` in `<ReportShell>`, identical to `booking-report.tsx` / `membership-report.tsx`. `formatHourLabel` is a 2-line copy. Acceptable.

**Type consistency:** SQL snake_case ↔ TS camelCase uniform across the four RPCs, service, fake, component. `collection_rate_pct` → `collectionRatePct` used in the KPI and the §50 assertion. `GuestBookingsBySportRow` deliberately distinct from Phase 2's `BookingsBySportRow` (adds `revenueMinor`).
