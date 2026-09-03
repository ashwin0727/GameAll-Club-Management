# Reports & Analytics — Phase 2: Bookings Report — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or subagent-driven-development) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** The first report with real data. `/reports/bookings` shows a booking-status KPI row, a booking-volume trend chart, a bookings-by-sport bar + table, a status breakdown, and a Guest/Member source split — all server-aggregated, filter-driven, with CSV export.

**Architecture:** One migration (`0058`) adds four `stable` plpgsql RPCs over the `bookings` table alone (no availability math), each `has_facility_role`-guarded and funnelled through `resolve_finance_date_range`. A new `src/services/reports/` layer (interface + Supabase impl + fake) mirrors `src/services/finance/`. `<BookingReport>` replaces the Phase 1 `ComingSoonReport` stub, keeping the exact `ReportShell` + filter-bar wiring, and adds a Recharts trend chart + a shared `<ReportBarList>` + `<DataTable>` pattern that Phases 3–7 reuse.

**Tech Stack:** PostgreSQL (Supabase), Next.js 15 / React 19, TypeScript, Recharts, Vitest + `@testing-library/react`, hand-maintained `src/types/database.types.ts`.

**Spec:** `docs/superpowers/specs/2026-09-03-reports-analytics-design.md` (§9, §10, §11, §29, §42, §43, §49)

## Global Constraints

- **Isolated branch:** all work on `feat/reports-analytics` in the OneDrive checkout. Phase 1 is committed (`17bb3e1`).
- **No business logic.** Booking status, validity and customer type are read from `bookings` as-is. Reports never re-derives them.
- **Server-side aggregation only.** The browser calls one RPC per widget-group and renders the result. It never counts bookings itself. The one client computation allowed is `pickGranularity` (already in `aggregation.ts`) choosing which `p_granularity` to request.
- **Booking status enum, verbatim:** `pending | confirmed | cancelled | completed` (`booking_status`, `0001_init.sql`). Never invent a status.
- **Customer type enum, verbatim:** `MEMBER | GUEST` (`bookings.customer_type`, `0007_bookings.sql`). The source split has exactly these two rows; no `OTHER`.
- **Bookings are dated by `start_time`** for every range filter (matches `get_pending_payments` "the date the court is booked for" and the existing `guest-bookings-dashboard`).
- **Total Bookings counts all statuses**, cancelled included; cancelled is also shown as its own KPI and its own trend series.
- **Migration file is immutable once shipped.** All Phase 2 DB changes go in `supabase/migrations/0058_analytics_bookings.sql`.
- **`database.types.ts` is hand-maintained** — add a `Functions` entry per new RPC, matching the `get_revenue_trend` block's shape.
- **No SQL harness** — `0058` is verified by the manual task (Task 6). Everything else is Vitest.
- **Money is minor units**; format only via `formatCurrency` from `@/features/pricing/money`.
- **Recharts**, matching `src/features/finance/components/revenue-trend-chart.tsx` (ResponsiveContainer, muted axes, themed tooltip, `role="img"` + `aria-label`).
- **Design tokens:** guest `#FFB020`, membership `#8B5CF6`, primary/booking `#00F08A`, success `#00D084`, error `#FF4D67`, payments `#5B6CFF`.
- **Per phase, green:** `npm run typecheck` (no *new* errors), `npm test`, `npm run lint`, `npm run build`.
- **Commit** only after full verification + user go-ahead (standing instruction this project).

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/0058_analytics_bookings.sql` | **Create.** `get_booking_analytics`, `get_booking_trend`, `get_bookings_by_sport`, `get_booking_source_split`. |
| `src/types/database.types.ts` | **Modify.** Four `Functions` entries. |
| `src/features/reports/types.ts` | **Modify.** Add `BookingAnalytics`, `BookingTrendPoint`, `BookingsBySportRow`, `BookingSourceRow`. |
| `src/features/reports/definitions.ts` | **Modify.** Reword `averageBookingValue` to match the SQL (captured value of paid, non-cancelled guest bookings ÷ their count). |
| `src/features/reports/report-filter.ts` | **Create.** `dateRangeArgs(filter)` + `scopeArgs(filter)` — the `AnalyticsFilter` → RPC-arg mapping, shared by every service method. |
| `src/features/reports/report-filter.test.ts` | **Create.** Arg-mapping unit tests. |
| `src/services/reports/reports.service.ts` | **Create.** `ReportsService` interface (Phase 2 methods). |
| `src/services/reports/supabase-reports.service.ts` | **Create.** `SupabaseReportsService` — RPC calls, snake→camel mapping, `mapError`. |
| `src/services/reports/supabase-reports.service.test.ts` | **Create.** Per-method: RPC name, args, mapping, error codes. |
| `src/services/reports/index.ts` | **Create.** `getReportsService()` / `setReportsService()` singleton seam. |
| `src/services/shared/service-error.ts` | **Modify.** Add `REPORTS_ACCESS_DENIED` + `REPORTS_DATA_ERROR` codes + friendly messages. |
| `src/features/reports/components/report-bar-list.tsx` | **Create.** Labelled horizontal bars from `{label, value, color?}[]` + a total. Reused Phases 3–7. |
| `src/features/reports/components/report-bar-list.test.tsx` | **Create.** |
| `src/features/reports/components/data-table.tsx` | **Create.** Minimal `<DataTable columns rows caption>` — the accessible companion under every chart (§42). Reused Phases 3–7. |
| `src/features/reports/components/data-table.test.tsx` | **Create.** |
| `src/features/reports/components/booking-trend-chart.tsx` | **Create.** Recharts area chart of booking counts (total + cancelled series). |
| `src/features/reports/components/booking-report.tsx` | **Rewrite.** The real report. |
| `src/features/reports/components/booking-report.test.tsx` | **Create.** Renders KPIs/chart/tables from a fake; loading/empty/error; CSV. |
| `src/test/fakes/fake-reports-service.ts` | **Create.** In-memory `ReportsService` with setwith-able fixtures. |

---

## Task 1: Migration `0058` — the four booking RPCs

**Files:** Create `supabase/migrations/0058_analytics_bookings.sql`

**Interfaces — Produces:**
- `get_booking_analytics(p_facility_id uuid, p_preset text, p_start_date date, p_end_date date, p_facility_sport_id uuid, p_court_id uuid)` → `table (total bigint, completed bigint, confirmed bigint, pending bigint, cancelled bigint, guest_count bigint, member_count bigint, avg_guest_booking_value_minor bigint)`
- `get_booking_trend(… same six args …, p_granularity text)` → `table (bucket_date date, total bigint, completed bigint, cancelled bigint)` — zero-filled across the range at the granularity, buckets in facility tz.
- `get_bookings_by_sport(… six args …)` → `table (facility_sport_id uuid, sport_name text, booking_count bigint)` — one row per **active** facility sport (LEFT JOIN, so a sport with 0 bookings still appears), ordered by count desc then name.
- `get_booking_source_split(… six args …)` → `table (source text, booking_count bigint)` — exactly two rows, `GUEST` and `MEMBER`, 0 allowed.

All: `language plpgsql stable`; `has_facility_role(p_facility_id, array['owner','manager','staff']::facility_role[])` → raise `42501` "Not authorized for this facility."; dates via `resolve_finance_date_range`; `range_ @> start_time`; `(p_facility_sport_id is null or facility_sport_id = p_facility_sport_id)`; `(p_court_id is null or court_id = p_court_id)`; `grant execute … to authenticated`.

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 2: Bookings.
--
-- Four read-only aggregates over `bookings` (the authoritative record — this
-- never decides what a booking's status or customer type is, it counts what
-- is already there). Same parameter shape as every analytics RPC:
--   p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_id,
--   p_court_id  [, p_granularity]
-- Dates resolve through resolve_finance_date_range so "This Month" means the
-- same window as Finance. Bookings are dated by start_time.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_booking_analytics(
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
  guest_count bigint,
  member_count bigint,
  avg_guest_booking_value_minor bigint
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
  with b as (
    select bk.status::text as status, bk.customer_type, bk.amount_minor, bk.payment_status
    from bookings bk
    where bk.facility_id = p_facility_id
      and range_ @> bk.start_time
      and (p_facility_sport_id is null or bk.facility_sport_id = p_facility_sport_id)
      and (p_court_id is null or bk.court_id = p_court_id)
  )
  select
    count(*)::bigint,
    count(*) filter (where status = 'completed')::bigint,
    count(*) filter (where status = 'confirmed')::bigint,
    count(*) filter (where status = 'pending')::bigint,
    count(*) filter (where status = 'cancelled')::bigint,
    count(*) filter (where customer_type = 'GUEST')::bigint,
    count(*) filter (where customer_type = 'MEMBER')::bigint,
    coalesce(
      round(
        avg(amount_minor) filter (
          where customer_type = 'GUEST' and payment_status = 'PAID' and status <> 'cancelled'
        )
      )::bigint,
      0
    )
  from b;
end;
$$;

grant execute on function get_booking_analytics(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_booking_trend(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_granularity text default 'daily'
) returns table (
  bucket_date date,
  total bigint,
  completed bigint,
  cancelled bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  unit text;
  step interval;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if p_granularity not in ('daily', 'weekly', 'monthly') then
    raise exception 'Unknown granularity: %', p_granularity using errcode = '22023';
  end if;
  unit := case p_granularity when 'daily' then 'day' when 'weekly' then 'week' else 'month' end;
  step := case p_granularity when 'daily' then interval '1 day' when 'weekly' then interval '1 week' else interval '1 month' end;

  select coalesce(timezone, 'Asia/Kolkata') into tz from facilities where id = p_facility_id;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with buckets as (
    select generate_series(
      date_trunc(unit, lower(range_) at time zone tz),
      date_trunc(unit, (upper(range_) - interval '1 microsecond') at time zone tz),
      step
    )::date as bucket
  ),
  grouped as (
    select date_trunc(unit, bk.start_time at time zone tz)::date as bucket,
           count(*) as total,
           count(*) filter (where bk.status = 'completed') as completed,
           count(*) filter (where bk.status = 'cancelled') as cancelled
    from bookings bk
    where bk.facility_id = p_facility_id
      and range_ @> bk.start_time
      and (p_facility_sport_id is null or bk.facility_sport_id = p_facility_sport_id)
      and (p_court_id is null or bk.court_id = p_court_id)
    group by 1
  )
  select b.bucket,
         coalesce(g.total, 0)::bigint,
         coalesce(g.completed, 0)::bigint,
         coalesce(g.cancelled, 0)::bigint
  from buckets b
  left join grouped g on g.bucket = b.bucket
  order by b.bucket;
end;
$$;

grant execute on function get_booking_trend(uuid, text, date, date, uuid, uuid, text) to authenticated;


create or replace function get_bookings_by_sport(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  facility_sport_id uuid,
  sport_name text,
  booking_count bigint
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
  select
    fs.id,
    coalesce(fs.custom_sport_name, sp.name) as sport_name,
    count(bk.id)::bigint
  from facility_sports fs
  join sports sp on sp.id = fs.sport_id
  left join bookings bk
    on bk.facility_sport_id = fs.id
    and range_ @> bk.start_time
    and (p_court_id is null or bk.court_id = p_court_id)
  where fs.facility_id = p_facility_id
    and fs.is_active
    and (p_facility_sport_id is null or fs.id = p_facility_sport_id)
  group by fs.id, sport_name
  order by count(bk.id) desc, sport_name;
end;
$$;

grant execute on function get_bookings_by_sport(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_booking_source_split(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  source text,
  booking_count bigint
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
  with b as (
    select bk.customer_type
    from bookings bk
    where bk.facility_id = p_facility_id
      and range_ @> bk.start_time
      and (p_facility_sport_id is null or bk.facility_sport_id = p_facility_sport_id)
      and (p_court_id is null or bk.court_id = p_court_id)
  )
  select s.source, coalesce(count(b.customer_type), 0)::bigint
  from (values ('GUEST'), ('MEMBER')) as s(source)
  left join b on b.customer_type = s.source
  group by s.source
  order by s.source;
end;
$$;

grant execute on function get_booking_source_split(uuid, text, date, date, uuid, uuid) to authenticated;
```

- [ ] **Step 2: Parse-sanity**

Run: `node -e "const s=require('fs').readFileSync('supabase/migrations/0058_analytics_bookings.sql','utf8'); for (const f of ['get_booking_analytics','get_booking_trend','get_bookings_by_sport','get_booking_source_split']) if(!s.includes('function '+f)) throw new Error('missing '+f); console.log('ok')"`
Expected: `ok`

- [ ] **Step 3: Commit** (hold per standing instruction — stage only)

---

## Task 2: `database.types.ts` — four Functions entries

**Files:** Modify `src/types/database.types.ts`

- [ ] **Step 1:** In the `Functions` block (before its closing `};`, after `get_finance_transaction`), add:

```ts
      get_booking_analytics: {
        Args: { p_facility_id: string; p_preset?: string; p_start_date?: string | null; p_end_date?: string | null; p_facility_sport_id?: string | null; p_court_id?: string | null };
        Returns: { total: number; completed: number; confirmed: number; pending: number; cancelled: number; guest_count: number; member_count: number; avg_guest_booking_value_minor: number }[];
      };
      get_booking_trend: {
        Args: { p_facility_id: string; p_preset?: string; p_start_date?: string | null; p_end_date?: string | null; p_facility_sport_id?: string | null; p_court_id?: string | null; p_granularity?: string };
        Returns: { bucket_date: string; total: number; completed: number; cancelled: number }[];
      };
      get_bookings_by_sport: {
        Args: { p_facility_id: string; p_preset?: string; p_start_date?: string | null; p_end_date?: string | null; p_facility_sport_id?: string | null; p_court_id?: string | null };
        Returns: { facility_sport_id: string; sport_name: string; booking_count: number }[];
      };
      get_booking_source_split: {
        Args: { p_facility_id: string; p_preset?: string; p_start_date?: string | null; p_end_date?: string | null; p_facility_sport_id?: string | null; p_court_id?: string | null };
        Returns: { source: string; booking_count: number }[];
      };
```

- [ ] **Step 2:** `npm run typecheck` — no new errors.

---

## Task 3: `report-filter.ts` + service-error codes + types

**Files:**
- Create `src/features/reports/report-filter.ts` + `.test.ts`
- Modify `src/features/reports/types.ts`, `src/features/reports/definitions.ts`
- Modify `src/services/shared/service-error.ts`

**Interfaces — Produces:**
- `dateRangeArgs(f: AnalyticsFilter): { p_preset: string; p_start_date: string | null; p_end_date: string | null }`
- `scopeArgs(f: AnalyticsFilter): { p_facility_sport_id: string | null; p_court_id: string | null }`
- `interface BookingAnalytics { total; completed; confirmed; pending; cancelled; guestCount; memberCount; avgGuestBookingValueMinor }` (all `number`)
- `interface BookingTrendPoint { date: string; total: number; completed: number; cancelled: number }`
- `interface BookingsBySportRow { facilitySportId: string; sportName: string; bookingCount: number }`
- `interface BookingSourceRow { source: "GUEST" | "MEMBER"; bookingCount: number }`
- `ServiceErrorCode` gains `"REPORTS_ACCESS_DENIED" | "REPORTS_DATA_ERROR"`

- [ ] **Step 1: Write `report-filter.test.ts`**

```ts
import { describe, expect, it } from "vitest";
import { dateRangeArgs, scopeArgs } from "./report-filter";
import type { AnalyticsFilter } from "./types";

const base: AnalyticsFilter = { facilityId: "f1", preset: "THIS_MONTH" };

describe("dateRangeArgs", () => {
  it("passes the preset and nulls the custom dates for a preset range", () => {
    expect(dateRangeArgs(base)).toEqual({ p_preset: "THIS_MONTH", p_start_date: null, p_end_date: null });
  });
  it("passes explicit dates for CUSTOM", () => {
    expect(dateRangeArgs({ ...base, preset: "CUSTOM", startDate: "2026-09-01", endDate: "2026-09-15" })).toEqual({
      p_preset: "CUSTOM",
      p_start_date: "2026-09-01",
      p_end_date: "2026-09-15",
    });
  });
});

describe("scopeArgs", () => {
  it("nulls absent sport/court", () => {
    expect(scopeArgs(base)).toEqual({ p_facility_sport_id: null, p_court_id: null });
  });
  it("passes sport and court when set", () => {
    expect(scopeArgs({ ...base, facilitySportId: "fs-1", courtId: "c-2" })).toEqual({
      p_facility_sport_id: "fs-1",
      p_court_id: "c-2",
    });
  });
});
```

- [ ] **Step 2: Run — fails** (`Cannot find module './report-filter'`).

- [ ] **Step 3: Write `report-filter.ts`**

```ts
// ═══════════════════════════════════════════════════════════════════════════
// AnalyticsFilter -> RPC argument mapping. Every reports service method builds
// its args from these two helpers so the date-range and sport/court contract
// is defined in exactly one place (mirrors SupabaseFinanceService's inline
// dateRangeArgs).
// ═══════════════════════════════════════════════════════════════════════════

import type { AnalyticsFilter } from "./types";

export function dateRangeArgs(f: AnalyticsFilter): {
  p_preset: string;
  p_start_date: string | null;
  p_end_date: string | null;
} {
  const custom = f.preset === "CUSTOM";
  return {
    p_preset: f.preset,
    p_start_date: custom ? (f.startDate ?? null) : null,
    p_end_date: custom ? (f.endDate ?? null) : null,
  };
}

export function scopeArgs(f: AnalyticsFilter): {
  p_facility_sport_id: string | null;
  p_court_id: string | null;
} {
  return {
    p_facility_sport_id: f.facilitySportId ?? null,
    p_court_id: f.courtId ?? null,
  };
}
```

- [ ] **Step 4: Run — passes.**

- [ ] **Step 5: Append to `src/features/reports/types.ts`**

```ts
// ─── Phase 2: Bookings ────────────────────────────────────────────────────

export interface BookingAnalytics {
  total: number;
  completed: number;
  confirmed: number;
  pending: number;
  cancelled: number;
  guestCount: number;
  memberCount: number;
  /** Captured value of paid, non-cancelled guest bookings ÷ their count. */
  avgGuestBookingValueMinor: number;
}

export interface BookingTrendPoint {
  date: string;
  total: number;
  completed: number;
  cancelled: number;
}

export interface BookingsBySportRow {
  facilitySportId: string;
  sportName: string;
  bookingCount: number;
}

export interface BookingSourceRow {
  source: "GUEST" | "MEMBER";
  bookingCount: number;
}
```

- [ ] **Step 6: Reword `definitions.ts` `averageBookingValue`** to:

```ts
  averageBookingValue:
    "Total captured value of paid, non-cancelled guest bookings in the range, divided by their count. Unpaid and cancelled bookings are excluded from both.",
```

- [ ] **Step 7: `service-error.ts`** — add to the `ServiceErrorCode` union and `FRIENDLY_MESSAGE`:

```ts
  | "REPORTS_ACCESS_DENIED"
  | "REPORTS_DATA_ERROR"
```
```ts
  REPORTS_ACCESS_DENIED: "You don't have access to this facility's reports.",
  REPORTS_DATA_ERROR: "Unable to load this report. Please try again.",
```

- [ ] **Step 8:** `npm test -- src/features/reports/report-filter.test.ts` + `npm run typecheck`.

---

## Task 4: `src/services/reports/` — interface, Supabase impl, fake, tests

**Files:** Create `reports.service.ts`, `supabase-reports.service.ts`, `supabase-reports.service.test.ts`, `index.ts`, `src/test/fakes/fake-reports-service.ts`

**Interfaces — Produces:**
```ts
interface ReportsService {
  getBookingAnalytics(filter: AnalyticsFilter): Promise<BookingAnalytics>;
  getBookingTrend(filter: AnalyticsFilter, granularity: AnalyticsGranularity): Promise<BookingTrendPoint[]>;
  getBookingsBySport(filter: AnalyticsFilter): Promise<BookingsBySportRow[]>;
  getBookingSourceSplit(filter: AnalyticsFilter): Promise<BookingSourceRow[]>;
}
function getReportsService(): ReportsService;
function setReportsService(s: ReportsService | null): void;
```

- [ ] **Step 1: `reports.service.ts`** — the interface above, with a header comment ("every figure is server-computed; this only describes the shape").

- [ ] **Step 2: `index.ts`** — copy `src/services/finance/index.ts` exactly, swapping `Finance`→`Reports`.

- [ ] **Step 3: Write `supabase-reports.service.test.ts`**

```ts
import { describe, expect, it, vi } from "vitest";
import { SupabaseReportsService } from "@/services/reports/supabase-reports.service";
import { ServiceError } from "@/services/shared/service-error";
import type { AnalyticsFilter } from "@/features/reports/types";

const filter: AnalyticsFilter = { facilityId: "fac-1", preset: "THIS_MONTH" };

const ANALYTICS_ROW = {
  total: 205, completed: 120, confirmed: 60, pending: 5, cancelled: 20,
  guest_count: 130, member_count: 75, avg_guest_booking_value_minor: 55000,
};

describe("SupabaseReportsService.getBookingAnalytics", () => {
  it("calls get_booking_analytics with resolved date + scope args and maps the row", async () => {
    const rpc = vi.fn(async () => ({ data: [ANALYTICS_ROW], error: null }));
    const service = new SupabaseReportsService({ rpc } as never);

    const result = await service.getBookingAnalytics({ ...filter, facilitySportId: "fs-1" });

    expect(rpc).toHaveBeenCalledWith("get_booking_analytics", {
      p_facility_id: "fac-1",
      p_preset: "THIS_MONTH",
      p_start_date: null,
      p_end_date: null,
      p_facility_sport_id: "fs-1",
      p_court_id: null,
    });
    expect(result).toEqual({
      total: 205, completed: 120, confirmed: 60, pending: 5, cancelled: 20,
      guestCount: 130, memberCount: 75, avgGuestBookingValueMinor: 55000,
    });
  });

  it("maps a facility-isolation denial to REPORTS_ACCESS_DENIED (never a fake zero row)", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "Not authorized for this facility." } }));
    const service = new SupabaseReportsService({ rpc } as never);
    await expect(service.getBookingAnalytics(filter)).rejects.toMatchObject({ code: "REPORTS_ACCESS_DENIED" });
  });

  it("maps an invalid custom range to INVALID_DATE_RANGE", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "A custom date range requires a valid start and end date." } }));
    const service = new SupabaseReportsService({ rpc } as never);
    await expect(service.getBookingAnalytics({ ...filter, preset: "CUSTOM" })).rejects.toMatchObject({ code: "INVALID_DATE_RANGE" });
  });

  it("throws ServiceError, not a raw object", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "boom" } }));
    const service = new SupabaseReportsService({ rpc } as never);
    await expect(service.getBookingAnalytics(filter)).rejects.toThrow(ServiceError);
  });
});

describe("SupabaseReportsService.getBookingTrend", () => {
  it("passes the granularity and maps bucket rows", async () => {
    const rpc = vi.fn(async () => ({
      data: [{ bucket_date: "2026-09-01", total: 8, completed: 5, cancelled: 1 }],
      error: null,
    }));
    const service = new SupabaseReportsService({ rpc } as never);
    const result = await service.getBookingTrend(filter, "weekly");
    expect(rpc).toHaveBeenCalledWith("get_booking_trend", expect.objectContaining({ p_granularity: "weekly", p_facility_id: "fac-1" }));
    expect(result).toEqual([{ date: "2026-09-01", total: 8, completed: 5, cancelled: 1 }]);
  });
});

describe("SupabaseReportsService.getBookingsBySport / getBookingSourceSplit", () => {
  it("maps by-sport rows", async () => {
    const rpc = vi.fn(async () => ({ data: [{ facility_sport_id: "fs-1", sport_name: "Badminton", booking_count: 120 }], error: null }));
    const service = new SupabaseReportsService({ rpc } as never);
    expect(await service.getBookingsBySport(filter)).toEqual([{ facilitySportId: "fs-1", sportName: "Badminton", bookingCount: 120 }]);
  });
  it("maps source-split rows", async () => {
    const rpc = vi.fn(async () => ({ data: [{ source: "GUEST", booking_count: 130 }, { source: "MEMBER", booking_count: 75 }], error: null }));
    const service = new SupabaseReportsService({ rpc } as never);
    expect(await service.getBookingSourceSplit(filter)).toEqual([
      { source: "GUEST", bookingCount: 130 },
      { source: "MEMBER", bookingCount: 75 },
    ]);
  });
});
```

- [ ] **Step 4: Run — fails.**

- [ ] **Step 5: Write `supabase-reports.service.ts`**

```ts
"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type { Database } from "@/types/database.types";
import type { ReportsService } from "@/services/reports/reports.service";
import { ServiceError } from "@/services/shared/service-error";
import { dateRangeArgs, scopeArgs } from "@/features/reports/report-filter";
import type {
  AnalyticsFilter,
  AnalyticsGranularity,
  BookingAnalytics,
  BookingTrendPoint,
  BookingsBySportRow,
  BookingSourceRow,
} from "@/features/reports/types";

export class SupabaseReportsService implements ReportsService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  private baseArgs(f: AnalyticsFilter) {
    return { p_facility_id: f.facilityId, ...dateRangeArgs(f), ...scopeArgs(f) };
  }

  async getBookingAnalytics(filter: AnalyticsFilter): Promise<BookingAnalytics> {
    const { data, error } = await this.supabase.rpc("get_booking_analytics", this.baseArgs(filter));
    if (error || !data?.[0]) throw this.mapError(error);
    const r = data[0];
    return {
      total: r.total,
      completed: r.completed,
      confirmed: r.confirmed,
      pending: r.pending,
      cancelled: r.cancelled,
      guestCount: r.guest_count,
      memberCount: r.member_count,
      avgGuestBookingValueMinor: r.avg_guest_booking_value_minor,
    };
  }

  async getBookingTrend(filter: AnalyticsFilter, granularity: AnalyticsGranularity): Promise<BookingTrendPoint[]> {
    const { data, error } = await this.supabase.rpc("get_booking_trend", {
      ...this.baseArgs(filter),
      p_granularity: granularity,
    });
    if (error) throw this.mapError(error);
    return (data ?? []).map((r) => ({
      date: r.bucket_date,
      total: r.total,
      completed: r.completed,
      cancelled: r.cancelled,
    }));
  }

  async getBookingsBySport(filter: AnalyticsFilter): Promise<BookingsBySportRow[]> {
    const { data, error } = await this.supabase.rpc("get_bookings_by_sport", this.baseArgs(filter));
    if (error) throw this.mapError(error);
    return (data ?? []).map((r) => ({
      facilitySportId: r.facility_sport_id,
      sportName: r.sport_name,
      bookingCount: r.booking_count,
    }));
  }

  async getBookingSourceSplit(filter: AnalyticsFilter): Promise<BookingSourceRow[]> {
    const { data, error } = await this.supabase.rpc("get_booking_source_split", this.baseArgs(filter));
    if (error) throw this.mapError(error);
    return (data ?? []).map((r) => ({
      source: r.source as "GUEST" | "MEMBER",
      bookingCount: r.booking_count,
    }));
  }

  private mapError(error: unknown): ServiceError {
    console.error("[reports-service] request failed", error);
    const message = (error as { message?: string } | null)?.message;
    if (message?.includes("Not authorized")) return new ServiceError("REPORTS_ACCESS_DENIED");
    if (message?.includes("valid start and end date")) return new ServiceError("INVALID_DATE_RANGE");
    return new ServiceError("REPORTS_DATA_ERROR");
  }
}
```

- [ ] **Step 6: Run — passes.**

- [ ] **Step 7: `src/test/fakes/fake-reports-service.ts`**

```ts
import type { ReportsService } from "@/services/reports/reports.service";
import { setReportsService } from "@/services/reports";
import type {
  AnalyticsFilter,
  AnalyticsGranularity,
  BookingAnalytics,
  BookingTrendPoint,
  BookingsBySportRow,
  BookingSourceRow,
} from "@/features/reports/types";

const EMPTY_ANALYTICS: BookingAnalytics = {
  total: 0, completed: 0, confirmed: 0, pending: 0, cancelled: 0,
  guestCount: 0, memberCount: 0, avgGuestBookingValueMinor: 0,
};

export class FakeReportsService implements ReportsService {
  bookingAnalytics: BookingAnalytics = EMPTY_ANALYTICS;
  bookingTrend: BookingTrendPoint[] = [];
  bookingsBySport: BookingsBySportRow[] = [];
  bookingSourceSplit: BookingSourceRow[] = [];
  error: Error | null = null;

  async getBookingAnalytics(_f: AnalyticsFilter): Promise<BookingAnalytics> {
    if (this.error) throw this.error;
    return this.bookingAnalytics;
  }
  async getBookingTrend(_f: AnalyticsFilter, _g: AnalyticsGranularity): Promise<BookingTrendPoint[]> {
    if (this.error) throw this.error;
    return this.bookingTrend;
  }
  async getBookingsBySport(_f: AnalyticsFilter): Promise<BookingsBySportRow[]> {
    if (this.error) throw this.error;
    return this.bookingsBySport;
  }
  async getBookingSourceSplit(_f: AnalyticsFilter): Promise<BookingSourceRow[]> {
    if (this.error) throw this.error;
    return this.bookingSourceSplit;
  }
}

export function installFakeReportsService(): FakeReportsService {
  const service = new FakeReportsService();
  setReportsService(service);
  return service;
}
```

---

## Task 5: shared `<ReportBarList>` + `<DataTable>` + `<BookingTrendChart>`

**Files:** Create `report-bar-list.tsx` (+test), `data-table.tsx` (+test), `booking-trend-chart.tsx`

**Interfaces — Produces:**
- `<ReportBarList items={{ label: string; value: number; color?: string; caption?: string }[]} max?: number />` — horizontal bars, each width `value/max` (max defaults to the largest value), value right-aligned. Purely presentational.
- `<DataTable columns={{ key: string; label: string; align?: "left" | "right" }[]} rows={Record<string, string | number>[]} caption: string />` — a plain `<table>` with `<caption className="sr-only">`, `scope="col"`, `overflow-x-auto` wrapper.
- `<BookingTrendChart points={BookingTrendPoint[]} />` — Recharts `AreaChart`, `total` as the filled series (`#00F08A`), `cancelled` as a thin line (`#FF4D67`); `role="img"`, `aria-label="Booking volume trend"`; empty → muted "No bookings in this period."

- [ ] **Step 1: `report-bar-list.test.tsx`**

```tsx
import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { ReportBarList } from "./report-bar-list";

describe("ReportBarList", () => {
  it("renders a labelled row per item with its value", () => {
    render(<ReportBarList items={[{ label: "Badminton", value: 120 }, { label: "Football", value: 60 }]} />);
    expect(screen.getByText("Badminton")).toBeInTheDocument();
    expect(screen.getByText("120")).toBeInTheDocument();
  });

  it("sizes each bar relative to the largest value", () => {
    const { container } = render(
      <ReportBarList items={[{ label: "A", value: 100 }, { label: "B", value: 25 }]} />,
    );
    const bars = container.querySelectorAll("[data-bar]");
    expect((bars[0] as HTMLElement).style.width).toBe("100%");
    expect((bars[1] as HTMLElement).style.width).toBe("25%");
  });
});
```

- [ ] **Step 2: `report-bar-list.tsx`**

```tsx
"use client";

export interface ReportBar {
  label: string;
  value: number;
  color?: string;
  caption?: string;
}

/** Labelled horizontal bars — the readable companion to a chart, and the
 *  whole widget where a chart would be overkill (spec §7, §14, §42). */
export function ReportBarList({ items, max }: { items: ReportBar[]; max?: number }) {
  const peak = Math.max(max ?? 0, ...items.map((i) => i.value), 1);
  return (
    <ul className="space-y-2.5">
      {items.map((item) => (
        <li key={item.label} className="space-y-1">
          <div className="flex items-baseline justify-between gap-3 text-sm">
            <span className="truncate">{item.label}</span>
            <span className="shrink-0 font-medium tabular-nums">
              {item.caption ?? item.value.toLocaleString("en-IN")}
            </span>
          </div>
          <div className="h-2 overflow-hidden rounded-full bg-muted">
            <div
              data-bar
              className="h-full rounded-full"
              style={{
                width: `${Math.round((item.value / peak) * 100)}%`,
                backgroundColor: item.color ?? "var(--primary)",
              }}
            />
          </div>
        </li>
      ))}
    </ul>
  );
}
```

- [ ] **Step 3: Run — passes.**

- [ ] **Step 4: `data-table.test.tsx`**

```tsx
import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { DataTable } from "./data-table";

describe("DataTable", () => {
  it("renders headers, rows and an accessible caption", () => {
    render(
      <DataTable
        caption="Bookings by sport"
        columns={[{ key: "sport", label: "Sport" }, { key: "count", label: "Bookings", align: "right" }]}
        rows={[{ sport: "Badminton", count: 120 }, { sport: "Football", count: 60 }]}
      />,
    );
    expect(screen.getByRole("table", { name: "Bookings by sport" })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "Sport" })).toBeInTheDocument();
    expect(screen.getByRole("cell", { name: "120" })).toBeInTheDocument();
  });
});
```

- [ ] **Step 5: `data-table.tsx`**

```tsx
"use client";

export interface DataColumn {
  key: string;
  label: string;
  align?: "left" | "right";
}

/** The precise, accessible companion under every report chart (spec §42/§54). */
export function DataTable({
  columns,
  rows,
  caption,
}: {
  columns: DataColumn[];
  rows: Array<Record<string, string | number>>;
  caption: string;
}) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <caption className="sr-only">{caption}</caption>
        <thead>
          <tr className="border-b border-border text-left text-xs text-muted-foreground">
            {columns.map((c) => (
              <th
                key={c.key}
                scope="col"
                className={`py-2 pr-3 font-medium ${c.align === "right" ? "text-right" : ""}`}
              >
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr key={i} className="border-b border-border last:border-0">
              {columns.map((c) => (
                <td
                  key={c.key}
                  className={`py-2.5 pr-3 tabular-nums ${c.align === "right" ? "text-right" : ""}`}
                >
                  {typeof row[c.key] === "number"
                    ? (row[c.key] as number).toLocaleString("en-IN")
                    : (row[c.key] ?? "—")}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
```

- [ ] **Step 6: Run — passes.**

- [ ] **Step 7: `booking-trend-chart.tsx`** — copy `revenue-trend-chart.tsx`, swap: data type `BookingTrendPoint`, `dataKey="total"` stroke/fill `#00F08A` (gradient id `bookingTotalGradient`), add a second `<Area dataKey="cancelled" stroke="#FF4D67" fill="none" strokeWidth={1.5} dot={false} />`, Y axis is a plain integer count (`tickFormatter={(v) => `${v}`}`, `allowDecimals={false}`), tooltip `formatter={(value: number, name) => [value, name === "total" ? "Bookings" : "Cancelled"]}`. `aria-label="Booking volume trend"`. Empty-state text "No bookings in this period."

- [ ] **Step 8:** `npm test -- src/features/reports/components/report-bar-list.test.tsx src/features/reports/components/data-table.test.tsx` + `npm run typecheck`.

---

## Task 6: `<BookingReport>` — the assembled report

**Files:** Rewrite `src/features/reports/components/booking-report.tsx`; create `booking-report.test.tsx`

**Interfaces — Consumes:** `useAnalyticsFilter`, `AnalyticsFilterBar`, `AnalyticsFilterSheet`, `ReportShell`, `KpiStrip`, `ReportBarList`, `DataTable`, `BookingTrendChart`, `getReportsService`, `pickGranularity` + `previousPeriod` + `toCsv` from `../aggregation`, `formatCurrency`.

**Behaviour:**
- On `ready` filter, fetch all four RPCs in parallel (`Promise.all`) — plus a second `getBookingAnalytics(previousPeriod(filter))` for the KPI deltas (swallowed on failure, like `finance-dashboard.tsx`).
- Granularity for the trend = `pickGranularity` on the resolved range. For a preset the client can't resolve to dates, default `daily` and let the RPC's own range drive it — **actually** always pass `pickGranularity(resolved.start, resolved.end)`; get the resolved dates by asking the trend RPC? No — pass `"daily"` for day-level presets and derive for CUSTOM. **Decision:** add a tiny `presetSpanDays(preset)` map in `aggregation.ts` (TODAY→1, YESTERDAY→1, THIS_WEEK/LAST_WEEK→7, THIS_MONTH/LAST_MONTH→31, THIS_QUARTER→92, THIS_YEAR→365, CUSTOM→spanDays(dates)) and feed that to `pickGranularity`-by-days. Add `pickGranularityForDays(days)` alongside `pickGranularity`.
- **status** = `"loading"` until the four resolve; `"error"` on any rejection (with `onRetry` re-running the load); `"empty"` when `analytics.total === 0`; else `"ready"`.
- KPI strip: Total / Completed / Confirmed / Pending / Cancelled bookings + Avg Guest Booking Value (`formatCurrency(avgGuestBookingValueMinor, "INR")`). Deltas vs previous period where available.
- Trend `<Card>`: `<BookingTrendChart>` + `<DataTable caption="Bookings over time" columns=[date,total,completed,cancelled]>`.
- By-sport `<Card>`: `<ReportBarList>` (bar colour `#00F08A`) + `<DataTable caption="Bookings by sport">`. Each sport row links to `/reports/bookings?…&sport=<fsId>` via the bar list? Keep bars presentational; put the drill-down on the table rows (a `<Link>` in the sport cell) — spec §28. (If wiring a link into `DataTable` is awkward, defer drill-down to Phase 8 and leave a `// TODO(phase 8): sport drill-down` — **no**, do it: pass an optional `href?: (row) => string` to `DataTable` that wraps the first cell in a `<Link>`.)
- Source split `<Card>`: `<ReportBarList>` with Guest `#FFB020` / Member `#8B5CF6`.
- `onExportCsv`: `toCsv` of a flat summary (one section per widget, or just the KPI + by-sport + source rows concatenated) → `Blob` → `URL.createObjectURL` → click a temp `<a download>` — copy the exact download snippet from wherever the app already does a client download (search `createObjectURL`; `add-expense`/receipt flows). Filename: `bookings-<facilityId>-<preset>.csv`.

- [ ] **Step 1: Add `pickGranularityForDays` + `presetSpanDays` to `aggregation.ts`** (+ tests in `aggregation.test.ts`):

```ts
export function pickGranularityForDays(days: number): AnalyticsGranularity {
  if (days <= 31) return "daily";
  if (days <= 183) return "weekly";
  return "monthly";
}

const PRESET_SPAN_DAYS: Record<Exclude<AnalyticsPreset, "CUSTOM">, number> = {
  TODAY: 1, YESTERDAY: 1, THIS_WEEK: 7, LAST_WEEK: 7,
  THIS_MONTH: 31, LAST_MONTH: 31, THIS_QUARTER: 92, THIS_YEAR: 365,
};

export function filterSpanDays(f: AnalyticsFilter): number {
  if (f.preset === "CUSTOM") {
    return f.startDate && f.endDate ? spanDays(f.startDate, f.endDate) : 31;
  }
  return PRESET_SPAN_DAYS[f.preset];
}
```
Tests: `pickGranularityForDays(31) === "daily"`, `(32) === "weekly"`, `(184) === "monthly"`; `filterSpanDays({preset:"THIS_QUARTER"}) === 92`; `filterSpanDays({preset:"CUSTOM", startDate:"2026-09-01", endDate:"2026-09-10"}) === 10`.

- [ ] **Step 2: Write `booking-report.test.tsx`**

```tsx
import { describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { BookingReport } from "./booking-report";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";
import { installFakeReportsService } from "@/test/fakes/fake-reports-service";

function setup() {
  installFakeReportsFilterDeps();
  const reports = installFakeReportsService();
  return reports;
}

describe("BookingReport", () => {
  it("shows the empty state when there are no bookings", async () => {
    setup();
    render(<BookingReport />);
    expect(await screen.findByText("No booking data for this period.")).toBeInTheDocument();
  });

  it("renders KPIs, the trend table and the by-sport table when there is data", async () => {
    const reports = setup();
    reports.bookingAnalytics = {
      total: 205, completed: 120, confirmed: 60, pending: 5, cancelled: 20,
      guestCount: 130, memberCount: 75, avgGuestBookingValueMinor: 55000,
    };
    reports.bookingTrend = [{ date: "2026-09-01", total: 8, completed: 5, cancelled: 1 }];
    reports.bookingsBySport = [
      { facilitySportId: "fs-1", sportName: "Badminton", bookingCount: 120 },
      { facilitySportId: "fs-2", sportName: "Football", bookingCount: 85 },
    ];
    reports.bookingSourceSplit = [
      { source: "GUEST", bookingCount: 130 },
      { source: "MEMBER", bookingCount: 75 },
    ];

    render(<BookingReport />);

    expect(await screen.findByText("205")).toBeInTheDocument(); // total
    expect(screen.getByText("120")).toBeInTheDocument(); // completed KPI + badminton — at least present
    expect(screen.getByRole("table", { name: /bookings by sport/i })).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /bookings over time/i })).toBeInTheDocument();
    expect(screen.getByText("₹550.00")).toBeInTheDocument(); // avg guest booking value
  });

  it("shows an error state with a retry that re-fetches", async () => {
    const reports = setup();
    reports.error = new Error("boom");
    render(<BookingReport />);
    expect(await screen.findByText(/unable to load/i)).toBeInTheDocument();

    reports.error = null;
    reports.bookingAnalytics = { ...reports.bookingAnalytics, total: 3 };
    await userEvent.click(screen.getByRole("button", { name: /try again/i }));
    await waitFor(() => expect(screen.queryByText(/unable to load/i)).not.toBeInTheDocument());
  });

  it("offers a CSV download once data is loaded", async () => {
    const reports = setup();
    reports.bookingAnalytics = { ...reports.bookingAnalytics, total: 10 };
    render(<BookingReport />);
    expect(await screen.findByRole("button", { name: /download csv/i })).toBeInTheDocument();
  });
});
```

- [ ] **Step 3: Run — fails.**

- [ ] **Step 4: Write `booking-report.tsx`** — assemble per the Behaviour section. Structure mirrors `finance-dashboard.tsx`: `useAnalyticsFilter` → `load` callback (`Promise.all` of the four + previous-period analytics) → `useEffect` calling it → status derivation → `ReportShell` with `filterBar`, `onExportCsv`, `onRetry`. KPI strip via `<KpiStrip>`. Three `<Card>`s. Use `data-testid` sparingly; prefer role queries.

- [ ] **Step 5: Run — passes.**

- [ ] **Step 6: full verification** — `npm test` (reports suite green + no *new* full-suite failures), `npm run typecheck`, `npm run lint`, `npm run build`.

- [ ] **Step 7: Manual DB verification (reviewer, against linked Supabase)** — apply `0056` + `0058`, seed the §50 fixture (Champz Turf, 03 Sep 2026: 3 guest bookings — 2 paid ₹400+₹600, 1 pending ₹800 — statuses confirmed), then:

```sql
select * from get_booking_analytics('<champz-id>', 'CUSTOM', '2026-09-03', '2026-09-03', null, null);
-- expect: total 3, confirmed 3, completed 0, cancelled 0, guest_count 3, member_count 0,
--         avg_guest_booking_value_minor = 50000  (avg of the two PAID: (40000+60000)/2)
select * from get_booking_source_split('<champz-id>', 'CUSTOM', '2026-09-03', '2026-09-03', null, null);
-- expect: GUEST 3, MEMBER 0
select * from get_bookings_by_sport('<champz-id>', 'THIS_MONTH', null, null, null, null);
-- expect: one row per active facility sport, badminton (or whichever) = 3, others 0
select * from get_booking_trend('<champz-id>', 'THIS_MONTH', null, null, null, null, 'daily');
-- expect: one row per day of the month; 2026-09-03 total=3, every other day total=0
```

Cross-facility: `get_booking_analytics('<other-facility>', …)` as a Champz-only user → **raises "Not authorized"**, not a zero row.

---

## Self-Review

**Spec coverage:** §9 booking totals + by-sport + trend → Tasks 1, 6. §10 status breakdown → `get_booking_analytics` + KPI strip + trend series. §11 source split (Guest/Member, no OTHER) → `get_booking_source_split`. §22 avg booking value (documented, excludes cancelled/unpaid) → definition reworded + SQL. §28 drill-down (sport → filtered) → `DataTable` `href`. §29 chart tooltips/labels/data-table companion → `BookingTrendChart` + `DataTable`. §42 supporting tables → `DataTable` under every chart. §43/§44/§45 states → `ReportShell` wiring. §49 tests 4 (booking count), 5 (completed), 6 (cancelled), 7 (guest count), 17–20 (filters), 21 (comparison), 23 (RLS) → service + component + manual tasks.

**Placeholder scan:** Task 6 Step 4 says "assemble per the Behaviour section" rather than pasting the full component — acceptable because every piece it composes (`ReportShell`, `KpiStrip`, the three cards, the `load`/status pattern) is fully specified here or lifted verbatim from `finance-dashboard.tsx`, which the step names. If the implementer wants it spelled out, `finance-dashboard.tsx` is the template.

**Type consistency:** `BookingAnalytics` / `BookingTrendPoint` / `BookingsBySportRow` / `BookingSourceRow` identical across `types.ts`, the service, the fake, and the component. RPC arg object identical between `report-filter.ts`, the service, and the service test's `toHaveBeenCalledWith`. `AnalyticsGranularity` reused from Phase 1.
