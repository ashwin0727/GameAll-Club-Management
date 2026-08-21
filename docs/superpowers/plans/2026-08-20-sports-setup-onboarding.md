# Sports Setup Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the "Sports Setup" onboarding page — reached after Facility Details — where the owner selects which sports their facility operates, saved as a `facilityId -> sportId` relationship, then hands off to a Courts placeholder.

**Architecture:** A new `src/features/sports-setup/` feature module (types, validation, mock service, section components, the integration form) plus a new `src/app/onboarding/courts/` placeholder route and a real `src/app/onboarding/sports/` page (replacing its current placeholder). The existing `useOnboardingStore` (zustand) is extended, not duplicated, with sports-selection state — matching how it already holds `facilityDetailsCompleted`/`draft`. `MockSportService` mirrors `MockFacilityService`'s exact seam so a future `SupabaseSportService` swaps in without UI changes.

**Tech Stack:** Next.js App Router, React 19, TypeScript, Tailwind CSS, zod, zustand (+ `persist`), Vitest + Testing Library — no new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-20-sports-setup-onboarding-design.md`

## Global Constraints

- Reuse the existing design system exactly: same tokens, `Card`/`Button`/`TextField`/`SubmitButton`/`FormMessage`/`SaveStatus`/`ErrorState`/`Skeleton` — no new theme, no duplicate primitives (spec §10).
- Sports are attached to `facilityId`, never to `userId` — this is the core business rule (spec §1, §13).
- `Sport` (global catalog) and `FacilitySport` (relationship) stay separate models; the one approved exception is `FacilitySport.customSportName?`, used only when `sportId === "sport_other"` (spec §3, §15 of the source request).
- Facility-type preselection (spec §12) applies only on first-ever visit (no saved `FacilitySport` rows yet) and never overrides an existing saved selection.
- At least one sport must be selected to continue; Other requires a trimmed 2–50 character name (spec §10–§11 of the source request).
- Auto-save is debounced ~400ms — do not persist on every click immediately (spec §25 of the source request, same lesson already applied in `FacilityDetailsForm`).
- No secrets, tokens, or passwords ever touch localStorage — only sport selections (spec §17 of the source request).
- This repository has no Flutter project — web (Next.js) only.
- Do not touch `supabase/migrations` or any DB schema.
- `MockFacilityService`/`MockSportService` are localStorage-backed and cannot run in a server component — facility/sport loading happens client-side, guarded behind a loading state, not `next/navigation`'s server `redirect()`.
- Every new test file follows the existing harness conventions: `renderWithProviders`, `routerMock`, `installFakeAuthService` from `@/test/harness` and `@/test/router-mock`.

---

## Task 1: Sport/FacilitySport types and constants

**Files:**
- Create: `src/features/sports-setup/types.ts`
- Create: `src/features/sports-setup/constants.ts`
- Test: `src/features/sports-setup/constants.test.ts`

**Interfaces:**
- Produces: `Sport`, `FacilitySport`, `FacilitySportInput` types; `OTHER_SPORT_ID`, `AVAILABLE_SPORTS: Sport[]`, `SINGLE_SPORT_TYPE_MAP: Partial<Record<FacilityType, string>>` — imported by every later task in this plan.

- [ ] **Step 1: Write the failing test**

```ts
// src/features/sports-setup/constants.test.ts
import { describe, expect, it } from "vitest";
import { AVAILABLE_SPORTS, OTHER_SPORT_ID, SINGLE_SPORT_TYPE_MAP } from "@/features/sports-setup/constants";

describe("sports-setup constants", () => {
  it("lists exactly six sports, each active, ending with Other", () => {
    expect(AVAILABLE_SPORTS).toHaveLength(6);
    expect(AVAILABLE_SPORTS.every((sport) => sport.isActive)).toBe(true);
    expect(AVAILABLE_SPORTS[AVAILABLE_SPORTS.length - 1].id).toBe(OTHER_SPORT_ID);
  });

  it("gives every sport a unique id and a non-empty icon/description", () => {
    const ids = AVAILABLE_SPORTS.map((sport) => sport.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const sport of AVAILABLE_SPORTS) {
      expect(sport.icon.length).toBeGreaterThan(0);
      expect(sport.description.length).toBeGreaterThan(0);
    }
  });

  it("maps only the five single-sport facility types to a preselected sport", () => {
    expect(SINGLE_SPORT_TYPE_MAP.BADMINTON).toBe("sport_badminton");
    expect(SINGLE_SPORT_TYPE_MAP.PICKLEBALL).toBe("sport_pickleball");
    expect(SINGLE_SPORT_TYPE_MAP.CRICKET).toBe("sport_cricket");
    expect(SINGLE_SPORT_TYPE_MAP.FOOTBALL).toBe("sport_football");
    expect(SINGLE_SPORT_TYPE_MAP.TENNIS).toBe("sport_tennis");
    expect(SINGLE_SPORT_TYPE_MAP.MULTI_SPORT).toBeUndefined();
    expect(SINGLE_SPORT_TYPE_MAP.OTHER).toBeUndefined();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/sports-setup/constants.test.ts`
Expected: FAIL — `Cannot find module '@/features/sports-setup/constants'`

- [ ] **Step 3: Write `types.ts`**

```ts
// src/features/sports-setup/types.ts
/** The global sport catalog — never facility-specific. */
export interface Sport {
  id: string;
  name: string;
  code: string;
  /** A single emoji character, rendered directly by SportCard. */
  icon: string;
  description: string;
  isActive: boolean;
}

/**
 * "This facility operates this sport." The only place facilityId and
 * sportId meet — kept deliberately separate from Sport (which stays
 * global). customSportName is the one facility-specific attribute this
 * relationship needs (only set when sportId is the Other sport), not a
 * merge of the two models.
 */
export interface FacilitySport {
  id: string;
  facilityId: string;
  sportId: string;
  enabled: boolean;
  customSportName?: string;
  createdAt: string;
  updatedAt: string;
}

export type FacilitySportInput = Omit<FacilitySport, "id" | "createdAt" | "updatedAt">;
```

- [ ] **Step 4: Write `constants.ts`**

```ts
// src/features/sports-setup/constants.ts
import type { FacilityType } from "@/features/onboarding/types";
import type { Sport } from "@/features/sports-setup/types";

export const OTHER_SPORT_ID = "sport_other";

export const AVAILABLE_SPORTS: Sport[] = [
  {
    id: "sport_badminton",
    name: "Badminton",
    code: "BADMINTON",
    icon: "🏸",
    description: "Indoor racket sport",
    isActive: true,
  },
  {
    id: "sport_pickleball",
    name: "Pickleball",
    code: "PICKLEBALL",
    icon: "🏓",
    description: "Court-based paddle sport",
    isActive: true,
  },
  {
    id: "sport_cricket",
    name: "Cricket",
    code: "CRICKET",
    icon: "🏏",
    description: "Bat-and-ball team sport",
    isActive: true,
  },
  {
    id: "sport_football",
    name: "Football",
    code: "FOOTBALL",
    icon: "⚽",
    description: "Outdoor team sport",
    isActive: true,
  },
  {
    id: "sport_tennis",
    name: "Tennis",
    code: "TENNIS",
    icon: "🎾",
    description: "Racket sport on a court",
    isActive: true,
  },
  {
    id: OTHER_SPORT_ID,
    name: "Other",
    code: "OTHER",
    icon: "➕",
    description: "A sport not listed here",
    isActive: true,
  },
];

/**
 * Only the five single-sport facility types preselect a matching sport on
 * first visit. MULTI_SPORT and OTHER intentionally have no entry — nothing
 * is force-preselected for them.
 */
export const SINGLE_SPORT_TYPE_MAP: Partial<Record<FacilityType, string>> = {
  BADMINTON: "sport_badminton",
  PICKLEBALL: "sport_pickleball",
  CRICKET: "sport_cricket",
  FOOTBALL: "sport_football",
  TENNIS: "sport_tennis",
};
```

- [ ] **Step 5: Run test to verify it passes**

Run: `npx vitest run src/features/sports-setup/constants.test.ts`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add src/features/sports-setup/types.ts src/features/sports-setup/constants.ts src/features/sports-setup/constants.test.ts
git commit -m "feat(sports-setup): add sport and facility-sport types and constants"
```

---

## Task 2: Other-sport-name validation schema

**Files:**
- Create: `src/features/sports-setup/validation.ts`
- Test: `src/features/sports-setup/validation.test.ts`

**Interfaces:**
- Produces: `otherSportNameSchema` (zod) — consumed by Task 9 (the form's submit validation).

- [ ] **Step 1: Write the failing test**

```ts
// src/features/sports-setup/validation.test.ts
import { describe, expect, it } from "vitest";
import { otherSportNameSchema } from "@/features/sports-setup/validation";

describe("otherSportNameSchema", () => {
  it("accepts a valid trimmed name", () => {
    expect(otherSportNameSchema.safeParse("Basketball").success).toBe(true);
  });

  it("trims surrounding whitespace before validating length", () => {
    const result = otherSportNameSchema.safeParse("  Go  ");
    expect(result.success).toBe(true);
    if (result.success) expect(result.data).toBe("Go");
  });

  it("rejects an empty name", () => {
    expect(otherSportNameSchema.safeParse("").success).toBe(false);
  });

  it("rejects a whitespace-only name", () => {
    expect(otherSportNameSchema.safeParse("   ").success).toBe(false);
  });

  it("rejects a name under 2 characters", () => {
    expect(otherSportNameSchema.safeParse("A").success).toBe(false);
  });

  it("rejects a name over 50 characters", () => {
    expect(otherSportNameSchema.safeParse("a".repeat(51)).success).toBe(false);
  });

  it("accepts a name at exactly 50 characters", () => {
    expect(otherSportNameSchema.safeParse("a".repeat(50)).success).toBe(true);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/sports-setup/validation.test.ts`
Expected: FAIL — `Cannot find module '@/features/sports-setup/validation'`

- [ ] **Step 3: Write the implementation**

```ts
// src/features/sports-setup/validation.ts
import { z } from "zod";

export const otherSportNameSchema = z
  .string()
  .trim()
  .min(2, "Sport name must be at least 2 characters")
  .max(50, "Keep this under 50 characters");
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/sports-setup/validation.test.ts`
Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/sports-setup/validation.ts src/features/sports-setup/validation.test.ts
git commit -m "feat(sports-setup): add other-sport-name validation schema"
```

---

## Task 3: MockSportService

**Files:**
- Create: `src/features/sports-setup/services/mock-sport-service.ts`
- Test: `src/features/sports-setup/services/mock-sport-service.test.ts`

**Interfaces:**
- Consumes: `Sport`, `FacilitySport`, `FacilitySportInput` (Task 1); `AVAILABLE_SPORTS` (Task 1)
- Produces: `MockSportService.getAvailableSports(): Promise<Sport[]>`, `.getFacilitySports(facilityId): Promise<FacilitySport[]>`, `.saveFacilitySports(facilityId, sports): Promise<FacilitySport[]>`, `.updateFacilitySports(facilityId, sports): Promise<FacilitySport[]>` — consumed by Task 9.

- [ ] **Step 1: Write the failing test**

```ts
// src/features/sports-setup/services/mock-sport-service.test.ts
import { beforeEach, describe, expect, it } from "vitest";
import { MockSportService } from "@/features/sports-setup/services/mock-sport-service";
import { OTHER_SPORT_ID } from "@/features/sports-setup/constants";
import type { FacilitySportInput } from "@/features/sports-setup/types";

const FACILITY_A = "facility_a";
const FACILITY_B = "facility_b";

function rows(facilityId: string, sportIds: string[]): FacilitySportInput[] {
  return sportIds.map((sportId) => ({ facilityId, sportId, enabled: true }));
}

describe("MockSportService", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it("returns all six active sports", async () => {
    const sports = await MockSportService.getAvailableSports();
    expect(sports).toHaveLength(6);
    expect(sports.every((sport) => sport.isActive)).toBe(true);
  });

  it("returns an empty array for a facility with no saved sports", async () => {
    expect(await MockSportService.getFacilitySports(FACILITY_A)).toEqual([]);
  });

  it("saves sports for a facility and assigns ids and timestamps", async () => {
    const saved = await MockSportService.saveFacilitySports(
      FACILITY_A,
      rows(FACILITY_A, ["sport_badminton", "sport_pickleball"]),
    );

    expect(saved).toHaveLength(2);
    for (const row of saved) {
      expect(row.id).toBeTruthy();
      expect(row.createdAt).toBeTruthy();
      expect(row.facilityId).toBe(FACILITY_A);
    }
  });

  it("retrieves saved sports scoped to the correct facility only", async () => {
    await MockSportService.saveFacilitySports(FACILITY_A, rows(FACILITY_A, ["sport_badminton"]));
    await MockSportService.saveFacilitySports(FACILITY_B, rows(FACILITY_B, ["sport_cricket"]));

    const aSports = await MockSportService.getFacilitySports(FACILITY_A);
    const bSports = await MockSportService.getFacilitySports(FACILITY_B);

    expect(aSports.map((row) => row.sportId)).toEqual(["sport_badminton"]);
    expect(bSports.map((row) => row.sportId)).toEqual(["sport_cricket"]);
  });

  it("replaces a facility's sports on re-save, removing deselected ones", async () => {
    await MockSportService.saveFacilitySports(
      FACILITY_A,
      rows(FACILITY_A, ["sport_badminton", "sport_pickleball", "sport_cricket"]),
    );

    const updated = await MockSportService.saveFacilitySports(FACILITY_A, rows(FACILITY_A, ["sport_badminton"]));

    expect(updated.map((row) => row.sportId)).toEqual(["sport_badminton"]);
    const reread = await MockSportService.getFacilitySports(FACILITY_A);
    expect(reread.map((row) => row.sportId)).toEqual(["sport_badminton"]);
  });

  it("re-saving one facility's sports does not affect another facility's rows", async () => {
    await MockSportService.saveFacilitySports(FACILITY_A, rows(FACILITY_A, ["sport_badminton"]));
    await MockSportService.saveFacilitySports(FACILITY_B, rows(FACILITY_B, ["sport_cricket"]));

    await MockSportService.saveFacilitySports(FACILITY_A, rows(FACILITY_A, ["sport_tennis"]));

    const bSports = await MockSportService.getFacilitySports(FACILITY_B);
    expect(bSports.map((row) => row.sportId)).toEqual(["sport_cricket"]);
  });

  it("stores customSportName only on the Other row", async () => {
    const saved = await MockSportService.saveFacilitySports(FACILITY_A, [
      { facilityId: FACILITY_A, sportId: "sport_badminton", enabled: true },
      { facilityId: FACILITY_A, sportId: OTHER_SPORT_ID, enabled: true, customSportName: "Basketball" },
    ]);

    const other = saved.find((row) => row.sportId === OTHER_SPORT_ID);
    const badminton = saved.find((row) => row.sportId === "sport_badminton");
    expect(other?.customSportName).toBe("Basketball");
    expect(badminton?.customSportName).toBeUndefined();
  });

  it("updateFacilitySports also replaces the full set", async () => {
    await MockSportService.saveFacilitySports(FACILITY_A, rows(FACILITY_A, ["sport_badminton"]));
    const updated = await MockSportService.updateFacilitySports(
      FACILITY_A,
      rows(FACILITY_A, ["sport_badminton", "sport_football"]),
    );

    expect(updated.map((row) => row.sportId).sort()).toEqual(["sport_badminton", "sport_football"]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/sports-setup/services/mock-sport-service.test.ts`
Expected: FAIL — `Cannot find module '@/features/sports-setup/services/mock-sport-service'`

- [ ] **Step 3: Write the implementation**

```ts
// src/features/sports-setup/services/mock-sport-service.ts
import { AVAILABLE_SPORTS } from "@/features/sports-setup/constants";
import type { FacilitySport, FacilitySportInput, Sport } from "@/features/sports-setup/types";

const STORAGE_KEY = "turf.facility-sports.mock.v1";

function readAll(): FacilitySport[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as FacilitySport[]) : [];
  } catch {
    return [];
  }
}

function writeAll(rows: FacilitySport[]): void {
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(rows));
}

function replaceForFacility(facilityId: string, inputs: FacilitySportInput[]): FacilitySport[] {
  const now = new Date().toISOString();
  const newRows: FacilitySport[] = inputs.map((input) => ({
    ...input,
    id: crypto.randomUUID(),
    createdAt: now,
    updatedAt: now,
  }));

  const others = readAll().filter((row) => row.facilityId !== facilityId);
  writeAll([...others, ...newRows]);
  return newRows;
}

export const MockSportService = {
  async getAvailableSports(): Promise<Sport[]> {
    return AVAILABLE_SPORTS.filter((sport) => sport.isActive);
  },

  async getFacilitySports(facilityId: string): Promise<FacilitySport[]> {
    return readAll().filter((row) => row.facilityId === facilityId);
  },

  async saveFacilitySports(facilityId: string, sports: FacilitySportInput[]): Promise<FacilitySport[]> {
    return replaceForFacility(facilityId, sports);
  },

  async updateFacilitySports(facilityId: string, sports: FacilitySportInput[]): Promise<FacilitySport[]> {
    return replaceForFacility(facilityId, sports);
  },
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/sports-setup/services/mock-sport-service.test.ts`
Expected: PASS (8 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/sports-setup/services/mock-sport-service.ts src/features/sports-setup/services/mock-sport-service.test.ts
git commit -m "feat(sports-setup): add mock facility-sports persistence service"
```

---

## Task 4: Extend useOnboardingStore with sports state

**Files:**
- Modify: `src/features/onboarding/state/onboarding-store.ts`
- Modify: `src/features/onboarding/state/onboarding-store.test.ts`

**Interfaces:**
- Produces: new store fields `selectedSportIds: string[]`, `otherSportName: string`, new actions `setSelectedSportIds(ids)`, `setOtherSportName(name)`, `completeSports()` — consumed by Task 9. Existing fields/actions (`draft`, `setDraft`, `completeFacilityDetails`, `facility`, `reset`) are unchanged in name and behavior.

- [ ] **Step 1: Update the test file first (add new cases, keep all 5 existing ones)**

```ts
// src/features/onboarding/state/onboarding-store.test.ts
import { beforeEach, describe, expect, it } from "vitest";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";

const sampleFacility = {
  id: "facility-1",
  ownerId: "owner-1",
  name: "GameAll Sports Arena",
  type: "MULTI_SPORT" as const,
  businessEmail: "owner@yourturf.com",
  businessPhone: "9876543210",
  address: {
    line1: "123 Anna Salai",
    area: "Ambattur",
    city: "Chennai",
    state: "Tamil Nadu",
    country: "India" as const,
    pinCode: "600053",
  },
  status: "ACTIVE" as const,
  createdAt: "2026-08-20T00:00:00.000Z",
  updatedAt: "2026-08-20T00:00:00.000Z",
};

describe("useOnboardingStore", () => {
  beforeEach(() => {
    window.localStorage.clear();
    useOnboardingStore.getState().reset();
  });

  it("starts on step 1 with nothing completed", () => {
    const state = useOnboardingStore.getState();
    expect(state.currentStep).toBe(1);
    expect(state.completedSteps).toEqual([]);
    expect(state.facilityDetailsCompleted).toBe(false);
  });

  it("merges partial draft updates without dropping other fields", () => {
    useOnboardingStore.getState().setDraft({ facilityName: "GameAll Sports Arena" });
    useOnboardingStore.getState().setDraft({ city: "Chennai" });

    const { draft } = useOnboardingStore.getState();
    expect(draft.facilityName).toBe("GameAll Sports Arena");
    expect(draft.city).toBe("Chennai");
  });

  it("marks facility details complete and advances to step 2", () => {
    useOnboardingStore.getState().completeFacilityDetails(sampleFacility);

    const state = useOnboardingStore.getState();
    expect(state.facilityDetailsCompleted).toBe(true);
    expect(state.currentStep).toBe(2);
    expect(state.completedSteps).toEqual([1]);
  });

  it("persists the draft to localStorage", () => {
    useOnboardingStore.getState().setDraft({ facilityName: "GameAll Sports Arena" });

    const raw = window.localStorage.getItem("turf.onboarding.v1");
    expect(raw).toContain("GameAll Sports Arena");
  });

  it("never persists a password or token field", () => {
    useOnboardingStore.getState().setDraft({ facilityName: "GameAll Sports Arena" });

    const raw = window.localStorage.getItem("turf.onboarding.v1") ?? "";
    expect(raw).not.toMatch(/password|token/i);
  });

  it("starts with no sports selected and an empty other-sport name", () => {
    const state = useOnboardingStore.getState();
    expect(state.selectedSportIds).toEqual([]);
    expect(state.otherSportName).toBe("");
  });

  it("sets selected sport ids and other-sport name independently", () => {
    useOnboardingStore.getState().setSelectedSportIds(["sport_badminton", "sport_pickleball"]);
    useOnboardingStore.getState().setOtherSportName("Basketball");

    const state = useOnboardingStore.getState();
    expect(state.selectedSportIds).toEqual(["sport_badminton", "sport_pickleball"]);
    expect(state.otherSportName).toBe("Basketball");
  });

  it("marks sports complete and advances to step 3", () => {
    useOnboardingStore.getState().completeFacilityDetails(sampleFacility);
    useOnboardingStore.getState().setSelectedSportIds(["sport_badminton"]);
    useOnboardingStore.getState().completeSports();

    const state = useOnboardingStore.getState();
    expect(state.sportsCompleted).toBe(true);
    expect(state.currentStep).toBe(3);
    expect(state.completedSteps).toEqual([1, 2]);
  });

  it("reset clears sports selection state along with everything else", () => {
    useOnboardingStore.getState().setSelectedSportIds(["sport_badminton"]);
    useOnboardingStore.getState().setOtherSportName("Basketball");
    useOnboardingStore.getState().reset();

    const state = useOnboardingStore.getState();
    expect(state.selectedSportIds).toEqual([]);
    expect(state.otherSportName).toBe("");
  });
});
```

- [ ] **Step 2: Run test to verify the new cases fail**

Run: `npx vitest run src/features/onboarding/state/onboarding-store.test.ts`
Expected: the 5 pre-existing tests still PASS; the 4 new tests FAIL (`selectedSportIds`/`otherSportName`/`setSelectedSportIds`/`setOtherSportName`/`completeSports` don't exist yet).

- [ ] **Step 3: Update `onboarding-store.ts`**

```ts
// src/features/onboarding/state/onboarding-store.ts
import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { Facility } from "@/features/onboarding/types";
import type { FacilityDetailsInput } from "@/features/onboarding/validation";

export type FacilityDraft = Partial<FacilityDetailsInput>;

interface OnboardingState {
  currentStep: number;
  completedSteps: number[];
  facilityDetailsCompleted: boolean;
  sportsCompleted: boolean;
  courtsCompleted: boolean;
  operatingHoursCompleted: boolean;
  pricingCompleted: boolean;
  facility: Facility | null;
  draft: FacilityDraft;
  selectedSportIds: string[];
  otherSportName: string;
  setDraft: (patch: FacilityDraft) => void;
  completeFacilityDetails: (facility: Facility) => void;
  setSelectedSportIds: (ids: string[]) => void;
  setOtherSportName: (name: string) => void;
  completeSports: () => void;
  reset: () => void;
}

const INITIAL_STATE = {
  currentStep: 1,
  completedSteps: [] as number[],
  facilityDetailsCompleted: false,
  sportsCompleted: false,
  courtsCompleted: false,
  operatingHoursCompleted: false,
  pricingCompleted: false,
  facility: null as Facility | null,
  draft: {} as FacilityDraft,
  selectedSportIds: [] as string[],
  otherSportName: "",
};

export const useOnboardingStore = create<OnboardingState>()(
  persist(
    (set) => ({
      ...INITIAL_STATE,
      setDraft: (patch) => set((s) => ({ draft: { ...s.draft, ...patch } })),
      completeFacilityDetails: (facility) =>
        set((s) => ({
          facility,
          facilityDetailsCompleted: true,
          currentStep: 2,
          completedSteps: s.completedSteps.includes(1) ? s.completedSteps : [...s.completedSteps, 1],
        })),
      setSelectedSportIds: (ids) => set({ selectedSportIds: ids }),
      setOtherSportName: (name) => set({ otherSportName: name }),
      completeSports: () =>
        set((s) => ({
          sportsCompleted: true,
          currentStep: 3,
          completedSteps: s.completedSteps.includes(2) ? s.completedSteps : [...s.completedSteps, 2],
        })),
      reset: () => set({ ...INITIAL_STATE }),
    }),
    { name: "turf.onboarding.v1", skipHydration: true },
  ),
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/onboarding/state/onboarding-store.test.ts`
Expected: PASS (9 tests)

- [ ] **Step 5: Run the full suite to confirm nothing else depending on this store broke**

Run: `npx vitest run`
Expected: every file passes (the onboarding layout and `FacilityDetailsForm` both read this store — confirm neither regressed).

- [ ] **Step 6: Commit**

```bash
git add src/features/onboarding/state/onboarding-store.ts src/features/onboarding/state/onboarding-store.test.ts
git commit -m "feat(sports-setup): extend onboarding store with sports selection state"
```

---

## Task 5: FacilityContextCard

**Files:**
- Create: `src/features/sports-setup/components/facility-context-card.tsx`
- Test: `src/features/sports-setup/components/facility-context-card.test.tsx`

**Interfaces:**
- Consumes: `Card` (`@/components/ui/card`, existing); `FACILITY_TYPE_OPTIONS` (`@/features/onboarding/constants`, existing); `Facility` (Task 1 of the Facility Details plan, already in `@/features/onboarding/types`)
- Produces: `<FacilityContextCard facility={Facility} />` — consumed by Task 9.

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/sports-setup/components/facility-context-card.test.tsx
import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { FacilityContextCard } from "@/features/sports-setup/components/facility-context-card";
import type { Facility } from "@/features/onboarding/types";

const FACILITY: Facility = {
  id: "facility-1",
  ownerId: "owner-1",
  name: "GameAll Sports Arena",
  type: "MULTI_SPORT",
  businessEmail: "owner@yourturf.com",
  businessPhone: "9876543210",
  address: {
    line1: "123 Anna Salai",
    area: "Ambattur",
    city: "Chennai",
    state: "Tamil Nadu",
    country: "India",
    pinCode: "600053",
  },
  status: "ACTIVE",
  createdAt: "2026-08-20T00:00:00.000Z",
  updatedAt: "2026-08-20T00:00:00.000Z",
};

describe("FacilityContextCard", () => {
  it("shows the facility name and city", () => {
    render(<FacilityContextCard facility={FACILITY} />);
    expect(screen.getByText("GameAll Sports Arena")).toBeInTheDocument();
    expect(screen.getByText("Chennai")).toBeInTheDocument();
  });

  it("shows a human-readable facility type label, not the raw enum value", () => {
    render(<FacilityContextCard facility={FACILITY} />);
    expect(screen.getByText(/Multi-Sport Facility/)).toBeInTheDocument();
    expect(screen.queryByText("MULTI_SPORT")).not.toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/sports-setup/components/facility-context-card.test.tsx`
Expected: FAIL — `Cannot find module '@/features/sports-setup/components/facility-context-card'`

- [ ] **Step 3: Write the implementation**

```tsx
// src/features/sports-setup/components/facility-context-card.tsx
import { Building2 } from "lucide-react";
import { Card } from "@/components/ui/card";
import { FACILITY_TYPE_OPTIONS } from "@/features/onboarding/constants";
import type { Facility } from "@/features/onboarding/types";

export function FacilityContextCard({ facility }: { facility: Facility }) {
  const typeLabel =
    FACILITY_TYPE_OPTIONS.find((option) => option.value === facility.type)?.label ?? facility.type;

  return (
    <Card className="p-5">
      <div className="flex items-center gap-4">
        <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
          <Building2 className="h-6 w-6" aria-hidden="true" />
        </div>
        <div className="min-w-0">
          <p className="truncate text-base font-semibold text-foreground">{facility.name}</p>
          <p className="truncate text-sm text-muted-foreground">{facility.address.city}</p>
          <p className="text-xs text-muted-foreground">Facility Type: {typeLabel}</p>
        </div>
      </div>
    </Card>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/sports-setup/components/facility-context-card.test.tsx`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/sports-setup/components/facility-context-card.tsx src/features/sports-setup/components/facility-context-card.test.tsx
git commit -m "feat(sports-setup): add facility context card"
```

---

## Task 6: SportCard and SportGrid

**Files:**
- Create: `src/features/sports-setup/components/sport-card.tsx`
- Create: `src/features/sports-setup/components/sport-grid.tsx`
- Test: `src/features/sports-setup/components/sport-grid.test.tsx`

**Interfaces:**
- Consumes: `Sport` (Task 1)
- Produces: `<SportCard sport selected onToggle />`, `<SportGrid sports selectedSportIds onToggle />` — consumed by Task 9.

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/sports-setup/components/sport-grid.test.tsx
import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SportGrid } from "@/features/sports-setup/components/sport-grid";
import { AVAILABLE_SPORTS } from "@/features/sports-setup/constants";

describe("SportGrid / SportCard", () => {
  it("renders every sport as a card with its name and description", () => {
    render(<SportGrid sports={AVAILABLE_SPORTS} selectedSportIds={[]} onToggle={vi.fn()} />);

    for (const sport of AVAILABLE_SPORTS) {
      expect(screen.getByText(sport.name)).toBeInTheDocument();
      expect(screen.getByText(sport.description)).toBeInTheDocument();
    }
  });

  it("marks selected cards with aria-checked=true and unselected ones false", () => {
    render(
      <SportGrid
        sports={AVAILABLE_SPORTS}
        selectedSportIds={["sport_badminton"]}
        onToggle={vi.fn()}
      />,
    );

    expect(screen.getByRole("checkbox", { name: /Badminton/ })).toHaveAttribute("aria-checked", "true");
    expect(screen.getByRole("checkbox", { name: /Cricket/ })).toHaveAttribute("aria-checked", "false");
  });

  it("toggles a sport when the whole card is clicked, not just an inner checkbox", async () => {
    const user = userEvent.setup();
    const onToggle = vi.fn();
    render(<SportGrid sports={AVAILABLE_SPORTS} selectedSportIds={[]} onToggle={onToggle} />);

    await user.click(screen.getByText("Indoor racket sport"));

    expect(onToggle).toHaveBeenCalledWith("sport_badminton");
  });

  it("is keyboard-operable via Enter on a focused card", async () => {
    const user = userEvent.setup();
    const onToggle = vi.fn();
    render(<SportGrid sports={AVAILABLE_SPORTS} selectedSportIds={[]} onToggle={onToggle} />);

    screen.getByRole("checkbox", { name: /Tennis/ }).focus();
    await user.keyboard("{Enter}");

    expect(onToggle).toHaveBeenCalledWith("sport_tennis");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/sports-setup/components/sport-grid.test.tsx`
Expected: FAIL — `Cannot find module '@/features/sports-setup/components/sport-grid'`

- [ ] **Step 3: Write `sport-card.tsx`**

```tsx
// src/features/sports-setup/components/sport-card.tsx
"use client";

import { Check } from "lucide-react";
import { cn } from "@/lib/utils";
import type { Sport } from "@/features/sports-setup/types";

export interface SportCardProps {
  sport: Sport;
  selected: boolean;
  onToggle: (sportId: string) => void;
}

/**
 * The entire card is one button — per spec, touching anywhere inside
 * toggles selection, never just a small checkbox. min-h-12 (48px) meets
 * the "prefer 48px+" touch-target guidance.
 */
export function SportCard({ sport, selected, onToggle }: SportCardProps) {
  return (
    <button
      type="button"
      role="checkbox"
      aria-checked={selected}
      aria-label={`${sport.name} — ${sport.description}`}
      onClick={() => onToggle(sport.id)}
      className={cn(
        "flex min-h-12 w-full items-center gap-3 rounded-xl border p-4 text-left transition-colors duration-150",
        selected ? "border-primary bg-primary/5" : "border-border bg-card hover:border-muted-foreground/40",
      )}
    >
      <span className="text-2xl" aria-hidden="true">
        {sport.icon}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-sm font-semibold text-foreground">{sport.name}</span>
        <span className="block truncate text-xs text-muted-foreground">{sport.description}</span>
      </span>
      {selected && (
        <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground">
          <Check className="h-3.5 w-3.5" aria-hidden="true" />
        </span>
      )}
    </button>
  );
}
```

- [ ] **Step 4: Write `sport-grid.tsx`**

```tsx
// src/features/sports-setup/components/sport-grid.tsx
import { SportCard } from "@/features/sports-setup/components/sport-card";
import type { Sport } from "@/features/sports-setup/types";

export interface SportGridProps {
  sports: Sport[];
  selectedSportIds: string[];
  onToggle: (sportId: string) => void;
}

export function SportGrid({ sports, selectedSportIds, onToggle }: SportGridProps) {
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {sports.map((sport) => (
        <SportCard
          key={sport.id}
          sport={sport}
          selected={selectedSportIds.includes(sport.id)}
          onToggle={onToggle}
        />
      ))}
    </div>
  );
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `npx vitest run src/features/sports-setup/components/sport-grid.test.tsx`
Expected: PASS (4 tests)

- [ ] **Step 6: Commit**

```bash
git add src/features/sports-setup/components/sport-card.tsx src/features/sports-setup/components/sport-grid.tsx src/features/sports-setup/components/sport-grid.test.tsx
git commit -m "feat(sports-setup): add SportCard and SportGrid"
```

---

## Task 7: OtherSportInput

**Files:**
- Create: `src/features/sports-setup/components/other-sport-input.tsx`
- Test: `src/features/sports-setup/components/other-sport-input.test.tsx`

**Interfaces:**
- Consumes: `TextField` (`@/features/auth/components/text-field`, existing, read-only)
- Produces: `<OtherSportInput value onChange error />` — consumed by Task 9.

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/sports-setup/components/other-sport-input.test.tsx
import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { OtherSportInput } from "@/features/sports-setup/components/other-sport-input";

describe("OtherSportInput", () => {
  it("renders the Sport Name label and current value", () => {
    render(<OtherSportInput value="Basketball" onChange={vi.fn()} />);
    expect(screen.getByLabelText("Sport Name")).toHaveValue("Basketball");
  });

  it("calls onChange as the user types", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(<OtherSportInput value="" onChange={onChange} />);

    await user.type(screen.getByLabelText("Sport Name"), "B");

    expect(onChange).toHaveBeenCalledWith("B");
  });

  it("shows an error message when provided", () => {
    render(<OtherSportInput value="" onChange={vi.fn()} error="Sport name must be at least 2 characters" />);
    expect(screen.getByText("Sport name must be at least 2 characters")).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/sports-setup/components/other-sport-input.test.tsx`
Expected: FAIL — `Cannot find module '@/features/sports-setup/components/other-sport-input'`

- [ ] **Step 3: Write the implementation**

```tsx
// src/features/sports-setup/components/other-sport-input.tsx
"use client";

import { TextField } from "@/features/auth/components/text-field";

export interface OtherSportInputProps {
  value: string;
  onChange: (value: string) => void;
  error?: string | null;
}

export function OtherSportInput({ value, onChange, error }: OtherSportInputProps) {
  return (
    <TextField
      id="other-sport-name"
      label="Sport Name"
      placeholder="e.g. Basketball"
      maxLength={50}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      error={error ?? undefined}
    />
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/sports-setup/components/other-sport-input.test.tsx`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/sports-setup/components/other-sport-input.tsx src/features/sports-setup/components/other-sport-input.test.tsx
git commit -m "feat(sports-setup): add OtherSportInput"
```

---

## Task 8: SelectedSportsSummary

**Files:**
- Create: `src/features/sports-setup/components/selected-sports-summary.tsx`
- Test: `src/features/sports-setup/components/selected-sports-summary.test.tsx`

**Interfaces:**
- Produces: `<SelectedSportsSummary count={number} />` — consumed by Task 9.

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/sports-setup/components/selected-sports-summary.test.tsx
import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { SelectedSportsSummary } from "@/features/sports-setup/components/selected-sports-summary";

describe("SelectedSportsSummary", () => {
  it("shows 'No sports selected' for zero", () => {
    render(<SelectedSportsSummary count={0} />);
    expect(screen.getByText("No sports selected")).toBeInTheDocument();
  });

  it("uses singular phrasing for exactly one", () => {
    render(<SelectedSportsSummary count={1} />);
    expect(screen.getByText("1 sport selected")).toBeInTheDocument();
  });

  it("uses plural phrasing for more than one", () => {
    render(<SelectedSportsSummary count={3} />);
    expect(screen.getByText("3 sports selected")).toBeInTheDocument();
  });

  it("counts all six when everything including Other is selected", () => {
    render(<SelectedSportsSummary count={6} />);
    expect(screen.getByText("6 sports selected")).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/sports-setup/components/selected-sports-summary.test.tsx`
Expected: FAIL — `Cannot find module '@/features/sports-setup/components/selected-sports-summary'`

- [ ] **Step 3: Write the implementation**

```tsx
// src/features/sports-setup/components/selected-sports-summary.tsx
export function SelectedSportsSummary({ count }: { count: number }) {
  const label = count === 0 ? "No sports selected" : count === 1 ? "1 sport selected" : `${count} sports selected`;

  return (
    <p className="text-sm text-muted-foreground" role="status">
      {label}
    </p>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/sports-setup/components/selected-sports-summary.test.tsx`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/sports-setup/components/selected-sports-summary.tsx src/features/sports-setup/components/selected-sports-summary.test.tsx
git commit -m "feat(sports-setup): add SelectedSportsSummary"
```

---

## Task 9: SportsSetupForm (integration)

**Files:**
- Create: `src/features/sports-setup/components/sports-setup-form.tsx`
- Test: `src/features/sports-setup/components/sports-setup-form.test.tsx`

**Interfaces:**
- Consumes: `FacilityContextCard` (Task 5); `SportGrid` (Task 6); `OtherSportInput` (Task 7); `SelectedSportsSummary` (Task 8); `otherSportNameSchema` (Task 2); `MockSportService` (Task 3); `AVAILABLE_SPORTS`, `OTHER_SPORT_ID`, `SINGLE_SPORT_TYPE_MAP` (Task 1); `useOnboardingStore`'s `setSelectedSportIds`/`setOtherSportName`/`completeSports` (Task 4); `MockFacilityService` (`@/features/onboarding/services/mock-facility-service`, existing); `useCurrentUser` (`@/features/auth/hooks/use-auth`, existing); `SaveStatus`, `Skeleton`, `ErrorState`, `SubmitButton`, `FormMessage` (all existing, read-only)
- Produces: `<SportsSetupForm />` — consumed by Task 10 (the page).

This is the integration point: loads the facility (client-side, since the mock services are localStorage-backed), loads/preselects existing sport selections, manages selection state, auto-saves the draft, and on Continue saves the `FacilitySport` rows and navigates.

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/sports-setup/components/sports-setup-form.test.tsx
import { beforeEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SportsSetupForm } from "@/features/sports-setup/components/sports-setup-form";
import { MockFacilityService } from "@/features/onboarding/services/mock-facility-service";
import { MockSportService } from "@/features/sports-setup/services/mock-sport-service";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import { installFakeAuthService, renderWithProviders } from "@/test/harness";
import { routerMock } from "@/test/router-mock";

const FAKE_USER = {
  id: "owner-1",
  name: "Uma Shankar",
  email: "owner@yourturf.com",
  emailVerified: true,
  onboardingCompleted: false,
};

function installAuth() {
  return installFakeAuthService({ getCurrentUser: vi.fn(async () => FAKE_USER) });
}

async function seedFacility(type: "MULTI_SPORT" | "BADMINTON" = "MULTI_SPORT") {
  return MockFacilityService.saveFacility({
    ownerId: FAKE_USER.id,
    name: "GameAll Sports Arena",
    type,
    businessEmail: FAKE_USER.email,
    businessPhone: "9876543210",
    address: {
      line1: "123 Anna Salai",
      area: "Ambattur",
      city: "Chennai",
      state: "Tamil Nadu",
      country: "India",
      pinCode: "600053",
    },
  });
}

describe("SportsSetupForm", () => {
  beforeEach(() => {
    window.localStorage.clear();
    useOnboardingStore.getState().reset();
  });

  it("redirects to /login when there is no signed-in user", async () => {
    installFakeAuthService({ getCurrentUser: vi.fn(async () => null) });
    renderWithProviders(<SportsSetupForm />);

    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/login"));
  });

  it("redirects to /onboarding/facility when the user has no facility yet", async () => {
    installAuth();
    renderWithProviders(<SportsSetupForm />);

    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/facility"));
  });

  it("shows the facility name once loaded", async () => {
    installAuth();
    await seedFacility();
    renderWithProviders(<SportsSetupForm />);

    expect(await screen.findByText("GameAll Sports Arena")).toBeInTheDocument();
  });

  it("preselects the matching sport for a single-sport facility type on first visit", async () => {
    installAuth();
    await seedFacility("BADMINTON");
    renderWithProviders(<SportsSetupForm />);

    await screen.findByText("GameAll Sports Arena");
    expect(screen.getByRole("checkbox", { name: /Badminton/ })).toHaveAttribute("aria-checked", "true");
  });

  it("keeps Continue disabled until at least one sport is selected", async () => {
    installAuth();
    await seedFacility();
    renderWithProviders(<SportsSetupForm />);

    await screen.findByText("GameAll Sports Arena");
    expect(screen.getByRole("button", { name: /Continue/ })).toBeDisabled();
  });

  it("allows selecting multiple sports and updates the summary count", async () => {
    const user = userEvent.setup();
    installAuth();
    await seedFacility();
    renderWithProviders(<SportsSetupForm />);

    await screen.findByText("GameAll Sports Arena");
    await user.click(screen.getByText("Indoor racket sport"));
    await user.click(screen.getByText("Court-based paddle sport"));

    expect(await screen.findByText("2 sports selected")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Continue/ })).toBeEnabled();
  });

  it("deselecting a sport removes it from the count", async () => {
    const user = userEvent.setup();
    installAuth();
    await seedFacility();
    renderWithProviders(<SportsSetupForm />);

    await screen.findByText("GameAll Sports Arena");
    await user.click(screen.getByText("Indoor racket sport"));
    expect(await screen.findByText("1 sport selected")).toBeInTheDocument();

    await user.click(screen.getByText("Indoor racket sport"));
    expect(await screen.findByText("No sports selected")).toBeInTheDocument();
  });

  it("shows the sport-name input only when Other is selected, and requires a valid name to continue", async () => {
    const user = userEvent.setup();
    installAuth();
    await seedFacility();
    renderWithProviders(<SportsSetupForm />);

    await screen.findByText("GameAll Sports Arena");
    expect(screen.queryByLabelText("Sport Name")).not.toBeInTheDocument();

    await user.click(screen.getByText("A sport not listed here"));
    expect(await screen.findByLabelText("Sport Name")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: /Continue/ }));
    expect(await screen.findByText("Sport name must be at least 2 characters")).toBeInTheDocument();
    expect(routerMock.push).not.toHaveBeenCalled();
  });

  it("saves the selected sports and navigates to the courts placeholder on submit", async () => {
    const user = userEvent.setup();
    installAuth();
    const facility = await seedFacility();
    renderWithProviders(<SportsSetupForm />);

    await screen.findByText("GameAll Sports Arena");
    await user.click(screen.getByText("Indoor racket sport"));
    await user.click(screen.getByText("Court-based paddle sport"));
    await user.click(screen.getByRole("button", { name: /Continue/ }));

    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/courts"));

    const saved = await MockSportService.getFacilitySports(facility.id);
    expect(saved.map((row) => row.sportId).sort()).toEqual(["sport_badminton", "sport_pickleball"]);
    expect(useOnboardingStore.getState().sportsCompleted).toBe(true);
  });

  it("restores a previously saved selection scoped to the correct facility", async () => {
    installAuth();
    const facility = await seedFacility();
    await MockSportService.saveFacilitySports(facility.id, [
      { facilityId: facility.id, sportId: "sport_cricket", enabled: true },
    ]);

    renderWithProviders(<SportsSetupForm />);

    await screen.findByText("GameAll Sports Arena");
    expect(screen.getByRole("checkbox", { name: /Cricket/ })).toHaveAttribute("aria-checked", "true");
    expect(screen.getByRole("checkbox", { name: /Badminton/ })).toHaveAttribute("aria-checked", "false");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/sports-setup/components/sports-setup-form.test.tsx`
Expected: FAIL — `Cannot find module '@/features/sports-setup/components/sports-setup-form'`

- [ ] **Step 3: Write the implementation**

```tsx
// src/features/sports-setup/components/sports-setup-form.tsx
"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { SubmitButton } from "@/features/auth/components/submit-button";
import { FormMessage } from "@/features/auth/components/form-message";
import { ErrorState } from "@/components/shared/error-state";
import { Skeleton } from "@/components/ui/skeleton";
import { MockFacilityService } from "@/features/onboarding/services/mock-facility-service";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import type { Facility } from "@/features/onboarding/types";
import { FacilityContextCard } from "@/features/sports-setup/components/facility-context-card";
import { SportGrid } from "@/features/sports-setup/components/sport-grid";
import { OtherSportInput } from "@/features/sports-setup/components/other-sport-input";
import { SelectedSportsSummary } from "@/features/sports-setup/components/selected-sports-summary";
import { SaveStatus } from "@/features/onboarding/components/save-status";
import { AVAILABLE_SPORTS, OTHER_SPORT_ID, SINGLE_SPORT_TYPE_MAP } from "@/features/sports-setup/constants";
import { MockSportService } from "@/features/sports-setup/services/mock-sport-service";
import { otherSportNameSchema } from "@/features/sports-setup/validation";

type LoadState = "loading" | "ready" | "forbidden";

export function SportsSetupForm() {
  const router = useRouter();
  const { data: user, isLoading: userLoading } = useCurrentUser();
  const setSelectedSportIdsInStore = useOnboardingStore((s) => s.setSelectedSportIds);
  const setOtherSportNameInStore = useOnboardingStore((s) => s.setOtherSportName);
  const completeSports = useOnboardingStore((s) => s.completeSports);

  const [facility, setFacility] = useState<Facility | null>(null);
  const [loadState, setLoadState] = useState<LoadState>("loading");
  const [selectedSportIds, setSelectedSportIds] = useState<string[]>([]);
  const [otherSportName, setOtherSportName] = useState("");
  const [otherNameError, setOtherNameError] = useState<string | null>(null);
  const [selectionError, setSelectionError] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  // Facility/sport loading: client-side only, since MockFacilityService and
  // MockSportService are localStorage-backed and cannot run on the server.
  useEffect(() => {
    if (userLoading) return;
    if (!user) {
      router.replace("/login");
      return;
    }

    let cancelled = false;

    (async () => {
      const loadedFacility = await MockFacilityService.getFacility(user.id);
      if (cancelled) return;
      if (!loadedFacility) {
        router.replace("/onboarding/facility");
        return;
      }
      // Guaranteed true by construction (the service already filters by
      // ownerId) — kept as an explicit check per spec rather than trusted
      // silently.
      if (loadedFacility.ownerId !== user.id) {
        setLoadState("forbidden");
        return;
      }

      const existing = await MockSportService.getFacilitySports(loadedFacility.id);
      if (cancelled) return;

      let initialIds = existing.map((row) => row.sportId);
      const initialOtherName = existing.find((row) => row.sportId === OTHER_SPORT_ID)?.customSportName ?? "";

      // Preselection only applies on a genuinely first-ever visit — never
      // overrides an existing saved selection.
      if (existing.length === 0) {
        const preselected = SINGLE_SPORT_TYPE_MAP[loadedFacility.type];
        if (preselected) initialIds = [preselected];
      }

      setFacility(loadedFacility);
      setSelectedSportIds(initialIds);
      setOtherSportName(initialOtherName);
      setSelectedSportIdsInStore(initialIds);
      setOtherSportNameInStore(initialOtherName);
      setLoadState("ready");
    })();

    return () => {
      cancelled = true;
    };
  }, [user, userLoading, router, setSelectedSportIdsInStore, setOtherSportNameInStore]);

  // Debounced auto-save of the draft selection — same ~400ms pattern as
  // FacilityDetailsForm, per spec: don't persist on every click immediately.
  useEffect(() => {
    if (loadState !== "ready") return;
    const timeout = setTimeout(() => {
      setSelectedSportIdsInStore(selectedSportIds);
      setOtherSportNameInStore(otherSportName);
    }, 400);
    return () => clearTimeout(timeout);
  }, [selectedSportIds, otherSportName, loadState, setSelectedSportIdsInStore, setOtherSportNameInStore]);

  function toggleSport(sportId: string) {
    setSelectionError(null);
    setSelectedSportIds((prev) => (prev.includes(sportId) ? prev.filter((id) => id !== sportId) : [...prev, sportId]));
  }

  async function handleContinue() {
    if (selectedSportIds.length === 0) {
      setSelectionError("Select at least one sport to continue.");
      return;
    }

    if (selectedSportIds.includes(OTHER_SPORT_ID)) {
      const result = otherSportNameSchema.safeParse(otherSportName);
      if (!result.success) {
        setOtherNameError(result.error.issues[0]?.message ?? "Enter the sport name.");
        return;
      }
    }
    setOtherNameError(null);
    setSelectionError(null);

    if (!facility) return;
    setIsSaving(true);
    setSaveError(null);

    try {
      await MockSportService.saveFacilitySports(
        facility.id,
        selectedSportIds.map((sportId) => ({
          facilityId: facility.id,
          sportId,
          enabled: true,
          customSportName: sportId === OTHER_SPORT_ID ? otherSportName.trim() : undefined,
        })),
      );

      completeSports();
      router.push("/onboarding/courts");
    } catch {
      setSaveError("Unable to save your sports. Please try again.");
      setIsSaving(false);
    }
  }

  if (userLoading || loadState === "loading") {
    return (
      <div className="space-y-6">
        <Skeleton className="h-24 w-full rounded-xl" />
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 6 }).map((_, index) => (
            <Skeleton key={index} className="h-28 w-full rounded-xl" />
          ))}
        </div>
      </div>
    );
  }

  if (loadState === "forbidden") {
    return <ErrorState title="Access denied" message="You don't have access to this facility." />;
  }

  if (!facility) return null;

  return (
    <div className="space-y-8">
      <FacilityContextCard facility={facility} />

      {saveError && <FormMessage>{saveError}</FormMessage>}

      <SportGrid sports={AVAILABLE_SPORTS} selectedSportIds={selectedSportIds} onToggle={toggleSport} />

      {selectedSportIds.includes(OTHER_SPORT_ID) && (
        <OtherSportInput
          value={otherSportName}
          onChange={(value) => {
            setOtherSportName(value);
            setOtherNameError(null);
          }}
          error={otherNameError}
        />
      )}

      {selectionError && <FormMessage>{selectionError}</FormMessage>}

      <div className="flex items-center justify-between gap-4">
        <div className="space-y-1">
          <SelectedSportsSummary count={selectedSportIds.length} />
          <SaveStatus dirtyToken={JSON.stringify({ selectedSportIds, otherSportName })} />
        </div>
        <SubmitButton
          type="button"
          onClick={handleContinue}
          pending={isSaving}
          disabled={selectedSportIds.length === 0}
          pendingLabel="Saving…"
          className="w-auto sm:min-w-[10rem]"
        >
          Continue →
        </SubmitButton>
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/sports-setup/components/sports-setup-form.test.tsx`
Expected: PASS (11 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/sports-setup/components/sports-setup-form.tsx src/features/sports-setup/components/sports-setup-form.test.tsx
git commit -m "feat(sports-setup): add SportsSetupForm integration"
```

---

## Task 10: Route wiring — real sports page, courts placeholder, layout dirty-check

**Files:**
- Modify: `src/app/onboarding/sports/page.tsx` (replace placeholder content with the real page)
- Create: `src/app/onboarding/courts/page.tsx`
- Modify: `src/app/onboarding/layout.tsx` (extend the Back-button dirty check to cover sports selections)

**Interfaces:**
- Consumes: `SportsSetupForm` (Task 9)
- Produces: the real `/onboarding/sports` route; the `/onboarding/courts` placeholder route.

No new automated test in this task — page/layout wiring in this codebase has no dedicated test convention (established in the Facility Details plan's equivalent task). Follow this exactly.

- [ ] **Step 1: Replace `src/app/onboarding/sports/page.tsx`**

```tsx
// src/app/onboarding/sports/page.tsx
import type { Metadata } from "next";
import { SportsSetupForm } from "@/features/sports-setup/components/sports-setup-form";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Sports Setup — ${PRODUCT_NAME}`,
};

export default function SportsSetupPage() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">What sports do you operate?</h1>
        <p className="mt-2 text-sm text-muted-foreground sm:text-base">
          Select the sports available at your facility. You can add or remove sports later.
        </p>
      </div>

      <SportsSetupForm />
    </div>
  );
}
```

- [ ] **Step 2: Write `src/app/onboarding/courts/page.tsx`**

```tsx
// src/app/onboarding/courts/page.tsx
import type { Metadata } from "next";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Courts Setup — ${PRODUCT_NAME}`,
};

export default function CourtsSetupPlaceholderPage() {
  return (
    <div className="space-y-2 text-center">
      <h1 className="text-2xl font-semibold tracking-tight">Courts Setup — Coming Next</h1>
      <p className="text-sm text-muted-foreground">
        Nice work! Next you&apos;ll set up the courts and turfs for each sport. This step is being built next.
      </p>
    </div>
  );
}
```

- [ ] **Step 3: Update `src/app/onboarding/layout.tsx`'s dirty check**

The Back-button confirm dialog currently only checks the facility `draft` for unsaved progress. Once Sports Setup exists, an in-progress sport selection on `/onboarding/sports` must also trigger it — otherwise clicking Back there silently discards selections without asking. Replace the full file with:

```tsx
// src/app/onboarding/layout.tsx
"use client";

import { useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { OnboardingProgress } from "@/features/onboarding/components/onboarding-progress";
import { LeaveConfirmDialog } from "@/features/onboarding/components/leave-confirm-dialog";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";

export default function OnboardingLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const currentStep = useOnboardingStore((s) => s.currentStep);
  const draft = useOnboardingStore((s) => s.draft);
  const selectedSportIds = useOnboardingStore((s) => s.selectedSportIds);
  const [confirmOpen, setConfirmOpen] = useState(false);

  const hasUnsavedProgress =
    Object.values(draft).some((value) => Boolean(value)) || selectedSportIds.length > 0;
  const previousStepPath = pathname === "/onboarding/sports" ? "/onboarding/facility" : "/dashboard";

  // The store uses skipHydration so the client's first render matches the
  // server's default (empty/step-1) HTML. Rehydrate here too — not every
  // onboarding step (e.g. the /onboarding/courts placeholder) mounts a form
  // that would otherwise trigger this, and OnboardingProgress's currentStep
  // needs the real persisted value once it's safe to show it.
  useEffect(() => {
    useOnboardingStore.persist.rehydrate();
  }, []);

  function handleBack() {
    if (hasUnsavedProgress) {
      setConfirmOpen(true);
      return;
    }
    router.replace(previousStepPath);
  }

  return (
    <div className="min-h-[100dvh] bg-background">
      <header className="border-b border-border">
        <div className="mx-auto flex max-w-[1000px] items-center justify-between px-5 py-4 sm:px-8">
          <button
            type="button"
            onClick={handleBack}
            className="flex items-center gap-1.5 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
          >
            <ArrowLeft className="h-4 w-4" aria-hidden="true" />
            Back
          </button>
          <OnboardingProgress currentStep={currentStep} />
        </div>
      </header>

      <main className="mx-auto max-w-[1000px] px-5 py-10 sm:px-8">{children}</main>

      <LeaveConfirmDialog
        open={confirmOpen}
        onOpenChange={setConfirmOpen}
        onLeave={() => router.replace(previousStepPath)}
      />
    </div>
  );
}
```

The only changes from the current file: the new `selectedSportIds` selector line, and `hasUnsavedProgress` now ORs in `selectedSportIds.length > 0`. Everything else (the `previousStepPath` ternary, the rehydrate effect, `handleBack`, the JSX) is unchanged from the version this task started with.

- [ ] **Step 4: Run `npx tsc --noEmit`**

Expected: clean.

- [ ] **Step 5: Run the full suite**

Run: `npx vitest run`
Expected: every test file passes, including the untouched Facility Details suites.

- [ ] **Step 6: Manual verification**

Use the `run` skill (or `npm run dev`), sign in with a test account that has already completed Facility Details, and confirm:
- `/onboarding/sports` renders the facility context card, the 6-sport grid, and the correct heading/subtitle copy
- Selecting Other reveals the Sport Name input
- Continue is disabled with nothing selected, enabled once something is
- Submitting navigates to `/onboarding/courts`, which shows its placeholder heading
- Refreshing `/onboarding/sports` mid-selection restores the selection
- Back from `/onboarding/sports` returns to `/onboarding/facility`; Back from `/onboarding/facility` (or Leave, when a selection exists) still behaves as before

- [ ] **Step 7: Commit**

```bash
git add src/app/onboarding/sports/page.tsx src/app/onboarding/courts/page.tsx src/app/onboarding/layout.tsx
git commit -m "feat(sports-setup): wire the real sports page, courts placeholder, and layout dirty-check"
```

---

## Task 11: Full verification pass

**Files:** none created — this task only runs checks and fixes anything they surface.

- [ ] **Step 1: Typecheck**

Run: `npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 2: Full test suite**

Run: `npx vitest run`
Expected: every test file passes, including every pre-existing suite from the Facility Details plan, untouched.

- [ ] **Step 3: Lint**

Run: `npm run lint`
Expected: no new errors.

- [ ] **Step 4: Production build**

Run: `npm run build`
Expected: succeeds; confirm `/onboarding/sports` and `/onboarding/courts` both appear as registered routes in the build output.

- [ ] **Step 5: Manual responsive pass**

Check `/onboarding/sports` at 375px, 768px, and 1440px widths:
- 1 column at mobile, 2 at tablet, 3 at desktop for the sport grid
- No horizontal overflow at any width
- Continue button remains reachable and not obscured

- [ ] **Step 6: Confirm the business-rule acceptance criteria hold**

Walk through: Facility Details → Sports Setup → select Badminton + Pickleball → Continue. Verify in devtools/localStorage that the saved `FacilitySport` rows carry the real `facilityId` from the just-created facility, and that no row anywhere carries a bare `userId`-to-sport mapping.

- [ ] **Step 7: Final commit (only if Steps 1–4 required fixes)**

```bash
git add -A
git commit -m "fix(sports-setup): address verification pass findings"
```

If no fixes were needed, skip this step.

---

## Self-Review Notes

- **Spec coverage:** facility-relationship rule (§1, §13 — Task 3/9), facility context header (§2–§3 — Task 5), page title/subtitle (§4 — Task 10), progress indicator (§5 — already built, unmodified, confirmed non-clickable matches "not already supported"), sport list/cards (§6–§8 — Task 6), multi-select + minimum one (§9–§10 — Task 9), Other sport (§11 — Task 2/7/9), facility-type preselection without forcing (§12 — Task 9), FacilitySport relationship shape (§13–§16 — Task 1/3), local mock storage scoped by facilityId (§17 — Task 3), restore on reopen (§18 — Task 9), facility/auth/ownership validation (§19–§20 — Task 9), facility summary (§21 — Task 5), selected count (§22 — Task 8), Continue flow (§23 — Task 9), Back (§24 — Task 10), auto-save (§25 — Task 9), remove sport (§26 — Task 3/9), active-only sports (§27 — Task 3), multi-facility-ready architecture (§28 — `ownerId` already on `Facility`, `facilityId` on every `FacilitySport` row), responsive grid (§29 — Task 6), component reuse (§34 — throughout), service layer (§35 — Task 3), state management (§36 — Task 4), error/loading states (§37–§38 — Task 9), testing (§39 — every task's own test file) all have a task. Courts/Operating Hours/Pricing/Dashboard are explicitly out of scope and not touched.
- **No placeholders:** every step has complete, real code.
- **Type consistency:** `Sport`/`FacilitySport`/`FacilitySportInput` (Task 1) are the single types threaded through Tasks 3, 6, 9. `MockSportService`'s method names/signatures (Task 3) match exactly what Task 9 calls. Store field/action names (`selectedSportIds`, `otherSportName`, `setSelectedSportIds`, `setOtherSportName`, `completeSports`) match between Task 4's definition and Task 9/10's consumers.
