# Reports & Analytics — Phase 6: Membership Report — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use `- [ ]`.

> **Status: implemented (2026-09-04), pending user verification + commit.** Notes:
> - Built on Phase 5 (`cedcd97`). `membershipOutstanding` added to `KpiKey` + `KPI_DEFINITIONS`.
> - `get_membership_analytics` calls `get_revenue_breakdown` internally for membership revenue (matches Finance). Payment-completion counts (`paid`/`partial`/`pending`) + `outstanding_minor` cover memberships **created in the range**; `active_members` / `expiring_soon` are a current snapshot.
> - **`next build` not run** (standing rule). `tsc` + `next lint` + `vitest` (96 reports tests) + dev server compiles clean. Full suite **625/625**.

**Goal:** `/reports/memberships` — active / new / expiring members, membership revenue + payment completion, a by-type table, a Membership Session capacity panel, and a Guest Release panel.

**Architecture:** One migration (`0061`) adds four RPCs over `memberships`, `membership_sessions`, `membership_session_bookings` and `payments`. Membership revenue is taken from the existing `get_revenue_breakdown` (called inside `get_membership_analytics`) so it matches Finance. `<MembershipReport>` follows the established assembly pattern; no new chart/table components.

**Tech Stack:** PostgreSQL (Supabase), Next.js 15 / React 19, TypeScript, Vitest.

**Spec:** `docs/superpowers/specs/2026-09-03-reports-analytics-design.md` §17, §18, §19, §20, §42, §43, §52.

## Global Constraints

- Branch `feat/reports-analytics`. HEAD is Phase 4 (`0d3f6f0`); **Phase 5 is uncommitted in the working tree** — this phase stacks on it.
- **No business logic.** Membership `status`, `membership_type`, session capacity and `released_capacity`, and slot-booking `status` are read as-is. Revenue comes from Finance's `get_revenue_breakdown`.
- **Enums, verbatim:** `membership_status` = `active | expired | cancelled | pending`. `memberships.membership_type` ∈ `INDIVIDUAL | FAMILY | CORPORATE`. `membership_session_bookings.participant_type` ∈ `MEMBER | GUEST`, `.status` ∈ `CONFIRMED | CANCELLED`, `.slot_source` ∈ `MEMBERSHIP | RELEASED`.
- **Membership plan_id is nullable** (`0028`) — join `membership_plans` with `left join`, label a null plan `—`.
- **Session usage is never revenue** (spec §19/§52). `member_allocations` = confirmed MEMBER slot bookings. `unused_capacity = total_capacity − member_allocations − guest_booked` (matches §19's `500 − 360 − 75 = 65`).
- **Membership analytics is not sport/court scoped** (`get_membership_analytics`, `get_memberships_by_type`) — a membership is not court-bound. **Session + guest-release analytics ARE** sport/court scoped (via `membership_sessions.facility_sport_id` / `.court_id`).
- **Date scoping:** new-membership + by-type + payment-completion counts cover memberships **created in the range** (`memberships.created_at`). "Active members" and "expiring soon" are **as of now** (not range-scoped) — a current snapshot. Sessions are scoped by `session_date` in the range (resolved to local dates via the facility timezone). Guest-release revenue is scoped by `coalesce(payments.paid_at, created_at)` in the range.
- **Deferred (spec §17):** Membership Retention — no `renewed_from` linkage exists; not attempted.
- Migration `0061_analytics_memberships.sql` — new file, immutable once shipped.
- `database.types.ts` — four `Functions` entries.
- No SQL harness — `0061` verified by the manual task (Task 4). §52 fixture becomes a check.
- Per phase: `npm run typecheck` (no *new* errors), `npx next lint --dir src`, `npx vitest run`. **No `next build` while `next dev` runs.**
- Commit only after verification + explicit user go-ahead.

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/0061_analytics_memberships.sql` | **Create.** `get_membership_analytics`, `get_memberships_by_type`, `get_membership_session_analytics`, `get_guest_release_analytics`. |
| `src/types/database.types.ts` | **Modify.** Four `Functions` entries. |
| `src/features/reports/types.ts` | **Modify.** `MembershipAnalytics`, `MembershipTypeRow`, `MembershipSessionAnalytics`, `GuestReleaseAnalytics`. |
| `src/services/reports/reports.service.ts` | **Modify.** Four methods. |
| `src/services/reports/supabase-reports.service.ts` | **Modify.** Four RPC calls. |
| `src/services/reports/supabase-reports.service.test.ts` | **Modify.** Contract tests. |
| `src/test/fakes/fake-reports-service.ts` | **Modify.** Four fields + methods. |
| `src/features/reports/components/membership-report.tsx` | **Rewrite.** The assembled report. |
| `src/features/reports/components/membership-report.test.tsx` | **Create.** |
| `src/features/reports/definitions.ts` | **Modify.** Add `membershipPaymentCompletion` + `membershipTypes` keys (or reuse existing membership keys). |

---

## Task 1: Migration `0061`

**Files:** Create `supabase/migrations/0061_analytics_memberships.sql`

**Interfaces — Produces** (`has_facility_role` → `42501`; `resolve_finance_date_range`; `grant execute … to authenticated`):
- `get_membership_analytics(p_facility_id, p_preset, p_start_date, p_end_date)` → `table (active_members bigint, new_memberships bigint, expiring_soon bigint, membership_revenue_minor bigint, paid_count bigint, partially_paid_count bigint, pending_count bigint, outstanding_minor bigint)`
- `get_memberships_by_type(p_facility_id, p_preset, p_start_date, p_end_date)` → `table (membership_type text, plan_name text, count bigint, revenue_minor bigint)`
- `get_membership_session_analytics(p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_id, p_court_id)` → `table (session_count bigint, total_capacity bigint, member_allocations bigint, guest_released bigint, guest_booked bigint, remaining_released bigint, unused_capacity bigint)`
- `get_guest_release_analytics(p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_id, p_court_id)` → `table (released bigint, booked bigint, remaining bigint, revenue_minor bigint)`

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 6: Memberships, sessions, guest release.
--
-- Membership revenue is Finance's (get_revenue_breakdown). Session usage is
-- never revenue — member_allocations counts confirmed MEMBER slot bookings,
-- and unused_capacity = capacity − member_allocations − guest_booked
-- (spec §19). New-membership / by-type / payment-completion figures cover
-- memberships created in the range; active_members and expiring_soon are a
-- current snapshot.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_membership_analytics(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null
) returns table (
  active_members bigint,
  new_memberships bigint,
  expiring_soon bigint,
  membership_revenue_minor bigint,
  paid_count bigint,
  partially_paid_count bigint,
  pending_count bigint,
  outstanding_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  today date;
  v_rev bigint;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  select coalesce(timezone, 'Asia/Kolkata') into tz from facilities where id = p_facility_id;
  today := (now() at time zone tz)::date;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  select b.membership_revenue_minor into v_rev
    from get_revenue_breakdown(p_facility_id, p_preset, p_start_date, p_end_date) b;

  return query
  with new_m as (
    select
      mm.id,
      (coalesce(mm.total_amount_inr, mm.membership_fee_inr, mp.price_inr, 0) * 100)::bigint as total_minor,
      (coalesce(
        (select sum(pp.amount_inr) from payments pp where pp.membership_id = mm.id and pp.status = 'paid'),
        0
      ) * 100)::bigint as paid_minor
    from memberships mm
    left join membership_plans mp on mp.id = mm.plan_id
    where mm.facility_id = p_facility_id
      and range_ @> mm.created_at
  )
  select
    (select count(*) from memberships where facility_id = p_facility_id and status = 'active')::bigint,
    (select count(*) from new_m)::bigint,
    (select count(*) from memberships
       where facility_id = p_facility_id and status = 'active'
         and end_date >= today and end_date <= today + 30)::bigint,
    coalesce(v_rev, 0),
    (select count(*) from new_m where total_minor > 0 and paid_minor >= total_minor)::bigint,
    (select count(*) from new_m where paid_minor > 0 and paid_minor < total_minor)::bigint,
    (select count(*) from new_m where paid_minor = 0 and total_minor > 0)::bigint,
    (select coalesce(sum(greatest(total_minor - paid_minor, 0)), 0) from new_m)::bigint;
end;
$$;

grant execute on function get_membership_analytics(uuid, text, date, date) to authenticated;


create or replace function get_memberships_by_type(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null
) returns table (
  membership_type text,
  plan_name text,
  count bigint,
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
  with m as (
    select
      mm.membership_type,
      coalesce(mp.name, '—') as plan_name,
      (coalesce(
        (select sum(pp.amount_inr) from payments pp where pp.membership_id = mm.id and pp.status = 'paid'),
        0
      ) * 100)::bigint as paid_minor
    from memberships mm
    left join membership_plans mp on mp.id = mm.plan_id
    where mm.facility_id = p_facility_id
      and range_ @> mm.created_at
  )
  select m.membership_type, m.plan_name, count(*)::bigint, coalesce(sum(m.paid_minor), 0)::bigint
  from m
  group by m.membership_type, m.plan_name
  order by count(*) desc, m.membership_type;
end;
$$;

grant execute on function get_memberships_by_type(uuid, text, date, date) to authenticated;


create or replace function get_membership_session_analytics(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  session_count bigint,
  total_capacity bigint,
  member_allocations bigint,
  guest_released bigint,
  guest_booked bigint,
  remaining_released bigint,
  unused_capacity bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  start_d date;
  end_d date;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  select coalesce(timezone, 'Asia/Kolkata') into tz from facilities where id = p_facility_id;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);
  start_d := (lower(range_) at time zone tz)::date;
  end_d := ((upper(range_) - interval '1 microsecond') at time zone tz)::date;

  return query
  with s as (
    select
      ms.capacity,
      ms.released_capacity,
      (select count(*) from membership_session_bookings b
         where b.session_id = ms.id and b.participant_type = 'MEMBER' and b.status = 'CONFIRMED') as member_cnt,
      (select count(*) from membership_session_bookings b
         where b.session_id = ms.id and b.participant_type = 'GUEST' and b.status = 'CONFIRMED') as guest_cnt
    from membership_sessions ms
    where ms.facility_id = p_facility_id
      and ms.session_date >= start_d
      and ms.session_date <= end_d
      and (p_facility_sport_id is null or ms.facility_sport_id = p_facility_sport_id)
      and (p_court_id is null or ms.court_id = p_court_id)
  )
  select
    count(*)::bigint,
    coalesce(sum(capacity), 0)::bigint,
    coalesce(sum(member_cnt), 0)::bigint,
    coalesce(sum(released_capacity), 0)::bigint,
    coalesce(sum(guest_cnt), 0)::bigint,
    coalesce(sum(released_capacity) - sum(guest_cnt), 0)::bigint,
    coalesce(sum(capacity) - sum(member_cnt) - sum(guest_cnt), 0)::bigint
  from s;
end;
$$;

grant execute on function get_membership_session_analytics(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_guest_release_analytics(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  released bigint,
  booked bigint,
  remaining bigint,
  revenue_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  start_d date;
  end_d date;
  v_released bigint;
  v_booked bigint;
  v_rev bigint;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  select coalesce(timezone, 'Asia/Kolkata') into tz from facilities where id = p_facility_id;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);
  start_d := (lower(range_) at time zone tz)::date;
  end_d := ((upper(range_) - interval '1 microsecond') at time zone tz)::date;

  select
    coalesce(sum(ms.released_capacity), 0),
    coalesce(sum((
      select count(*) from membership_session_bookings b
      where b.session_id = ms.id and b.participant_type = 'GUEST' and b.status = 'CONFIRMED'
    )), 0)
  into v_released, v_booked
  from membership_sessions ms
  where ms.facility_id = p_facility_id
    and ms.session_date >= start_d
    and ms.session_date <= end_d
    and (p_facility_sport_id is null or ms.facility_sport_id = p_facility_sport_id)
    and (p_court_id is null or ms.court_id = p_court_id);

  select coalesce(sum(p.amount_inr), 0) * 100
  into v_rev
  from payments p
  join membership_session_bookings msb on msb.id = p.membership_session_booking_id
  join membership_sessions ms on ms.id = msb.session_id
  where p.facility_id = p_facility_id
    and p.status = 'paid'
    and range_ @> coalesce(p.paid_at, p.created_at)
    and (p_facility_sport_id is null or ms.facility_sport_id = p_facility_sport_id)
    and (p_court_id is null or ms.court_id = p_court_id);

  return query select
    v_released::bigint,
    v_booked::bigint,
    greatest(v_released - v_booked, 0)::bigint,
    v_rev::bigint;
end;
$$;

grant execute on function get_guest_release_analytics(uuid, text, date, date, uuid, uuid) to authenticated;
```

- [ ] **Step 2: Parse-sanity** — the four function names present.

---

## Task 2: types + `database.types.ts` + service + fake

- [ ] **Step 1: `types.ts`** — append:

```ts
// ─── Phase 6: Memberships ────────────────────────────────────────────────

export interface MembershipAnalytics {
  activeMembers: number;
  newMemberships: number;
  expiringSoon: number;
  membershipRevenueMinor: number;
  paidCount: number;
  partiallyPaidCount: number;
  pendingCount: number;
  outstandingMinor: number;
}

export interface MembershipTypeRow {
  membershipType: string;
  planName: string;
  count: number;
  revenueMinor: number;
}

export interface MembershipSessionAnalytics {
  sessionCount: number;
  totalCapacity: number;
  memberAllocations: number;
  guestReleased: number;
  guestBooked: number;
  remainingReleased: number;
  unusedCapacity: number;
}

export interface GuestReleaseAnalytics {
  released: number;
  booked: number;
  remaining: number;
  revenueMinor: number;
}
```

- [ ] **Step 2: `database.types.ts`** — after `get_analytics_overview`, add:
  - `get_membership_analytics` Args `{ p_facility_id, p_preset?, p_start_date?, p_end_date? }` (**no sport/court**), Returns `{ active_members; new_memberships; expiring_soon; membership_revenue_minor; paid_count; partially_paid_count; pending_count; outstanding_minor }[]` (all `number`).
  - `get_memberships_by_type` same Args, Returns `{ membership_type: string; plan_name: string; count: number; revenue_minor: number }[]`.
  - `get_membership_session_analytics` Args with sport/court, Returns `{ session_count; total_capacity; member_allocations; guest_released; guest_booked; remaining_released; unused_capacity }[]` (all `number`).
  - `get_guest_release_analytics` Args with sport/court, Returns `{ released; booked; remaining; revenue_minor }[]` (all `number`).

- [ ] **Step 3: `reports.service.ts`** — add signatures + import the four types:
```ts
  getMembershipAnalytics(filter: AnalyticsFilter): Promise<MembershipAnalytics>;
  getMembershipsByType(filter: AnalyticsFilter): Promise<MembershipTypeRow[]>;
  getMembershipSessionAnalytics(filter: AnalyticsFilter): Promise<MembershipSessionAnalytics>;
  getGuestReleaseAnalytics(filter: AnalyticsFilter): Promise<GuestReleaseAnalytics>;
```

- [ ] **Step 4: `supabase-reports.service.ts`**:
```ts
async getMembershipAnalytics(filter: AnalyticsFilter): Promise<MembershipAnalytics> {
  const { data, error } = await this.supabase.rpc("get_membership_analytics", {
    p_facility_id: filter.facilityId,
    ...dateRangeArgs(filter),
  });
  if (error || !data?.[0]) throw this.mapError(error);
  const r = data[0];
  return {
    activeMembers: r.active_members,
    newMemberships: r.new_memberships,
    expiringSoon: r.expiring_soon,
    membershipRevenueMinor: r.membership_revenue_minor,
    paidCount: r.paid_count,
    partiallyPaidCount: r.partially_paid_count,
    pendingCount: r.pending_count,
    outstandingMinor: r.outstanding_minor,
  };
}

async getMembershipsByType(filter: AnalyticsFilter): Promise<MembershipTypeRow[]> {
  const { data, error } = await this.supabase.rpc("get_memberships_by_type", {
    p_facility_id: filter.facilityId,
    ...dateRangeArgs(filter),
  });
  if (error) throw this.mapError(error);
  return (data ?? []).map((r) => ({
    membershipType: r.membership_type,
    planName: r.plan_name,
    count: r.count,
    revenueMinor: r.revenue_minor,
  }));
}

async getMembershipSessionAnalytics(filter: AnalyticsFilter): Promise<MembershipSessionAnalytics> {
  const { data, error } = await this.supabase.rpc("get_membership_session_analytics", this.baseArgs(filter));
  if (error || !data?.[0]) throw this.mapError(error);
  const r = data[0];
  return {
    sessionCount: r.session_count,
    totalCapacity: r.total_capacity,
    memberAllocations: r.member_allocations,
    guestReleased: r.guest_released,
    guestBooked: r.guest_booked,
    remainingReleased: r.remaining_released,
    unusedCapacity: r.unused_capacity,
  };
}

async getGuestReleaseAnalytics(filter: AnalyticsFilter): Promise<GuestReleaseAnalytics> {
  const { data, error } = await this.supabase.rpc("get_guest_release_analytics", this.baseArgs(filter));
  if (error || !data?.[0]) throw this.mapError(error);
  const r = data[0];
  return { released: r.released, booked: r.booked, remaining: r.remaining, revenueMinor: r.revenue_minor };
}
```

- [ ] **Step 5: `supabase-reports.service.test.ts`** — `describe("SupabaseReportsService memberships")` with: `getMembershipAnalytics` (RPC name, facility+date args only, mapping, one `REPORTS_ACCESS_DENIED`), `getMembershipsByType` (mapping), `getMembershipSessionAnalytics` (full `baseArgs`, mapping — assert `unusedCapacity` maps), `getGuestReleaseAnalytics` (mapping).

- [ ] **Step 6: `fake-reports-service.ts`** — four fields (zeroed) + four param-less methods.

- [ ] **Step 7:** `npx vitest run src/services/reports` + `npm run typecheck`.

---

## Task 3: `<MembershipReport>`

**Files:** rewrite `membership-report.tsx`; create `membership-report.test.tsx`

**Behaviour** (pattern per `court-utilization-report.tsx`):
- `load()` = `Promise.all([getMembershipAnalytics, getMembershipsByType, getMembershipSessionAnalytics, getGuestReleaseAnalytics])`. No previous-period.
- `status`: `loading` → `error` (`onRetry`) → `empty` when `analytics.activeMembers === 0 && analytics.newMemberships === 0 && session.sessionCount === 0` → `ready`.
- **KPI strip** (6): Active Members, New Memberships, Expiring Soon, Membership Revenue (`formatCurrency`), Membership Outstanding (`formatCurrency`), Session Utilization (`session.totalCapacity ? round((memberAllocations+guestBooked)/totalCapacity*100) : 0` + `%`).
- **`<Card>` "Membership Payments"** — a small table: Paid / Partially Paid / Pending counts + Outstanding amount. (`<DataTable caption="Membership payment completion">` rows `[{status:"Paid", count}, {status:"Partially paid", count}, {status:"Pending", count}]` + a line "Outstanding: <amount>".)
- **`<Card>` "Membership Types"** — `<ReportBarList>` (value = `count`, caption = `<count> · <formatCurrency(revenueMinor)>`) + `<DataTable caption="Memberships by type" columns=[Type, Plan, Count, Revenue]>`. Label = `membershipType` (title-case) + plan when not `—`.
- **`<Card>` "Membership Sessions"** — labelled rows (`<DataTable caption="Membership session capacity">` or a small grid): Total Capacity, Member Allocations, Guest Released, Guest Booked, Remaining Released, Unused Capacity. Plus a "usage never counts as revenue" `<p className="text-[11px] text-muted-foreground">`.
- **`<Card>` "Guest Release"** — Released / Booked / Remaining + Revenue (`formatCurrency`). Small `<DataTable>` or labelled rows. A "View pending →" link? No — just the numbers. Add `<Link href="/reports/guest-bookings?…">` "Guest booking detail →".
- `onExportCsv`: KPIs + by-type rows + session panel + guest-release panel, filename `memberships-<facilityId>-<preset>.csv`.

- [ ] **Step 1: `definitions.ts`** — the membership KPI keys already exist (`activeMembers`, `newMemberships`, `expiringMemberships`, `membershipRevenue`, `membershipSessionUtilization`, `guestReleased`, `guestBooked`, `guestRemaining`, `guestReleaseRevenue`). Add one: `membershipOutstanding: "Membership fees still owed on memberships created in the range (total price minus payments collected)."` + the `KpiKey` union entry.

- [ ] **Step 2: `membership-report.test.tsx`**

```tsx
import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { MembershipReport } from "./membership-report";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";
import { installFakeReportsService } from "@/test/fakes/fake-reports-service";

const SLOW = { timeout: 4000 } as const;

function setup() {
  installFakeReportsFilterDeps();
  return installFakeReportsService();
}

describe("MembershipReport", () => {
  it("shows the empty state with no membership activity", async () => {
    setup();
    render(<MembershipReport />);
    expect(await screen.findByText(/no membership activity/i, {}, SLOW)).toBeInTheDocument();
  });

  it("renders KPIs, the by-type table and the session panel", async () => {
    const reports = setup();
    reports.membershipAnalytics = {
      activeMembers: 84, newMemberships: 12, expiringSoon: 5,
      membershipRevenueMinor: 60_000_00, paidCount: 9, partiallyPaidCount: 2, pendingCount: 1,
      outstandingMinor: 10_000_00,
    };
    reports.membershipsByType = [
      { membershipType: "INDIVIDUAL", planName: "Monthly", count: 8, revenueMinor: 40_000_00 },
      { membershipType: "FAMILY", planName: "—", count: 4, revenueMinor: 20_000_00 },
    ];
    reports.membershipSessionAnalytics = {
      sessionCount: 40, totalCapacity: 500, memberAllocations: 360,
      guestReleased: 100, guestBooked: 75, remainingReleased: 25, unusedCapacity: 65,
    };
    reports.guestReleaseAnalytics = { released: 100, booked: 75, remaining: 25, revenueMinor: 38_000_00 };

    render(<MembershipReport />);

    expect(await screen.findByText("84", {}, SLOW)).toBeInTheDocument(); // active members
    expect(screen.getByRole("table", { name: /memberships by type/i })).toBeInTheDocument();
    expect(screen.getByText("65")).toBeInTheDocument(); // unused capacity
  });
});
```

- [ ] **Step 3: run — fails.**

- [ ] **Step 4: write `membership-report.tsx`** per Behaviour.

- [ ] **Step 5: run — passes.**

- [ ] **Step 6:** `npx vitest run src/features/reports src/services/reports` + `npm run typecheck` + `npx next lint --dir src` + full `npx vitest run`.

---

## Task 4: manual DB verification (reviewer, against linked Supabase)

Apply `0056`–`0062`. Using the §52 fixture (a session: capacity 5, 3 confirmed member slots, `released_capacity` 2, 1 confirmed guest slot, guest booking generated ₹400):

```sql
select * from get_membership_session_analytics('<fac>', 'CUSTOM', '<session-date>', '<session-date>', null, null);
-- session_count 1, total_capacity 5, member_allocations 3, guest_released 2,
-- guest_booked 1, remaining_released 1, unused_capacity 1

select * from get_guest_release_analytics('<fac>', 'CUSTOM', '<session-date>', '<session-date>', null, null);
-- released 2, booked 1, remaining 1, revenue_minor 40000  (the ₹400, once its payment is 'paid')

-- membership snapshot (§50 fixture: one ₹5,000 membership, fully paid, created 03 Sep)
select * from get_membership_analytics('<champz>', 'CUSTOM', '2026-09-03', '2026-09-03');
-- new_memberships 1, membership_revenue_minor 500000, paid_count 1, outstanding_minor 0

-- facility isolation
select * from get_membership_analytics('<other>', 'THIS_MONTH', null, null);  -- raises "Not authorized"
```

Confirm §52: the 3 member allocations are **not** in any revenue figure.

---

## Self-Review

**Spec coverage:** §17 active/new/expiring/revenue/completion/types → `get_membership_analytics` + `get_memberships_by_type`; retention explicitly deferred (no linkage). §18 paid/partial/pending/outstanding → `get_membership_analytics` payment-completion block, from `total_amount_inr` vs paid `payments`. §19 session capacity/allocations/released/booked/unused → `get_membership_session_analytics`, `unused = capacity − member − guest_booked`. §20 guest-release released/booked/remaining/revenue → `get_guest_release_analytics`, revenue via `payments.membership_session_booking_id` (Finance's own classification, `0051`). §42 tables → every card. §52 → manual task.

**Placeholder scan:** Task 3 Step 4 "write per Behaviour" — the report is `<KpiStrip>` + four `<Card>`s of `<DataTable>` / `<ReportBarList>` inside `<ReportShell>`, identical structure to `court-utilization-report.tsx`. Acceptable.

**Type consistency:** SQL snake_case ↔ TS camelCase mapping uniform across all four RPCs, service, fake, component. `MembershipSessionAnalytics.unusedCapacity` ← `unused_capacity` used in the §52 assertion. `membership_type` values are the raw enum (`INDIVIDUAL`/`FAMILY`/`CORPORATE`) — the component title-cases for display, the CSV keeps them raw.
