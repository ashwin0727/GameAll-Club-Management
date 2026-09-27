# Coaching Module v1 — Add Coach Wizard + Landing Page Redesign

**Goal:** Phase 1 of a larger Coaching-module rework request. Scope is deliberately narrowed to
the three screens the user attached as reference designs:

1. The "Add Coach" wizard (stepper: Basic Information → Coaching Details → Availability → Review).
2. The "Coach Added Successfully" confirmation screen.
3. The redesigned Coaching landing page (hero + KPI row + coach list + Upcoming Sessions /
   Coaching Insights / Quick Actions rail).

**Platform:** **Web only.** The user explicitly asked to skip the Flutter implementation for
this phase — `mobile/lib/features/coaching/` is untouched here and picked up in a later phase.

**Out of scope for this phase** (deferred to later phases of the larger request):
- Add Student wizard with integrated recurring session scheduling.
- Coach/court availability validation wired into the booking engine.
- Coach Profile tab redesign (Overview/Schedule/Programs/Students tabs already exist and are
  untouched; only the Availability tab's editor is extracted for reuse, not redesigned).
- Program management redesign.
- Reports/notifications/finance integration changes.
- Any coach rating/review system — see below.

## Why existing functionality is reused, not rebuilt

Audited before designing anything:
- A "Coach" is not a standalone person — it's an existing **Staff member** with a coaching
  profile layered on top (`coaches.user_id → profiles`, `coaches` table from migration 0082).
  This is a deliberate architectural rule (`add_coach` RPC rejects any `user_id` that isn't an
  active `facility_users` row) and must be preserved.
- Coach availability is **already fully built end-to-end**: `coach_availability` +
  `coach_availability_exceptions` tables, `set_coach_availability` /
  `set_coach_availability_exception` / `delete_coach_availability_exception` RPCs, and a working
  editor (`AvailabilityTab` in `coach-details-page.tsx`). This phase reuses all of it — the only
  change is extracting the editor into a shared component so the wizard and the Coach Profile
  page don't drift.
- Coach candidate listing (`listCoachCandidates`), coach CRUD (`add_coach`, `update_coach`,
  `list_coaches`, `get_coach`), and the Coaches list UI (`coaches-page.tsx`) already exist and
  are extended, not replaced.
- Staff creation already exists end-to-end (`getStaffService().createStaff()` → `create-staff`
  edge function, `listRoles()` for the role picker) and is reused for the wizard's inline
  "new person" path.
- No rating/review system exists anywhere in the app (no session-feedback table, no aggregation).
  The reference screenshot shows star ratings, but faking a number with no backing collection
  mechanism would be worse than omitting it. **This phase omits the Rating column/KPI/tile
  entirely.** A real rating feature (session feedback → aggregated score) is a candidate for a
  later phase, not invented here.
- No sport/expertise-level association exists on `coaches` today — `specialization` is a single
  free-text field. `coaching_programs.level`/`facility_sport_id` are the closest existing
  concepts (program-level, not coach-level), so the vocabulary (`Beginner`, `Intermediate`,
  `Advanced`, `All Levels`) is reused from `program-wizard-page.tsx`'s `LEVELS` constant rather
  than invented fresh.

## Data model

### Migration `0095_coaching_add_coach_wizard.sql`

```sql
-- A coach can be capable of coaching more than one of the facility's sports.
-- Junction table (not an array column) because facility_sport_id is a real FK
-- and other coaching queries (e.g. "coaches for this sport") benefit from a join
-- rather than an array-contains scan.
create table coach_sports (
  coach_id uuid not null references coaches (id) on delete cascade,
  facility_sport_id uuid not null references facility_sports (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (coach_id, facility_sport_id)
);

create index coach_sports_sport_idx on coach_sports (facility_sport_id);

alter table coach_sports enable row level security;

drop policy if exists "coach_sports_select" on coach_sports;
create policy "coach_sports_select" on coach_sports for select
  using (
    exists (
      select 1 from coaches c
      where c.id = coach_sports.coach_id
        and has_permission(c.facility_id, 'COACHING_VIEW')
    )
  );
-- Writes go through add_coach/update_coach (SECURITY DEFINER, gated COACHING_MANAGE_COACHES).

-- Expertise is a small, fixed vocabulary (Beginner/Intermediate/Advanced/All Levels) shared
-- with coaching_programs.level's own UI list — a plain array column, not a lookup table.
alter table coaches add column expertise_levels text[] not null default '{}';

-- The coach's default session length, used to prefill the (separate, existing) Schedule
-- Session flow. Nullable: existing coaches have no default until they set one.
alter table coaches add column default_session_duration_minutes integer
  check (default_session_duration_minutes is null or default_session_duration_minutes > 0);
```

`add_coach` / `update_coach` RPCs gain `p_sport_ids uuid[] default '{}'`,
`p_expertise_levels text[] default '{}'`, `p_default_session_duration_minutes integer default
null`. Inside the same function body (still one transaction per call), after the `insert`/
`update` into `coaches`, sync `coach_sports`:

```sql
delete from coach_sports where coach_id = result.id;
insert into coach_sports (coach_id, facility_sport_id)
  select result.id, unnest(p_sport_ids)
  where p_sport_ids is not null and array_length(p_sport_ids, 1) > 0;
```

Read RPCs (`list_coaches`, `get_coach` in migration 0086) gain a `sports` aggregate
(`jsonb_agg(jsonb_build_object('id', fs.id, 'name', s.name))` joined through `coach_sports` →
`facility_sports` → `sports`) and pass through `expertise_levels` and
`default_session_duration_minutes` directly.

### Types (`src/features/coaching/types.ts`)

- `CoachRow`, `CoachDetail`: add `sports: { id: string; name: string }[]`,
  `expertiseLevels: string[]`, `defaultSessionDurationMinutes: number | null`.
- New `AddCoachInput` fields: `sportIds: string[]`, `expertiseLevels: string[]`,
  `defaultSessionDurationMinutes: number | null`.
- `specialization` stays on the type (existing certifications/bio-style free text some coaches
  may still have from before this phase) but is dropped from the wizard's own form — Sports +
  Expertise Level replace its role going forward. Existing values are preserved, just not edited
  through the new wizard.

## Add Coach wizard (`add-coach-page.tsx` rewritten)

A 4-step stepper (`WizardStepper`-style component, following the same pattern as the Membership
module's `wizard-stepper.tsx` / `plan-wizard-stepper.tsx` — reused, not reinvented).

### Step 1 — Basic Information

- Default mode: searchable dropdown over `listCoachCandidates(facilityId)`. Confirmed today's
  `list_coach_candidates` RPC and `CoachCandidate` type return only `userId`/`fullName`/`email`/
  `title` — no `avatarUrl`/`phone`. Both need extending: the RPC to also select `p.avatar_url`
  and `p.phone` from `profiles`, and `CoachCandidate` to carry them. Selecting a candidate then
  shows their photo/phone/email read-only below the picker.
- "+ New person" toggle switches to an inline form: full name, phone, email (required — matches
  `CreateStaffInput`), and a role `Select` populated from `getStaffService().listRoles(facilityId)`,
  defaulting to a role whose name matches `/coach/i` if one exists.
  **Amendment during implementation:** the screenshot does show an optional Date of Birth field.
  `CreateStaffInput`/`profiles` have no DOB column to reuse, so rather than drop the field or
  silently discard it, `coaches.date_of_birth date` was added (migration 0095) — same column
  name/type `members.date_of_birth` already uses (0013) — and threaded through
  `add_coach`/`update_coach`/`get_coach`.
  **Second amendment:** re-reading the reference screenshot, "Add Coach" is a single scrollable
  panel with three numbered section headers (Basic Information / Coaching Details / Availability
  & Settings) — not a Next/Back stepper, and with no separate Review step; "+ Add Coach" submits
  directly from that one panel. The implementation follows the screenshot exactly instead of the
  4-step-plus-review flow described earlier in this doc. It also confirmed the Availability &
  Settings section only collects Status + Default Session Duration + Bio — the full weekly
  availability grid is **not** part of onboarding; it's set afterward from the Coach Profile's
  existing Availability tab (reachable from the success screen's "Manage Availability" action),
  which is simpler and matches the screenshot's actual field list.
- On Next in "new person" mode: call `createStaff()` first (shows its own loading/error state,
  since it's a real mutation with side effects — a temporary password is generated). On success,
  proceed as if that new `userId` had been picked from the candidate list. On failure, show the
  error inline and do not advance.
- Required: a selected/created user. Next is disabled until satisfied.

### Step 2 — Coaching Details

- Sports: multi-select chips, options from `useFacilitySportOptions(facilityId)` (existing hook,
  reused from the Membership module's sport-scoping work). At least one required.
- Expertise Level: multi-select chips from `["Beginner", "Intermediate", "Advanced", "All
  Levels"]`. At least one required.
- Years of Experience: numeric, required (matches existing form's requirement level — currently
  optional in the DB but the wizard nudges completeness; keep it optional to avoid a behavior
  change, just always shown).
- Certification: optional text (existing `certifications` field).
- Bio: optional textarea (existing `bio` field, carried over unchanged).

### Step 3 — Availability

- Extract `AvailabilityTab`'s weekly-windows editor (currently inline in
  `coach-details-page.tsx`) into `src/features/coaching/components/coach-availability-editor.tsx`,
  taking `windows`/`onChange` as props with no fetching/saving of its own. Both the wizard and
  the (unchanged) Coach Profile Availability tab render it; the profile tab keeps its own
  save button/RPC call, the wizard defers saving until the final submit.
- Status toggle (Active/Inactive — `ON_LEAVE` stays reachable only from the Coach Profile, not
  onboarding, since a coach can't go on leave before they exist).
- Default Session Duration: `Select` (30 min / 45 min / 1 hour / 1.5 hours / 2 hours), optional.

### Step 4 — Review & Add

- Read-only summary of all three steps, each with an "Edit" link that jumps back to that step
  without losing later steps' state.
- Submit: `add_coach` (now carrying sports/expertise/duration) then, if any availability windows
  were set, `set_coach_availability`. If `set_coach_availability` fails after `add_coach`
  succeeded, surface the coach as created with a warning to set availability from their profile
  — do not roll back a successful coach creation for a follow-up call's failure (matches how the
  existing Coach Profile page already treats availability as independently editable).
- Disable the button during submission; no double-submit.

### Success screen

Replaces the current `router.push` straight to the coach's profile. A new state on
`AddCoachPage` (`"form" | "success"`) swaps the wizard card for:
- Checkmark + "Coach Added Successfully!" + the coach's name/sports summary sentence.
- Coach summary card: photo, name, status badge, phone, email, sports, expertise, experience.
- Four next-action cards: **Schedule a Session** (→ `/coaching/sessions/new?coachId=...`),
  **Manage Availability** (→ `/coaching/coaches/:id?tab=Availability`), **Assign to Program**
  (→ program picker, reuses whatever the Coach Profile's Programs tab already offers), **View
  Coach Profile** (→ `/coaching/coaches/:id`).
- Footer buttons: "Add Another Coach" (resets wizard state to Step 1) and "Go to Coaches List"
  (→ `/coaching/coaches`).

## Coaching landing page redesign (`overview-page.tsx`)

Same pattern the Membership Dashboard already established (hero + embedded list, not a link-out):

- Hero banner: "Better Coaching. Stronger Players." / "Manage coaches, schedule sessions, and
  grow your community." — same hero component family as
  `membership-dashboard-hero.tsx` (generalize it to accept these props if it isn't already
  generic; do not fork a second hero component).
- KPI row restyled using the same stat-card visual language as `MembershipStatCard`
  (icon + colored background + value + delta), four cards: Active Coaches, Total Students,
  Coaching Sessions, Coaching Revenue. (No Average Rating tile — see rating note above.) Existing
  `getOverview()` data (`k.activeCoaches`, total students from `studentsByProgram`,
  `k.sessionsThisMonth`, `k.revenueThisMonthMinor`) is reused; no new read RPC needed for the KPI
  row itself.
- Main content, two-column at `lg`+:
  - **Left (primary):** the existing `CoachesPage` table logic inlined directly into this page
    (not routed to separately) — tabs (All/Active/Inactive), search, Status filter, new **Sport**
    filter (via `coach_sports`), list/grid view toggle, pagination. The new Sport column in the
    table renders `CoachRow.sports`. The standalone `/coaching/coaches` route keeps working
    unchanged (still useful as a direct link/bookmark) — it is not deleted, just no longer the
    only place this table renders.
  - **Right (rail):** "Upcoming Coaching Sessions" (existing `data.upcomingSessions`, restyled as
    a compact list with a colored time badge per row instead of a table), "Coaching Insights" —
    confirmed `CoachingOverview` has no attendance figure, so (matching the Rating decision) the
    2x2 grid uses four tiles all backed by data the RPC already returns: Total Students, Sessions
    This Month, Coaching Revenue, Upcoming Sessions — "Quick Actions" (Add Coach, Schedule
    Session, Manage Students → `/coaching/enrollments`, Coaching Programs → `/coaching/programs`).

## Testing

- **Unit:** sports/expertise-level validation for the new wizard fields; `coach_sports` sync
  logic if it's expressed in a TS-testable form (e.g. a pure "diff old vs new sport ids" helper
  if one is introduced) — the SQL sync itself is covered by the DB test below.
- **Widget/component:** each wizard step's field validation and Next-button gating; the inline
  "new person" branch (mocking `createStaff`); the Review step's Edit links; the success screen's
  next-action links; the landing page's new Sport filter and restyled KPI/rail sections; loading
  and error states for the `createStaff` call.
- **DB/RLS:** `coach_sports` facility isolation (a user from facility A cannot read facility B's
  coach_sports rows even with a guessed coach_id); `add_coach`/`update_coach` correctly sync the
  junction table on repeated calls (add then remove a sport).
- **Build validation:** `tsc --noEmit`, `npm run lint`, `vitest run src/features/coaching`,
  `npm run build` (or the project's known `NEXT_DIST_DIR` workaround per existing team
  guidance). No E2E tests.

All three open items from the earlier draft were resolved during spec-writing (see inline notes
above): `list_coach_candidates`/`CoachCandidate` need extending with `avatarUrl`/`phone` (they
don't carry them today), `CoachingOverview` has no attendance figure (Insights rail uses four
existing-data tiles instead), and DOB is dropped entirely (no column/precedent anywhere in staff
creation).
