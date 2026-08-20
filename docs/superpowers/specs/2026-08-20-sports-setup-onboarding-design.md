# Sports Setup Onboarding — Design

Status: Approved for planning
Owner: ashwin0727

## 1. Purpose

Add the second step of the facility onboarding flow — "Sports Setup" —
reached after Facility Details. It lets the owner select which sports
their facility operates, saved as a `facilityId -> sportId` relationship
(never attached to the user), then hands off to a Courts placeholder.
Frontend-only phase: mock service, local persistence, shaped for a future
Supabase-backed swap.

## 2. Scope boundaries

In scope:
- `/onboarding/courts` placeholder page
- Facility context card (name, location, type) at the top of the page
- Sport selection grid (6 sports: Badminton, Pickleball, Cricket,
  Football, Tennis, Other), multi-select, minimum one required
- "Other" custom sport name input
- Facility-type-based preselection on first visit only
- `Sport` (global) and `FacilitySport` (relationship) models, kept separate
- `MockSportService`, mirroring `MockFacilityService`'s seam
- Facility-context loading/validation (auth check, facility check,
  ownership check) before the page renders
- Auto-save with restore-on-reopen, matching the Facility Details pattern
- Continue/Back navigation, onboarding state (`sportsCompleted`,
  `currentStep`) extended on the existing `useOnboardingStore`
- Tests per spec §39

Out of scope:
- Courts, Operating Hours, Pricing, Dashboard pages
- Real Supabase persistence
- Multi-facility switcher UI (architecture must not block it — see §6)
- Global sport management (disabling a sport for all facilities) — only
  the `isActive` filter on read is implemented, no admin UI

## 3. Data model

`src/features/sports-setup/types.ts`:

```ts
export interface Sport {
  id: string;
  name: string;
  code: string;
  icon: string; // lucide-react icon name, resolved by SportCard
  description: string;
  isActive: boolean;
}

export interface FacilitySport {
  id: string;
  facilityId: string;
  sportId: string;
  enabled: boolean;
  /**
   * Only set when sportId === "sport_other". Sport itself stays global —
   * this is the one piece of facility-specific data the relationship
   * needs, not a merge of the two models.
   */
  customSportName?: string;
  createdAt: string;
  updatedAt: string;
}

export type FacilitySportInput = Omit<FacilitySport, "id" | "createdAt" | "updatedAt">;
```

The 6 sports are static, seeded in `src/features/sports-setup/constants.ts`:
`sport_badminton`, `sport_pickleball`, `sport_cricket`, `sport_football`,
`sport_tennis`, `sport_other` — each with a code (`BADMINTON`, ...,
`OTHER`), a lucide icon name, a short description, `isActive: true`.

## 4. Service

`src/features/sports-setup/services/mock-sport-service.ts`, same shape as
`MockFacilityService`:

```ts
export const MockSportService = {
  getAvailableSports(): Promise<Sport[]>,          // static list, isActive only
  getFacilitySports(facilityId: string): Promise<FacilitySport[]>,
  saveFacilitySports(facilityId: string, sports: FacilitySportInput[]): Promise<FacilitySport[]>,
  updateFacilitySports(facilityId: string, sports: FacilitySportInput[]): Promise<FacilitySport[]>,
};
```

`saveFacilitySports`/`updateFacilitySports` both fully replace the
facility's existing rows with the new set (localStorage key
`turf.facility-sports.mock.v1`) — deselecting a sport means it's simply
absent from the next save, satisfying §26 without a separate delete path.
Both methods exist because §35 names them both; they call the same
internal replace logic.

## 5. State

Extends the existing `useOnboardingStore` (`src/features/onboarding/state/onboarding-store.ts`)
rather than introducing a second onboarding store — `facilityDetailsCompleted`/
`currentStep`/etc. already live there, and Sports Setup's state belongs
alongside them:

```ts
// added to OnboardingState
selectedSportIds: string[];
otherSportName: string;
sportsCompleted: boolean; // already existed as a placeholder field
setSelectedSportIds: (ids: string[]) => void;
setOtherSportName: (name: string) => void;
completeSports: () => void; // sets sportsCompleted, currentStep: 3, completedSteps += 2
```

`reset()` (already called on logout, per the Facility Details fix) clears
these too — no separate reset path needed.

## 6. Facility Sport hierarchy (why the models stay separate)

```
users
  └── facilities
        └── facility_sports
              └── sports
```

`Sport` is the global catalog (what sports exist on the platform).
`FacilitySport` is "this facility operates this sport" — the only place
`facilityId` and `sportId` meet. Nothing in this feature writes a sport
directly to a user. `Facility` already carries `ownerId`, so
`Owner -> [Facility A, Facility B, ...] -> sports` is not blocked by this
design even though only one facility exists per owner today (same
pattern as the Facility Details spec's §29).

## 7. Facility context loading

A loader (colocated with the page, not a separate hook file — small
enough) runs before the form renders:

1. `useCurrentUser()` — no user → `redirect("/login")` (server-side, since
   the page is a server component like `dashboard/page.tsx`, or client-side
   equivalent if the page must be a client component — see §9).
2. `MockFacilityService.getFacility(user.id)` — source of truth, not the
   store's cached `facility` (defense in depth per §20) — no facility →
   `redirect("/onboarding/facility")`.
3. `facility.ownerId === user.id` assertion — guaranteed true by
   construction (the service already filters by `ownerId`), kept as an
   explicit check per spec §20 rather than trusted silently; if it somehow
   fails, show "You don't have access to this facility." instead of
   rendering the form.

## 8. Preselection (§12)

Only on first-ever visit — i.e. `getFacilitySports(facilityId)` returns an
empty array. If `facility.type` is one of the five single-sport types
(`BADMINTON`, `PICKLEBALL`, `CRICKET`, `FOOTBALL`, `TENNIS`), preselect
the matching sport. `MULTI_SPORT` and `OTHER` preselect nothing. Never
overrides an existing saved selection on a later visit — the loader only
applies this when the fetched `FacilitySport[]` is empty.

## 9. Routing

`src/app/onboarding/courts/page.tsx` — placeholder, same shape as the
existing `src/app/onboarding/sports/page.tsx` placeholder it replaces as
the Continue target. `src/app/onboarding/sports/page.tsx` becomes the real
page (its current placeholder content is deleted).

No changes to `src/app/onboarding/layout.tsx`: its Back routing already
sends `/onboarding/sports -> /onboarding/facility` correctly. Courts is a
placeholder, so its Back target falling through to `/dashboard` (the
layout's default) is acceptable and out of scope to special-case.
`OnboardingProgress` needs no changes — it's already non-clickable, and
§5's "allow clicking the previous step only if backward navigation is
already supported" condition isn't met (the app's only backward-nav
mechanism is the dedicated Back button, not clicking a progress step).

Server-component note: `MockFacilityService`/`MockSportService` are
localStorage-backed, so they cannot run on the server. Unlike
`dashboard/page.tsx` (which reads Supabase server-side), this page's
facility/sport loading must happen client-side, inside a `"use client"`
component — matching how `FacilityDetailsForm` itself already reads
`useCurrentUser()` and calls `MockFacilityService` from a client component.
The redirects in §7 become client-side `router.replace(...)` calls guarded
behind a loading state, not `next/navigation`'s server `redirect()`.

## 10. Components

`src/features/sports-setup/components/`:
- `facility-context-card.tsx` — icon, facility name, city, type; no
  "Change Facility" affordance rendered (single-facility phase, per §3 —
  hidden, not built-and-disabled, since there's nothing to switch to yet)
- `sport-card.tsx` — full-card-clickable (not just a checkbox), ≥48px
  touch target, ~150ms border/background/check transition, `aria-pressed`
  for the selected state, keyboard-operable (`Enter`/`Space` via a real
  `<button>` element)
- `sport-grid.tsx` — 1 column mobile, 2 tablet, 3 desktop (Tailwind
  `grid-cols-1 sm:grid-cols-2 lg:grid-cols-3`)
- `other-sport-input.tsx` — appears only when the Other card is selected;
  reuses `TextField`
- `selected-sports-summary.tsx` — "N sport(s) selected" / "No sports
  selected", including Other in the count when selected
- `sports-setup-form.tsx` — the integration point, same shape as
  `FacilityDetailsForm`: owns loading state, selection state, save/continue,
  composes the pieces above
- Reused unmodified: `Card`, `Button`, `TextField`, `SaveStatus`,
  `LeaveConfirmDialog` (already wired in the shared layout), `FormMessage`

## 11. Validation

- At least one sport selected — Continue disabled otherwise, and a
  `FormMessage` "Select at least one sport to continue." if submitted
  anyway (defense in depth, matching the disabled-button as primary gate)
- When Other is selected: name required, trimmed, 2–50 characters —
  validated with a small zod schema alongside the existing
  `facilityDetailsSchema` convention, in
  `src/features/sports-setup/validation.ts`

## 12. Continue / submit flow

1. Validate facility (already loaded, guaranteed present by this point).
2. Validate selection (≥1 sport) and Other's name if applicable.
3. Build `FacilitySportInput[]` from `selectedSportIds` (+ `customSportName`
   on the Other row) and call `MockSportService.saveFacilitySports`.
4. `useOnboardingStore.getState().completeSports()`.
5. `router.push("/onboarding/courts")`.
6. On failure: `FormMessage` "Unable to save your sports. Please try
   again." — no technical detail.

## 13. Auto-save

Same pattern established in `FacilityDetailsForm`: a debounced (~400ms)
write on every selection change (not on every click without delay, per
§25 and the already-fixed spec §22 lesson from Facility Details), driving
the existing `SaveStatus` component. No new debounce mechanism — reuse
`SaveStatus` and the same `useEffect` + `setTimeout` pattern.

## 14. Testing

`src/features/sports-setup/components/sports-setup-form.test.tsx` (+ one
file per smaller component where it earns its own suite), using the
existing `renderWithProviders`/harness/`routerMock` conventions:

- Facility relationship: sports load for the current facility; a facility
  belonging to a different `ownerId` cannot be accessed (loader redirects
  or shows the access-denied message); no facility redirects to
  `/onboarding/facility`
- Selection: one sport, multiple sports, deselect, select all, Other
- Validation: no sport selected, Other selected without a name, name too
  short, name too long
- Persistence: save, "reload" (remount), selections restored, and scoped
  to the correct `facilityId`
- Navigation: Back → `/onboarding/facility`, Continue →
  `/onboarding/courts`, unauthenticated → `/login`, missing facility →
  `/onboarding/facility`

Responsive behavior is verified manually (same disclosed limitation as
Facility Details — no real authenticated browser session available in
this environment), not asserted in Vitest/jsdom.

## 15. Risks / open notes

- `customSportName` on `FacilitySport` is a deliberate, minimal extension
  beyond the spec's literal 6-field model (§3) — approved by the user
  during design; the alternative (name lives only in the ephemeral draft,
  never persisted with the saved relationship) was rejected because it
  would silently lose the owner's typed name on next visit.
- Facility/sport loading is unavoidably client-side (localStorage-backed
  mock services can't run in a server component) — flagged so nobody
  expects this page to match `dashboard/page.tsx`'s server-rendered
  pattern.
- No migration/version field on the new localStorage keys, matching the
  existing `MockFacilityService`/`onboarding-store` precedent (not a new
  gap introduced here).
