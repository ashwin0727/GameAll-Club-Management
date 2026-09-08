# Reports & Analytics — a read/analytics layer over Bookings, Memberships and Finance

**Date:** 2026-09-03
**Status:** Draft — awaiting review
**Branch:** `feat/reports-analytics` (isolated clone at `C:/Users/umash/gameall-reports-analytics`, outside OneDrive — the audit machine shares the OneDrive `main` and must not be disturbed)
**Related:** Finance module migrations `0024`–`0055`; client-side dashboard math in `src/features/dashboard/summary.ts`; operating-hours model `0004`; membership sessions `0014`/`0045`.

## Problem

GameAll has Bookings, Availability, Courts, Sports, Memberships, Membership Sessions,
Guest Release, Finance (transactions / expenses / refunds / pending payments) — but no
place for an owner to answer *what happened, why, and which parts of the business are
performing*. The only analytics today are computed **client-side** in
`src/features/dashboard/summary.ts` (utilization, peak hours, revenue trend, membership
summary) from raw rows fetched into the browser — the exact pattern the Reports brief
forbids at any real data volume.

Finance already solved money analytics the right way: `stable` plpgsql RPCs, each
`has_facility_role`-guarded, funnelling dates through `resolve_finance_date_range`, money
in minor units, never summed in the client. Reports & Analytics extends that pattern to
bookings, utilization, memberships and sessions, and **reuses the Finance RPCs unchanged**
for every monetary figure.

## Non-negotiables (from the brief)

- **No new business logic.** Reports never decides whether a booking is valid, a payment
  succeeded, a membership is active, or a slot is released. It consumes authoritative data.
- **No duplicate datasets.** No second booking/finance/membership/payment store. No
  materialized views unless a measured need appears (none is expected).
- **Server-side aggregation.** The browser/app never loads raw records to compute a KPI.
- **Finance stays authoritative for realized money.** If `get_finance_summary` says
  revenue is ₹100,000, Reports shows ₹100,000. Cash/collection basis — a pending booking
  amount is never realized revenue.
- **Facility isolation + RLS.** Every RPC re-checks `has_facility_role(...)` and returns a
  clear denial (never a fabricated zero). Public users: zero access.

## Approach

**Backend:** new migrations `0056`+ adding one RPC per report widget-group, all sharing a
single parameter shape. No new tables. Two small shared SQL helpers for the availability
math (the range-aggregate companions to `booking_window_fits_operating_hours`, reading the
*same* `operating_schedules`/`operating_days`/`operating_time_slots` tables with the *same*
per-court-override-then-facility precedence). `resolve_finance_date_range` gains
`THIS_QUARTER` + `THIS_YEAR` (additive; Finance UI doesn't expose them).

**Web:** a new feature module mirroring Finance exactly —
`src/features/reports/`, `src/services/reports/`, `src/app/(dashboard)/reports/**` —
one top-level **Reports** nav section with six children. Recharts, existing `StatCard` /
`Donut` / `Skeleton` / design tokens. A shared `<AnalyticsFilterBar>` (desktop) +
bottom-sheet variant (mobile). CSV export generated client-side from the (small) aggregate
payloads.

**Flutter:** Phase 9+ (own follow-up), reusing the identical RPCs via a
`reports_repository.dart` + `features/reports/`, hand-painted charts like
`revenue_trend_chart.dart`. Out of scope for this spec beyond the rollout note.

**The existing owner dashboard (`src/features/dashboard`) is left untouched.** Its
`summary.ts` math is *ported to SQL* for Reports; the file itself stays as-is.

## Shared filter model

```ts
// src/features/reports/types.ts
interface AnalyticsFilter {
  facilityId: string;          // never trusted from URL alone — RLS is the gate
  preset: AnalyticsPreset;     // TODAY | YESTERDAY | THIS_WEEK | LAST_WEEK
                               // | THIS_MONTH | LAST_MONTH | THIS_QUARTER | THIS_YEAR | CUSTOM
  startDate?: string | null;   // CUSTOM only
  endDate?: string | null;
  sportId?: string | null;     // facility_sport_id
  courtId?: string | null;
}
```

Default preset **THIS_MONTH**. Every RPC takes
`p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_id, p_court_id` (the
last two nullable = "no filter"). The service layer maps `AnalyticsFilter` → these args in
one place (`dateRangeArgs` + `scopeArgs`), exactly like `SupabaseFinanceService`.

### Automatic date aggregation (`groupBy`)

Chosen client-side from the resolved span and passed as `p_granularity` to the trend RPCs:

| Span | Granularity |
|---|---|
| ≤ 31 days | `daily` |
| 32–183 days | `weekly` |
| > 183 days | `monthly` |

(User can override on charts that expose a granularity selector, as Finance's trend does.)

## KPI definitions (authoritative — documented in each RPC's header comment and in `src/features/reports/definitions.ts`)

| KPI | Definition | Source |
|---|---|---|
| **Total Bookings** | `count(bookings)` whose `start_time` ∈ range, facility/sport/court filtered, **all statuses** (cancelled included, shown as its own slice). | `bookings` |
| **Completed / Cancelled / Confirmed / Pending Bookings** | same, filtered to `status = 'completed' / 'cancelled' / 'confirmed' / 'pending'`. Enum `booking_status` — never invented. | `bookings` |
| **Booking Revenue** | realized member-booking + guest-booking payments in range. | `get_revenue_breakdown` (`member_booking_revenue_minor + guest_booking_revenue_minor`) |
| **Membership Revenue** | realized membership payments in range. Session *usage* is never revenue. | `get_revenue_breakdown.membership_revenue_minor` |
| **Total Revenue** | `get_finance_summary.gross_revenue_minor` — sum of `payments.status='paid'` in range. Cash basis. | Finance |
| **Total Expenses** | `get_finance_summary.expenses_minor`. | Finance (`expenses`) |
| **Net Revenue** | `get_finance_summary.net_revenue_minor` = gross − refunds − expenses. Refund handling follows Finance. | Finance |
| **Outstanding Payments** | `get_pending_payments_summary.outstanding_minor`. Category split from `list_pending_payments.source_type` (`GUEST_BOOKING` → Guest, `MEMBERSHIP` → Membership, `BOOKING` → Other). | Finance / Pending Payments |
| **Court Utilization** | `Σ booked_minutes ÷ Σ open_minutes`, capped 100%. **Booked** = non-cancelled `bookings` duration overlapping range + `membership_sessions` (full `[start_time,end_time]` on `session_date`) that have ≥1 `CONFIRMED` `membership_session_bookings`. **Open** = operating minutes from the court's schedule (PLAYING_AREA override if present, else FACILITY) summed over each date in range. No maintenance table exists → open = bookable. Ported from `summary.ts::computeUtilization`, made per-court-schedule-aware to match `booking_window_fits_operating_hours`. | `bookings`, `membership_sessions`, `operating_*` |
| **Sport Utilization** | same, grouped by `facility_sport_id` (courts of that sport). | ″ |
| **Peak Hours** | per local hour-of-day: `booked_minutes_in_hour ÷ open_minutes_in_hour` over the range. Hours the facility is closed → excluded (not shown as 0% demand). | ″ |
| **Demand Heatmap** | `booked_minutes` by (day-of-week × hour-of-day) ÷ open_minutes for that cell. Encoded with a label + tooltip + intensity, never colour alone. | ″ |
| **Average Booking Value** | realized guest-booking revenue ÷ `count(paid guest bookings)` in range. "Paid" = booking has a `payments.status='paid'` row (or `bookings.payment_status='PAID'`). Never divided by cancelled/unpaid. | `bookings` + Finance |
| **Payment Collection Rate** | `collected ÷ (collected + outstanding)` for the range/scope. Pending ≠ collected. | Finance |
| **Active Members** | `count(memberships WHERE status='active')` as of now, facility filtered. | `memberships` |
| **New Memberships** | `count(memberships WHERE created_at ∈ range)`. | `memberships` |
| **Expiring Memberships** | `status='active' AND end_date ∈ [today, today+30d]`. | `memberships` |
| **Membership Session Utilization** | `Σ (member_booked + guest_booked) ÷ Σ capacity` over sessions with `session_date ∈ range`. | `membership_sessions` + bookings |
| **Guest Released / Booked / Remaining** | `Σ released_capacity` / `Σ CONFIRMED guest slot bookings` / difference, over sessions in range. | `membership_sessions`, `membership_session_bookings` |
| **Guest Release Revenue** | realized payments classified `GUEST_BOOKING` via `membership_session_booking_id` (per `0051`). | Finance |

## Backend — migrations

### `0056_analytics_date_presets.sql`

`create or replace function resolve_finance_date_range(...)` — add two branches:

- `THIS_QUARTER` → `date_trunc('quarter', today)` .. `+ 3 months`
- `THIS_YEAR` → `date_trunc('year', today)` .. `+ 1 year`

Everything else byte-identical. `0024` is never edited. Backwards compatible: every existing
caller passes one of the known presets and is unaffected.

### `0057_analytics_availability.sql` — the shared availability aggregates

Two `stable` functions, reading only `operating_schedules` / `operating_days` /
`operating_time_slots` (+ `courts`, `facilities` for tz), with the **same** override
precedence as `booking_window_fits_operating_hours`:

```
analytics_court_open_minutes(p_court_id uuid, p_range tstzrange)
  returns integer                       -- total bookable minutes for this court over the range

analytics_court_open_minutes_by_cell(p_court_id uuid, p_range tstzrange)
  returns table (dow smallint, hour smallint, minutes integer)
                                        -- for peak-hours / heatmap denominators
```

Day math mirrors `summary.ts::operatingMinutesForDay` exactly: closed → 0; 24h → 1440;
else Σ slot `(end−start, +1440 if crosses_midnight)`. Iterates local calendar dates in
`p_range` using the facility timezone.

### `0058_analytics_bookings.sql`

- `get_booking_analytics(...)` → `table (total, completed, confirmed, pending, cancelled,
  guest_count, member_count, other_count, avg_guest_booking_value_minor)`
- `get_booking_trend(..., p_granularity)` → `table (bucket_date date, total bigint,
  completed bigint, cancelled bigint)`
- `get_bookings_by_sport(...)` → `table (facility_sport_id uuid, sport_name text,
  booking_count bigint)` (only sports that exist for the facility; zero rows dropped)
- `get_booking_source_split(...)` → `table (source text, booking_count bigint)`
  (`source` ∈ `GUEST | MEMBER`, from `bookings.customer_type` — the enum has exactly these
  two values; no `OTHER` is invented. Released-seat session guests are **not** `bookings`
  rows and are reported only in the membership-session analytics, not here.)

All filter `bookings` by `start_time ∈ range`, `facility_id`, and optionally
`facility_sport_id` / `court_id`.

### `0059_analytics_utilization.sql`

- `get_court_utilization(...)` → `table (court_id uuid, court_name text,
  facility_sport_id uuid, sport_name text, open_minutes int, booked_minutes int,
  utilization_pct numeric)` — one row per active court; caller sorts.
- `get_sport_utilization(...)` → same shape keyed by sport.
- `get_overall_utilization(...)` → `table (open_minutes bigint, booked_minutes bigint,
  utilization_pct numeric)`
- `get_peak_hours(...)` → `table (hour smallint, open_minutes int, booked_minutes int,
  demand_pct numeric)` (closed hours omitted)
- `get_demand_heatmap(...)` → `table (dow smallint, hour smallint, demand_pct numeric,
  booked_minutes int)`

Booked minutes = non-cancelled `bookings` overlap-clipped to the range + `membership_sessions`
with ≥1 `CONFIRMED` slot booking (session occupies its court for its full window on
`session_date`). Sport/court filters apply.

### `0060_analytics_memberships.sql`

- `get_membership_analytics(...)` → `table (active_members bigint, new_memberships bigint,
  expiring_soon bigint, membership_revenue_minor bigint, paid_count bigint,
  partially_paid_count bigint, pending_count bigint, outstanding_minor bigint)`
- `get_memberships_by_type(...)` → `table (membership_type text, plan_name text,
  count bigint, revenue_minor bigint)` (group by `memberships.membership_type`, plan name
  when linked)
- `get_membership_session_analytics(...)` → `table (session_count bigint,
  total_capacity bigint, member_allocations bigint, guest_released bigint,
  guest_booked bigint, remaining_released bigint, unused_capacity bigint)` — sessions with
  `session_date ∈ range`, sport/court filtered. `unused_capacity = total_capacity −
  member_allocations − guest_booked` (matches brief §19 arithmetic).
- `get_guest_release_analytics(...)` → `table (released bigint, booked bigint,
  remaining bigint, revenue_minor bigint)` — revenue from Finance
  (`payments.membership_session_booking_id` → `GUEST_BOOKING`, per `0051`).

Membership revenue / paid / outstanding reuse `get_revenue_breakdown` +
`list_pending_payments` internally rather than re-summing `payments`.

**Deferred:** *Membership Retention* (§17) — there is no renewal-linkage field on
`memberships`, so a reliable renewed-vs-lapsed figure isn't available without heuristics.
Omitted from v1; revisit if a `renewed_from` link is added. *Active Sessions* (§19) is
folded into `session_count` (materialised sessions in range) rather than surfaced as a
separate number.

### `0061_analytics_revenue_dimensions.sql`

- `get_revenue_by_sport(...)` → `table (facility_sport_id uuid, sport_name text,
  revenue_minor bigint)` — **court-attributable** paid revenue only:
  `payments.booking_id → bookings → courts.facility_sport_id`, plus
  `payments.membership_session_booking_id → membership_sessions.facility_sport_id`.
  `status='paid'`, `effective_at ∈ range`.
- `get_revenue_by_court(...)` → same keyed by `court_id`.

Membership revenue is **not** sport/court attributed (a membership is not inherently
court-scoped) — the Revenue report shows it as its own row alongside the sport rows, using
`get_revenue_breakdown.membership_revenue_minor`. The by-sport/court totals plus the
membership row reconcile to `gross_revenue_minor` (any residual = "Other").

(These two are the only genuinely new revenue cuts — trend / breakdown / method / summary
all already exist in Finance and are called directly.)

### `0062_analytics_overview.sql`

`get_analytics_overview(...)` → one row with every headline KPI, composed by calling the
functions above + the Finance RPCs, so the Overview page makes **one** round trip:

```
gross_revenue_minor, booking_revenue_minor, membership_revenue_minor,
expenses_minor, net_revenue_minor, outstanding_minor,
total_bookings, completed_bookings, cancelled_bookings,
overall_utilization_pct
```

Each analytics RPC: `language plpgsql stable`, `has_facility_role(p_facility_id,
array['owner','manager','staff'])` at the top (raise `42501` otherwise), dates via
`resolve_finance_date_range`, `grant execute ... to authenticated`.

## Backend — types

`src/types/database.types.ts` is hand-written. Add a `Functions` entry per new RPC (args +
returns row shape) and any new view rows, matching the existing blocks. No generation step.

## Web — structure

```
src/app/(dashboard)/reports/
  page.tsx                     → <ReportsOverview/>
  bookings/page.tsx            → <BookingReport/>
  court-utilization/page.tsx   → <CourtUtilizationReport/>
  revenue/page.tsx             → <RevenueReport/>
  memberships/page.tsx         → <MembershipReport/>
  guest-bookings/page.tsx      → <GuestBookingReport/>

src/features/reports/
  types.ts                     AnalyticsFilter, all row types
  definitions.ts               exported KPI definition strings (rendered in tooltips)
  aggregation.ts + .test.ts    pickGranularity(span), previousPeriod(filter), csv(rows)
  components/
    analytics-filter-bar.tsx   facility / date / sport / court — desktop
    analytics-filter-sheet.tsx bottom-sheet variant (mobile)
    kpi-strip.tsx              horizontal-scroll KPI cards (reuses StatCard)
    report-shell.tsx           title + filter bar + loading/empty/error frame
    <one component per chart/table>

src/services/reports/
  reports.service.ts           interface
  supabase-reports.service.ts  + .test.ts   (mirrors SupabaseFinanceService)
  index.ts                     getReportsService()
```

`NAV_ITEMS` (in `src/lib/constants.ts`) gains, after Finance:

```ts
{
  label: "Reports", href: "/reports", roles: ["admin", "staff"],
  children: [
    { label: "Overview", href: "/reports" },
    { label: "Bookings", href: "/reports/bookings" },
    { label: "Court Utilization", href: "/reports/court-utilization" },
    { label: "Revenue", href: "/reports/revenue" },
    { label: "Memberships", href: "/reports/memberships" },
    { label: "Guest Bookings", href: "/reports/guest-bookings" },
  ],
}
```

`sidebar.tsx` `ICONS` map gains `"/reports": BarChart3`.

## Web — behaviour

- **Loading** → `<Skeleton>` per widget (never zeroes). **No data** → each widget's own
  message ("No booking data for this period." etc.). **Error** → widget-level
  "Unable to load … Try again.", never a raw DB message. Three states kept distinct, as
  Finance does.
- **Comparison period** — each Overview KPI shows `±%` vs the equal-length preceding
  window, fetched (not derived) via `previousPeriod(filter)` (extends the finance-dashboard
  `previousRange` map with `LAST_WEEK`, quarter, year). Suppressed when the prior figure is
  0 or the span is CUSTOM.
- **Drill-down** — "Revenue by Sport → Badminton" navigates to `/reports/revenue?…&sportId=…`
  keeping the date range; "Court 1 82% → `/reports/court-utilization?…&courtId=…`";
  Outstanding categories → `/finance/pending-payments?source=…`. Filters are URL-encoded so
  a report link is shareable; `facilityId` is still re-authorised by RLS.
- **CSV export** — `report-shell` "Download CSV" serialises the aggregate rows already in
  memory (KPI list, breakdown rows, trend points, utilization table) with the active filter
  in the filename. Not the "load raw records" anti-pattern — these payloads are tens of rows.
- **Charts** — Recharts, tooltips + readable axis labels + the supporting data table
  beneath (utilization, peak hours, breakdowns) for accessibility (§42/§54). No heavy
  animation. Mobile: charts keep a min-height and horizontal scroll inside their own
  container.
- **Freshness** — all real-time (RPCs read live). No cache layer (§47). Documented in
  `definitions.ts`.

## Phasing

One phase per working session, each a vertical slice (migration → types → service+tests →
page → feature tests) that builds and ships alone. `npm run build`, `npm test`,
`npm run typecheck`, `npm run lint` green per phase. Each phase is its own plan doc
(`docs/superpowers/plans/2026-09-03-reports-analytics-phase-N-*.md`), written when the
phase is reached so it builds on the concrete code the prior phase produced.

**Ordered by dependency** — reports whose RPCs stand alone come first; Overview comes
*after* its inputs exist so `get_analytics_overview` just composes them.

| Phase | Scope |
|---|---|
| **1 — Foundation** | `0056` (date presets). `AnalyticsFilter` + row types, `definitions.ts`, `aggregation.ts` (+tests), `reports.service.ts` + `supabase-reports.service.ts` skeleton (error mapping, `dateRangeArgs`/`scopeArgs`, no RPC methods yet) + fake, nav entry + `BarChart3` icon, `/reports/**` route group with all six pages rendering `<ReportShell>` + `<AnalyticsFilterBar>` + a "coming soon" body, URL-encoded filter state, `analytics-filter-sheet` (mobile), `kpi-strip`. Filter bar wired to real `getFacilities()` / sports / playing-areas. |
| **2 — Bookings** | `0058_analytics_bookings`. `<BookingReport>`: status KPI row, booking-trend chart, by-sport bar + table, status breakdown, source split (Guest/Member). Establishes the full RPC → service method → page → chart → table → CSV pattern on the simplest data source (`bookings` only, no availability math). |
| **3 — Court Utilization** | `0057_analytics_availability` (open-minutes aggregates) + `0059_analytics_utilization`. `<CourtUtilizationReport>`: overall gauge, by-court table (sortable ↑/↓) + bar, by-sport table + bar, peak-hours chart + table, demand heatmap (labels + tooltips + intensity). |
| **4 — Revenue** | `0061_analytics_revenue_dimensions` (`revenue_by_sport` / `_by_court`) + reuse Finance breakdown / method / trend. `<RevenueReport>`: trend, breakdown donut + table, payment-method donut + table, by-sport & by-court tables with drill-down, membership row. |
| **5 — Overview** | `0062_analytics_overview` `get_analytics_overview` (composes the Phase 2–4 functions + Finance RPCs) + reuse `get_revenue_trend`. `<ReportsOverview>`: 4–6 headline KPI cards with comparison period, revenue-trend chart, top-courts mini-table, peak-hours preview, drill-down links. |
| **6 — Memberships** | `0060_analytics_memberships`. `<MembershipReport>`: active/new/expiring KPIs, membership-revenue + payment-completion, by-type table, **Membership Session** panel (capacity/allocations/released/booked/unused), **Guest Release** panel. |
| **7 — Guest Bookings** | reuse `0058` guest fields + `0051` classification + `0059` peak-hours filtered to guest. `<GuestBookingReport>`: totals/completed/cancelled, guest revenue, avg booking value, collection rate, popular sports/courts, peak guest hours. |
| **8 — Export + a11y polish** | per-report CSV finalised, keyboard-nav + contrast + large-text pass, empty/error copy pass, mobile filter-sheet polish, drill-down cross-links verified end-to-end. |
| **9+ — Flutter** | Separate spec. `reports_repository.dart` + `features/reports/` over the same RPCs; hand-painted charts; existing mobile design system. |

## Validation scenarios (become tests)

- **§50** Champz Turf, 03 Sep 2026: guest ₹400 paid + ₹600 paid + ₹800 pending, membership
  ₹5,000 paid, maintenance expense ₹1,000 → **realized revenue ₹6,000, expenses ₹1,000,
  net ₹5,000, outstanding ₹800**. The ₹800 is never in realized revenue.
- **§51** Court 1: 10h open, 7h booked → 70%; if 2h were blocked they'd not be counted —
  moot here (no maintenance model), documented as such.
- **§52** Session capacity 5, member allocations 3, released 2, guest booked 1 →
  total 5 / member 3 / released 2 / booked 1 / **remaining released 1**; the guest ₹400
  is guest-booking revenue, the 3 member allocations are not revenue.

## Testing

Per §49 — **no E2E**. **This project has no SQL/pgTAP test harness** (confirmed:
`supabase/finance_sample_data.sql` is a manual eyeball seed, not a test; migration
behaviour is verified by a manual task in each plan, as in
`2026-08-30-membership-time-slots.md`). So:

- **Automated (`npm test`, Vitest + jsdom):**
  - **`aggregation.test.ts`** — `pickGranularity` boundaries (31/32/183/184 days),
    `previousPeriod` for every preset (incl. `LAST_WEEK`, quarter, year, CUSTOM→null),
    `csv()` escaping.
  - **`definitions.test.ts`** — every KPI key has a non-empty definition string.
  - **`supabase-reports.service.test.ts`** — each method: exact RPC name, `p_*` args
    (incl. resolved date-range + sport/court scope via `vi.fn()` `rpc`), snake→camel row
    mapping, `Not authorized` → `REPORTS_ACCESS_DENIED`, invalid range →
    `INVALID_DATE_RANGE`, throws `ServiceError`. Mirrors `supabase-finance.service.test.ts`.
  - **Component tests** (`@testing-library/react`) — `<ReportShell>` renders
    loading / empty / error distinctly (never zeroes while loading);
    `<AnalyticsFilterBar>` is keyboard-operable and writes filter state to the URL;
    `<KpiStrip>` renders on a 360px viewport with no overflow; each report page renders
    its data table when the chart is suppressed; drill-down links carry the active filter.
- **Manual DB verification (one task per phase):** `supabase/analytics_sample_data.sql`
  (revert-tagged, like `finance_sample_data.sql`) seeds the §50 + §52 fixtures against a
  real facility; the task lists the exact expected number for every RPC the phase adds
  (revenue, expenses, net, booking counts, membership revenue, outstanding, collection
  rate, court/sport utilization, peak hour, session utilization, guest-release
  utilization, guest-booking revenue) and the reviewer runs each RPC and checks.

## Out of scope

- Flutter (Phase 9+, separate spec).
- Materialized views / caching (§47 — add only on measured need).
- PDF export (CSV only in v1; the `download-transaction-receipt` edge pattern is available
  later).
- Any change to `bookings` / `payments` / `memberships` / `membership_sessions` schema or
  to existing Finance RPCs (except the additive `resolve_finance_date_range` presets).
- Migrating the existing owner dashboard.
- APK builds (per `feedback_no_unsolicited_apk_builds`).

## Rollout

The user applies migrations `0056`+ and needs no edge-function deploy (none added).
Each phase is one commit on `feat/reports-analytics` in the isolated clone. Before
integration: `git fetch local && git rebase local/main` to pick up audit commits, then
either push to GitHub for a PR **or** `git fetch <clone> feat/reports-analytics` from the
OneDrive repo once the audit is done. A new memory `project_reports_analytics` tracks phase
status.
