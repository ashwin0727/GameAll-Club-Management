# Membership Time Slots & Access Days — Design

Status: Draft — awaiting review
Owner: ashwin0727

## 1. Purpose

When a court owner creates a membership, they set the recurring window
the player will use the court (e.g. Mon–Fri, 6–7 AM). That window must:

1. **Reserve the court** — no ad-hoc booking (member or guest) can be
   made on that court during that window on those days. It renders as a
   locked slot in the Bookings calendar.
2. **Respect owner-chosen access days** — some facilities grant
   membership court access all 7 days, others only Mon–Fri. This is a
   per-facility default, overridable per membership.

The reservation mechanism (`membership_batches` +
`court_has_active_membership_window` + the 🔒 slot rendering in the
Bookings grid + `list_membership_sessions_for_date`) **already exists and
is fully wired**. The gap is that the Phase 4 full Create Membership page
(migration `0028`) bypasses it — it writes cosmetic
`memberships.time_slot_start` / `time_slot_end` text with no court and no
days, so nothing is reserved.

This design connects the Create Membership flow to `membership_batches`.

## 2. Scope boundaries

In scope:
- Migration `0029_membership_time_slots.sql`:
  - `facilities.membership_access_days smallint[]` (facility default,
    all-7 by default)
  - `membership_batches.plan_id` becomes nullable
  - `create_membership_full` extended to optionally join an existing
    batch or create a new one, then assign the member to it (atomic)
  - `set_facility_membership_access_days` RPC (owner/manager)
  - facility read RPC returns the new column
- Web Create Membership page: replace the free-text Time Slot inputs with
  a Court Time Slot block (sport → court → pick-existing-slot-or-new,
  days picker with All-7 / Mon–Fri presets pre-filled from the facility
  default, from/to, capacity)
- Web Memberships page: a "Membership access days" control that saves the
  facility default
- Web membership service + `Facility` type changes
- Migration + web tests

Out of scope (follow-up specs):
- Flutter Create Membership screen — ported after web is confirmed
- Editing a membership's slot after creation (done today via the
  `/membership-sessions` Membership Batches dialog — unchanged)
- Any change to guest-slot release, capacity math, the schedule timeline,
  or the Bookings grid — they already consume batches
- Removing the now-unused `memberships.time_slot_start/end` columns
  (kept for existing data; simply no longer written)
- A dedicated Settings screen (none exists; the control lives on the
  Memberships page)

## 3. Current-state facts (verified)

- `membership_batches(facility_id, plan_id NOT NULL, facility_sport_id,
  court_id, name, days_of_week smallint[], start_time, end_time,
  capacity > 0, is_active)` — 0=Sun..6=Sat. Composite FK
  `(facility_id, plan_id) → membership_plans` is MATCH SIMPLE, so a NULL
  `plan_id` row passes the FK unchecked.
- `assign_batch_member(batch, member, membership)` — idempotent,
  capacity-enforced (0027). Raises `23514` "This time slot is full
  (N / M members)." when over capacity.
- `court_has_active_membership_window(court, start, end, tz)` — used by
  `create_booking` and `reschedule_booking` to reject overlaps against
  any `is_active` batch on a matching day. Blocks the **entire window**
  regardless of how full the batch is; guests may only enter via
  explicitly released capacity (`book_guest_slot`).
- `list_assignable_batches(facility_id, plan_id?)` — every active batch
  with `enrolled_count` / `capacity` / `spare`. `plan_id` null → all
  batches.
- Bookings grid (`booking-operations-view.tsx`) already renders a batch
  window as a locked 🔒 cell via `findMembershipSlot` /
  `list_membership_sessions_for_date`.
- `create_membership_full` (0028) currently: get-or-create member →
  insert membership (`plan_id` null) → compute charges → insert payment.
  Writes `time_slot_start/end` from `p_time_slot_start/end`.
- No Settings screen. `NAV_ITEMS` has no settings entry. Facility columns
  are added by `alter table`.
- Web slot/court data sources (from `membership-batches-dialog.tsx`):
  `getSportsService().getFacilitySports(facilityId)`,
  `getPlayingAreasService().getPlayingAreas(facilityId)` filtered to
  `!archived && status === "ACTIVE" && bookingEnabled`, court belongs to
  the selected `facilitySportId`.

## 4. Data model & migration — `0029_membership_time_slots.sql`

### 4.1 Facility default access days

```sql
alter table facilities
  add column if not exists membership_access_days smallint[] not null
    default array[0,1,2,3,4,5,6]::smallint[];

alter table facilities
  add constraint facilities_membership_access_days_check check (
    coalesce(array_length(membership_access_days, 1), 0) > 0
    and membership_access_days <@ array[0,1,2,3,4,5,6]::smallint[]
  );
```

Rationale for all-7 default: matches "unrestricted" — an owner who wants
Mon–Fri opts in.

### 4.2 Nullable batch plan

```sql
alter table membership_batches alter column plan_id drop not null;
```

Self-contained memberships (Phase 4) have no plan. `create_membership_batch`
(0014) hard-requires `p_plan_id`; a new plan-less path is added in 4.4
rather than changing that RPC's signature.

### 4.3 `set_facility_membership_access_days`

```sql
create function set_facility_membership_access_days(
  p_facility_id uuid,
  p_days smallint[]
) returns facilities
language plpgsql
as $$
declare
  result facilities;
begin
  if not has_facility_role(p_facility_id, array['owner','manager']::facility_role[]) then
    raise exception 'Not authorized.' using errcode = '42501';
  end if;
  if coalesce(array_length(p_days, 1), 0) = 0 then
    raise exception 'Select at least one access day.' using errcode = '23514';
  end if;
  if not (p_days <@ array[0,1,2,3,4,5,6]::smallint[]) then
    raise exception 'Invalid day value.' using errcode = '23514';
  end if;
  update facilities set membership_access_days = p_days
  where id = p_facility_id
  returning * into result;
  return result;
end;
$$;

grant execute on function set_facility_membership_access_days(uuid, smallint[]) to authenticated;
```

### 4.4 `create_membership_full` — extended

Two new trailing optional params (keeps every existing caller working):

```
p_batch_id  uuid  default null   -- join this existing active batch
p_new_batch jsonb default null   -- create a batch, shape below
```

`p_new_batch` shape:

```json
{
  "courtId": "uuid",
  "facilitySportId": "uuid",
  "daysOfWeek": [1,2,3,4,5],
  "startTime": "06:00",
  "endTime": "07:00",
  "capacity": 10,
  "name": "Premium Membership · 6–7 AM"   // optional; auto-derived if absent
}
```

New logic, appended after the membership row is inserted, before the
function returns, **inside the same transaction**:

1. If both `p_batch_id` and `p_new_batch` are non-null → raise `23514`
   "Pick one time slot, not both."
2. If `p_new_batch` is non-null:
   - Validate `courtId` belongs to `p_facility_id` and its
     `facility_sport_id = facilitySportId` (mirror
     `create_membership_batch`'s court check → `23503`).
   - Validate `daysOfWeek` non-empty and `<@ {0..6}`; `endTime >
     startTime`; `capacity >= 1` (no upper bound — owner's call).
   - Insert into `membership_batches` with `plan_id = null`,
     `is_active = true`, name = provided or
     `coalesce(p_name, 'Membership') || ' · ' || to_char(startTime,'HH12:MI') || '–' || to_char(endTime,'HH12:MI AM')`.
   - Set `v_batch_id` to the new id.
3. If `v_batch_id` is set (joined or created) →
   `perform assign_batch_member(v_batch_id, v_member_id, v_membership_id);`
   (capacity error `23514` propagates to the caller as `INVALID_MEMBERSHIP`).
4. Stop writing `p_time_slot_start` / `p_time_slot_end` to `memberships`
   — leave those columns null. The batch is the source of truth and
   `list_memberships` (0027) already joins it.
   *(Alternative: keep mirroring them for defence-in-depth. Decision:
   drop the write — one source of truth.)*

Signature change ⇒ `drop function if exists create_membership_full(<old
25-arg list>)` then recreate with 25 args (25 − 2 removed `p_time_slot_*`
+ 2 added `p_batch_id`/`p_new_batch`); re-grant.

`p_time_slot_start` / `p_time_slot_end` params: **removed** from the
signature (they were only ever cosmetic and the web form no longer sends
them). This is a breaking arg-list change — the web service is updated in
lockstep (§6). No other caller exists.

### 4.5 Facility read

Whatever RPC/`select` the web facility service uses (`get_facility` or a
direct `facilities` select) must return `membership_access_days`. If it's
a `select *`, nothing to do; if column-listed, add it.

## 5. Web — Create Membership page

File: `src/features/memberships/components/create-membership-page.tsx`.

Section 2 ("Membership Details") currently has:

```
Time Slot   [ 06:00 ]  to  [ 07:00 ]     (plain <input type="time">)
```

Replace with a **Court Time Slot** sub-block (still optional — no slot =
no court reservation):

```
Court Time Slot   (optional — reserves this court/time for the member)

  Sport   [ Badminton      v ]      Court   [ Court 1        v ]

  ( ) Evening Batch   Court 1 · Mon/Wed/Fri 6–7 AM      4 / 6
  ( ) Morning Batch   Court 2 · Mon–Sat 7–8 AM          2 / 4
  (o) + New time slot
        Days   [M][T][W][T][F] S  S      [All 7] [Mon–Fri]
        From   [ 06:00 ]   To  [ 07:00 ]
        Capacity  [ 10 ]   membership players who share this slot
```

Behaviour:

- **Sport** dropdown from `getFacilitySports` (enabled only). Selecting a
  sport resets Court and filters the existing-batch list.
- **Court** dropdown from `getPlayingAreas` filtered as in §3, scoped to
  the chosen `facilitySportId`.
- **Existing-slot radios**: `list_assignable_batches(facilityId, null)`
  filtered client-side to the chosen court. Each shows
  `formatSlot(daysOfWeek,start,end)` + `enrolled/capacity`. A full slot
  (`spare === 0`) is shown disabled with hint "Slot full — raise its
  capacity in Membership Sessions".
- **"+ New time slot"** radio reveals:
  - **Days**: seven `[M][T][W][T][F][S][S]` toggle buttons
    (value 1..6,0), initial value = `facility.membershipAccessDays`.
    Preset buttons: **All 7** → `[0..6]`; **Mon–Fri** → `[1,2,3,4,5]`.
  - **From / To**: `<input type="time">`, default 06:00 / 07:00.
  - **Capacity**: numeric, **required**, no max. Default empty with
    placeholder, or a soft default of `4` (see Open Questions — leaning
    empty+required so the owner makes a deliberate choice).
- Time slot block collapsed/empty by default; a membership with no
  sport+court selected sends no batch info.
- **Validation** (client, before submit):
  - If a court is chosen but no slot option selected → "Pick a time slot
    or clear the court."
  - New slot: court required, ≥1 day, `end > start`, capacity ≥ 1.
- **Submit**: extends the `createMembershipFull` call with either
  `batchId` (existing radio) or `newBatch` (the new-slot fields).
- **Server errors**: capacity-full / court-mismatch from the RPC surface
  in the existing error area.

The post-create success/mandate panel is unchanged.

## 6. Web — service, types, hooks

`src/features/memberships/types.ts`:

```ts
export interface CreateMembershipFullInput {
  // …existing fields, MINUS timeSlotStart / timeSlotEnd…
  batchId?: string;
  newBatch?: {
    courtId: string;
    facilitySportId: string;
    daysOfWeek: number[];
    startTime: string;   // "HH:mm"
    endTime: string;
    capacity: number;
    name?: string;
  };
}
```

`src/services/memberships/supabase-membership.service.ts#createMembershipFull`:
- drop `p_time_slot_start` / `p_time_slot_end`
- add `p_batch_id: input.batchId ?? null`
- add `p_new_batch: input.newBatch ? { …camel→as-is JSON… } : null`
  (RPC reads camelCase keys from the jsonb)

`membership.service.ts` interface updated to match.

`Facility` type (`src/features/facility/types.ts` or equivalent) +
facility service: add `membershipAccessDays: number[]`, mapped from
`membership_access_days`.

New service method (membership service, since it's a membership concern):

```ts
setMembershipAccessDays(facilityId: string, days: number[]): Promise<number[]>
// → rpc("set_facility_membership_access_days", { p_facility_id, p_days })
```

## 7. Web — Memberships page: access-days control

File: `src/features/memberships/components/memberships-page.tsx`.

Header actions row currently: `Share Membership Link · Manage Plans ·
Create Membership`. Add **"Access Days"** button opening a small dialog:

```
Membership Access Days

Which days can members use the court? This pre-fills every new
membership's time slot.

  [M][T][W][T][F][S][S]        [All 7]  [Mon–Fri]

                              [ Cancel ]  [ Save ]
```

Saves via `setMembershipAccessDays`, then refetches the facility (so the
Create page picks up the new default). New component
`membership-access-days-dialog.tsx`.

## 8. Interaction / data flow

```
Owner → Create Membership page
  ├─ fills member + membership + charges + payment
  ├─ (optional) Sport → Court → [existing batch | new batch fields]
  └─ Submit
       └─ createMembershipFull RPC  (one transaction)
            ├─ get-or-create member
            ├─ insert membership (plan_id null)
            ├─ insert payment (unless FREE / 0)
            ├─ if newBatch: validate + insert membership_batches (plan_id null)
            ├─ if batch present: assign_batch_member (capacity-checked)
            └─ return membership row

Later, any Booking attempt on that court/time/day
  └─ create_booking → court_has_active_membership_window → REJECT
Bookings grid for that date
  └─ list_membership_sessions_for_date → 🔒 locked cell
```

## 9. Error handling

| Case | Where | Surface |
|---|---|---|
| both `batchId` and `newBatch` sent | RPC `23514` | "Pick one time slot, not both." (guarded client-side too) |
| court not in facility/sport | RPC `23503` | mapped `INVALID_MEMBERSHIP` |
| empty/invalid days, end ≤ start, capacity < 1 | RPC `23514` | mapped `INVALID_MEMBERSHIP`; client validates first |
| chosen batch is full | `assign_batch_member` `23514` | RPC message "This time slot is full (N / M members)." verbatim |
| access-days save by non-owner | RPC `42501` | mapped `UNAUTHORIZED` |
| membership created but batch assign fails | whole tx rolls back | nothing partially created |

## 10. Testing

**Migration (`0029` test file, pattern of existing SQL tests):**
- `create_membership_full` + `p_new_batch` → membership created, one
  `membership_batches` row (`plan_id` null), one `membership_batch_members`
  row; a subsequent overlapping `create_booking` on that court/day raises
  `23514`; a non-overlapping one succeeds.
- `create_membership_full` + `p_batch_id` for an existing batch → member
  assigned; when the batch is at capacity → `23514`.
- `create_membership_full` with neither → no batch rows, behaviour
  identical to today.
- both params → `23514`.
- `set_facility_membership_access_days`: owner succeeds; empty array
  `23514`; out-of-range value `23514`; non-member `42501`.
- `facilities.membership_access_days` default is `{0,1,2,3,4,5,6}`.

**Web:**
- `createMembershipFull` payload: `p_batch_id` / `p_new_batch` shape,
  `p_time_slot_*` gone.
- Create page: court chosen without slot → validation error; "New time
  slot" → All-7 / Mon–Fri presets set the right day arrays; days
  pre-filled from `facility.membershipAccessDays`; existing full batch
  disabled.
- `membership-access-days-dialog`: presets, save calls service, ≥1 day
  required.
- Facility mapper includes `membershipAccessDays`.

## 11. Follow-up (separate specs)

- Flutter: same Court Time Slot block + access-days control on the
  mobile Create Membership / Memberships screens.
- Edit a membership's time slot from the Memberships page (rather than
  the Membership Sessions batch dialog).

## 12. Open questions

1. **New-slot capacity default** — proposed: field is **required, no
   default** (owner makes a deliberate choice; no upper limit). Fallback:
   soft default `4`.
2. **Existing full batch** — proposed: show disabled + hint to raise
   capacity in Membership Sessions. Alternative: allow inline capacity
   bump from the Create page. Leaning disabled+hint for this round.