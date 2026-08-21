# Courts & Turfs Setup Onboarding — Design

Status: Approved for planning
Owner: ashwin0727

## 1. Purpose

Add the third step of the facility onboarding flow — "Courts & Turfs
Setup" — reached after Sports Setup. For each sport the facility
operates, the owner adds the playing areas (courts/turfs) available,
each one belonging to `facilityId` + `facilitySportId` + `sportId`. Hands
off to an Operating Hours placeholder. Frontend-only phase: mock service,
local persistence, shaped for a future Supabase-backed swap.

## 2. Scope boundaries

In scope:
- `/onboarding/operating-hours` placeholder page
- Facility context card + selected-sports-only sections (reusing what
  Sports Setup already built where possible)
- Add/rename/remove playing areas per sport, with dynamic Court/Turf/
  Playing Area terminology
- Type (Indoor/Outdoor), Status (Active/Inactive), Booking Enabled fields
- Name uniqueness within `facilityId + facilitySportId`
- Minimum one playing area per selected sport before Continue
- Incremental, debounced auto-save directly to the mock service (see §5
  for why this differs from Sports Setup's approach)
- `PlayingArea` model and `MockPlayingAreaService`
- Tests per spec §45

Out of scope:
- Operating Hours, Pricing, Dashboard pages
- Real Supabase persistence
- Court pricing, peak hours, membership pricing, discounts, maintenance
  schedules, lighting, flooring, equipment, booking/cancellation rules,
  capacity — explicitly deferred per the source spec §33
- Drag-and-drop reordering (the `displayOrder` field exists so it can be
  added later, per source spec §32)
- Multi-facility switcher UI

## 3. Data model

`src/features/courts-setup/types.ts`:

```ts
export interface PlayingArea {
  id: string;
  facilityId: string;
  facilitySportId: string;
  sportId: string;
  name: string;
  type: "INDOOR" | "OUTDOOR";
  status: "ACTIVE" | "INACTIVE";
  bookingEnabled: boolean;
  /**
   * Separate from `status`. Status is a legitimate, owner-set, always-
   * visible toggle ("this court exists but isn't bookable right now").
   * `archived` means "removed from the onboarding list" — set by Remove
   * on an already-saved playing area, per source spec §16's soft-delete
   * requirement. Archived rows are excluded from every read the UI
   * displays but never hard-deleted, preserving history for future
   * reporting/booking modules.
   */
  archived: boolean;
  displayOrder: number;
  createdAt: string;
  updatedAt: string;
}

export type PlayingAreaInput = Omit<PlayingArea, "id" | "createdAt" | "updatedAt">;
```

This is the one approved extension beyond the source spec's literal §24
model (which has no `archived` field) — same pattern as `FacilitySport.
customSportName` in the prior feature: a minimal, justified addition to
close a real gap between two of the spec's own requirements, not a model
merge.

## 4. Service

`src/features/courts-setup/services/mock-playing-area-service.ts`, same
seam shape as `MockFacilityService`/`MockSportService`:

```ts
export const MockPlayingAreaService = {
  getPlayingAreas(facilityId: string): Promise<PlayingArea[]>,
  getPlayingAreasByFacilitySport(facilitySportId: string): Promise<PlayingArea[]>,
  createPlayingArea(input: PlayingAreaInput): Promise<PlayingArea>,
  updatePlayingArea(id: string, patch: Partial<PlayingAreaInput>): Promise<PlayingArea>,
  removePlayingArea(id: string): Promise<void>, // sets archived: true, never deletes the row
};
```

LocalStorage key `turf.playing-areas.mock.v1`. `getPlayingAreas`/
`getPlayingAreasByFacilitySport` both filter out `archived: true` rows —
callers never see archived data through the normal read path (a future
reporting feature would need its own explicit "include archived" read,
not built here).

## 5. State — why this differs from Sports Setup's draft pattern

Sports Setup staged the in-progress selection in `useOnboardingStore` and
only persisted it to `MockSportService` on Continue. That created a real
bug (caught in that feature's final review): the load effect never read
the staged draft back, so refreshing before Continue silently lost
unsaved changes while the UI claimed "Saved."

Courts Setup avoids that class of bug by construction: **playing areas
are incrementally persisted directly to `MockPlayingAreaService`** as the
owner works, debounced ~400ms. "+ Add Court" first creates a local-only
draft object (per source spec §14 — "do not immediately persist every
empty card as a final record"); once the debounce settles, that draft
becomes a real `createPlayingArea` call, and every subsequent edit calls
`updatePlayingArea`. Every load simply reads current state from the
service — there is no second, separate draft store that can drift out of
sync with what's actually saved. Refresh-restore and Back-preserves-data
(source spec §22, §30) both fall out of this for free, the same way they
already do for `Facility`/`FacilitySport` records.

Only `courtsCompleted` and `currentStep` extend the existing
`useOnboardingStore`, mirroring `completeSports()`:

```ts
// added to OnboardingState
completeCourts: () => void; // sets courtsCompleted, currentStep: 4, completedSteps += 3
```

## 6. Facility/sport loading

Same client-side pattern `SportsSetupForm` already established (mock
services are localStorage-backed, cannot run in a Server Component):

1. `useCurrentUser()` — no user → `/login`.
2. `MockFacilityService.getFacility(user.id)` — no facility →
   `/onboarding/facility`.
3. `ownerId` mismatch → "You don't have access to this facility."
4. `MockSportService.getFacilitySports(facility.id)` — empty →
   `/onboarding/sports`.
5. `MockPlayingAreaService.getPlayingAreas(facility.id)` — group by
   `facilitySportId` for section rendering.

## 7. Terminology config

`src/features/courts-setup/constants.ts`:

```ts
export const PLAYING_AREA_LABEL: Record<string, "Court" | "Turf" | "Playing Area"> = {
  BADMINTON: "Court",
  PICKLEBALL: "Court",
  TENNIS: "Court",
  CRICKET: "Turf",
  FOOTBALL: "Turf",
  OTHER: "Playing Area",
};
```

Keyed by `Sport.code` (already on the global catalog from Sports Setup).
Drives the section heading ("Add the courts/turfs available for
{sport}"), the Add-button label ("+ Add Court"/"+ Add Turf"/"+ Add
Playing Area"), auto-generated names ("Court 1"/"Turf 1"), and the count
summary ("4 Courts"/"1 Turf") — no hardcoded "Court" string anywhere
else in the components.

## 8. Components

`src/features/courts-setup/components/`:
- `sport-section.tsx` — one per selected `FacilitySport`: icon + sport
  name + count, the Add button, and its playing-area cards or the empty
  state ("No courts added yet")
- `playing-area-card.tsx` — Name (`TextField`), Type/Status/Booking (all
  three as `SelectField`, reusing what Sports Setup already built — no
  new toggle/switch primitive needed), Remove
- `add-playing-area-button.tsx` — thin wrapper computing the next
  auto-generated name (`"{Label} {n+1}"`) and calling the create flow
- `playing-area-summary.tsx` — "N Sports / M Playing Areas" header
  summary, plus the per-section count
- `courts-setup-form.tsx` — the integration point, same shape as
  `SportsSetupForm`: loading/validation/save, composes the sections
- Reused unmodified: `FacilityContextCard`, `SelectField`, `TextField`,
  `SaveStatus`, `ErrorState`, `Skeleton`, `Card`, `Button`, `Dialog` (for
  the remove-confirmation on an already-saved court)

## 9. Validation

- At least one non-archived playing area per selected `FacilitySport`
  before Continue — error: "Add at least one court for {sport}."
  (dynamic label)
- Name: required, trim, 2–50 chars
- Name uniqueness scope: `facilityId + facilitySportId` (same name is
  valid across different sports, or the same sport at a different
  facility)

## 10. Continue / Back

Continue: validate → any failing sport shows its inline error and blocks
navigation → `useOnboardingStore.getState().completeCourts()` →
`router.push("/onboarding/operating-hours")`. Nothing further needs
"saving" at this point since every playing area is already persisted
incrementally.

Back → `/onboarding/sports`. Requires extending the shared
`src/app/onboarding/layout.tsx`'s `previousStepPath` lookup (already a
`Record<string, string>` after the Sports Setup final-review fix) with
`"/onboarding/courts": "/onboarding/sports"` — already present from that
fix — and `"/onboarding/operating-hours": "/onboarding/courts"` for the
new placeholder. `hasUnsavedProgress`'s dirty-check does not need a new
OR-clause for playing areas, since they're never held in `draft`/
`selectedSportIds`-style staged state to begin with (§5) — nothing to
lose on an in-app Back click that isn't already persisted.

## 11. Testing

`src/features/courts-setup/components/courts-setup-form.test.tsx` (+ one
file per smaller component where it earns its own suite), matching the
`renderWithProviders`/harness/`routerMock`/`installAuth()` conventions
already established:

- Facility/sport loading: only selected sports render sections; missing
  facility/sports/auth redirect correctly; wrong owner shows the access-
  denied message
- Playing areas: add, rename, remove (draft vs. already-saved
  confirmation), change type/status/booking, multiple per sport
- Validation: no playing areas for a sport, duplicate name within the
  same sport, name too short, empty name
- Persistence: add → reload (remount) → restored; scoped to the correct
  facility
- Navigation: Back → `/onboarding/sports`, Continue →
  `/onboarding/operating-hours`

Responsive behavior verified manually (same disclosed sandbox limitation
as the two prior onboarding features — no real authenticated browser
session available here).

## 12. Risks / open notes

- `archived` is the one deliberate model extension beyond source spec
  §24 — approved during design, same category of decision as
  `FacilitySport.customSportName`.
- The incremental-persist-per-field debounce (§5) is a genuine
  architectural change from how Sports Setup handled its draft, made
  specifically to avoid repeating that feature's caught bug — flagged
  here so a future reviewer understands why the two features differ.
- No drag-and-drop; `displayOrder` is set (insertion order today) but
  not yet user-editable, per source spec §32.