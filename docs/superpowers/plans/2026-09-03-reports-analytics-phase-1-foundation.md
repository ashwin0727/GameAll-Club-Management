# Reports & Analytics — Phase 1: Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status: implemented (2026-09-03), pending user verification + commit.** Deviations from the plan as written, all confirmed against the codebase during execution:
> - **No tooltip primitive exists** in `src/components/ui/`. `KpiStrip` exposes each KPI definition via the native `title` attribute plus an `sr-only` span instead of a Radix tooltip — no library pulled in. A richer tooltip is possible later polish.
> - **`FacilitySport` has no `name` field.** The filter bar resolves the sport label as `customSportName ?? activeSports.find(byId).name ?? "Sport"`, the same pattern the Bookings UI uses. It calls `getSportsService().getActiveSports()` in addition to `getFacilitySports()`.
> - **Fake:** `fake-reports-filter-deps.ts` is a self-contained deterministic fake (stable ids `fs-1..3`, `court-1..4`) rather than a wrapper over `installFakeSportsService` — the shared fake generates random ids, which tests can't assert on.
> - **`AnalyticsFilterBar` gained a `layout?: "row" | "stack"` prop**; the mobile sheet passes `layout="stack"` instead of CSS descendant overrides.
> - **Per-task `git commit` steps were skipped** at the user's instruction ("test before commit"). Everything is staged in the working tree; one commit after full verification.
> - **Pre-existing on `main` (not introduced here):** `tsc --noEmit` reports 2 errors in `src/services/payments/supabase-payment.service.test.ts`; `courts-setup-form.test.tsx` and `facility-details-form.test.tsx` have 2–4 flaky timer-based failures. All reproduce with this branch's changes stashed.

**Goal:** Stand up the Reports & Analytics shell — nav section, six routed report pages, a shared URL-persisted filter bar (facility / date / sport / court), the KPI/loading/empty/error scaffolding, and the pure client helpers — plus the additive date-preset migration. No report data yet; every report page renders its filter bar over a "coming soon" body.

**Architecture:** A new web feature module (`src/features/reports/`) mirroring `src/features/finance/`, with thin route wrappers under `src/app/(dashboard)/reports/`. The filter bar reads/writes `AnalyticsFilter` to the URL query string (so Phase 5+ drill-down links are just hrefs) and sources its dropdown options from the existing `FacilityService` / `SportsService` / `PlayingAreasService`. One additive migration extends the shared `resolve_finance_date_range` with `THIS_QUARTER` / `THIS_YEAR`. All aggregation is deferred to later phases.

**Tech Stack:** PostgreSQL (Supabase migrations), Next.js 15 / React 19 / App Router, TypeScript, Tailwind, shadcn UI primitives, lucide-react icons, Vitest + `@testing-library/react` (jsdom), hand-maintained `src/types/database.types.ts`.

**Spec:** `docs/superpowers/specs/2026-09-03-reports-analytics-design.md`

## Global Constraints

- **Isolated clone.** All work happens in `C:/Users/umash/gameall-reports-analytics` on branch `feat/reports-analytics`. Never touch the OneDrive checkout. `origin` = GitHub; `local` = the OneDrive repo (for rebasing onto audit commits, not for pushing).
- **No business logic in Reports.** This module never decides whether a booking is valid, a payment succeeded, a membership is active, or a slot is released. Later phases only *read* authoritative data; Phase 1 reads nothing but facility/sport/court lists.
- **The frontend never computes date boundaries.** It picks a preset string (or `CUSTOM` + explicit `startDate`/`endDate`); the backend's `resolve_finance_date_range` resolves it in the facility timezone. Same rule as Finance (`src/features/finance/components/date-range-picker.tsx` header comment).
- **Presets, verbatim:** `TODAY | YESTERDAY | THIS_WEEK | LAST_WEEK | THIS_MONTH | LAST_MONTH | THIS_QUARTER | THIS_YEAR | CUSTOM`. Default is `THIS_MONTH`.
- **Preset labels, verbatim:** `Today` / `Yesterday` / `This Week` / `Last Week` / `This Month` / `Last Month` / `This Quarter` / `This Year` / `Custom Range`.
- **Weeks start Monday** (ISO 8601 — `date_trunc('week', ...)` default; matches existing `resolve_finance_date_range`).
- **Migration files are immutable once shipped.** All Phase 1 DB changes go in the single new file `supabase/migrations/0056_analytics_date_presets.sql`. `0024_finance.sql` is never edited.
- **No SQL/pgTAP harness in this project.** `0056`'s behaviour is checked by the manual verification task (Task 1, Step 4). Everything else is covered by Vitest.
- **`database.types.ts` is hand-maintained** (see its header). Phase 1 changes **nothing** in it — `resolve_finance_date_range` is never called from the client (it runs inside other RPCs), so the two new preset strings need no type entry. Later phases update it per-RPC.
- **Design tokens (from the spec §55), used only via existing Tailwind classes / CSS vars:** primary `#00F08A`, success/revenue `#00D084`, payments `#5B6CFF`, membership `#8B5CF6`, guest `#FFB020`, error `#FF4D67`. Do not hand-roll SVG icons — use `lucide-react`.
- **Roles:** Reports is `["admin", "staff"]` only, exactly like Finance in `NAV_ITEMS`. Public users have no dashboard session at all.
- **Money is always minor units (paise)** in every type and never formatted by this module except through the existing `formatCurrency` from `@/features/pricing/money`. (Not exercised in Phase 1, but the constraint stands for the module.)
- **Per phase, all four must pass green:** `npm run typecheck`, `npm test`, `npm run lint`, `npm run build`.

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/0056_analytics_date_presets.sql` | **Create.** `create or replace resolve_finance_date_range` adding `THIS_QUARTER` + `THIS_YEAR` branches. Nothing else. |
| `src/features/reports/types.ts` | **Create.** `AnalyticsPreset`, `AnalyticsGranularity`, `AnalyticsFilter`, `PRESET_LABELS`, `DEFAULT_FILTER_PRESET`. The one shape every report RPC call is built from. |
| `src/features/reports/definitions.ts` | **Create.** `KPI_DEFINITIONS: Record<KpiKey, string>` — the authoritative one-line formula per KPI, rendered in tooltips. `FRESHNESS_NOTE`. |
| `src/features/reports/definitions.test.ts` | **Create.** Every `KpiKey` maps to a non-empty definition. |
| `src/features/reports/aggregation.ts` | **Create.** Pure helpers: `spanDays`, `pickGranularity`, `previousPeriod`, `toCsv`. No I/O, no React. |
| `src/features/reports/aggregation.test.ts` | **Create.** Boundary + escaping tests for all four helpers. |
| `src/features/reports/url-state.ts` | **Create.** `filterToSearchParams(filter)` / `filterFromSearchParams(params, fallbackFacilityId)` — the single encode/decode of `AnalyticsFilter` ↔ URL. |
| `src/features/reports/url-state.test.ts` | **Create.** Round-trip + malformed-input tests. |
| `src/features/reports/components/report-shell.tsx` | **Create.** Page frame: title, description, the filter bar slot, a "Download CSV" button slot, and a body that switches between `loading` / `empty` / `error` / `ready`. |
| `src/features/reports/components/report-shell.test.tsx` | **Create.** The four states render distinctly; loading shows skeletons not zeroes. |
| `src/features/reports/components/kpi-strip.tsx` | **Create.** Horizontal-scroll / wrap row of `StatCard`s from a `KpiStripItem[]`, each with an optional definition tooltip and optional drill-down `href`. |
| `src/features/reports/components/kpi-strip.test.tsx` | **Create.** Renders N cards; a 360px viewport has no horizontal page overflow; an item with `href` is a link. |
| `src/features/reports/components/analytics-filter-bar.tsx` | **Create.** Desktop filter bar: facility / date-preset (+ custom dates) / sport / court `Select`s. Reads current filter from props, calls `onChange`. |
| `src/features/reports/components/analytics-filter-bar.test.tsx` | **Create.** Renders options from injected fake services; changing a `Select` calls `onChange` with the updated filter; keyboard-operable. |
| `src/features/reports/components/analytics-filter-sheet.tsx` | **Create.** Mobile variant — a `Dialog` (bottom-sheet styling) wrapping the same controls, opened by a "Filters" button. |
| `src/features/reports/components/use-analytics-filter.ts` | **Create.** Hook: derives `AnalyticsFilter` from `useSearchParams` (+ the user's default facility), and returns a `setFilter` that writes it back via `router.replace`. |
| `src/features/reports/components/coming-soon-report.tsx` | **Create.** A report body placeholder used by every page this phase — `<ReportShell>` + "This report arrives in a later phase." Replaced per-phase.  |
| `src/features/reports/components/reports-overview.tsx` | **Create.** `<ReportsOverview>` — `<ComingSoonReport title="Overview" .../>` for now. |
| `src/features/reports/components/booking-report.tsx` | **Create.** `<BookingReport>` — coming-soon stub. |
| `src/features/reports/components/court-utilization-report.tsx` | **Create.** stub. |
| `src/features/reports/components/revenue-report.tsx` | **Create.** stub. |
| `src/features/reports/components/membership-report.tsx` | **Create.** stub. |
| `src/features/reports/components/guest-booking-report.tsx` | **Create.** stub. |
| `src/app/(dashboard)/reports/page.tsx` | **Create.** Renders `<ReportsOverview/>`; `metadata.title`. |
| `src/app/(dashboard)/reports/bookings/page.tsx` | **Create.** `<BookingReport/>` + breadcrumb. |
| `src/app/(dashboard)/reports/court-utilization/page.tsx` | **Create.** `<CourtUtilizationReport/>` + breadcrumb. |
| `src/app/(dashboard)/reports/revenue/page.tsx` | **Create.** `<RevenueReport/>` + breadcrumb. |
| `src/app/(dashboard)/reports/memberships/page.tsx` | **Create.** `<MembershipReport/>` + breadcrumb. |
| `src/app/(dashboard)/reports/guest-bookings/page.tsx` | **Create.** `<GuestBookingReport/>` + breadcrumb. |
| `src/lib/constants.ts` | **Modify.** Add the `Reports` entry to `NAV_ITEMS` after `Finance`. |
| `src/components/shared/sidebar.tsx` | **Modify.** Add `"/reports": BarChart3` to the `ICONS` map; import `BarChart3`. |
| `src/test/fakes/fake-reports-filter-deps.ts` | **Create.** Installs fake facility/sports/playing-areas services pre-seeded with one facility, three sports, four courts — the fixture the filter-bar tests share. |

---

## Task 1: Migration `0056` — `THIS_QUARTER` / `THIS_YEAR` presets

**Files:**
- Create: `supabase/migrations/0056_analytics_date_presets.sql`

**Interfaces:**
- Consumes: the current `resolve_finance_date_range(p_facility_id uuid, p_preset text, p_start_date date, p_end_date date) returns tstzrange` from `0024_finance.sql:42`.
- Produces: the same function, same signature, with two extra `p_preset` values accepted:
  - `THIS_QUARTER` → `[date_trunc('quarter', today), date_trunc('quarter', today) + interval '3 months')`
  - `THIS_YEAR` → `[date_trunc('year', today), date_trunc('year', today) + interval '1 year')`
  Every existing preset behaves byte-identically; an unknown preset still raises `22023`.

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/0056_analytics_date_presets.sql`:

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 1.
--
-- Analytics reuses Finance's date-range resolver so "This Month" means the
-- same window in both places, forever. The Reports brief adds two presets
-- Finance never needed: This Quarter and This Year.
--
-- This is `create or replace` of resolve_finance_date_range with the same
-- signature and every existing branch byte-identical — only two new
-- `elsif` arms. No Finance RPC or UI changes; the Finance date picker
-- simply doesn't offer the new presets.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function resolve_finance_date_range(
  p_facility_id uuid,
  p_preset text,
  p_start_date date default null,
  p_end_date date default null
) returns tstzrange
language plpgsql
stable
as $$
declare
  tz text;
  today date;
  range_start date;
  range_end_exclusive date;
begin
  select timezone into tz from facilities where id = p_facility_id;
  tz := coalesce(tz, 'Asia/Kolkata');
  today := (now() at time zone tz)::date;

  if p_preset = 'TODAY' then
    range_start := today; range_end_exclusive := today + 1;
  elsif p_preset = 'YESTERDAY' then
    range_start := today - 1; range_end_exclusive := today;
  elsif p_preset = 'THIS_WEEK' then
    range_start := date_trunc('week', today)::date; range_end_exclusive := range_start + 7;
  elsif p_preset = 'LAST_WEEK' then
    range_start := date_trunc('week', today)::date - 7; range_end_exclusive := range_start + 7;
  elsif p_preset = 'THIS_MONTH' then
    range_start := date_trunc('month', today)::date; range_end_exclusive := (date_trunc('month', today) + interval '1 month')::date;
  elsif p_preset = 'LAST_MONTH' then
    range_start := (date_trunc('month', today) - interval '1 month')::date; range_end_exclusive := date_trunc('month', today)::date;
  elsif p_preset = 'THIS_QUARTER' then
    range_start := date_trunc('quarter', today)::date; range_end_exclusive := (date_trunc('quarter', today) + interval '3 months')::date;
  elsif p_preset = 'THIS_YEAR' then
    range_start := date_trunc('year', today)::date; range_end_exclusive := (date_trunc('year', today) + interval '1 year')::date;
  elsif p_preset = 'CUSTOM' then
    if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
      raise exception 'A custom date range requires a valid start and end date.' using errcode = '22023';
    end if;
    range_start := p_start_date; range_end_exclusive := p_end_date + 1;
  else
    raise exception 'Unknown date range preset: %', p_preset using errcode = '22023';
  end if;

  return tstzrange(range_start::timestamp at time zone tz, range_end_exclusive::timestamp at time zone tz, '[)');
end;
$$;

grant execute on function resolve_finance_date_range(uuid, text, date, date) to authenticated;
```

- [ ] **Step 2: Sanity-check the SQL parses**

Run: `node -e "const s=require('fs').readFileSync('supabase/migrations/0056_analytics_date_presets.sql','utf8'); if(!/create or replace function resolve_finance_date_range/.test(s)||!/THIS_QUARTER/.test(s)||!/THIS_YEAR/.test(s)) throw new Error('missing pieces'); console.log('ok')"`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0056_analytics_date_presets.sql
git commit -m "feat(reports): 0056 — THIS_QUARTER / THIS_YEAR date presets"
```

- [ ] **Step 4: Manual verification (reviewer runs against the linked Supabase project)**

Apply `0056` (Supabase SQL editor or `supabase db push`), then run:

```sql
-- replace with a real facility id
select resolve_finance_date_range('<facility-id>', 'THIS_QUARTER');
select resolve_finance_date_range('<facility-id>', 'THIS_YEAR');
select resolve_finance_date_range('<facility-id>', 'THIS_MONTH');   -- unchanged
select resolve_finance_date_range('<facility-id>', 'BOGUS');        -- must raise 22023
```

Expected: quarter range spans exactly 3 months from the quarter start in the facility's timezone; year range spans Jan 1–Dec 31; `THIS_MONTH` identical to before; `BOGUS` errors with "Unknown date range preset".

---

## Task 2: `types.ts` + `definitions.ts`

**Files:**
- Create: `src/features/reports/types.ts`
- Create: `src/features/reports/definitions.ts`
- Test: `src/features/reports/definitions.test.ts`

**Interfaces:**
- Produces:
  - `type AnalyticsPreset = "TODAY" | "YESTERDAY" | "THIS_WEEK" | "LAST_WEEK" | "THIS_MONTH" | "LAST_MONTH" | "THIS_QUARTER" | "THIS_YEAR" | "CUSTOM"`
  - `type AnalyticsGranularity = "daily" | "weekly" | "monthly"`
  - `interface AnalyticsFilter { facilityId: string; preset: AnalyticsPreset; startDate?: string | null; endDate?: string | null; facilitySportId?: string | null; courtId?: string | null }`
  - `const PRESET_LABELS: Record<AnalyticsPreset, string>`
  - `const DEFAULT_FILTER_PRESET: AnalyticsPreset = "THIS_MONTH"`
  - `const ANALYTICS_PRESETS: AnalyticsPreset[]` (ordered for the dropdown)
  - `type KpiKey` (union) + `const KPI_DEFINITIONS: Record<KpiKey, string>` + `const FRESHNESS_NOTE: string`

- [ ] **Step 1: Write `types.ts`**

```ts
// ═══════════════════════════════════════════════════════════════════════════
// Reports & Analytics — the one filter shape every report RPC call is built
// from (spec §"Shared filter model"). Like Finance, the frontend only ever
// picks a preset string; the backend's resolve_finance_date_range turns it
// into real dates in the facility's timezone.
// ═══════════════════════════════════════════════════════════════════════════

export type AnalyticsPreset =
  | "TODAY"
  | "YESTERDAY"
  | "THIS_WEEK"
  | "LAST_WEEK"
  | "THIS_MONTH"
  | "LAST_MONTH"
  | "THIS_QUARTER"
  | "THIS_YEAR"
  | "CUSTOM";

export type AnalyticsGranularity = "daily" | "weekly" | "monthly";

export interface AnalyticsFilter {
  /** Never trusted from the URL alone — every RPC re-authorises via RLS. */
  facilityId: string;
  preset: AnalyticsPreset;
  /** Required, and only used, when preset is CUSTOM. ISO yyyy-mm-dd. */
  startDate?: string | null;
  endDate?: string | null;
  /** facility_sports.id — null means "all sports". */
  facilitySportId?: string | null;
  /** courts.id — null means "all courts". */
  courtId?: string | null;
}

export const DEFAULT_FILTER_PRESET: AnalyticsPreset = "THIS_MONTH";

export const PRESET_LABELS: Record<AnalyticsPreset, string> = {
  TODAY: "Today",
  YESTERDAY: "Yesterday",
  THIS_WEEK: "This Week",
  LAST_WEEK: "Last Week",
  THIS_MONTH: "This Month",
  LAST_MONTH: "Last Month",
  THIS_QUARTER: "This Quarter",
  THIS_YEAR: "This Year",
  CUSTOM: "Custom Range",
};

export const ANALYTICS_PRESETS: AnalyticsPreset[] = [
  "TODAY",
  "YESTERDAY",
  "THIS_WEEK",
  "THIS_MONTH",
  "LAST_MONTH",
  "THIS_QUARTER",
  "THIS_YEAR",
  "CUSTOM",
];
```

(`LAST_WEEK` is intentionally omitted from `ANALYTICS_PRESETS` — the dropdown offers the common set; `LAST_WEEK` is still a valid value the comparison-period helper produces.)

- [ ] **Step 2: Write `definitions.ts`**

```ts
// ═══════════════════════════════════════════════════════════════════════════
// The authoritative one-line definition of every KPI Reports shows, rendered
// in an info tooltip beside the figure (spec §53 "Data Definitions"). If a
// formula ever changes, it changes here and in the RPC header comment — the
// two must always agree.
// ═══════════════════════════════════════════════════════════════════════════

export type KpiKey =
  | "totalBookings"
  | "completedBookings"
  | "cancelledBookings"
  | "confirmedBookings"
  | "pendingBookings"
  | "bookingRevenue"
  | "membershipRevenue"
  | "totalRevenue"
  | "totalExpenses"
  | "netRevenue"
  | "outstandingPayments"
  | "courtUtilization"
  | "sportUtilization"
  | "peakHours"
  | "averageBookingValue"
  | "paymentCollectionRate"
  | "activeMembers"
  | "newMemberships"
  | "expiringMemberships"
  | "membershipSessionUtilization"
  | "guestReleased"
  | "guestBooked"
  | "guestRemaining"
  | "guestReleaseRevenue"
  | "guestBookingRevenue";

export const KPI_DEFINITIONS: Record<KpiKey, string> = {
  totalBookings: "Every booking whose start time falls in the selected range, all statuses (cancelled shown as its own slice).",
  completedBookings: "Bookings with status COMPLETED in the range.",
  cancelledBookings: "Bookings with status CANCELLED in the range.",
  confirmedBookings: "Bookings with status CONFIRMED in the range.",
  pendingBookings: "Bookings with status PENDING in the range.",
  bookingRevenue: "Realised member-booking + guest-booking payments in the range (Finance, cash basis). Unpaid booking amounts are not counted.",
  membershipRevenue: "Realised membership payments in the range. Membership session usage is never revenue.",
  totalRevenue: "Sum of successfully collected payments in the range (Finance gross revenue). Cash basis — a pending amount is not revenue.",
  totalExpenses: "Recorded facility expenses in the range (Finance). Voided expenses excluded.",
  netRevenue: "Gross revenue minus refunds minus expenses (Finance).",
  outstandingPayments: "Money still owed on bookings and memberships that have happened and not been fully paid (Pending Payments).",
  courtUtilization: "Booked minutes divided by open (bookable) minutes for the range, capped at 100%. Open minutes come from the court's operating hours; there is no separate maintenance model.",
  sportUtilization: "The same booked-over-open ratio, summed across all courts of one sport.",
  peakHours: "For each hour of day: booked minutes divided by the minutes the facility is open in that hour, over the range. Closed hours are excluded, not shown as zero demand.",
  averageBookingValue: "Realised guest-booking revenue divided by the count of paid guest bookings in the range. Cancelled and unpaid bookings are not in the divisor.",
  paymentCollectionRate: "Collected amount divided by (collected + outstanding) for the range. Pending payments are not counted as collected.",
  activeMembers: "Memberships with status ACTIVE as of now, for this facility.",
  newMemberships: "Memberships created within the selected range.",
  expiringMemberships: "Active memberships whose end date is within the next 30 days.",
  membershipSessionUtilization: "Confirmed member + guest slots divided by total session capacity, over sessions dated in the range.",
  guestReleased: "Total guest capacity the owner released across sessions dated in the range.",
  guestBooked: "Confirmed guest bookings against released capacity, over sessions in the range.",
  guestRemaining: "Released capacity minus guest bookings.",
  guestReleaseRevenue: "Realised payments for released-seat guest bookings, classified as guest-booking revenue by Finance.",
  guestBookingRevenue: "Realised payments for guest bookings (both ad-hoc and released-seat) in the range.",
};

export const FRESHNESS_NOTE =
  "Reports are real-time — every figure is read live from Bookings, Memberships and Finance when the page loads. There is no cached or delayed data.";
```

- [ ] **Step 3: Write the failing test**

Create `src/features/reports/definitions.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { KPI_DEFINITIONS, FRESHNESS_NOTE, type KpiKey } from "./definitions";

describe("KPI_DEFINITIONS", () => {
  it("gives every KPI key a non-empty, sentence-like definition", () => {
    const keys = Object.keys(KPI_DEFINITIONS) as KpiKey[];
    expect(keys.length).toBeGreaterThanOrEqual(20);
    for (const key of keys) {
      const def = KPI_DEFINITIONS[key];
      expect(def, key).toBeTruthy();
      expect(def.length, key).toBeGreaterThan(15);
      expect(def.trim().endsWith("."), key).toBe(true);
    }
  });

  it("states the cash-basis rule on the revenue KPIs", () => {
    expect(KPI_DEFINITIONS.totalRevenue.toLowerCase()).toContain("cash basis");
    expect(KPI_DEFINITIONS.bookingRevenue.toLowerCase()).toContain("not counted");
  });

  it("has a freshness note", () => {
    expect(FRESHNESS_NOTE.toLowerCase()).toContain("real-time");
  });
});
```

- [ ] **Step 4: Run test to verify it fails**

Run: `npm test -- src/features/reports/definitions.test.ts`
Expected: FAIL — `Cannot find module './definitions'` (only if you skipped Step 2) or, once `definitions.ts` exists, PASS.

- [ ] **Step 5: Run test to verify it passes**

Run: `npm test -- src/features/reports/definitions.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 6: Typecheck + commit**

Run: `npm run typecheck`
Expected: no errors.

```bash
git add src/features/reports/types.ts src/features/reports/definitions.ts src/features/reports/definitions.test.ts
git commit -m "feat(reports): AnalyticsFilter types + KPI definitions"
```

---

## Task 3: `aggregation.ts` — span / granularity / previous-period / CSV

**Files:**
- Create: `src/features/reports/aggregation.ts`
- Test: `src/features/reports/aggregation.test.ts`

**Interfaces:**
- Consumes: `AnalyticsFilter`, `AnalyticsGranularity`, `AnalyticsPreset` from `./types`.
- Produces:
  - `spanDays(startISO: string, endISO: string): number` — inclusive day count (`2026-09-01`..`2026-09-01` → 1).
  - `pickGranularity(startISO: string, endISO: string): AnalyticsGranularity` — ≤31 → `daily`, 32–183 → `weekly`, >183 → `monthly`.
  - `previousPeriod(filter: AnalyticsFilter): AnalyticsFilter | null` — the equal-length window immediately before. Preset map: `TODAY→YESTERDAY`, `THIS_WEEK→LAST_WEEK`, `THIS_MONTH→LAST_MONTH`; `YESTERDAY`/`LAST_WEEK`/`LAST_MONTH`/`THIS_QUARTER`/`THIS_YEAR` → an explicit `CUSTOM` range shifted back by its own length (caller resolves the current range's dates first — see signature note below); `CUSTOM` → `CUSTOM` shifted back; returns `null` when there is no sensible previous window (a `CUSTOM` with missing dates).
  - `toCsv(rows: Array<Record<string, string | number | null>>): string` — RFC-4180-ish: header from the first row's keys, `"` doubled, fields with `",\n` quoted, `\r\n` line endings, `""` for `null`.

  **Signature note:** `previousPeriod` needs concrete dates for the presets it can't map to another preset. To keep it pure, it takes the *resolved* current range as a second arg: `previousPeriod(filter: AnalyticsFilter, resolvedRange?: { startDate: string; endDate: string }): AnalyticsFilter | null`. When the preset maps directly (`TODAY`/`THIS_WEEK`/`THIS_MONTH`) `resolvedRange` is ignored; otherwise it's required and a missing one yields `null`.

- [ ] **Step 1: Write the failing test**

Create `src/features/reports/aggregation.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { spanDays, pickGranularity, previousPeriod, toCsv } from "./aggregation";
import type { AnalyticsFilter } from "./types";

const base: AnalyticsFilter = { facilityId: "f1", preset: "THIS_MONTH" };

describe("spanDays", () => {
  it("counts a single day as 1", () => {
    expect(spanDays("2026-09-03", "2026-09-03")).toBe(1);
  });
  it("counts an inclusive range", () => {
    expect(spanDays("2026-09-01", "2026-09-30")).toBe(30);
  });
});

describe("pickGranularity", () => {
  it("is daily up to 31 days", () => {
    expect(pickGranularity("2026-09-01", "2026-10-01")).toBe("daily"); // 31
  });
  it("is weekly from 32 to 183 days", () => {
    expect(pickGranularity("2026-09-01", "2026-10-02")).toBe("weekly"); // 32
    expect(pickGranularity("2026-01-01", "2026-07-02")).toBe("weekly"); // 183
  });
  it("is monthly beyond 183 days", () => {
    expect(pickGranularity("2026-01-01", "2026-07-03")).toBe("monthly"); // 184
  });
});

describe("previousPeriod", () => {
  it("maps the common presets to their prior preset", () => {
    expect(previousPeriod({ ...base, preset: "TODAY" })?.preset).toBe("YESTERDAY");
    expect(previousPeriod({ ...base, preset: "THIS_WEEK" })?.preset).toBe("LAST_WEEK");
    expect(previousPeriod({ ...base, preset: "THIS_MONTH" })?.preset).toBe("LAST_MONTH");
  });

  it("shifts a resolved quarter back by its own length as a CUSTOM range", () => {
    const prev = previousPeriod(
      { ...base, preset: "THIS_QUARTER" },
      { startDate: "2026-07-01", endDate: "2026-09-30" },
    );
    expect(prev).toEqual({ ...base, preset: "CUSTOM", startDate: "2026-04-02", endDate: "2026-06-30" });
  });

  it("shifts an explicit CUSTOM range back", () => {
    const prev = previousPeriod({ ...base, preset: "CUSTOM", startDate: "2026-09-10", endDate: "2026-09-19" });
    expect(prev).toEqual({ ...base, preset: "CUSTOM", startDate: "2026-08-31", endDate: "2026-09-09" });
  });

  it("returns null for a CUSTOM range with no dates", () => {
    expect(previousPeriod({ ...base, preset: "CUSTOM" })).toBeNull();
  });

  it("returns null for a resolved-range preset when no resolved range is given", () => {
    expect(previousPeriod({ ...base, preset: "THIS_YEAR" })).toBeNull();
  });
});

describe("toCsv", () => {
  it("writes a header row from the first object's keys", () => {
    expect(toCsv([{ sport: "Badminton", revenue: 45000 }])).toBe("sport,revenue\r\nBadminton,45000");
  });
  it("quotes fields containing comma, quote or newline and doubles quotes", () => {
    expect(toCsv([{ name: 'A, "B"', note: "line1\nline2" }])).toBe(
      'name,note\r\n"A, ""B""","line1\nline2"',
    );
  });
  it("renders null as an empty quoted field and returns '' for no rows", () => {
    expect(toCsv([{ a: null, b: 1 }])).toBe('a,b\r\n"",1');
    expect(toCsv([])).toBe("");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/features/reports/aggregation.test.ts`
Expected: FAIL — `Cannot find module './aggregation'`.

- [ ] **Step 3: Write `aggregation.ts`**

```ts
// ═══════════════════════════════════════════════════════════════════════════
// Pure client helpers for Reports. No I/O, no React, no date-boundary
// computation for the *server's* range (the backend owns that) — these only
// (a) pick a readable chart granularity from a span, (b) name the comparison
// window, and (c) serialise already-fetched aggregate rows to CSV.
// ═══════════════════════════════════════════════════════════════════════════

import type { AnalyticsFilter, AnalyticsGranularity, AnalyticsPreset } from "./types";

const MS_PER_DAY = 86_400_000;

function parseIso(iso: string): Date {
  // Midnight UTC — these are calendar dates, not instants; arithmetic below
  // only ever takes differences and adds whole days, so the zone is moot.
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y!, (m ?? 1) - 1, d ?? 1));
}

function toIso(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/** Inclusive day count: 2026-09-01..2026-09-01 → 1. */
export function spanDays(startISO: string, endISO: string): number {
  return Math.round((parseIso(endISO).getTime() - parseIso(startISO).getTime()) / MS_PER_DAY) + 1;
}

/** Readable chart buckets: daily ≤31d, weekly ≤183d, monthly beyond (spec §31). */
export function pickGranularity(startISO: string, endISO: string): AnalyticsGranularity {
  const days = spanDays(startISO, endISO);
  if (days <= 31) return "daily";
  if (days <= 183) return "weekly";
  return "monthly";
}

const PRIOR_PRESET: Partial<Record<AnalyticsPreset, AnalyticsPreset>> = {
  TODAY: "YESTERDAY",
  THIS_WEEK: "LAST_WEEK",
  THIS_MONTH: "LAST_MONTH",
};

/**
 * The equal-length window immediately before this one, for "vs previous
 * period". Common presets map to their sibling; the rest become an explicit
 * CUSTOM range shifted back by their own length (the caller passes the
 * resolved current dates). Null when there is no sensible previous window.
 */
export function previousPeriod(
  filter: AnalyticsFilter,
  resolvedRange?: { startDate: string; endDate: string },
): AnalyticsFilter | null {
  const mapped = PRIOR_PRESET[filter.preset];
  if (mapped) return { ...filter, preset: mapped, startDate: null, endDate: null };

  const range =
    filter.preset === "CUSTOM"
      ? filter.startDate && filter.endDate
        ? { startDate: filter.startDate, endDate: filter.endDate }
        : null
      : resolvedRange ?? null;
  if (!range) return null;

  const length = spanDays(range.startDate, range.endDate);
  const prevEnd = new Date(parseIso(range.startDate).getTime() - MS_PER_DAY);
  const prevStart = new Date(prevEnd.getTime() - (length - 1) * MS_PER_DAY);
  return { ...filter, preset: "CUSTOM", startDate: toIso(prevStart), endDate: toIso(prevEnd) };
}

const NEEDS_QUOTING = /[",\n]/;

/** RFC-4180-ish CSV of already-fetched aggregate rows (tens of rows, not raw records). */
export function toCsv(rows: Array<Record<string, string | number | null>>): string {
  if (rows.length === 0) return "";
  const headers = Object.keys(rows[0]!);
  const encodeCell = (value: string | number | null): string => {
    if (value === null) return '""';
    const s = String(value);
    return NEEDS_QUOTING.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const lines = [
    headers.join(","),
    ...rows.map((row) => headers.map((h) => encodeCell(row[h] ?? null)).join(",")),
  ];
  return lines.join("\r\n");
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/features/reports/aggregation.test.ts`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add src/features/reports/aggregation.ts src/features/reports/aggregation.test.ts
git commit -m "feat(reports): span / granularity / previous-period / CSV helpers"
```

---

## Task 4: `url-state.ts` — `AnalyticsFilter` ↔ URL query

**Files:**
- Create: `src/features/reports/url-state.ts`
- Test: `src/features/reports/url-state.test.ts`

**Interfaces:**
- Consumes: `AnalyticsFilter`, `AnalyticsPreset`, `ANALYTICS_PRESETS`, `DEFAULT_FILTER_PRESET` from `./types`.
- Produces:
  - `filterToSearchParams(filter: AnalyticsFilter): URLSearchParams` — keys: `facility`, `preset`, `from`, `to`, `sport`, `court`. Omits `facility` when equal to the fallback? No — always include `facility` (drill-down links must be explicit). Omits `from`/`to` unless preset is `CUSTOM`. Omits `sport`/`court` when null.
  - `filterFromSearchParams(params: URLSearchParams | ReadonlyURLSearchParams, fallbackFacilityId: string): AnalyticsFilter` — tolerant: unknown `preset` → `DEFAULT_FILTER_PRESET`; `CUSTOM` without both `from` and `to` → `DEFAULT_FILTER_PRESET`; missing `facility` → `fallbackFacilityId`.

- [ ] **Step 1: Write the failing test**

Create `src/features/reports/url-state.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { filterToSearchParams, filterFromSearchParams } from "./url-state";
import type { AnalyticsFilter } from "./types";

describe("filterToSearchParams", () => {
  it("emits facility + preset, and omits custom dates / null scope", () => {
    const f: AnalyticsFilter = { facilityId: "fac-1", preset: "THIS_MONTH", facilitySportId: null, courtId: null };
    expect(filterToSearchParams(f).toString()).toBe("facility=fac-1&preset=THIS_MONTH");
  });

  it("includes from/to only for CUSTOM, and sport/court when set", () => {
    const f: AnalyticsFilter = {
      facilityId: "fac-1", preset: "CUSTOM", startDate: "2026-09-01", endDate: "2026-09-15",
      facilitySportId: "fs-2", courtId: "c-3",
    };
    const p = filterToSearchParams(f);
    expect(p.get("from")).toBe("2026-09-01");
    expect(p.get("to")).toBe("2026-09-15");
    expect(p.get("sport")).toBe("fs-2");
    expect(p.get("court")).toBe("c-3");
  });
});

describe("filterFromSearchParams", () => {
  it("round-trips a CUSTOM filter", () => {
    const f: AnalyticsFilter = {
      facilityId: "fac-1", preset: "CUSTOM", startDate: "2026-09-01", endDate: "2026-09-15",
      facilitySportId: "fs-2", courtId: "c-3",
    };
    expect(filterFromSearchParams(filterToSearchParams(f), "fallback")).toEqual(f);
  });

  it("falls back to the default preset on an unknown preset", () => {
    const p = new URLSearchParams("facility=fac-1&preset=NONSENSE");
    expect(filterFromSearchParams(p, "fallback").preset).toBe("THIS_MONTH");
  });

  it("falls back to the default preset when CUSTOM is missing dates", () => {
    const p = new URLSearchParams("facility=fac-1&preset=CUSTOM&from=2026-09-01");
    expect(filterFromSearchParams(p, "fallback").preset).toBe("THIS_MONTH");
  });

  it("uses the fallback facility id when the param is absent", () => {
    const p = new URLSearchParams("preset=THIS_WEEK");
    expect(filterFromSearchParams(p, "fallback-fac")).toMatchObject({ facilityId: "fallback-fac", preset: "THIS_WEEK" });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/features/reports/url-state.test.ts`
Expected: FAIL — `Cannot find module './url-state'`.

- [ ] **Step 3: Write `url-state.ts`**

```ts
// ═══════════════════════════════════════════════════════════════════════════
// The single place AnalyticsFilter is encoded to / decoded from the URL
// query string. Report links (drill-down, "view all", shared bookmarks) are
// therefore just hrefs — no client state to thread through. facilityId is
// always in the URL and always re-authorised server-side by RLS.
// ═══════════════════════════════════════════════════════════════════════════

import {
  ANALYTICS_PRESETS,
  DEFAULT_FILTER_PRESET,
  type AnalyticsFilter,
  type AnalyticsPreset,
} from "./types";

type ParamsLike = { get(key: string): string | null };

const PRESET_SET = new Set<string>([...ANALYTICS_PRESETS, "LAST_WEEK"]);

export function filterToSearchParams(filter: AnalyticsFilter): URLSearchParams {
  const params = new URLSearchParams();
  params.set("facility", filter.facilityId);
  params.set("preset", filter.preset);
  if (filter.preset === "CUSTOM") {
    if (filter.startDate) params.set("from", filter.startDate);
    if (filter.endDate) params.set("to", filter.endDate);
  }
  if (filter.facilitySportId) params.set("sport", filter.facilitySportId);
  if (filter.courtId) params.set("court", filter.courtId);
  return params;
}

export function filterFromSearchParams(params: ParamsLike, fallbackFacilityId: string): AnalyticsFilter {
  const rawPreset = params.get("preset");
  let preset: AnalyticsPreset =
    rawPreset && PRESET_SET.has(rawPreset) ? (rawPreset as AnalyticsPreset) : DEFAULT_FILTER_PRESET;

  const from = params.get("from");
  const to = params.get("to");
  if (preset === "CUSTOM" && !(from && to)) preset = DEFAULT_FILTER_PRESET;

  return {
    facilityId: params.get("facility") ?? fallbackFacilityId,
    preset,
    startDate: preset === "CUSTOM" ? from : null,
    endDate: preset === "CUSTOM" ? to : null,
    facilitySportId: params.get("sport"),
    courtId: params.get("court"),
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/features/reports/url-state.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/features/reports/url-state.ts src/features/reports/url-state.test.ts
git commit -m "feat(reports): AnalyticsFilter URL encode/decode"
```

---

## Task 5: Nav entry + route group + report stubs

**Files:**
- Modify: `src/lib/constants.ts` (the `NAV_ITEMS` array — add the `Reports` object right after the `Finance` object)
- Modify: `src/components/shared/sidebar.tsx` (import `BarChart3`; add `"/reports": BarChart3` to `ICONS`)
- Create: `src/features/reports/components/coming-soon-report.tsx`
- Create: `src/features/reports/components/reports-overview.tsx`
- Create: `src/features/reports/components/booking-report.tsx`
- Create: `src/features/reports/components/court-utilization-report.tsx`
- Create: `src/features/reports/components/revenue-report.tsx`
- Create: `src/features/reports/components/membership-report.tsx`
- Create: `src/features/reports/components/guest-booking-report.tsx`
- Create: `src/app/(dashboard)/reports/page.tsx`
- Create: `src/app/(dashboard)/reports/bookings/page.tsx`
- Create: `src/app/(dashboard)/reports/court-utilization/page.tsx`
- Create: `src/app/(dashboard)/reports/revenue/page.tsx`
- Create: `src/app/(dashboard)/reports/memberships/page.tsx`
- Create: `src/app/(dashboard)/reports/guest-bookings/page.tsx`

**Interfaces:**
- Consumes: `NavItem` type from `@/lib/constants`; `APP_NAME`.
- Produces:
  - `NAV_ITEMS` contains a `{ label: "Reports", href: "/reports", roles: ["admin","staff"], children: [...6] }` entry.
  - `<ComingSoonReport title="…" description="…" />` — client component rendering a titled panel with "This report arrives in a later phase." (temporary; replaced per phase).
  - `<ReportsOverview/>`, `<BookingReport/>`, `<CourtUtilizationReport/>`, `<RevenueReport/>`, `<MembershipReport/>`, `<GuestBookingReport/>` — each a client component; in Phase 1 each renders `<ComingSoonReport>`.

- [ ] **Step 1: Add the nav entry**

In `src/lib/constants.ts`, insert into `NAV_ITEMS` immediately after the `Finance` object:

```ts
  {
    label: "Reports",
    href: "/reports",
    roles: ["admin", "staff"],
    children: [
      { label: "Overview", href: "/reports" },
      { label: "Bookings", href: "/reports/bookings" },
      { label: "Court Utilization", href: "/reports/court-utilization" },
      { label: "Revenue", href: "/reports/revenue" },
      { label: "Memberships", href: "/reports/memberships" },
      { label: "Guest Bookings", href: "/reports/guest-bookings" },
    ],
  },
```

- [ ] **Step 2: Add the sidebar icon**

In `src/components/shared/sidebar.tsx`, add `BarChart3` to the lucide import list, and add to the `ICONS` map:

```ts
  "/reports": BarChart3,
```

- [ ] **Step 3: Write `coming-soon-report.tsx`**

```tsx
"use client";

import { Card } from "@/components/ui/card";

/**
 * Temporary body for a report page whose data layer lands in a later phase.
 * Replaced wholesale when that phase implements the real report.
 */
export function ComingSoonReport({ title, description }: { title: string; description: string }) {
  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold">{title}</h1>
        <p className="text-sm text-muted-foreground">{description}</p>
      </div>
      <Card className="border-dashed p-10 text-center">
        <p className="text-sm text-muted-foreground">This report arrives in a later phase.</p>
      </Card>
    </div>
  );
}
```

- [ ] **Step 4: Write the six report components**

`src/features/reports/components/reports-overview.tsx`:

```tsx
"use client";

import { ComingSoonReport } from "./coming-soon-report";

export function ReportsOverview() {
  return <ComingSoonReport title="Reports & Analytics" description="Business performance at a glance." />;
}
```

`booking-report.tsx`:

```tsx
"use client";

import { ComingSoonReport } from "./coming-soon-report";

export function BookingReport() {
  return <ComingSoonReport title="Booking Report" description="Volume, status mix and demand by sport." />;
}
```

`court-utilization-report.tsx`:

```tsx
"use client";

import { ComingSoonReport } from "./coming-soon-report";

export function CourtUtilizationReport() {
  return <ComingSoonReport title="Court Utilization" description="How hard each court and sport is working." />;
}
```

`revenue-report.tsx`:

```tsx
"use client";

import { ComingSoonReport } from "./coming-soon-report";

export function RevenueReport() {
  return <ComingSoonReport title="Revenue Report" description="Trend, breakdown and payment methods." />;
}
```

`membership-report.tsx`:

```tsx
"use client";

import { ComingSoonReport } from "./coming-soon-report";

export function MembershipReport() {
  return <ComingSoonReport title="Membership Report" description="Members, renewals, sessions and released capacity." />;
}
```

`guest-booking-report.tsx`:

```tsx
"use client";

import { ComingSoonReport } from "./coming-soon-report";

export function GuestBookingReport() {
  return <ComingSoonReport title="Guest Booking Report" description="Guest volume, value and collection." />;
}
```

- [ ] **Step 5: Write the six page wrappers**

`src/app/(dashboard)/reports/page.tsx`:

```tsx
import type { Metadata } from "next";
import { ReportsOverview } from "@/features/reports/components/reports-overview";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Reports & Analytics — ${APP_NAME}` };

export default function ReportsOverviewPage() {
  return <ReportsOverview />;
}
```

Each sub-page follows the Finance sub-page pattern (`src/app/(dashboard)/finance/expenses/page.tsx`) — breadcrumb + component. `src/app/(dashboard)/reports/bookings/page.tsx`:

```tsx
import type { Metadata } from "next";
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { BookingReport } from "@/features/reports/components/booking-report";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Booking Report — ${APP_NAME}` };

export default function ReportsBookingsPage() {
  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/reports" className="hover:text-foreground">Reports</Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">Bookings</span>
      </nav>
      <BookingReport />
    </div>
  );
}
```

Repeat for `court-utilization` (`Court Utilization` / `<CourtUtilizationReport/>`), `revenue` (`Revenue` / `<RevenueReport/>`), `memberships` (`Memberships` / `<MembershipReport/>`), `guest-bookings` (`Guest Bookings` / `<GuestBookingReport/>`) — same structure, swapping the label, component and `metadata.title` (`Revenue Report`, `Court Utilization`, `Membership Report`, `Guest Booking Report`).

- [ ] **Step 6: Verify build + lint + typecheck**

Run: `npm run typecheck && npm run lint && npm run build`
Expected: all green. `npm run build` lists the six `/reports*` routes.

- [ ] **Step 7: Manual check**

Run: `npm run dev`, sign in, confirm the **Reports** section appears in the sidebar under Finance, expands, and all six links load their "coming soon" page with the correct breadcrumb and title.

- [ ] **Step 8: Commit**

```bash
git add src/lib/constants.ts src/components/shared/sidebar.tsx src/features/reports/components src/app/\(dashboard\)/reports
git commit -m "feat(reports): nav section + six routed report pages (stubs)"
```

---

## Task 6: `<ReportShell>` — the loading / empty / error / ready frame

**Files:**
- Create: `src/features/reports/components/report-shell.tsx`
- Test: `src/features/reports/components/report-shell.test.tsx`

**Interfaces:**
- Consumes: `Skeleton` from `@/components/ui/skeleton`, `Button` from `@/components/ui/button`, `Download` / `AlertCircle` from `lucide-react`.
- Produces:
  - `type ReportStatus = "loading" | "error" | "empty" | "ready"`
  - `<ReportShell>` props: `{ title: string; description: string; status: ReportStatus; onRetry?: () => void; emptyMessage?: string; errorMessage?: string; filterBar?: React.ReactNode; onExportCsv?: () => void; children: React.ReactNode }`.
  - Behaviour: header (title + description) always renders. `filterBar` renders under the header when provided. When `status==="ready"`, `children` render and — if `onExportCsv` given — a "Download CSV" `Button` shows in the header row. `loading` → three `Skeleton` blocks (`h-24`, `h-64`, `h-64`), never any numeric content. `empty` → a dashed panel with `emptyMessage ?? "No data for this period."`. `error` → a panel with `AlertCircle`, `errorMessage ?? "Unable to load this report."`, and a "Try again" `Button` when `onRetry` is given.

- [ ] **Step 1: Write the failing test**

Create `src/features/reports/components/report-shell.test.tsx`:

```tsx
import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ReportShell } from "./report-shell";

const base = { title: "Booking Report", description: "desc" as string };

describe("ReportShell", () => {
  it("shows skeletons and no children while loading", () => {
    render(
      <ReportShell {...base} status="loading">
        <div>revenue ₹1,20,000</div>
      </ReportShell>,
    );
    expect(screen.queryByText(/1,20,000/)).not.toBeInTheDocument();
    expect(document.querySelectorAll("[data-slot='skeleton'], .animate-pulse").length).toBeGreaterThan(0);
  });

  it("renders children and an export button when ready", async () => {
    const onExportCsv = vi.fn();
    render(
      <ReportShell {...base} status="ready" onExportCsv={onExportCsv}>
        <div>revenue ₹1,20,000</div>
      </ReportShell>,
    );
    expect(screen.getByText(/1,20,000/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: /download csv/i }));
    expect(onExportCsv).toHaveBeenCalledOnce();
  });

  it("shows a distinct empty message", () => {
    render(<ReportShell {...base} status="empty" emptyMessage="No booking data for this period."><div /></ReportShell>);
    expect(screen.getByText("No booking data for this period.")).toBeInTheDocument();
  });

  it("shows an error with a working retry", async () => {
    const onRetry = vi.fn();
    render(<ReportShell {...base} status="error" onRetry={onRetry}><div /></ReportShell>);
    expect(screen.getByText(/unable to load/i)).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: /try again/i }));
    expect(onRetry).toHaveBeenCalledOnce();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/features/reports/components/report-shell.test.tsx`
Expected: FAIL — `Cannot find module './report-shell'`.

- [ ] **Step 3: Write `report-shell.tsx`**

```tsx
"use client";

import { AlertCircle, Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

export type ReportStatus = "loading" | "error" | "empty" | "ready";

/**
 * Every report page's frame. The header always renders; the body switches on
 * `status` so "still loading", "loaded but empty" and "failed" are always
 * visually distinct and a figure never flashes as 0 mid-load (spec §43/§44/§45).
 */
export function ReportShell({
  title,
  description,
  status,
  onRetry,
  emptyMessage = "No data for this period.",
  errorMessage = "Unable to load this report. Please try again.",
  filterBar,
  onExportCsv,
  children,
}: {
  title: string;
  description: string;
  status: ReportStatus;
  onRetry?: () => void;
  emptyMessage?: string;
  errorMessage?: string;
  filterBar?: React.ReactNode;
  onExportCsv?: () => void;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">{title}</h1>
          <p className="text-sm text-muted-foreground">{description}</p>
        </div>
        {status === "ready" && onExportCsv && (
          <Button variant="outline" size="sm" className="min-h-9" onClick={onExportCsv}>
            <Download className="h-4 w-4" aria-hidden /> Download CSV
          </Button>
        )}
      </div>

      {filterBar}

      {status === "loading" && (
        <div className="space-y-4" aria-busy>
          <Skeleton className="h-24 w-full rounded-xl" />
          <Skeleton className="h-64 w-full rounded-xl" />
          <Skeleton className="h-64 w-full rounded-xl" />
        </div>
      )}

      {status === "error" && (
        <Card className="flex flex-col items-center gap-3 border-destructive/40 p-10 text-center">
          <AlertCircle className="h-6 w-6 text-destructive" aria-hidden />
          <p className="text-sm text-muted-foreground">{errorMessage}</p>
          {onRetry && (
            <Button variant="outline" size="sm" onClick={onRetry}>
              Try again
            </Button>
          )}
        </Card>
      )}

      {status === "empty" && (
        <Card className="border-dashed p-10 text-center">
          <p className="text-sm text-muted-foreground">{emptyMessage}</p>
        </Card>
      )}

      {status === "ready" && children}
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/features/reports/components/report-shell.test.tsx`
Expected: PASS. If the skeleton selector fails, check `src/components/ui/skeleton.tsx` for its actual class/attribute and adjust the test's selector to match (do not change the component).

- [ ] **Step 5: Commit**

```bash
git add src/features/reports/components/report-shell.tsx src/features/reports/components/report-shell.test.tsx
git commit -m "feat(reports): ReportShell loading/empty/error/ready frame"
```

---

## Task 7: `<KpiStrip>` — the KPI card row

**Files:**
- Create: `src/features/reports/components/kpi-strip.tsx`
- Test: `src/features/reports/components/kpi-strip.test.tsx`

**Interfaces:**
- Consumes: `StatCard` from `@/components/shared/stat-card`, `Tooltip*` from `@/components/ui/tooltip`, `Link` from `next/link`, `Info` from `lucide-react`, `KPI_DEFINITIONS` / `KpiKey` from `../definitions`.
- Produces:
  - `interface KpiStripItem { key: KpiKey; label: string; value: string; accent: string; hint?: React.ReactNode; href?: string }`
  - `<KpiStrip items={KpiStripItem[]} />` — a responsive grid (`grid-cols-2 sm:grid-cols-3 xl:grid-cols-6`, gap-3) of `StatCard`s. An `href` wraps its card in a `Link`. Each card shows a small `Info` affordance whose tooltip is `KPI_DEFINITIONS[item.key]`. The strip never overflows the page horizontally (grid wraps; no fixed-width row).

- [ ] **Step 1: Write the failing test**

Create `src/features/reports/components/kpi-strip.test.tsx`:

```tsx
import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { KpiStrip } from "./kpi-strip";

describe("KpiStrip", () => {
  const items = [
    { key: "totalRevenue" as const, label: "Total Revenue", value: "₹1,20,000", accent: "#00D084" },
    { key: "netRevenue" as const, label: "Net Revenue", value: "₹85,000", accent: "#00F08A" },
    { key: "courtUtilization" as const, label: "Utilization", value: "68%", accent: "#5B6CFF", href: "/reports/court-utilization?facility=f1&preset=THIS_MONTH" },
  ];

  it("renders one card per item with its value", () => {
    render(<KpiStrip items={items} />);
    expect(screen.getByText("Total Revenue")).toBeInTheDocument();
    expect(screen.getByText("₹85,000")).toBeInTheDocument();
  });

  it("wraps an item with href in a link to that report", () => {
    render(<KpiStrip items={items} />);
    const link = screen.getByRole("link", { name: /utilization/i });
    expect(link).toHaveAttribute("href", "/reports/court-utilization?facility=f1&preset=THIS_MONTH");
  });

  it("uses a wrapping grid, not a fixed-width row", () => {
    const { container } = render(<KpiStrip items={items} />);
    expect(container.firstElementChild?.className).toMatch(/grid/);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/features/reports/components/kpi-strip.test.tsx`
Expected: FAIL — `Cannot find module './kpi-strip'`.

- [ ] **Step 3: Write `kpi-strip.tsx`**

```tsx
"use client";

import Link from "next/link";
import { Info } from "lucide-react";
import { StatCard } from "@/components/shared/stat-card";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { KPI_DEFINITIONS, type KpiKey } from "../definitions";

export interface KpiStripItem {
  key: KpiKey;
  label: string;
  /** Already formatted for display (currency, %, count). */
  value: string;
  accent: string;
  hint?: React.ReactNode;
  /** When set, the whole card links here (drill-down). */
  href?: string;
}

/**
 * The KPI row shared by every report. A wrapping grid — never a fixed-width
 * scroller — so it reflows cleanly from a 360px phone to a wide desktop
 * without the page scrolling sideways (spec §38/§54).
 */
export function KpiStrip({ items }: { items: KpiStripItem[] }) {
  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-6">
      {items.map((item, index) => {
        const card = (
          <StatCard
            icon={undefined}
            label={item.label}
            value={item.value}
            accent={item.accent}
            index={index}
            hint={
              <span className="inline-flex items-center gap-1">
                {item.hint}
                <Tooltip>
                  <TooltipTrigger asChild>
                    <button
                      type="button"
                      aria-label={`What is ${item.label}?`}
                      className="text-muted-foreground hover:text-foreground"
                    >
                      <Info className="h-3 w-3" aria-hidden />
                    </button>
                  </TooltipTrigger>
                  <TooltipContent className="max-w-xs text-xs">{KPI_DEFINITIONS[item.key]}</TooltipContent>
                </Tooltip>
              </span>
            }
            className="h-full"
          />
        );
        return item.href ? (
          <Link
            key={item.key}
            href={item.href}
            className="rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            {card}
          </Link>
        ) : (
          <div key={item.key}>{card}</div>
        );
      })}
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/features/reports/components/kpi-strip.test.tsx`
Expected: PASS. If `<Tooltip>` requires a `TooltipProvider` ancestor and the test throws, wrap the test render in the app's provider (check `src/components/ui/tooltip.tsx` — if it re-exports a provider, add it; if `app-shell.tsx` mounts one globally, add a tiny local `<TooltipProvider>` wrapper in the component instead so it is self-contained).

- [ ] **Step 5: Commit**

```bash
git add src/features/reports/components/kpi-strip.tsx src/features/reports/components/kpi-strip.test.tsx
git commit -m "feat(reports): KpiStrip card row with definition tooltips"
```

---

## Task 8: `<AnalyticsFilterBar>` + `useAnalyticsFilter` + `<AnalyticsFilterSheet>`

**Files:**
- Create: `src/features/reports/components/use-analytics-filter.ts`
- Create: `src/features/reports/components/analytics-filter-bar.tsx`
- Create: `src/features/reports/components/analytics-filter-sheet.tsx`
- Create: `src/test/fakes/fake-reports-filter-deps.ts`
- Test: `src/features/reports/components/analytics-filter-bar.test.tsx`

**Interfaces:**
- Consumes:
  - `getFacilityService().getFacilities()` → `Facility[]` (`{ id, name, ... }`)
  - `getSportsService().getFacilitySports(facilityId)` → `FacilitySport[]` (`{ id, sportId, name?, ... }` — inspect `src/features/sports-setup/types.ts` for the display-name field; use `presentSport`/existing helper if names need resolving)
  - `getPlayingAreasService().getPlayingAreas(facilityId)` → `PlayingArea[]` (`{ id, name, facilitySportId, ... }`)
  - `Select*` from `@/components/ui/select`, `Input` from `@/components/ui/input`, `Dialog*` from `@/components/ui/dialog`, `Button`
  - `filterFromSearchParams` / `filterToSearchParams` from `../url-state`; `PRESET_LABELS`, `ANALYTICS_PRESETS` from `../types`
  - `useRouter`, `usePathname`, `useSearchParams` from `next/navigation`
- Produces:
  - `useAnalyticsFilter(): { filter: AnalyticsFilter | null; setFilter: (next: AnalyticsFilter) => void; ready: boolean }` — resolves the user's facilities once, seeds `filter` from the URL (falling back to the first facility + `THIS_MONTH`), and `setFilter` does `router.replace(pathname + "?" + filterToSearchParams(next))` (scroll: false).
  - `<AnalyticsFilterBar filter onChange />` — four controls in a `flex flex-wrap gap-2` row: **Facility** `Select` (hidden when the user has ≤1 facility), **Date** `Select` of `ANALYTICS_PRESETS` + two `Input type="date"` when `CUSTOM`, **Sport** `Select` (`All Sports` + the facility's sports), **Court** `Select` (`All Courts` + courts, filtered to the chosen sport when one is set). Changing any control calls `onChange` with the next `AnalyticsFilter` (clearing `courtId` when the sport changes and the court no longer belongs).
  - `<AnalyticsFilterSheet filter onChange />` — a "Filters" `Button` opening a `Dialog` that contains the same controls stacked vertically, with an "Apply" button; used at `md:hidden`.

- [ ] **Step 1: Write the shared fake**

Create `src/test/fakes/fake-reports-filter-deps.ts`:

```ts
import { installFakeSportsService } from "@/test/fakes/fake-sports-service";
import { installFakePlayingAreasService } from "@/test/fakes/fake-playing-areas-service";
import { setFacilityService } from "@/services/facility";
import type { FacilityService } from "@/services/facility/facility.service";
import type { Facility } from "@/features/onboarding/types";

/** One facility, three sports, four courts — the fixture the filter-bar tests share. */
export function installFakeReportsFilterDeps(opts: { facilities?: number } = {}) {
  const facilities: Facility[] = Array.from({ length: opts.facilities ?? 1 }, (_, i) => ({
    id: `fac-${i + 1}`,
    name: `Facility ${i + 1}`,
  } as Facility));

  const facilityService: Partial<FacilityService> = {
    getFacility: async () => facilities[0] ?? null,
    getFacilities: async () => facilities,
  };
  setFacilityService(facilityService as FacilityService);

  const sports = installFakeSportsService();
  const courts = installFakePlayingAreasService();
  // Seed via the fakes' own row arrays / save methods — match their shapes
  // (see fake-sports-service.ts / fake-playing-areas-service.ts).
  return { facilities, sports, courts };
}
```

(When implementing: open `fake-sports-service.ts` and `fake-playing-areas-service.ts` and seed `sports`/`courts` with three `FacilitySport` and four `PlayingArea` rows for `fac-1`, two courts under the first sport. Keep the field names exactly as those types declare.)

- [ ] **Step 2: Write the failing test**

Create `src/features/reports/components/analytics-filter-bar.test.tsx`:

```tsx
import { describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AnalyticsFilterBar } from "./analytics-filter-bar";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";
import type { AnalyticsFilter } from "../types";

const filter: AnalyticsFilter = { facilityId: "fac-1", preset: "THIS_MONTH", facilitySportId: null, courtId: null };

describe("AnalyticsFilterBar", () => {
  it("offers every preset and reports a change", async () => {
    installFakeReportsFilterDeps();
    const onChange = vi.fn();
    render(<AnalyticsFilterBar filter={filter} onChange={onChange} />);

    await userEvent.click(screen.getByRole("combobox", { name: /date range/i }));
    await userEvent.click(screen.getByRole("option", { name: "This Quarter" }));
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ preset: "THIS_QUARTER" }));
  });

  it("shows custom date inputs only for CUSTOM", async () => {
    installFakeReportsFilterDeps();
    const { rerender } = render(<AnalyticsFilterBar filter={filter} onChange={vi.fn()} />);
    expect(screen.queryByLabelText(/start date/i)).not.toBeInTheDocument();
    rerender(<AnalyticsFilterBar filter={{ ...filter, preset: "CUSTOM" }} onChange={vi.fn()} />);
    expect(screen.getByLabelText(/start date/i)).toBeInTheDocument();
  });

  it("lists the facility's sports and clears the court when the sport changes", async () => {
    installFakeReportsFilterDeps();
    const onChange = vi.fn();
    render(<AnalyticsFilterBar filter={{ ...filter, facilitySportId: "fs-1", courtId: "court-1" }} onChange={onChange} />);
    await waitFor(() => expect(screen.getByRole("combobox", { name: /sport/i })).toBeInTheDocument());
    await userEvent.click(screen.getByRole("combobox", { name: /sport/i }));
    await userEvent.click(screen.getByRole("option", { name: /all sports/i }));
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ facilitySportId: null, courtId: null }));
  });

  it("hides the facility control when the user has one facility", () => {
    installFakeReportsFilterDeps({ facilities: 1 });
    render(<AnalyticsFilterBar filter={filter} onChange={vi.fn()} />);
    expect(screen.queryByRole("combobox", { name: /facility/i })).not.toBeInTheDocument();
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `npm test -- src/features/reports/components/analytics-filter-bar.test.tsx`
Expected: FAIL — `Cannot find module './analytics-filter-bar'`.

- [ ] **Step 4: Write `use-analytics-filter.ts`**

```ts
"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { getFacilityService } from "@/services/facility";
import type { Facility } from "@/features/onboarding/types";
import { filterFromSearchParams, filterToSearchParams } from "../url-state";
import { DEFAULT_FILTER_PRESET, type AnalyticsFilter } from "../types";

/**
 * The report filter, sourced from and written back to the URL query string.
 * On first load, when the URL has no facility, the user's first facility is
 * used. `setFilter` replaces (not pushes) so the back button doesn't step
 * through every tweak.
 */
export function useAnalyticsFilter(): {
  filter: AnalyticsFilter | null;
  facilities: Facility[];
  setFilter: (next: AnalyticsFilter) => void;
  ready: boolean;
} {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const [facilities, setFacilities] = useState<Facility[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    getFacilityService()
      .getFacilities()
      .then((list) => !cancelled && setFacilities(list))
      .catch(() => !cancelled && setFacilities([]));
    return () => {
      cancelled = true;
    };
  }, []);

  const fallbackFacilityId = facilities?.[0]?.id ?? "";
  const filter = useMemo<AnalyticsFilter | null>(() => {
    if (facilities === null) return null;
    if (!fallbackFacilityId) return null;
    return filterFromSearchParams(params, fallbackFacilityId);
  }, [facilities, fallbackFacilityId, params]);

  const setFilter = useCallback(
    (next: AnalyticsFilter) => {
      router.replace(`${pathname}?${filterToSearchParams(next).toString()}`, { scroll: false });
    },
    [router, pathname],
  );

  return {
    filter,
    facilities: facilities ?? [],
    setFilter,
    ready: facilities !== null && Boolean(fallbackFacilityId),
  };
}

export { DEFAULT_FILTER_PRESET };
```

- [ ] **Step 5: Write `analytics-filter-bar.tsx`**

```tsx
"use client";

import { useEffect, useState } from "react";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { getFacilityService } from "@/services/facility";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import type { Facility } from "@/features/onboarding/types";
import { ANALYTICS_PRESETS, PRESET_LABELS, type AnalyticsFilter, type AnalyticsPreset } from "../types";

const ALL_SPORTS = "__all_sports__";
const ALL_COURTS = "__all_courts__";

interface SportOption { id: string; name: string }
interface CourtOption { id: string; name: string; facilitySportId: string }

export function AnalyticsFilterBar({
  filter,
  onChange,
}: {
  filter: AnalyticsFilter;
  onChange: (next: AnalyticsFilter) => void;
}) {
  const [facilities, setFacilities] = useState<Facility[]>([]);
  const [sports, setSports] = useState<SportOption[]>([]);
  const [courts, setCourts] = useState<CourtOption[]>([]);

  useEffect(() => {
    let cancelled = false;
    getFacilityService().getFacilities().then((l) => !cancelled && setFacilities(l)).catch(() => {});
    return () => { cancelled = true; };
  }, []);

  useEffect(() => {
    let cancelled = false;
    const fid = filter.facilityId;
    if (!fid) return;
    Promise.all([
      getSportsService().getFacilitySports(fid),
      getPlayingAreasService().getPlayingAreas(fid),
    ])
      .then(([fs, cs]) => {
        if (cancelled) return;
        // Field names per src/features/sports-setup/types.ts — resolve the
        // display name the same way the Sports Setup UI does.
        setSports(fs.map((s) => ({ id: s.id, name: sportDisplayName(s) })));
        setCourts(cs.map((c) => ({ id: c.id, name: c.name, facilitySportId: c.facilitySportId })));
      })
      .catch(() => {
        if (!cancelled) { setSports([]); setCourts([]); }
      });
    return () => { cancelled = true; };
  }, [filter.facilityId]);

  const visibleCourts = filter.facilitySportId
    ? courts.filter((c) => c.facilitySportId === filter.facilitySportId)
    : courts;

  return (
    <div className="flex flex-wrap items-center gap-2">
      {facilities.length > 1 && (
        <Select
          value={filter.facilityId}
          onValueChange={(v) => onChange({ ...filter, facilityId: v, facilitySportId: null, courtId: null })}
        >
          <SelectTrigger className="w-[180px]" aria-label="Facility"><SelectValue /></SelectTrigger>
          <SelectContent>
            {facilities.map((f) => <SelectItem key={f.id} value={f.id}>{f.name}</SelectItem>)}
          </SelectContent>
        </Select>
      )}

      <Select
        value={filter.preset}
        onValueChange={(v) =>
          onChange({
            ...filter,
            preset: v as AnalyticsPreset,
            startDate: v === "CUSTOM" ? filter.startDate ?? null : null,
            endDate: v === "CUSTOM" ? filter.endDate ?? null : null,
          })
        }
      >
        <SelectTrigger className="w-[160px]" aria-label="Date range"><SelectValue /></SelectTrigger>
        <SelectContent>
          {ANALYTICS_PRESETS.map((p) => <SelectItem key={p} value={p}>{PRESET_LABELS[p]}</SelectItem>)}
        </SelectContent>
      </Select>

      {filter.preset === "CUSTOM" && (
        <>
          <Input
            type="date" aria-label="Start date" className="w-[150px]"
            value={filter.startDate ?? ""}
            onChange={(e) => onChange({ ...filter, startDate: e.target.value })}
          />
          <span className="text-sm text-muted-foreground">to</span>
          <Input
            type="date" aria-label="End date" className="w-[150px]"
            value={filter.endDate ?? ""}
            onChange={(e) => onChange({ ...filter, endDate: e.target.value })}
          />
        </>
      )}

      <Select
        value={filter.facilitySportId ?? ALL_SPORTS}
        onValueChange={(v) =>
          onChange({ ...filter, facilitySportId: v === ALL_SPORTS ? null : v, courtId: null })
        }
      >
        <SelectTrigger className="w-[150px]" aria-label="Sport"><SelectValue /></SelectTrigger>
        <SelectContent>
          <SelectItem value={ALL_SPORTS}>All Sports</SelectItem>
          {sports.map((s) => <SelectItem key={s.id} value={s.id}>{s.name}</SelectItem>)}
        </SelectContent>
      </Select>

      <Select
        value={filter.courtId ?? ALL_COURTS}
        onValueChange={(v) => onChange({ ...filter, courtId: v === ALL_COURTS ? null : v })}
      >
        <SelectTrigger className="w-[150px]" aria-label="Court"><SelectValue /></SelectTrigger>
        <SelectContent>
          <SelectItem value={ALL_COURTS}>All Courts</SelectItem>
          {visibleCourts.map((c) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}
        </SelectContent>
      </Select>
    </div>
  );
}

/** Resolve a FacilitySport's label — mirror src/features/sports-setup logic. */
function sportDisplayName(fs: { name?: string; customSportName?: string | null }): string {
  return fs.customSportName?.trim() || fs.name || "Sport";
}
```

**Implementer note:** open `src/features/sports-setup/types.ts` + `src/features/sports-setup/constants.ts` and confirm the real `FacilitySport` field for the display name; adjust `sportDisplayName` to match (there is a `presentSport` helper referenced in `fake-sports-service.ts`). Same for `PlayingArea.facilitySportId` in `src/features/courts-setup/types.ts`.

- [ ] **Step 6: Write `analytics-filter-sheet.tsx`**

```tsx
"use client";

import { useState } from "react";
import { SlidersHorizontal } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { AnalyticsFilterBar } from "./analytics-filter-bar";
import type { AnalyticsFilter } from "../types";

/** Mobile filter entry point — the same controls in a sheet (spec §38). */
export function AnalyticsFilterSheet({
  filter,
  onChange,
}: {
  filter: AnalyticsFilter;
  onChange: (next: AnalyticsFilter) => void;
}) {
  const [open, setOpen] = useState(false);
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm" className="min-h-9">
          <SlidersHorizontal className="h-4 w-4" aria-hidden /> Filters
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Filters</DialogTitle>
        </DialogHeader>
        <div className="[&_.flex-wrap]:flex-col [&_.flex-wrap>*]:w-full [&_[data-slot=select-trigger]]:w-full">
          <AnalyticsFilterBar filter={filter} onChange={onChange} />
        </div>
        <Button onClick={() => setOpen(false)}>Apply</Button>
      </DialogContent>
    </Dialog>
  );
}
```

(If the `[&_...]` utility overrides prove brittle against the real `Select` markup, give `AnalyticsFilterBar` an optional `layout?: "row" | "stack"` prop instead and switch the container class on it — decide during implementation, keep whichever is simpler.)

- [ ] **Step 7: Run test to verify it passes**

Run: `npm test -- src/features/reports/components/analytics-filter-bar.test.tsx`
Expected: PASS. Radix `Select` in jsdom: if `userEvent.click` on an option doesn't fire `onValueChange`, follow the pattern already used in `src/components/form/select-field.test.tsx` (check how that existing test drives a Radix Select) and mirror it.

- [ ] **Step 8: Full suite + typecheck + lint + build**

Run: `npm test && npm run typecheck && npm run lint && npm run build`
Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add src/features/reports/components/use-analytics-filter.ts src/features/reports/components/analytics-filter-bar.tsx src/features/reports/components/analytics-filter-sheet.tsx src/test/fakes/fake-reports-filter-deps.ts src/features/reports/components/analytics-filter-bar.test.tsx
git commit -m "feat(reports): AnalyticsFilterBar + URL-backed useAnalyticsFilter + mobile sheet"
```

---

## Task 9: Wire the filter bar + shell into every report page

**Files:**
- Modify: `src/features/reports/components/coming-soon-report.tsx` → replace with a version that renders `<ReportShell>` + the real filter bar
- Modify: `src/features/reports/components/reports-overview.tsx` and the five other report components to pass a `title` / `description` / `emptyMessage` through
- Test: `src/features/reports/components/coming-soon-report.test.tsx`

**Interfaces:**
- Consumes: `useAnalyticsFilter`, `<AnalyticsFilterBar>`, `<AnalyticsFilterSheet>`, `<ReportShell>`.
- Produces: `<ComingSoonReport title description emptyMessage? />` now renders the full frame — filter bar (desktop) / sheet trigger (mobile), `ReportShell` with `status="empty"` and the report's `emptyMessage`, so each page already shows its real chrome. Later phases swap the `status`/body for live data but keep this exact shell usage.

- [ ] **Step 1: Write the failing test**

Create `src/features/reports/components/coming-soon-report.test.tsx`:

```tsx
import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { ComingSoonReport } from "./coming-soon-report";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";

describe("ComingSoonReport", () => {
  it("renders the title, a filter control and an empty-state message", async () => {
    installFakeReportsFilterDeps();
    render(<ComingSoonReport title="Booking Report" description="desc" emptyMessage="No booking data for this period." />);
    expect(await screen.findByRole("heading", { name: "Booking Report" })).toBeInTheDocument();
    expect(screen.getByText("No booking data for this period.")).toBeInTheDocument();
    // a date-range control is present (desktop bar or mobile sheet trigger)
    expect(
      screen.queryByRole("combobox", { name: /date range/i }) ?? screen.getByRole("button", { name: /filters/i }),
    ).toBeTruthy();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/features/reports/components/coming-soon-report.test.tsx`
Expected: FAIL — the current `ComingSoonReport` renders no filter control / no `ReportShell`.

- [ ] **Step 3: Rewrite `coming-soon-report.tsx`**

```tsx
"use client";

import { useAnalyticsFilter } from "./use-analytics-filter";
import { AnalyticsFilterBar } from "./analytics-filter-bar";
import { AnalyticsFilterSheet } from "./analytics-filter-sheet";
import { ReportShell } from "./report-shell";

/**
 * The report frame with the real filter bar, an empty body. Each phase
 * replaces the body (and flips `status` to loading/ready) for its report but
 * keeps this exact shell + filter wiring.
 */
export function ComingSoonReport({
  title,
  description,
  emptyMessage = "This report arrives in a later phase.",
}: {
  title: string;
  description: string;
  emptyMessage?: string;
}) {
  const { filter, setFilter, ready } = useAnalyticsFilter();

  const filterBar =
    ready && filter ? (
      <>
        <div className="hidden md:block">
          <AnalyticsFilterBar filter={filter} onChange={setFilter} />
        </div>
        <div className="md:hidden">
          <AnalyticsFilterSheet filter={filter} onChange={setFilter} />
        </div>
      </>
    ) : null;

  return (
    <ReportShell
      title={title}
      description={description}
      status={ready ? "empty" : "loading"}
      emptyMessage={emptyMessage}
      filterBar={filterBar}
    >
      <div />
    </ReportShell>
  );
}
```

- [ ] **Step 4: Give each report component its copy**

Update the six components so each passes a report-specific `emptyMessage` (spec §43):

- `reports-overview.tsx` → `emptyMessage="No activity for this period yet."`
- `booking-report.tsx` → `"No booking data for this period."`
- `court-utilization-report.tsx` → `"No court activity for this period."`
- `revenue-report.tsx` → `"No revenue data for this period."`
- `membership-report.tsx` → `"No membership activity for this period."`
- `guest-booking-report.tsx` → `"No guest bookings for this period."`

(Keep the `title`/`description` strings from Task 5.)

- [ ] **Step 5: Run test to verify it passes**

Run: `npm test -- src/features/reports/components/coming-soon-report.test.tsx`
Expected: PASS.

- [ ] **Step 6: Full green + manual pass**

Run: `npm test && npm run typecheck && npm run lint && npm run build`
Expected: all green.

Run `npm run dev`: each `/reports*` page shows its header, a working date/sport/court filter that writes to the URL (`?facility=…&preset=…`), and its own empty-state line. Resize to a phone width — the bar collapses to a **Filters** button opening the sheet, and nothing scrolls sideways.

- [ ] **Step 7: Commit**

```bash
git add src/features/reports/components
git commit -m "feat(reports): every report page renders the live filter bar + shell"
```

---

## Self-Review (completed while writing)

**Spec coverage (Phase 1 rows only):**
- §2 nav / §37 layout — Task 5 (nav) + Task 6 (`ReportShell` header) + Task 9 (bar placement). ✅
- §3 global filter bar (facility/date/sport/court + all presets, default This Month) — Tasks 2, 8. ✅
- §30 shared filter model — Task 2 (`AnalyticsFilter`). ✅
- §31 auto date aggregation — Task 3 (`pickGranularity`); consumed from Phase 2. ✅
- §36 RLS/roles — Task 5 (`roles: ["admin","staff"]`); RPC guards are later phases. ✅
- §43 empty / §44 loading / §45 error — Task 6 (`ReportShell` three distinct states). ✅
- §47/§48 freshness — Task 2 (`FRESHNESS_NOTE`). ✅
- §53 data definitions — Task 2 (`KPI_DEFINITIONS`) + Task 7 (tooltips). ✅
- §54 accessibility (keyboard filter, no colour-only, large-text reflow) — Tasks 7, 8 (`aria-label`s, grid reflow, tooltip button). ✅
- §40 export foundation — Task 3 (`toCsv`); wired to pages from Phase 2. ✅
- Migration `0056` — Task 1. ✅

Deferred to later phases by design: every RPC, every real KPI value, charts, drill-down targets that need report data, comparison-period rendering.

**Placeholder scan:** none — every step has literal code. Two "implementer note" callouts (sport display-name field, Radix Select test-driving) point at specific existing files to copy from, not vague instructions.

**Type consistency:** `AnalyticsFilter` shape identical across `types.ts`, `url-state.ts`, `aggregation.ts`, `use-analytics-filter.ts`, `analytics-filter-bar.tsx`. `KpiKey` used identically in `definitions.ts` and `kpi-strip.tsx`. `ReportStatus` values (`loading|error|empty|ready`) consistent between `report-shell.tsx` and `coming-soon-report.tsx`.
