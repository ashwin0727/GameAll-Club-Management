# Facility Details Onboarding — Design

Status: Approved for planning
Owner: ashwin0727

## 1. Purpose

Add the first step of a multi-step facility onboarding flow — "Facility
Details" — reached after Sign In (or Signup, when the session is already
active). It collects the basic facility record that becomes the parent
entity for everything else in the product (sports, courts, bookings,
customers, payments). Only this step and a placeholder for the next
("Sports Setup") are built now; Sports/Courts/Hours/Pricing/Dashboard pages
are out of scope.

This phase is frontend-only: form, validation, local persistence, and a
mock service shaped like the future Supabase-backed one. No real backend
integration in this task.

## 2. Scope boundaries

In scope:
- `/onboarding/facility` page and its shared `/onboarding` layout
- `/onboarding/sports` placeholder page
- Onboarding progress indicator (non-clickable)
- Facility Information / Facility Location / Facility Branding sections
- Client-side validation, auto-save to localStorage, restore-on-refresh
- Mock facility service (`saveFacility`/`getFacility`/`updateFacility`)
- Reusable `Facility`/`FacilityType` types shaped for future Supabase use
- Wiring the post Sign In / Signup redirect and splash entry route to send
  an onboarding-incomplete user to `/onboarding/facility`
- Tests for validation, persistence, and navigation

Out of scope:
- Sports, Courts, Operating Hours, Pricing, Dashboard-facing pages
- Real Supabase persistence (schema/migration changes)
- Multi-facility UI, role management UI
- Flutter — this repository contains only the Next.js web app; there is no
  Flutter project to extend
- Intercepting arbitrary in-app navigation or browser tab-close with a
  custom dialog (see §7)

## 3. Routing & layout

```
src/app/onboarding/
├── layout.tsx          # shared onboarding shell
├── facility/
│   └── page.tsx         # this task's page
└── sports/
    └── page.tsx          # placeholder: "Sports Setup — Coming Next"
```

`src/app/onboarding/layout.tsx` renders a dedicated shell — distinct from
both the auth split-panel shell and the dashboard sidebar/topbar shell:
- Top bar: `← Back` button (left) + `OnboardingProgress` (right on desktop,
  full-width compact bar on mobile)
- Centered content container, max-width ~1000px, consistent with the
  existing `container` padding conventions in `tailwind.config.ts`

No middleware change is required: `/onboarding/*` is not in
`PUBLIC_ROUTES`, so a signed-out visitor is already redirected to
`/login` by the existing rule in `src/lib/supabase/middleware.ts`.

### Redirect wiring (touches existing auth code, deliberately)

- `useLogin()` and `useSignup()` in `src/features/auth/hooks/use-auth.ts`:
  where they currently `router.replace("/dashboard")` after establishing a
  session, branch on `user.onboardingCompleted` /
  `result.onboardingCompleted`: `false` → `/onboarding/facility`, `true` →
  `/dashboard`. `useSignup`'s email-verification branch
  (`sessionActive: false` → `/verify-email`) is unchanged.
- `resolveEntryRoute` in `src/features/auth/entry-route.ts` gains a third
  input, `onboardingCompleted: boolean`, and a third branch: signed in +
  incomplete → `/onboarding/facility`. The splash screen
  (`src/app/page.tsx`) fetches `getCurrentAuthUser()` (already
  request-cached, one round trip) instead of only the boolean
  `signedIn`, and passes `onboardingCompleted` down to
  `SplashScreen`/`resolveEntryRoute`.
- This is the only change to existing Login/Create Account/Splash
  behavior. Nothing else in those flows changes; acceptance criterion
  "existing Login/Create Account functionality remains untouched" is
  read as "unbroken", not "byte-for-byte unmodified" — this redirect
  branch is required to satisfy "user reaches Facility Details after
  successful Sign In."

## 4. State management

`src/features/onboarding/state/onboarding-store.ts` — a `zustand` store
using the `persist` middleware (same library already used for
`src/stores/ui-store.ts`), localStorage key `turf.onboarding.v1`:

```ts
interface OnboardingState {
  currentStep: number;                  // 1-based
  completedSteps: number[];
  facilityDetailsCompleted: boolean;
  sportsCompleted: boolean;
  courtsCompleted: boolean;
  operatingHoursCompleted: boolean;
  pricingCompleted: boolean;
  draft: FacilityDraft;                 // the in-progress form values
  setDraft: (patch: Partial<FacilityDraft>) => void;
  completeFacilityDetails: (facility: Facility) => void;
  reset: () => void;
}
```

`persist` gives restore-on-refresh for free. A separate small hook
(`useAutoSaveStatus`, colocated with `save-status.tsx`) debounces only the
**status text** ("Saving…" → "Saved" after 300–500ms of no changes) — the
actual store writes are cheap synchronous localStorage writes and are not
throttled.

No secrets, tokens, or passwords are ever written to this store or to
localStorage — only the facility draft fields.

## 5. Mock service

`src/features/onboarding/services/mock-facility-service.ts`:

```ts
export const MockFacilityService = {
  saveFacility(input: FacilityInput): Promise<Facility>,
  getFacility(ownerId: string): Promise<Facility | null>,
  updateFacility(id: string, patch: Partial<FacilityInput>): Promise<Facility>,
};
```

Backed by `localStorage` (key `turf.facility.mock.v1`), generating a
`crypto.randomUUID()` id and timestamps. Shaped so a future
`SupabaseFacilityService` implementing the same three methods can be
swapped in behind a `getFacilityService()` seam (mirroring
`src/services/auth`'s existing `getAuthService()` pattern) without
touching the form/UI layer.

## 6. Data model

`src/features/onboarding/types.ts`:

```ts
export type FacilityType =
  | "BADMINTON" | "PICKLEBALL" | "CRICKET" | "FOOTBALL" | "TENNIS"
  | "MULTI_SPORT" | "OTHER";

export interface Facility {
  id: string;
  ownerId: string;              // future FK → profiles.id / facility_users
  name: string;
  type: FacilityType;
  customType?: string;          // only when type === "OTHER"
  businessEmail: string;        // read from the signed-in account, not editable here
  businessPhone: string;
  address: {
    line1: string;
    area: string;
    city: string;
    state: string;
    country: "India";
    pinCode: string;
  };
  logoUrl?: string;              // object URL in this phase, real storage URL later
  description?: string;
  status: "ACTIVE" | "INACTIVE";
  createdAt: string;
  updatedAt: string;
}
```

`ownerId` is carried on every record from day one — even though the UI
only ever creates one facility per owner right now — so the shape does
not block the future `Owner → [Facility A, Facility B, ...]` switcher.

**Known gap, intentionally not fixed here:** the real
`facilities` table in `supabase/migrations` (see
`src/types/database.types.ts`) is currently leaner — `name, slug,
owner_id, city, address: string, timezone, currency` — with no `type`,
`phone`, structured address, logo, or description columns. This
frontend model is what a future migration will need to grow into; a code
comment on `Facility` notes this so nobody assumes the columns already
exist.

## 7. Components

`src/features/onboarding/components/`:
- `onboarding-progress.tsx` — desktop: horizontal stepper (● current, ○
  future, connecting line); mobile: "Step 1 of 5" + a filled progress bar.
  Steps are never clickable in this phase.
- `facility-information-section.tsx` — name, type (+ conditional custom
  type), phone, read-only verified business email
- `facility-location-section.tsx` — address, area, city, state, PIN
- `facility-branding-section.tsx` — optional logo upload + description
  with a live `0/500` counter
- `facility-details-form.tsx` — composes the three sections inside one
  `react-hook-form` (`zodResolver`, `mode: "onTouched"` — same pattern as
  `signup-form.tsx`), wires the store, renders `Continue`
- `save-status.tsx` — small "Saving…"/"Saved" text, no toasts
- `leave-confirm-dialog.tsx` — built on the existing `Dialog` primitive;
  shown only when `← Back` is clicked and the draft has unsaved changes
  relative to the last completed step. Per your decision, this is scoped
  to the in-app Back button only — Next.js App Router has no supported
  hook to intercept arbitrary `<Link>`/router navigation, and tab-close/
  refresh is left to autosave alone (no native `beforeunload` prompt
  added).

New generic primitives (none exist yet, none duplicate existing ones):
- `src/components/ui/textarea.tsx` — shadcn-style, matches `Input`'s
  existing visual language
- `src/components/form/select-field.tsx` — label+error+hint wrapper
  around the existing Radix-based `Select`, same contract as
  `TextField` (`label`, `error`, `hint`, `id`)
- `src/components/shared/file-upload.tsx` — drag/click to upload, image
  preview, Replace/Remove, client-side type (PNG/JPG/JPEG/WebP) and size
  (5MB) validation, object-URL preview only (no upload in this phase);
  reusable later for e.g. profile avatar upload

Explicitly reused, not duplicated: `TextField`, `Button`, `Card` (+
sub-parts), `Select` (Radix primitives), `Label`, `cn()`.

Phone field: no general international `PhoneInput` component. Per spec
§8/§37, only India is in scope now, so it's a `TextField` with
`inputMode="tel"`, a fixed "+91" visual affordance, and an Indian
10-digit regex — avoiding a speculative multi-country component the
product doesn't need yet.

## 8. Validation

`src/features/onboarding/validation.ts` (zod, mirrors
`src/features/auth/validation.ts`):

- `facilityName`: trim, 2–100 chars, required
- `facilityType`: enum of `FacilityType`, default `MULTI_SPORT`
- `customFacilityType`: required + ≤50 chars, only when `facilityType ===
  "OTHER"` (via `.refine`)
- `businessPhone`: required, Indian 10-digit mobile, optional leading
  `+91`
- `address` (line1): required, ≤250 chars
- `area`: required, ≤100 chars
- `city`: required text field (no location-service lookup this phase)
- `state`: required, one of `INDIAN_STATES`
- `pinCode`: required, exactly 6 digits, numeric only
- `description`: optional, ≤500 chars

Validation fires on blur, then live once touched (`mode: "onTouched"`,
same UX as the existing signup form) — never before the user has
interacted with a field. Errors render through the existing `TextField`
error slot (icon + message + `aria-invalid`/`aria-describedby`), so no
new error-rendering pattern is introduced.

## 9. Continue / submit flow

1. `handleSubmit` runs zod validation; invalid → inline errors, no
   submission.
2. Button enters a `Saving…` disabled state (same `SubmitButton` pattern
   as `login-form.tsx`/`signup-form.tsx`, preventing duplicate clicks).
3. `MockFacilityService.saveFacility(...)` persists the record.
4. On success: `onboardingStore.completeFacilityDetails(facility)` sets
   `facilityDetailsCompleted = true`, `currentStep = 2`, appends `1` to
   `completedSteps`.
5. `router.push("/onboarding/sports")`.
6. On failure: a `FormMessage` shows "We couldn't save your facility
   details. Please try again." — no stack trace, no technical detail
   surfaced.

## 10. Testing

`src/features/onboarding/components/facility-details-form.test.tsx` (+
one file per section component where it earns its own suite), using the
existing `renderWithProviders`/harness/`routerMock` conventions:

- Required-field validation: name, type, phone, address, area, city,
  state, PIN
- Format validation: invalid phone, invalid PIN, name too short, "Other"
  requires custom type
- Behavior: save + restore across a remount (persistence), Continue
  navigates to `/onboarding/sports`, Back triggers the leave dialog only
  when dirty, logo preview + remove, description counter, auto-save
  status text, submit button disabled during save and until valid
- `resolveEntryRoute`/`useLogin` redirect branch: new test cases added
  to the existing `entry-route.test.ts` / `login-form.test.tsx` covering
  the onboarding-incomplete branch

Responsive behavior (320/375/390/430/768/1024/1280/1440/1920) is verified
manually via the `run` skill in a real browser, not asserted in Vitest/jsdom.

## 11. Risks / open notes

- The richer `Facility` type intentionally exceeds today's `facilities`
  table columns (§6) — flagged in code, not fixed here.
- `leave-confirm-dialog` only covers the in-app Back button, not tab
  close — accepted tradeoff, autosave covers the data-loss risk.
- No location/PIN-code lookup service yet; `city`/`state`/`pinCode` are
  independent plain fields today, structured so a lookup service can be
  layered in later without a shape change.