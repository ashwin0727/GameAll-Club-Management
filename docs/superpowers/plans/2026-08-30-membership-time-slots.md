# Membership Time Slots & Access Days Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the web Create Membership page reserve a court time window (via `membership_batches`) with owner-chosen access days, so ad-hoc bookings on that court/time are blocked and the window shows as a locked slot in the Bookings calendar.

**Architecture:** The reservation + calendar-blocking machinery already exists via `membership_batches` and `court_has_active_membership_window`. This connects the Phase 4 Create Membership flow to it: `create_membership_full` gains optional args to join an existing batch or atomically create one and enrol the member. A new `facilities.membership_access_days` column holds the per-facility default day set that pre-fills the form's day picker.

**Tech Stack:** PostgreSQL (Supabase migrations), Next.js / React 19, TypeScript, TanStack Query, Vitest + Testing Library, hand-maintained `src/types/database.types.ts`.

**Spec:** `docs/superpowers/specs/2026-08-30-membership-time-slots-design.md`

## Global Constraints

- Days-of-week values are `smallint` `0=Sunday .. 6=Saturday` (matches `extract(dow from ...)`), stored as `smallint[]` in Postgres and `number[]` in TS. Verbatim day arrays: **All 7** = `[0,1,2,3,4,5,6]`, **Mon–Fri** = `[1,2,3,4,5]`.
- `facilities.membership_access_days` default is `[0,1,2,3,4,5,6]` (all week — "unrestricted" is the default; Mon–Fri is opt-in).
- New-slot **capacity** is a required numeric field, minimum 1, **no upper bound** (owner's decision — 10 membership players in one 6–7 AM slot is valid).
- `court_has_active_membership_window` blocks the **entire** court window regardless of batch fullness — unchanged; do not touch it.
- `membership_batches.plan_id` becomes nullable; the composite FK `(facility_id, plan_id) → membership_plans` is MATCH SIMPLE so a NULL `plan_id` row passes unchecked. Do not drop that FK.
- `create_membership_full` is called from exactly one place: `SupabaseMembershipService.createMembershipFull`. No other caller exists.
- This project has **no SQL/pgTAP test harness**. Migration-level behaviour is checked by the manual verification task (Task 8); automated tests cover the TS service payloads and pure helpers.
- Migration files are immutable once shipped — all DB changes go in the single new file `supabase/migrations/0029_membership_time_slots.sql`.
- `database.types.ts` is hand-maintained (see its header comment); update it by hand to match the migration.
- Follow existing patterns: service unit tests use `vi.fn()` for `rpc` and `fakeQueryBuilder` from `@/test/fakes/fake-supabase-query` for `from`. Pure logic lives in a `.ts` module beside the feature with a `.test.ts` next to it (see `src/features/memberships/status.ts` + `status.test.ts`).

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/0029_membership_time_slots.sql` | **Create.** Facility access-days column + constraint; `membership_batches.plan_id` nullable; `set_facility_membership_access_days` RPC; `create_membership_full` recreated with batch args. |
| `src/types/database.types.ts` | **Modify.** `facilities` Row/Insert/Update gain `membership_access_days`; `membership_batches` `plan_id` → nullable; `create_membership_full` Args updated; `set_facility_membership_access_days` function added. |
| `src/features/onboarding/types.ts` | **Modify.** `Facility` interface gains `membershipAccessDays: number[]`. |
| `src/services/facility/supabase-facility.service.ts` | **Modify.** `toFacility` maps the new column. |
| `src/services/facility/supabase-facility.service.test.ts` | **Modify.** Assert the mapping. |
| `src/features/memberships/types.ts` | **Modify.** `CreateMembershipFullInput`: drop `timeSlotStart`/`timeSlotEnd`, add `batchId?` and `newBatch?`. |
| `src/services/memberships/membership.service.ts` | **Modify.** Interface: add `setMembershipAccessDays`. |
| `src/services/memberships/supabase-membership.service.ts` | **Modify.** `createMembershipFull` payload; new `setMembershipAccessDays`. |
| `src/services/memberships/supabase-membership.service.test.ts` | **Modify.** Payload-shape + new-method tests. |
| `src/features/memberships/slot-form.ts` | **Create.** Pure helpers: day presets, `validateNewSlot`, `describeBatchOption`. |
| `src/features/memberships/slot-form.test.ts` | **Create.** Unit tests for the above. |
| `src/features/memberships/components/court-time-slot-section.tsx` | **Create.** The Court Time Slot sub-form (sport → court → existing-batch radios / new-slot fields). |
| `src/features/memberships/components/create-membership-page.tsx` | **Modify.** Replace the plain time-slot inputs with `<CourtTimeSlotSection>`; thread its value into `createMembershipFull`. |
| `src/features/memberships/components/membership-access-days-dialog.tsx` | **Create.** Dialog to set the facility default day set. |
| `src/features/memberships/components/memberships-page.tsx` | **Modify.** Add the "Access Days" header button + dialog. |

---

## Task 1: Migration — facility access days, nullable batch plan, batch-aware `create_membership_full`

**Files:**
- Create: `supabase/migrations/0029_membership_time_slots.sql`

**Interfaces:**
- Consumes: existing `assign_batch_member(uuid, uuid, uuid)`, `has_facility_role(uuid, facility_role[])`, `resolve_booking_price`, table `membership_batches`, current `create_membership_full` (25-arg form from `0028_membership_creation_form.sql`).
- Produces:
  - `facilities.membership_access_days smallint[] not null default '{0,1,2,3,4,5,6}'`
  - `set_facility_membership_access_days(p_facility_id uuid, p_days smallint[]) returns facilities`
  - `create_membership_full(...25 args...)` where the arg list drops `p_time_slot_start`/`p_time_slot_end` and adds `p_batch_id uuid default null`, `p_new_batch jsonb default null` at the end. `p_new_batch` shape: `{ "courtId": uuid, "facilitySportId": uuid, "daysOfWeek": [int], "startTime": "HH:MM", "endTime": "HH:MM", "capacity": int, "name": text? }`. Returns `memberships`.

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/0029_membership_time_slots.sql`:

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- Membership time slots — Phase 5.
--
-- The Phase 4 Create Membership page (0028) stored a cosmetic
-- time_slot_start/end on the membership row that reserved nothing. This wires
-- the membership's play window into `membership_batches` — the mechanism that
-- ALREADY blocks ad-hoc bookings (court_has_active_membership_window) and
-- renders a locked slot in the Bookings grid.
--
--   • facilities        += membership_access_days (the per-facility default
--                          day set the Create form pre-fills)
--   • membership_batches : plan_id becomes NULLable (self-contained
--                          memberships have no plan; the composite FK is
--                          MATCH SIMPLE so a NULL row is unchecked)
--   • set_facility_membership_access_days — owner/manager sets the default
--   • create_membership_full — after inserting the membership, optionally
--     join an existing batch (p_batch_id) or create one (p_new_batch) and
--     enrol the member via assign_batch_member (capacity-checked). The
--     cosmetic p_time_slot_start/end args are removed.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- Facility default membership access days
-- ─────────────────────────────────────────────────────────────────────────
alter table facilities
  add column if not exists membership_access_days smallint[] not null
    default array[0, 1, 2, 3, 4, 5, 6]::smallint[];

alter table facilities
  drop constraint if exists facilities_membership_access_days_check;
alter table facilities
  add constraint facilities_membership_access_days_check check (
    coalesce(array_length(membership_access_days, 1), 0) > 0
    and membership_access_days <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]
  );

-- ─────────────────────────────────────────────────────────────────────────
-- Self-contained memberships have no plan, so neither does their batch.
-- ─────────────────────────────────────────────────────────────────────────
alter table membership_batches alter column plan_id drop not null;

-- ─────────────────────────────────────────────────────────────────────────
-- set_facility_membership_access_days
-- ─────────────────────────────────────────────────────────────────────────
create or replace function set_facility_membership_access_days(
  p_facility_id uuid,
  p_days smallint[]
) returns facilities
language plpgsql
as $$
declare
  result facilities;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized to change membership settings.' using errcode = '42501';
  end if;
  if coalesce(array_length(p_days, 1), 0) = 0 then
    raise exception 'Select at least one access day.' using errcode = '23514';
  end if;
  if not (p_days <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]) then
    raise exception 'Invalid day value.' using errcode = '23514';
  end if;

  update facilities set membership_access_days = p_days
  where id = p_facility_id
  returning * into result;

  if result.id is null then
    raise exception 'Facility not found' using errcode = 'P0002';
  end if;
  return result;
end;
$$;

grant execute on function set_facility_membership_access_days(uuid, smallint[]) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- create_membership_full — batch-aware. Arg list changes (drops the two
-- cosmetic time-slot params, adds p_batch_id / p_new_batch), so drop+recreate.
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists create_membership_full(
  uuid, text, text, text, date, text, text,
  text, text, integer, date, integer, time, time, text,
  integer, integer, numeric, text, text, text, uuid, text, text, integer
);

create function create_membership_full(
  p_facility_id uuid,
  p_full_name text,
  p_phone text,
  p_email text,
  p_date_of_birth date,
  p_gender text,
  p_address text,
  p_name text,
  p_membership_type text,
  p_max_family_members integer,
  p_start_date date,
  p_duration_days integer,
  p_description text,
  p_membership_fee_inr integer,
  p_registration_fee_inr integer,
  p_gst_percent numeric,
  p_payment_mode text,
  p_payment_methods text,
  p_payment_reference text,
  p_referral_member_id uuid,
  p_discovery_source text,
  p_notes text,
  p_monthly_price_inr integer default null,
  p_batch_id uuid default null,
  p_new_batch jsonb default null
) returns memberships
language plpgsql
as $$
declare
  v_member_id uuid;
  computed_end date;
  fee integer := greatest(coalesce(p_membership_fee_inr, 0), 0);
  reg integer := greatest(coalesce(p_registration_fee_inr, 0), 0);
  gst numeric := greatest(coalesce(p_gst_percent, 0), 0);
  gst_amount integer;
  total integer;
  result memberships;
  v_batch_id uuid;
  v_court courts;
  v_days smallint[];
  v_start time;
  v_end time;
  v_capacity integer;
  v_batch_name text;
begin
  if trim(coalesce(p_full_name, '')) = '' or trim(coalesce(p_phone, '')) = '' then
    raise exception 'Member name and phone are required.' using errcode = '23514';
  end if;
  if coalesce(p_duration_days, 0) <= 0 then
    raise exception 'Choose a membership duration.' using errcode = '23514';
  end if;
  if p_batch_id is not null and p_new_batch is not null then
    raise exception 'Pick one time slot, not both.' using errcode = '23514';
  end if;

  -- Get-or-create the member by (facility, phone).
  select id into v_member_id from members
    where facility_id = p_facility_id and phone = trim(p_phone);
  if v_member_id is null then
    insert into members (facility_id, full_name, phone, email, date_of_birth, gender, address)
    values (p_facility_id, trim(p_full_name), trim(p_phone), nullif(trim(p_email), ''),
            p_date_of_birth, nullif(trim(p_gender), ''), nullif(trim(p_address), ''))
    returning id into v_member_id;
  else
    update members set
      email = coalesce(email, nullif(trim(p_email), '')),
      date_of_birth = coalesce(date_of_birth, p_date_of_birth),
      gender = coalesce(gender, nullif(trim(p_gender), '')),
      address = coalesce(address, nullif(trim(p_address), ''))
    where id = v_member_id;
  end if;

  computed_end := p_start_date + p_duration_days;
  gst_amount := round(fee * gst / 100.0);
  total := fee + gst_amount + reg;

  insert into memberships (
    facility_id, member_id, plan_id, status, start_date, end_date, created_by,
    name, membership_type, max_family_members, duration_days,
    description,
    membership_fee_inr, registration_fee_inr, gst_percent, total_amount_inr,
    monthly_price_inr, payment_reference, referral_member_id, discovery_source, notes
  )
  values (
    p_facility_id, v_member_id, null,
    (case when computed_end >= current_date then 'active' else 'expired' end)::membership_status,
    p_start_date, computed_end, auth.uid(),
    nullif(trim(p_name), ''),
    coalesce(nullif(trim(p_membership_type), ''), 'INDIVIDUAL'),
    greatest(coalesce(p_max_family_members, 1), 1),
    p_duration_days,
    nullif(trim(p_description), ''),
    fee, reg, gst, total,
    coalesce(p_monthly_price_inr, fee),
    nullif(trim(p_payment_reference), ''), p_referral_member_id, nullif(trim(p_discovery_source), ''),
    nullif(trim(p_notes), '')
  )
  returning * into result;

  if upper(coalesce(p_payment_mode, 'PENDING')) <> 'FREE' and total > 0 then
    insert into payments (facility_id, member_id, membership_id, amount_inr, status, payment_method)
    values (
      p_facility_id, v_member_id, result.id, total,
      case when upper(p_payment_mode) = 'PAID' then 'paid'::payment_status else 'created'::payment_status end,
      nullif(trim(p_payment_methods), '')
    );
  end if;

  -- ── Reserved court time slot ──────────────────────────────────────────
  if p_new_batch is not null then
    select array_agg(value::smallint) into v_days
      from jsonb_array_elements_text(p_new_batch->'daysOfWeek');
    v_start := (p_new_batch->>'startTime')::time;
    v_end := (p_new_batch->>'endTime')::time;
    v_capacity := (p_new_batch->>'capacity')::integer;

    if coalesce(array_length(v_days, 1), 0) = 0 or not (v_days <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]) then
      raise exception 'Select at least one valid access day for the time slot.' using errcode = '23514';
    end if;
    if v_end <= v_start then
      raise exception 'Time slot end must be after the start.' using errcode = '23514';
    end if;
    if coalesce(v_capacity, 0) < 1 then
      raise exception 'Time slot capacity must be at least 1.' using errcode = '23514';
    end if;

    select * into v_court from courts
      where id = (p_new_batch->>'courtId')::uuid
        and facility_id = p_facility_id
        and facility_sport_id = (p_new_batch->>'facilitySportId')::uuid;
    if v_court.id is null then
      raise exception 'That court does not belong to this facility/sport.' using errcode = '23503';
    end if;

    v_batch_name := coalesce(
      nullif(trim(p_new_batch->>'name'), ''),
      coalesce(nullif(trim(p_name), ''), 'Membership') || ' · '
        || to_char(v_start, 'FMHH12:MI') || '–' || to_char(v_end, 'FMHH12:MI AM')
    );

    insert into membership_batches (
      facility_id, plan_id, facility_sport_id, court_id, name,
      days_of_week, start_time, end_time, capacity, is_active
    ) values (
      p_facility_id, null, v_court.facility_sport_id, v_court.id, v_batch_name,
      v_days, v_start, v_end, v_capacity, true
    ) returning id into v_batch_id;
  elsif p_batch_id is not null then
    if not exists (
      select 1 from membership_batches
      where id = p_batch_id and facility_id = p_facility_id and is_active
    ) then
      raise exception 'That time slot is not available.' using errcode = '23503';
    end if;
    v_batch_id := p_batch_id;
  end if;

  if v_batch_id is not null then
    perform assign_batch_member(v_batch_id, v_member_id, result.id);
  end if;

  return result;
end;
$$;

grant execute on function create_membership_full(
  uuid, text, text, text, date, text, text,
  text, text, integer, date, integer, text,
  integer, integer, numeric, text, text, text, uuid, text, text, integer,
  uuid, jsonb
) to authenticated;
```

- [ ] **Step 2: Sanity-check the SQL parses**

Run: `grep -c "create function\|create or replace function" supabase/migrations/0029_membership_time_slots.sql`
Expected: `2`

If a local Supabase is available, run `supabase db reset` (or `supabase migration up`) and confirm it applies with no error. If not, defer full verification to Task 8.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0029_membership_time_slots.sql
git commit -m "feat(db): membership time slots — access days + batch-aware create_membership_full"
```

---

## Task 2: `database.types.ts` — reflect the migration

**Files:**
- Modify: `src/types/database.types.ts` (facilities ~line 69, membership_batches ~line 901, Functions `create_membership_full` ~line 1481)

**Interfaces:**
- Consumes: Task 1's migration (column names, function signature).
- Produces: `Database["public"]["Tables"]["facilities"]["Row"].membership_access_days: number[]`; `membership_batches` `plan_id: string | null`; `create_membership_full` Args without `p_time_slot_start/end`, with `p_batch_id?` / `p_new_batch?`; `Database["public"]["Functions"]["set_facility_membership_access_days"]`.

- [ ] **Step 1: Add `membership_access_days` to the `facilities` table type**

In `facilities.Row` (after `updated_at: string;`), add:

```ts
          membership_access_days: number[];
```

In `facilities.Insert` (after the last field, before the closing `}`), add:

```ts
          membership_access_days?: number[];
```

`facilities.Update` — locate it; if it is `Partial<...Insert>` leave it. If it is a spelled-out object, add `membership_access_days?: number[];`.

- [ ] **Step 2: Make `membership_batches.plan_id` nullable**

In `membership_batches.Row` change `plan_id: string;` → `plan_id: string | null;`
In `membership_batches.Insert` change `plan_id: string;` → `plan_id?: string | null;`

- [ ] **Step 3: Update the `create_membership_full` function Args**

Replace the whole `create_membership_full` entry (currently ~lines 1481–1510) with:

```ts
      create_membership_full: {
        Args: {
          p_facility_id: string;
          p_full_name: string;
          p_phone: string;
          p_email: string | null;
          p_date_of_birth: string | null;
          p_gender: string | null;
          p_address: string | null;
          p_name: string | null;
          p_membership_type: string;
          p_max_family_members: number;
          p_start_date: string;
          p_duration_days: number;
          p_description: string | null;
          p_membership_fee_inr: number;
          p_registration_fee_inr: number;
          p_gst_percent: number;
          p_payment_mode: string;
          p_payment_methods: string | null;
          p_payment_reference: string | null;
          p_referral_member_id: string | null;
          p_discovery_source: string | null;
          p_notes: string | null;
          p_monthly_price_inr?: number | null;
          p_batch_id?: string | null;
          p_new_batch?: {
            courtId: string;
            facilitySportId: string;
            daysOfWeek: number[];
            startTime: string;
            endTime: string;
            capacity: number;
            name?: string;
          } | null;
        };
        Returns: Database["public"]["Tables"]["memberships"]["Row"];
      };
```

- [ ] **Step 4: Add the `set_facility_membership_access_days` function type**

Immediately after the `create_membership_full` entry, add:

```ts
      set_facility_membership_access_days: {
        Args: { p_facility_id: string; p_days: number[] };
        Returns: Database["public"]["Tables"]["facilities"]["Row"];
      };
```

- [ ] **Step 5: Type-check**

Run: `npx tsc --noEmit`
Expected: PASS (no errors). If `toFacility` now errors on a missing property, that is fixed in Task 3 — note it and continue only if it is the *only* error; otherwise fix the type file.

- [ ] **Step 6: Commit**

```bash
git add src/types/database.types.ts
git commit -m "chore(types): db types for membership access days + batch-aware create_membership_full"
```

---

## Task 3: `Facility` type + facility service mapping

**Files:**
- Modify: `src/features/onboarding/types.ts` (`Facility` interface ~line 28)
- Modify: `src/services/facility/supabase-facility.service.ts` (`toFacility` ~line 12)
- Modify: `src/services/facility/supabase-facility.service.test.ts`

**Interfaces:**
- Consumes: Task 2's `facilities.Row.membership_access_days: number[]`.
- Produces: `Facility.membershipAccessDays: number[]`.

- [ ] **Step 1: Write the failing test**

In `src/services/facility/supabase-facility.service.test.ts`, find the fixture row used for `getFacility` (search for `owner_id:` / a `FACILITY_ROW`-style const). Add `membership_access_days: [1, 2, 3, 4, 5]` to that fixture. Then add:

```ts
  it("maps membership_access_days onto the Facility", async () => {
    // uses the same getFacility setup as the surrounding tests
    const facility = await getFacilityUnderTest();
    expect(facility?.membershipAccessDays).toEqual([1, 2, 3, 4, 5]);
  });
```

Adapt `getFacilityUnderTest()` to whatever helper/inline setup the neighbouring `getFacility` tests use (an `auth.getUser` stub returning a user + a `from` returning `fakeQueryBuilder({ data: FACILITY_ROW, error: null })`).

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run src/services/facility/supabase-facility.service.test.ts -t "membership_access_days"`
Expected: FAIL — `expected undefined to deeply equal [ 1, 2, 3, 4, 5 ]`

- [ ] **Step 3: Add the field to the `Facility` interface**

In `src/features/onboarding/types.ts`, inside `interface Facility`, after `updatedAt: string;`:

```ts
  /** Days of week (0=Sun..6=Sat) a member may use the court. Pre-fills the
   *  time-slot day picker on the Create Membership page. */
  membershipAccessDays: number[];
```

- [ ] **Step 4: Map it in `toFacility`**

In `src/services/facility/supabase-facility.service.ts`, in the object returned by `toFacility`, after `updatedAt: row.updated_at,`:

```ts
    membershipAccessDays: row.membership_access_days ?? [0, 1, 2, 3, 4, 5, 6],
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `npx vitest run src/services/facility/supabase-facility.service.test.ts`
Expected: PASS (all tests in the file).

- [ ] **Step 6: Type-check**

Run: `npx tsc --noEmit`
Expected: PASS. If other call sites construct a `Facility` literal (e.g. test fixtures, `session_controller` mocks), add `membershipAccessDays: [0,1,2,3,4,5,6]` to each until clean.

- [ ] **Step 7: Commit**

```bash
git add src/features/onboarding/types.ts src/services/facility/
git commit -m "feat(facility): expose membershipAccessDays on the Facility model"
```

---

## Task 4: Membership service — batch args + `setMembershipAccessDays`

**Files:**
- Modify: `src/features/memberships/types.ts` (`CreateMembershipFullInput`)
- Modify: `src/services/memberships/membership.service.ts` (interface)
- Modify: `src/services/memberships/supabase-membership.service.ts` (`createMembershipFull` ~line 360, add `setMembershipAccessDays`)
- Modify: `src/services/memberships/supabase-membership.service.test.ts`

**Interfaces:**
- Consumes: Task 2's `create_membership_full` Args, `set_facility_membership_access_days` function type.
- Produces:
  - `CreateMembershipFullInput` with `batchId?: string` and `newBatch?: { courtId: string; facilitySportId: string; daysOfWeek: number[]; startTime: string; endTime: string; capacity: number; name?: string }`, and **no** `timeSlotStart`/`timeSlotEnd`.
  - `MembershipService.setMembershipAccessDays(facilityId: string, days: number[]): Promise<number[]>`.

- [ ] **Step 1: Write the failing tests**

In `src/services/memberships/supabase-membership.service.test.ts` add a `describe("createMembershipFull time slots")` block:

```ts
  it("createMembershipFull passes a new-batch payload through to the RPC", async () => {
    const rpc = vi.fn(async () => ({ data: { ...MEMBERSHIP_ROW, plan_id: null, name: "Premium" }, error: null }));
    const service = new SupabaseMembershipService({ rpc } as never);

    await service.createMembershipFull({
      facilityId: "facility-1",
      fullName: "Arun",
      phone: "9999999999",
      membershipType: "INDIVIDUAL",
      maxFamilyMembers: 1,
      startDate: "2026-09-01",
      durationDays: 90,
      membershipFeeInr: 1000,
      registrationFeeInr: 0,
      gstPercent: 0,
      paymentMode: "PAID",
      newBatch: {
        courtId: "court-1",
        facilitySportId: "fs-1",
        daysOfWeek: [1, 2, 3, 4, 5],
        startTime: "06:00",
        endTime: "07:00",
        capacity: 10,
      },
    });

    expect(rpc).toHaveBeenCalledWith(
      "create_membership_full",
      expect.objectContaining({
        p_batch_id: null,
        p_new_batch: {
          courtId: "court-1",
          facilitySportId: "fs-1",
          daysOfWeek: [1, 2, 3, 4, 5],
          startTime: "06:00",
          endTime: "07:00",
          capacity: 10,
        },
      }),
    );
    const payload = rpc.mock.calls[0][1];
    expect(payload).not.toHaveProperty("p_time_slot_start");
    expect(payload).not.toHaveProperty("p_time_slot_end");
  });

  it("createMembershipFull passes an existing batchId through", async () => {
    const rpc = vi.fn(async () => ({ data: { ...MEMBERSHIP_ROW, plan_id: null, name: "Premium" }, error: null }));
    const service = new SupabaseMembershipService({ rpc } as never);

    await service.createMembershipFull({
      facilityId: "facility-1",
      fullName: "Arun",
      phone: "9999999999",
      membershipType: "INDIVIDUAL",
      maxFamilyMembers: 1,
      startDate: "2026-09-01",
      durationDays: 90,
      membershipFeeInr: 1000,
      registrationFeeInr: 0,
      gstPercent: 0,
      paymentMode: "PAID",
      batchId: "batch-9",
    });

    expect(rpc).toHaveBeenCalledWith(
      "create_membership_full",
      expect.objectContaining({ p_batch_id: "batch-9", p_new_batch: null }),
    );
  });

  it("setMembershipAccessDays calls the RPC and returns the days", async () => {
    const rpc = vi.fn(async () => ({
      data: { id: "facility-1", membership_access_days: [1, 2, 3, 4, 5] },
      error: null,
    }));
    const service = new SupabaseMembershipService({ rpc } as never);

    const days = await service.setMembershipAccessDays("facility-1", [1, 2, 3, 4, 5]);

    expect(rpc).toHaveBeenCalledWith("set_facility_membership_access_days", {
      p_facility_id: "facility-1",
      p_days: [1, 2, 3, 4, 5],
    });
    expect(days).toEqual([1, 2, 3, 4, 5]);
  });

  it("setMembershipAccessDays maps an unauthorized error", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { code: "42501", message: "no" } }));
    const service = new SupabaseMembershipService({ rpc } as never);
    await expect(service.setMembershipAccessDays("f", [1])).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });
```

If `MEMBERSHIP_ROW` has no `name` key, add `name: "Premium"` to the file's fixture or inline it as shown.

- [ ] **Step 2: Run to verify failure**

Run: `npx vitest run src/services/memberships/supabase-membership.service.test.ts -t "time slots"`
Expected: FAIL — `p_time_slot_start` still present / `setMembershipAccessDays is not a function`.

- [ ] **Step 3: Update `CreateMembershipFullInput`**

In `src/features/memberships/types.ts`, in `CreateMembershipFullInput`, delete:

```ts
  timeSlotStart?: string;
  timeSlotEnd?: string;
```

and add (in the "Membership details" group, replacing them):

```ts
  /** Join an existing membership_batches time slot for this facility. */
  batchId?: string;
  /** Or create a new reserved court time slot. Mutually exclusive with batchId. */
  newBatch?: {
    courtId: string;
    facilitySportId: string;
    daysOfWeek: number[];
    startTime: string; // "HH:mm"
    endTime: string; // "HH:mm"
    capacity: number;
    name?: string;
  };
```

- [ ] **Step 4: Update `createMembershipFull` in the service**

In `src/services/memberships/supabase-membership.service.ts#createMembershipFull`, in the `rpc("create_membership_full", { ... })` object: delete the `p_time_slot_start` and `p_time_slot_end` lines, and add:

```ts
      p_batch_id: input.batchId ?? null,
      p_new_batch: input.newBatch ?? null,
```

- [ ] **Step 5: Add `setMembershipAccessDays`**

In `src/services/memberships/membership.service.ts` interface, add:

```ts
  setMembershipAccessDays(facilityId: string, days: number[]): Promise<number[]>;
```

In `src/services/memberships/supabase-membership.service.ts` (near `createMembershipFull`):

```ts
  async setMembershipAccessDays(facilityId: string, days: number[]): Promise<number[]> {
    const { data, error } = await this.supabase.rpc("set_facility_membership_access_days", {
      p_facility_id: facilityId,
      p_days: days,
    });
    if (error) throw mapSupabaseError(error, { invalid: "INVALID_MEMBERSHIP" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return (data as { membership_access_days: number[] }).membership_access_days;
  }
```

`mapSupabaseError` already maps Postgres `42501` → `UNAUTHORIZED` (see `service-error.ts`), so no extra option is needed for that case.

- [ ] **Step 6: Run tests**

Run: `npx vitest run src/services/memberships/supabase-membership.service.test.ts`
Expected: PASS (whole file). Also run `npx tsc --noEmit` — fix any `timeSlotStart`/`timeSlotEnd` references the compiler now flags (the create page is handled in Task 6; if it is the only remaining error, note it and proceed).

- [ ] **Step 7: Commit**

```bash
git add src/features/memberships/types.ts src/services/memberships/
git commit -m "feat(memberships): batch args on createMembershipFull + setMembershipAccessDays"
```

---

## Task 5: Pure slot-form helpers

**Files:**
- Create: `src/features/memberships/slot-form.ts`
- Create: `src/features/memberships/slot-form.test.ts`

**Interfaces:**
- Consumes: `AssignableBatch` from `src/features/memberships/types.ts` (fields: `batchId`, `courtId`, `daysOfWeek`, `startTime`, `endTime`, `capacity`, `enrolledCount`, `spare`). `formatSlot` from `src/features/memberships/slot-format.ts`.
- Produces:
  - `DAY_OPTIONS: { value: number; label: string }[]` — Mon..Sun, values `[1,2,3,4,5,6,0]`.
  - `ALL_DAYS: number[]` = `[0,1,2,3,4,5,6]`; `WEEKDAYS: number[]` = `[1,2,3,4,5]`.
  - `sameDays(a: number[], b: number[]): boolean`
  - `type NewSlotDraft = { facilitySportId: string; courtId: string; daysOfWeek: number[]; startTime: string; endTime: string; capacity: string }`
  - `type SlotSelection = { kind: "none" } | { kind: "existing"; batchId: string } | { kind: "new"; draft: NewSlotDraft }`
  - `validateSlotSelection(sel: SlotSelection): string | null` — returns an error message or null.
  - `describeBatchOption(b: AssignableBatch): string` — e.g. `"Mon/Wed/Fri · 6:00 AM – 7:00 AM · 4 / 6"`.
  - `toNewBatchPayload(draft: NewSlotDraft): { courtId: string; facilitySportId: string; daysOfWeek: number[]; startTime: string; endTime: string; capacity: number }`

- [ ] **Step 1: Write the failing tests**

Create `src/features/memberships/slot-form.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import {
  ALL_DAYS,
  WEEKDAYS,
  sameDays,
  validateSlotSelection,
  describeBatchOption,
  toNewBatchPayload,
  type SlotSelection,
} from "@/features/memberships/slot-form";
import type { AssignableBatch } from "@/features/memberships/types";

const draft = {
  facilitySportId: "fs-1",
  courtId: "court-1",
  daysOfWeek: [1, 2, 3, 4, 5],
  startTime: "06:00",
  endTime: "07:00",
  capacity: "10",
};

describe("sameDays", () => {
  it("is order-insensitive", () => {
    expect(sameDays([1, 2, 3, 4, 5], [5, 4, 3, 2, 1])).toBe(true);
    expect(sameDays([1, 2], [1, 2, 3])).toBe(false);
  });
});

describe("validateSlotSelection", () => {
  it("accepts 'none'", () => {
    expect(validateSlotSelection({ kind: "none" })).toBeNull();
  });
  it("accepts a well-formed new slot", () => {
    expect(validateSlotSelection({ kind: "new", draft })).toBeNull();
  });
  it("rejects a new slot with no court", () => {
    expect(validateSlotSelection({ kind: "new", draft: { ...draft, courtId: "" } })).toMatch(/court/i);
  });
  it("rejects a new slot with no days", () => {
    expect(validateSlotSelection({ kind: "new", draft: { ...draft, daysOfWeek: [] } })).toMatch(/day/i);
  });
  it("rejects end <= start", () => {
    expect(validateSlotSelection({ kind: "new", draft: { ...draft, endTime: "06:00" } })).toMatch(/after/i);
  });
  it("rejects capacity below 1", () => {
    expect(validateSlotSelection({ kind: "new", draft: { ...draft, capacity: "0" } })).toMatch(/capacity/i);
    expect(validateSlotSelection({ kind: "new", draft: { ...draft, capacity: "" } })).toMatch(/capacity/i);
  });
  it("accepts an existing selection with a batchId", () => {
    expect(validateSlotSelection({ kind: "existing", batchId: "b1" } as SlotSelection)).toBeNull();
  });
  it("rejects an existing selection without a batchId", () => {
    expect(validateSlotSelection({ kind: "existing", batchId: "" } as SlotSelection)).toMatch(/slot/i);
  });
});

describe("describeBatchOption", () => {
  it("renders days, time range and capacity fraction", () => {
    const batch = {
      batchId: "b1", name: "Evening", planId: null, courtId: "c1", courtName: "Court 1",
      sportName: "Badminton", daysOfWeek: [1, 3, 5], startTime: "06:00:00", endTime: "07:00:00",
      capacity: 6, enrolledCount: 4, spare: 2,
    } as unknown as AssignableBatch;
    expect(describeBatchOption(batch)).toBe("Mon/Wed/Fri · 6:00 AM – 7:00 AM · 4 / 6");
  });
});

describe("toNewBatchPayload", () => {
  it("coerces capacity to a number and drops the sport-only field shape", () => {
    expect(toNewBatchPayload(draft)).toEqual({
      courtId: "court-1",
      facilitySportId: "fs-1",
      daysOfWeek: [1, 2, 3, 4, 5],
      startTime: "06:00",
      endTime: "07:00",
      capacity: 10,
    });
  });
});

it("ALL_DAYS and WEEKDAYS constants", () => {
  expect(ALL_DAYS).toEqual([0, 1, 2, 3, 4, 5, 6]);
  expect(WEEKDAYS).toEqual([1, 2, 3, 4, 5]);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `npx vitest run src/features/memberships/slot-form.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `slot-form.ts`**

```ts
import { formatSlot } from "@/features/memberships/slot-format";
import type { AssignableBatch } from "@/features/memberships/types";

export const ALL_DAYS = [0, 1, 2, 3, 4, 5, 6];
export const WEEKDAYS = [1, 2, 3, 4, 5];

export const DAY_OPTIONS: { value: number; label: string }[] = [
  { value: 1, label: "Mon" },
  { value: 2, label: "Tue" },
  { value: 3, label: "Wed" },
  { value: 4, label: "Thu" },
  { value: 5, label: "Fri" },
  { value: 6, label: "Sat" },
  { value: 0, label: "Sun" },
];

export interface NewSlotDraft {
  facilitySportId: string;
  courtId: string;
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
  capacity: string;
}

export type SlotSelection =
  | { kind: "none" }
  | { kind: "existing"; batchId: string }
  | { kind: "new"; draft: NewSlotDraft };

export function sameDays(a: number[], b: number[]): boolean {
  if (a.length !== b.length) return false;
  const sa = [...a].sort((x, y) => x - y);
  const sb = [...b].sort((x, y) => x - y);
  return sa.every((v, i) => v === sb[i]);
}

export function validateSlotSelection(sel: SlotSelection): string | null {
  if (sel.kind === "none") return null;
  if (sel.kind === "existing") {
    return sel.batchId ? null : "Pick a time slot or clear the court.";
  }
  const d = sel.draft;
  if (!d.courtId) return "Select a court for the time slot.";
  if (d.daysOfWeek.length === 0) return "Select at least one day for the time slot.";
  if (!d.startTime || !d.endTime || d.endTime <= d.startTime) {
    return "Time slot end must be after the start.";
  }
  const cap = Number(d.capacity);
  if (!Number.isInteger(cap) || cap < 1) return "Enter a time slot capacity of at least 1.";
  return null;
}

export function describeBatchOption(b: AssignableBatch): string {
  return `${formatSlot(b.daysOfWeek, b.startTime, b.endTime)} · ${b.enrolledCount} / ${b.capacity}`;
}

export function toNewBatchPayload(draft: NewSlotDraft) {
  return {
    courtId: draft.courtId,
    facilitySportId: draft.facilitySportId,
    daysOfWeek: draft.daysOfWeek,
    startTime: draft.startTime,
    endTime: draft.endTime,
    capacity: Number(draft.capacity),
  };
}
```

Check `formatSlot`'s output format against the test's expected string (`"Mon/Wed/Fri · 6:00 AM – 7:00 AM"`). `slot-format.ts` already produces exactly this (`DAY_ABBR` + `formatClock`). If the separator differs, fix the **test expectation**, not `formatSlot` (it is shared with the memberships table).

- [ ] **Step 4: Run tests**

Run: `npx vitest run src/features/memberships/slot-form.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/features/memberships/slot-form.ts src/features/memberships/slot-form.test.ts
git commit -m "feat(memberships): pure helpers for the court time-slot sub-form"
```

---

## Task 6: Court Time Slot section + Create Membership page wiring

**Files:**
- Create: `src/features/memberships/components/court-time-slot-section.tsx`
- Modify: `src/features/memberships/components/create-membership-page.tsx`

**Interfaces:**
- Consumes: `SlotSelection`, `NewSlotDraft`, `DAY_OPTIONS`, `ALL_DAYS`, `WEEKDAYS`, `sameDays`, `describeBatchOption`, `toNewBatchPayload`, `validateSlotSelection` from Task 5. `getMembershipService().listAssignableBatches(facilityId)` → `AssignableBatch[]`. `getSportsService().getFacilitySports(facilityId)` → `FacilitySport[]`. `getPlayingAreasService().getPlayingAreas(facilityId)` → `PlayingArea[]` (fields `id`, `name`, `facilitySportId`, `status`, `bookingEnabled`, `archived`). `getSportsService().getActiveSports()` → `Sport[]`. `Facility.membershipAccessDays`.
- Produces: `<CourtTimeSlotSection value={SlotSelection} onChange={(s: SlotSelection) => void} facilityId={string} defaultAccessDays={number[]} />`.

- [ ] **Step 1: Write the component**

Create `src/features/memberships/components/court-time-slot-section.tsx`:

```tsx
"use client";

import { useEffect, useMemo, useState } from "react";
import { getMembershipService } from "@/services/memberships";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import type { AssignableBatch } from "@/features/memberships/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import {
  ALL_DAYS,
  WEEKDAYS,
  DAY_OPTIONS,
  sameDays,
  describeBatchOption,
  type NewSlotDraft,
  type SlotSelection,
} from "@/features/memberships/slot-form";

const selectCls = "h-10 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm";

function emptyDraft(sportId: string, days: number[]): NewSlotDraft {
  return { facilitySportId: sportId, courtId: "", daysOfWeek: days, startTime: "06:00", endTime: "07:00", capacity: "" };
}

export function CourtTimeSlotSection({
  value,
  onChange,
  facilityId,
  defaultAccessDays,
}: {
  value: SlotSelection;
  onChange: (s: SlotSelection) => void;
  facilityId: string;
  defaultAccessDays: number[];
}) {
  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [sports, setSports] = useState<Sport[]>([]);
  const [areas, setAreas] = useState<PlayingArea[]>([]);
  const [batches, setBatches] = useState<AssignableBatch[]>([]);
  const [facilitySportId, setFacilitySportId] = useState("");

  useEffect(() => {
    let cancelled = false;
    Promise.all([
      getSportsService().getFacilitySports(facilityId),
      getSportsService().getActiveSports(),
      getPlayingAreasService().getPlayingAreas(facilityId),
      getMembershipService().listAssignableBatches(facilityId),
    ])
      .then(([fs, allSports, playingAreas, assignable]) => {
        if (cancelled) return;
        setFacilitySports(fs.filter((f) => f.enabled));
        setSports(allSports);
        setAreas(playingAreas.filter((a) => !a.archived && a.status === "ACTIVE" && a.bookingEnabled));
        setBatches(assignable);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [facilityId]);

  const courts = useMemo(
    () => areas.filter((a) => a.facilitySportId === facilitySportId),
    [areas, facilitySportId],
  );
  const courtIds = useMemo(() => new Set(courts.map((c) => c.id)), [courts]);
  const batchesForSport = useMemo(
    () => batches.filter((b) => courtIds.has(b.courtId)),
    [batches, courtIds],
  );

  const draft = value.kind === "new" ? value.draft : null;

  function pickSport(id: string) {
    setFacilitySportId(id);
    if (value.kind === "new") onChange({ kind: "new", draft: emptyDraft(id, value.draft.daysOfWeek) });
    else if (value.kind === "existing") onChange({ kind: "none" });
  }

  function setDraft(patch: Partial<NewSlotDraft>) {
    if (value.kind !== "new") return;
    onChange({ kind: "new", draft: { ...value.draft, ...patch } });
  }

  function toggleDay(day: number) {
    if (!draft) return;
    const next = draft.daysOfWeek.includes(day)
      ? draft.daysOfWeek.filter((d) => d !== day)
      : [...draft.daysOfWeek, day];
    setDraft({ daysOfWeek: next });
  }

  return (
    <div className="space-y-3 rounded-md border border-border p-3">
      <p className="text-xs font-medium text-muted-foreground">
        Court Time Slot <span className="font-normal">(optional — reserves this court/time for the member)</span>
      </p>

      <select
        aria-label="Sport"
        value={facilitySportId}
        onChange={(e) => pickSport(e.target.value)}
        className={selectCls}
      >
        <option value="">Select sport (to add a time slot)</option>
        {facilitySports.map((fs) => {
          const s = sports.find((sp) => sp.id === fs.sportId);
          return (
            <option key={fs.id} value={fs.id}>
              {fs.customSportName ?? s?.name ?? "Sport"}
            </option>
          );
        })}
      </select>

      {facilitySportId && (
        <div className="space-y-2">
          <label className="flex items-start gap-2 text-sm">
            <input
              type="radio"
              name="slot-kind"
              checked={value.kind === "none"}
              onChange={() => onChange({ kind: "none" })}
              className="mt-1"
            />
            <span>No reserved slot</span>
          </label>

          {batchesForSport.map((b) => (
            <label key={b.batchId} className="flex items-start gap-2 text-sm">
              <input
                type="radio"
                name="slot-kind"
                disabled={b.spare <= 0}
                checked={value.kind === "existing" && value.batchId === b.batchId}
                onChange={() => onChange({ kind: "existing", batchId: b.batchId })}
                className="mt-1"
              />
              <span className={b.spare <= 0 ? "text-muted-foreground" : undefined}>
                {b.courtName} · {describeBatchOption(b)}
                {b.spare <= 0 && " — full, raise its capacity in Membership Sessions"}
              </span>
            </label>
          ))}

          <label className="flex items-start gap-2 text-sm">
            <input
              type="radio"
              name="slot-kind"
              checked={value.kind === "new"}
              onChange={() =>
                onChange({ kind: "new", draft: emptyDraft(facilitySportId, defaultAccessDays) })
              }
              className="mt-1"
            />
            <span>+ New time slot</span>
          </label>

          {draft && (
            <div className="ml-6 space-y-2">
              <select
                aria-label="Court"
                value={draft.courtId}
                onChange={(e) => setDraft({ courtId: e.target.value })}
                className={selectCls}
              >
                <option value="">Select court</option>
                {courts.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>

              <div className="flex flex-wrap items-center gap-2">
                {DAY_OPTIONS.map((d) => (
                  <button
                    key={d.value}
                    type="button"
                    onClick={() => toggleDay(d.value)}
                    className={`h-8 rounded-md border px-2 text-xs font-medium ${
                      draft.daysOfWeek.includes(d.value)
                        ? "border-primary bg-primary text-primary-foreground"
                        : "border-input bg-secondary/60"
                    }`}
                  >
                    {d.label}
                  </button>
                ))}
                <button
                  type="button"
                  onClick={() => setDraft({ daysOfWeek: [...ALL_DAYS] })}
                  className={`h-8 rounded-md border px-2 text-xs ${
                    sameDays(draft.daysOfWeek, ALL_DAYS) ? "border-primary text-primary" : "border-input"
                  }`}
                >
                  All 7
                </button>
                <button
                  type="button"
                  onClick={() => setDraft({ daysOfWeek: [...WEEKDAYS] })}
                  className={`h-8 rounded-md border px-2 text-xs ${
                    sameDays(draft.daysOfWeek, WEEKDAYS) ? "border-primary text-primary" : "border-input"
                  }`}
                >
                  Mon–Fri
                </button>
              </div>

              <div className="grid grid-cols-3 gap-2">
                <input
                  aria-label="Start time"
                  type="time"
                  value={draft.startTime}
                  onChange={(e) => setDraft({ startTime: e.target.value })}
                  className={selectCls}
                />
                <input
                  aria-label="End time"
                  type="time"
                  value={draft.endTime}
                  onChange={(e) => setDraft({ endTime: e.target.value })}
                  className={selectCls}
                />
                <input
                  aria-label="Capacity"
                  inputMode="numeric"
                  placeholder="Capacity"
                  value={draft.capacity}
                  onChange={(e) => setDraft({ capacity: e.target.value })}
                  className={selectCls}
                />
              </div>
              <p className="text-[11px] text-muted-foreground">
                How many membership players share this court/time. Owner&apos;s choice — no limit.
              </p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Wire it into `create-membership-page.tsx`**

In `src/features/memberships/components/create-membership-page.tsx`:

1. Add imports:

```tsx
import { CourtTimeSlotSection } from "@/features/memberships/components/court-time-slot-section";
import { validateSlotSelection, toNewBatchPayload, ALL_DAYS, type SlotSelection } from "@/features/memberships/slot-form";
import { getFacilityService } from "@/services/facility";
```

(`getFacilityService` may already be imported — check first.)

2. Replace the slot state. Delete:

```tsx
  const [slotStart, setSlotStart] = useState("");
  const [slotEnd, setSlotEnd] = useState("");
```

Add:

```tsx
  const [slot, setSlot] = useState<SlotSelection>({ kind: "none" });
  const [accessDays, setAccessDays] = useState<number[]>(ALL_DAYS);
```

3. In the existing `useEffect` that loads the facility (the one calling `getFacilityService().getFacility()`), after `setFacilityId(f?.id ?? null)`, add:

```tsx
        if (f) setAccessDays(f.membershipAccessDays);
```

4. In `submit()`, replace the time-slot validation:

```tsx
    if (slotStart && slotEnd && slotEnd <= slotStart) return setError("Time slot end must be after the start.");
```

with:

```tsx
    const slotError = validateSlotSelection(slot);
    if (slotError) return setError(slotError);
```

5. In the `createMembershipFull({ ... })` call, remove:

```tsx
        timeSlotStart: slotStart || undefined,
        timeSlotEnd: slotEnd || undefined,
```

and add:

```tsx
        batchId: slot.kind === "existing" ? slot.batchId : undefined,
        newBatch: slot.kind === "new" ? toNewBatchPayload(slot.draft) : undefined,
```

6. In section 2's JSX, replace the whole `<Field label="Time Slot" …>…</Field>` block (the one with the two `<input type="time">`) with:

```tsx
          <div className="sm:col-span-2">
            {facilityId && (
              <CourtTimeSlotSection
                value={slot}
                onChange={setSlot}
                facilityId={facilityId}
                defaultAccessDays={accessDays}
              />
            )}
          </div>
```

- [ ] **Step 3: Type-check + full test run**

Run: `npx tsc --noEmit && npx vitest run`
Expected: PASS. Fix any remaining `slotStart`/`slotEnd`/`timeSlotStart` references.

- [ ] **Step 4: Commit**

```bash
git add src/features/memberships/components/court-time-slot-section.tsx src/features/memberships/components/create-membership-page.tsx
git commit -m "feat(memberships): court time-slot picker on the Create Membership page"
```

---

## Task 7: Membership access-days dialog + Memberships page button

**Files:**
- Create: `src/features/memberships/components/membership-access-days-dialog.tsx`
- Modify: `src/features/memberships/components/memberships-page.tsx`

**Interfaces:**
- Consumes: `getMembershipService().setMembershipAccessDays(facilityId, days)` (Task 4). `getFacilityService().getFacility()` for the current value. `DAY_OPTIONS`, `ALL_DAYS`, `WEEKDAYS`, `sameDays` (Task 5). Existing UI primitives `Dialog`, `DialogContent`, `DialogHeader`, `DialogTitle`, `DialogDescription`, `Button` (same imports as `membership-plans-dialog.tsx`).
- Produces: `<MembershipAccessDaysDialog open onOpenChange facilityId currentDays onSaved />`.

- [ ] **Step 1: Write the dialog**

Create `src/features/memberships/components/membership-access-days-dialog.tsx`:

```tsx
"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { getMembershipService } from "@/services/memberships";
import { ServiceError } from "@/services/shared/service-error";
import { ALL_DAYS, WEEKDAYS, DAY_OPTIONS, sameDays } from "@/features/memberships/slot-form";

export function MembershipAccessDaysDialog({
  open,
  onOpenChange,
  facilityId,
  currentDays,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  facilityId: string;
  currentDays: number[];
  onSaved: (days: number[]) => void;
}) {
  const [days, setDays] = useState<number[]>(currentDays);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) {
      setDays(currentDays);
      setError(null);
    }
  }, [open, currentDays]);

  function toggle(day: number) {
    setDays((prev) => (prev.includes(day) ? prev.filter((d) => d !== day) : [...prev, day]));
  }

  async function save() {
    if (days.length === 0) {
      setError("Select at least one day.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const saved = await getMembershipService().setMembershipAccessDays(facilityId, days);
      onSaved(saved);
      onOpenChange(false);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to save access days.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Membership Access Days</DialogTitle>
          <DialogDescription>
            Which days can members use the court? This pre-fills every new membership&apos;s time slot.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-wrap items-center gap-2">
          {DAY_OPTIONS.map((d) => (
            <button
              key={d.value}
              type="button"
              onClick={() => toggle(d.value)}
              className={`h-9 rounded-md border px-3 text-sm font-medium ${
                days.includes(d.value)
                  ? "border-primary bg-primary text-primary-foreground"
                  : "border-input bg-secondary/60"
              }`}
            >
              {d.label}
            </button>
          ))}
          <Button type="button" variant="outline" size="sm" onClick={() => setDays([...ALL_DAYS])}>
            All 7
          </Button>
          <Button type="button" variant="outline" size="sm" onClick={() => setDays([...WEEKDAYS])}>
            Mon–Fri
          </Button>
        </div>

        {error && <p className="text-sm text-destructive">{error}</p>}

        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button type="button" onClick={save} disabled={saving || sameDays(days, currentDays)}>
            {saving ? "Saving…" : "Save"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
```

Confirm the `Dialog`/`Button` import paths against `membership-plans-dialog.tsx` and match them.

- [ ] **Step 2: Wire into `memberships-page.tsx`**

In `src/features/memberships/components/memberships-page.tsx`:

1. Imports:

```tsx
import { MembershipAccessDaysDialog } from "@/features/memberships/components/membership-access-days-dialog";
import { ALL_DAYS } from "@/features/memberships/slot-form";
```

2. State (near `plansOpen`):

```tsx
  const [accessDaysOpen, setAccessDaysOpen] = useState(false);
  const [accessDays, setAccessDays] = useState<number[]>(ALL_DAYS);
```

3. In the `useEffect` that loads the facility, after `setFacilityId(facility.id)`:

```tsx
      setAccessDays(facility.membershipAccessDays);
```

4. In the header actions row, next to the "Manage Plans" `<Button>`:

```tsx
        <Button type="button" variant="outline" size="sm" onClick={() => setAccessDaysOpen(true)}>
          Access Days
        </Button>
```

5. Where `MembershipPlansDialog` is rendered (inside the `{facilityId && (...)}` block), add:

```tsx
          <MembershipAccessDaysDialog
            open={accessDaysOpen}
            onOpenChange={setAccessDaysOpen}
            facilityId={facilityId}
            currentDays={accessDays}
            onSaved={setAccessDays}
          />
```

- [ ] **Step 3: Type-check + tests + lint**

Run: `npx tsc --noEmit && npx vitest run && npx next lint`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/features/memberships/components/membership-access-days-dialog.tsx src/features/memberships/components/memberships-page.tsx
git commit -m "feat(memberships): facility membership access-days setting"
```

---

## Task 8: End-to-end verification against a real database

**Files:** none (verification only)

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Apply the migration**

Run: `supabase db reset` (local) or apply `0029` to the linked project (`supabase migration up`).
Expected: applies cleanly. If `supabase` CLI is unavailable, run the migration file's SQL directly in the SQL editor.

- [ ] **Step 2: Verify the schema changes**

```sql
select column_name, column_default, is_nullable
from information_schema.columns
where table_name = 'facilities' and column_name = 'membership_access_days';
-- expect: default array[0,1,2,3,4,5,6], NOT NULL

select is_nullable from information_schema.columns
where table_name = 'membership_batches' and column_name = 'plan_id';
-- expect: YES
```

- [ ] **Step 3: Create a membership with a new time slot, confirm the batch + block**

Using a real facility / court id, call:

```sql
select create_membership_full(
  '<facility_id>', 'Slot Test', '9000000001', null, null, null, null,
  'Morning Membership', 'INDIVIDUAL', 1, current_date, 90,
  null, 1000, 0, 0, 'PAID', 'Cash', null, null, null, null, 1000,
  null,
  jsonb_build_object(
    'courtId', '<court_id>', 'facilitySportId', '<facility_sport_id>',
    'daysOfWeek', jsonb_build_array(1,2,3,4,5),
    'startTime', '06:00', 'endTime', '07:00', 'capacity', 10
  )
);
```

Then:

```sql
select b.name, b.days_of_week, b.start_time, b.end_time, b.capacity, b.plan_id
from membership_batches b
order by b.created_at desc limit 1;
-- expect: '...· 6:00–7:00 AM', {1,2,3,4,5}, 06:00, 07:00, 10, plan_id NULL

select count(*) from membership_batch_members
where batch_id = (select id from membership_batches order by created_at desc limit 1);
-- expect: 1
```

- [ ] **Step 4: Confirm ad-hoc booking is blocked in that window**

Pick a weekday date and call `create_booking` for `<court_id>` at 06:00–07:00 local. Expect:
`This time is reserved for a membership session. Use guest slot booking for this court/time instead.`

A booking at 08:00–09:00 on the same court/day should still succeed.

- [ ] **Step 5: Verify `set_facility_membership_access_days`**

```sql
select membership_access_days from set_facility_membership_access_days('<facility_id>', array[1,2,3,4,5]::smallint[]);
-- expect: {1,2,3,4,5}
select set_facility_membership_access_days('<facility_id>', array[]::smallint[]);
-- expect: ERROR "Select at least one access day."
```

- [ ] **Step 6: Manual UI smoke test**

`npm run dev`, sign in, open **Memberships → Access Days**, set Mon–Fri, save. Open **Create Membership**, scroll to **Court Time Slot** — the day picker in "New time slot" is pre-checked Mon–Fri. Create a membership with an existing batch and with a new slot. Open **Bookings**, navigate to a covered weekday, confirm the 6–7 AM cell on that court shows the 🔒 locked state.

- [ ] **Step 7: Record the result**

Append a short "Verified <date>" note to the spec file's status line and commit.

```bash
git add docs/superpowers/specs/2026-08-30-membership-time-slots-design.md
git commit -m "docs: mark membership time-slots spec verified"
```

---

## Self-Review

**Spec coverage:**
- §4.1 facility access-days column + constraint → Task 1 Step 1, Task 8 Step 2 ✓
- §4.2 nullable batch plan → Task 1, Task 2 Step 2 ✓
- §4.3 `set_facility_membership_access_days` → Task 1, Task 4 (service), Task 7 (UI), Task 8 Step 5 ✓
- §4.4 `create_membership_full` batch args, drop cosmetic time params, atomic batch create + assign → Task 1, Task 2 Step 3, Task 4 ✓
- §4.5 facility read returns the column → `getFacility` uses `select("*")`; Task 3 maps it ✓
- §5 Create page Court Time Slot block (sport→court→existing/new, day presets pre-filled, capacity required no-max) → Task 5 + Task 6 ✓
- §6 service/types/`Facility` changes → Tasks 3, 4 ✓
- §7 Memberships page access-days control → Task 7 ✓
- §10 tests → Tasks 3–5 automated; Task 8 manual for the DB layer (project has no SQL test harness — noted in Global Constraints) ✓
- §12 open questions resolved in Global Constraints (capacity required/no-default/no-max; full batch = disabled + hint) ✓
- Out-of-scope (Flutter, editing a slot post-create, dropping `time_slot_*` columns) → not planned, matches spec ✓

**Placeholder scan:** No TBD/TODO. Every code step has literal code. Test steps include assertions. The one unavoidable soft spot — "adapt `getFacilityUnderTest()` to the neighbouring test's setup" in Task 3 Step 1 — is bounded by pointing at the exact sibling tests to copy.

**Type consistency:** `SlotSelection` / `NewSlotDraft` shape is identical in Tasks 5, 6, 7. `CreateMembershipFullInput.newBatch` (Task 4) matches `toNewBatchPayload`'s return (Task 5) and `p_new_batch` jsonb keys (Task 1): `courtId, facilitySportId, daysOfWeek, startTime, endTime, capacity`. `setMembershipAccessDays` returns `number[]` in Tasks 4, 7. `membershipAccessDays` on `Facility` used in Tasks 3, 6, 7. Day constants `ALL_DAYS=[0..6]` / `WEEKDAYS=[1..5]` consistent throughout.