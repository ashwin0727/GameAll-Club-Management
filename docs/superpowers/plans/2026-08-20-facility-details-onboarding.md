# Facility Details Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the "Facility Details" onboarding page — the step reached after Sign In — that collects the facility record and hands off to a Sports Setup placeholder.

**Architecture:** A new `src/features/onboarding/` feature module (types, validation, zustand store, mock service, section components, form) plus a new `src/app/onboarding/` route (shared layout, `/facility` page, `/sports` placeholder). Three small new reusable primitives (`Textarea`, `SelectField`, `FileUpload`) fill gaps in the existing `components/ui`/`components/shared` libraries; everything else (`TextField`, `Button`, `Card`, `Select`, `Dialog`, `FormMessage`, `useDebouncedValue`) is reused unmodified. Login/Signup/Splash get a small redirect branch so a user with `onboardingCompleted: false` lands here instead of `/dashboard`.

**Tech Stack:** Next.js App Router, React 19, TypeScript, Tailwind CSS, react-hook-form + zod, zustand (+ `persist`), Vitest + Testing Library (existing conventions only — no new dependencies).

**Spec:** `docs/superpowers/specs/2026-08-20-facility-details-onboarding-design.md`

## Global Constraints

- Reuse the existing design system exactly: same colors/typography/spacing/radius tokens, `TextField`/`Button`/`Card`/`Select`/`Dialog` components — no new theme, no duplicate primitives (per spec §7).
- No secrets, tokens, or passwords ever written to localStorage — only the facility draft (spec §4).
- Validation fires on blur, then live once touched (`mode: "onTouched"`) — never before interaction (spec §8).
- Facility Name: trim, 2–100 chars. Area: ≤100 chars. Address line: ≤250 chars. Description: ≤500 chars, optional. Custom facility type: required + ≤50 chars only when type is `OTHER`. Phone: Indian 10-digit, optional leading `+91`. PIN: exactly 6 digits, numeric only (spec §8).
- Logo upload: PNG/JPG/JPEG/WebP only, max 5MB, local object-URL preview only — no real upload in this phase (spec §7, §16 of the source request).
- This repository has no Flutter project — web (Next.js) only (spec §2).
- Do not touch `supabase/migrations` or the `facilities` DB schema — the richer frontend `Facility` type is intentionally ahead of the current table (spec §6).
- `leave-confirm-dialog` triggers only on the in-app `← Back` button, never on tab-close/refresh (spec §7).
- Every new/modified test file follows the existing harness conventions: `renderWithProviders`, `routerMock`, `installFakeAuthService` from `@/test/harness` and `@/test/router-mock`.

---

## Task 1: Facility types and constants

**Files:**
- Create: `src/features/onboarding/types.ts`
- Create: `src/features/onboarding/constants.ts`
- Test: `src/features/onboarding/constants.test.ts`

**Interfaces:**
- Produces: `FacilityType` union, `FACILITY_TYPE_OPTIONS: { value: FacilityType; label: string }[]`, `Facility` interface, `FacilityAddress` interface, `INDIAN_STATES: string[]`, all imported by every later task.

- [ ] **Step 1: Write the failing test**

```ts
// src/features/onboarding/constants.test.ts
import { describe, expect, it } from "vitest";
import { FACILITY_TYPE_OPTIONS, INDIAN_STATES } from "@/features/onboarding/constants";

describe("onboarding constants", () => {
  it("lists every facility type option exactly once, defaulting to Multi-Sport", () => {
    const values = FACILITY_TYPE_OPTIONS.map((option) => option.value);
    expect(new Set(values).size).toBe(values.length);
    expect(values).toEqual([
      "BADMINTON",
      "PICKLEBALL",
      "CRICKET",
      "FOOTBALL",
      "TENNIS",
      "MULTI_SPORT",
      "OTHER",
    ]);
  });

  it("lists every Indian state and union territory exactly once", () => {
    expect(new Set(INDIAN_STATES).size).toBe(INDIAN_STATES.length);
    expect(INDIAN_STATES).toContain("Tamil Nadu");
    expect(INDIAN_STATES).toContain("Delhi");
    expect(INDIAN_STATES.length).toBe(36);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/onboarding/constants.test.ts`
Expected: FAIL — `Cannot find module '@/features/onboarding/constants'`

- [ ] **Step 3: Write `types.ts`**

```ts
// src/features/onboarding/types.ts
export type FacilityType =
  | "BADMINTON"
  | "PICKLEBALL"
  | "CRICKET"
  | "FOOTBALL"
  | "TENNIS"
  | "MULTI_SPORT"
  | "OTHER";

export interface FacilityAddress {
  line1: string;
  area: string;
  city: string;
  state: string;
  country: "India";
  pinCode: string;
}

/**
 * Frontend-only shape for this onboarding phase. Intentionally richer than
 * the current `facilities` table (see src/types/database.types.ts), which
 * has no `type`, `phone`, structured address, logo, or description columns
 * yet — a future migration grows the schema to match, not the other way
 * round. `ownerId` is carried from day one so the shape never blocks
 * Owner -> [Facility A, Facility B, ...] later, even though only one
 * facility per owner is created today.
 */
export interface Facility {
  id: string;
  ownerId: string;
  name: string;
  type: FacilityType;
  customType?: string;
  businessEmail: string;
  businessPhone: string;
  address: FacilityAddress;
  logoUrl?: string;
  description?: string;
  status: "ACTIVE" | "INACTIVE";
  createdAt: string;
  updatedAt: string;
}

export type FacilityInput = Omit<Facility, "id" | "createdAt" | "updatedAt" | "status"> & {
  status?: Facility["status"];
};
```

- [ ] **Step 4: Write `constants.ts`**

```ts
// src/features/onboarding/constants.ts
import type { FacilityType } from "@/features/onboarding/types";

export const FACILITY_TYPE_OPTIONS: { value: FacilityType; label: string }[] = [
  { value: "BADMINTON", label: "Badminton Court" },
  { value: "PICKLEBALL", label: "Pickleball Court" },
  { value: "CRICKET", label: "Cricket Turf" },
  { value: "FOOTBALL", label: "Football Turf" },
  { value: "TENNIS", label: "Tennis Court" },
  { value: "MULTI_SPORT", label: "Multi-Sport Facility" },
  { value: "OTHER", label: "Other" },
];

export const DEFAULT_FACILITY_TYPE: FacilityType = "MULTI_SPORT";

export const INDIAN_STATES = [
  "Andhra Pradesh",
  "Arunachal Pradesh",
  "Assam",
  "Bihar",
  "Chhattisgarh",
  "Goa",
  "Gujarat",
  "Haryana",
  "Himachal Pradesh",
  "Jharkhand",
  "Karnataka",
  "Kerala",
  "Madhya Pradesh",
  "Maharashtra",
  "Manipur",
  "Meghalaya",
  "Mizoram",
  "Nagaland",
  "Odisha",
  "Punjab",
  "Rajasthan",
  "Sikkim",
  "Tamil Nadu",
  "Telangana",
  "Tripura",
  "Uttar Pradesh",
  "Uttarakhand",
  "West Bengal",
  "Andaman and Nicobar Islands",
  "Chandigarh",
  "Dadra and Nagar Haveli and Daman and Diu",
  "Delhi",
  "Jammu and Kashmir",
  "Ladakh",
  "Lakshadweep",
  "Puducherry",
];

export const MAX_LOGO_SIZE_BYTES = 5 * 1024 * 1024;
export const ACCEPTED_LOGO_TYPES = ["image/png", "image/jpeg", "image/webp"];
```

- [ ] **Step 5: Run test to verify it passes**

Run: `npx vitest run src/features/onboarding/constants.test.ts`
Expected: PASS (2 tests)

- [ ] **Step 6: Commit**

```bash
git add src/features/onboarding/types.ts src/features/onboarding/constants.ts src/features/onboarding/constants.test.ts
git commit -m "feat(onboarding): add facility types and constants"
```

---

## Task 2: Validation schema

**Files:**
- Create: `src/features/onboarding/validation.ts`
- Test: `src/features/onboarding/validation.test.ts`

**Interfaces:**
- Consumes: `FACILITY_TYPE_OPTIONS`, `DEFAULT_FACILITY_TYPE` (Task 1)
- Produces: `facilityDetailsSchema`, `type FacilityDetailsInput = z.infer<typeof facilityDetailsSchema>` — consumed by the store (Task 3) and the form (Task 14).

- [ ] **Step 1: Write the failing test**

```ts
// src/features/onboarding/validation.test.ts
import { describe, expect, it } from "vitest";
import { facilityDetailsSchema } from "@/features/onboarding/validation";

const VALID = {
  facilityName: "GameAll Sports Arena",
  facilityType: "MULTI_SPORT" as const,
  customFacilityType: "",
  businessPhone: "9876543210",
  addressLine: "123 Anna Salai",
  area: "Ambattur",
  city: "Chennai",
  state: "Tamil Nadu",
  pinCode: "600053",
  description: "",
};

describe("facilityDetailsSchema", () => {
  it("accepts a fully valid facility", () => {
    expect(facilityDetailsSchema.safeParse(VALID).success).toBe(true);
  });

  it("rejects an empty facility name", () => {
    const result = facilityDetailsSchema.safeParse({ ...VALID, facilityName: "" });
    expect(result.success).toBe(false);
  });

  it("rejects a facility name under 2 characters", () => {
    const result = facilityDetailsSchema.safeParse({ ...VALID, facilityName: "G" });
    expect(result.success).toBe(false);
  });

  it("rejects a whitespace-only facility name", () => {
    const result = facilityDetailsSchema.safeParse({ ...VALID, facilityName: "   " });
    expect(result.success).toBe(false);
  });

  it("requires customFacilityType when facilityType is OTHER", () => {
    const result = facilityDetailsSchema.safeParse({
      ...VALID,
      facilityType: "OTHER",
      customFacilityType: "",
    });
    expect(result.success).toBe(false);
  });

  it("accepts OTHER with a custom type under 50 characters", () => {
    const result = facilityDetailsSchema.safeParse({
      ...VALID,
      facilityType: "OTHER",
      customFacilityType: "Basketball Court",
    });
    expect(result.success).toBe(true);
  });

  it("accepts a phone with a +91 prefix", () => {
    expect(
      facilityDetailsSchema.safeParse({ ...VALID, businessPhone: "+919876543210" }).success,
    ).toBe(true);
  });

  it("rejects a phone that isn't 10 digits", () => {
    expect(facilityDetailsSchema.safeParse({ ...VALID, businessPhone: "98765" }).success).toBe(
      false,
    );
  });

  it("rejects a PIN code with letters", () => {
    expect(facilityDetailsSchema.safeParse({ ...VALID, pinCode: "6000AB" }).success).toBe(false);
  });

  it("rejects a PIN code that isn't exactly 6 digits", () => {
    expect(facilityDetailsSchema.safeParse({ ...VALID, pinCode: "60005" }).success).toBe(false);
  });

  it("rejects a description over 500 characters", () => {
    const result = facilityDetailsSchema.safeParse({
      ...VALID,
      description: "a".repeat(501),
    });
    expect(result.success).toBe(false);
  });

  it("requires address line, area, city, and state", () => {
    for (const field of ["addressLine", "area", "city", "state"] as const) {
      const result = facilityDetailsSchema.safeParse({ ...VALID, [field]: "" });
      expect(result.success).toBe(false);
    }
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/onboarding/validation.test.ts`
Expected: FAIL — `Cannot find module '@/features/onboarding/validation'`

- [ ] **Step 3: Write the implementation**

```ts
// src/features/onboarding/validation.ts
import { z } from "zod";
import { FACILITY_TYPE_OPTIONS } from "@/features/onboarding/constants";

const facilityTypeValues = FACILITY_TYPE_OPTIONS.map((option) => option.value) as [
  string,
  ...string[],
];

export const facilityDetailsSchema = z
  .object({
    facilityName: z
      .string()
      .trim()
      .min(2, "Facility name must be at least 2 characters")
      .max(100, "Facility name is too long"),
    facilityType: z.enum(facilityTypeValues as [string, ...string[]]),
    customFacilityType: z
      .string()
      .trim()
      .max(50, "Keep this under 50 characters")
      .optional()
      .default(""),
    businessPhone: z
      .string()
      .trim()
      .regex(/^(\+91)?[6-9]\d{9}$/, "Enter a valid 10-digit mobile number"),
    addressLine: z
      .string()
      .trim()
      .min(1, "Address is required")
      .max(250, "Address is too long"),
    area: z.string().trim().min(1, "Area / locality is required").max(100, "Area is too long"),
    city: z.string().trim().min(1, "City is required"),
    state: z.string().trim().min(1, "State is required"),
    pinCode: z.string().trim().regex(/^\d{6}$/, "PIN code must be exactly 6 digits"),
    description: z.string().max(500, "Keep this under 500 characters").optional().default(""),
  })
  .refine(
    (values) => values.facilityType !== "OTHER" || values.customFacilityType.trim().length > 0,
    { path: ["customFacilityType"], message: "Specify your facility type" },
  );

export type FacilityDetailsInput = z.infer<typeof facilityDetailsSchema>;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/onboarding/validation.test.ts`
Expected: PASS (12 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/onboarding/validation.ts src/features/onboarding/validation.test.ts
git commit -m "feat(onboarding): add facility details validation schema"
```

---

## Task 3: Onboarding store (zustand + persist)

**Files:**
- Create: `src/features/onboarding/state/onboarding-store.ts`
- Test: `src/features/onboarding/state/onboarding-store.test.ts`

**Interfaces:**
- Consumes: `FacilityDetailsInput` (Task 2), `Facility` (Task 1)
- Produces: `useOnboardingStore` hook with state `{ currentStep, completedSteps, facilityDetailsCompleted, sportsCompleted, courtsCompleted, operatingHoursCompleted, pricingCompleted, draft }` and actions `setDraft(patch)`, `completeFacilityDetails(facility)`, `reset()` — consumed by Task 13 (form). (Task 16's redirect wiring does not read this store directly.)

- [ ] **Step 1: Write the failing test**

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
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/onboarding/state/onboarding-store.test.ts`
Expected: FAIL — `Cannot find module '@/features/onboarding/state/onboarding-store'`

- [ ] **Step 3: Write the implementation**

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
  setDraft: (patch: FacilityDraft) => void;
  completeFacilityDetails: (facility: Facility) => void;
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
      reset: () => set({ ...INITIAL_STATE }),
    }),
    { name: "turf.onboarding.v1" },
  ),
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/onboarding/state/onboarding-store.test.ts`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/onboarding/state/onboarding-store.ts src/features/onboarding/state/onboarding-store.test.ts
git commit -m "feat(onboarding): add persisted onboarding store"
```

---

## Task 4: Mock facility service

**Files:**
- Create: `src/features/onboarding/services/mock-facility-service.ts`
- Test: `src/features/onboarding/services/mock-facility-service.test.ts`

**Interfaces:**
- Consumes: `Facility`, `FacilityInput` (Task 1)
- Produces: `MockFacilityService.saveFacility(input): Promise<Facility>`, `.getFacility(ownerId): Promise<Facility | null>`, `.updateFacility(id, patch): Promise<Facility>` — consumed by Task 13.

- [ ] **Step 1: Write the failing test**

```ts
// src/features/onboarding/services/mock-facility-service.test.ts
import { beforeEach, describe, expect, it } from "vitest";
import { MockFacilityService } from "@/features/onboarding/services/mock-facility-service";
import type { FacilityInput } from "@/features/onboarding/types";

const INPUT: FacilityInput = {
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
};

describe("MockFacilityService", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it("saves a facility and assigns an id and timestamps", async () => {
    const facility = await MockFacilityService.saveFacility(INPUT);

    expect(facility.id).toBeTruthy();
    expect(facility.name).toBe("GameAll Sports Arena");
    expect(facility.status).toBe("ACTIVE");
    expect(facility.createdAt).toBeTruthy();
    expect(facility.updatedAt).toBe(facility.createdAt);
  });

  it("retrieves a saved facility by owner id", async () => {
    const saved = await MockFacilityService.saveFacility(INPUT);

    const found = await MockFacilityService.getFacility("owner-1");
    expect(found?.id).toBe(saved.id);
  });

  it("returns null for an owner with no facility", async () => {
    const found = await MockFacilityService.getFacility("owner-does-not-exist");
    expect(found).toBeNull();
  });

  it("updates a facility and bumps updatedAt", async () => {
    const saved = await MockFacilityService.saveFacility(INPUT);
    await new Promise((resolve) => setTimeout(resolve, 2));

    const updated = await MockFacilityService.updateFacility(saved.id, { name: "New Name" });
    expect(updated.name).toBe("New Name");
    expect(updated.updatedAt).not.toBe(saved.updatedAt);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/onboarding/services/mock-facility-service.test.ts`
Expected: FAIL — `Cannot find module '@/features/onboarding/services/mock-facility-service'`

- [ ] **Step 3: Write the implementation**

```ts
// src/features/onboarding/services/mock-facility-service.ts
import type { Facility, FacilityInput } from "@/features/onboarding/types";

const STORAGE_KEY = "turf.facility.mock.v1";

function readAll(): Facility[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as Facility[]) : [];
  } catch {
    return [];
  }
}

function writeAll(facilities: Facility[]): void {
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(facilities));
}

export const MockFacilityService = {
  async saveFacility(input: FacilityInput): Promise<Facility> {
    const now = new Date().toISOString();
    const facility: Facility = {
      ...input,
      id: crypto.randomUUID(),
      status: input.status ?? "ACTIVE",
      createdAt: now,
      updatedAt: now,
    };

    const facilities = readAll().filter((f) => f.ownerId !== input.ownerId);
    writeAll([...facilities, facility]);
    return facility;
  },

  async getFacility(ownerId: string): Promise<Facility | null> {
    return readAll().find((f) => f.ownerId === ownerId) ?? null;
  },

  async updateFacility(id: string, patch: Partial<FacilityInput>): Promise<Facility> {
    const facilities = readAll();
    const index = facilities.findIndex((f) => f.id === id);
    if (index === -1) throw new Error("Facility not found");

    const updated: Facility = {
      ...facilities[index],
      ...patch,
      updatedAt: new Date().toISOString(),
    };
    facilities[index] = updated;
    writeAll(facilities);
    return updated;
  },
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/onboarding/services/mock-facility-service.test.ts`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/onboarding/services/mock-facility-service.ts src/features/onboarding/services/mock-facility-service.test.ts
git commit -m "feat(onboarding): add mock facility persistence service"
```

---

## Task 5: SelectField form primitive

**Files:**
- Create: `src/components/form/select-field.tsx`
- Test: `src/components/form/select-field.test.tsx`

**Interfaces:**
- Consumes: `Select`, `SelectTrigger`, `SelectValue`, `SelectContent`, `SelectItem` from `@/components/ui/select` (existing); `Label` from `@/components/ui/label`; `FieldError` from `@/features/auth/components/text-field` (existing, exported already)
- Produces: `<SelectField id label options value onValueChange error hint placeholder />` — consumed by Task 10 (facility type) and Task 11 (state).

- [ ] **Step 1: Write the failing test**

```tsx
// src/components/form/select-field.test.tsx
import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SelectField } from "@/components/form/select-field";

const OPTIONS = [
  { value: "A", label: "Option A" },
  { value: "B", label: "Option B" },
];

describe("SelectField", () => {
  it("renders the label and current value", () => {
    render(
      <SelectField id="test" label="Test field" options={OPTIONS} value="A" onValueChange={vi.fn()} />,
    );

    expect(screen.getByText("Test field")).toBeInTheDocument();
    expect(screen.getByText("Option A")).toBeInTheDocument();
  });

  it("calls onValueChange when a new option is selected", async () => {
    const user = userEvent.setup();
    const onValueChange = vi.fn();
    render(
      <SelectField
        id="test"
        label="Test field"
        options={OPTIONS}
        value="A"
        onValueChange={onValueChange}
      />,
    );

    await user.click(screen.getByRole("combobox"));
    await user.click(await screen.findByRole("option", { name: "Option B" }));

    expect(onValueChange).toHaveBeenCalledWith("B");
  });

  it("shows an error message and marks the trigger invalid", () => {
    render(
      <SelectField
        id="test"
        label="Test field"
        options={OPTIONS}
        value="A"
        onValueChange={vi.fn()}
        error="This field is required"
      />,
    );

    expect(screen.getByText("This field is required")).toBeInTheDocument();
    expect(screen.getByRole("combobox")).toHaveAttribute("aria-invalid", "true");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/components/form/select-field.test.tsx`
Expected: FAIL — `Cannot find module '@/components/form/select-field'`

- [ ] **Step 3: Write the implementation**

```tsx
// src/components/form/select-field.tsx
"use client";

import * as React from "react";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { FieldError } from "@/features/auth/components/text-field";
import { cn } from "@/lib/utils";

export interface SelectFieldOption {
  value: string;
  label: string;
}

export interface SelectFieldProps {
  id: string;
  label: string;
  options: SelectFieldOption[];
  value: string;
  onValueChange: (value: string) => void;
  onBlur?: () => void;
  error?: string;
  hint?: string;
  placeholder?: string;
  className?: string;
}

/**
 * Label + Select + message, mirroring TextField's contract so the two
 * compose identically inside a form grid.
 */
export function SelectField({
  id,
  label,
  options,
  value,
  onValueChange,
  onBlur,
  error,
  hint,
  placeholder,
  className,
}: SelectFieldProps) {
  const errorId = `${id}-error`;
  const hintId = `${id}-hint`;
  const describedBy = [error ? errorId : null, hint ? hintId : null].filter(Boolean).join(" ");

  return (
    <div className={cn("space-y-2", className)}>
      <Label htmlFor={id}>{label}</Label>
      <Select value={value} onValueChange={onValueChange}>
        <SelectTrigger
          id={id}
          onBlur={onBlur}
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy || undefined}
          className={cn("h-11 bg-secondary/60 text-base sm:text-sm", error && "border-destructive")}
        >
          <SelectValue placeholder={placeholder} />
        </SelectTrigger>
        <SelectContent>
          {options.map((option) => (
            <SelectItem key={option.value} value={option.value}>
              {option.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      {hint && !error && (
        <p id={hintId} className="text-xs text-muted-foreground">
          {hint}
        </p>
      )}
      {error && <FieldError id={errorId}>{error}</FieldError>}
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/components/form/select-field.test.tsx`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add src/components/form/select-field.tsx src/components/form/select-field.test.tsx
git commit -m "feat(form): add reusable SelectField primitive"
```

---

## Task 6: FileUpload shared component

**Files:**
- Create: `src/components/shared/file-upload.tsx`
- Test: `src/components/shared/file-upload.test.tsx`

**Interfaces:**
- Consumes: `Button` (existing), `MAX_LOGO_SIZE_BYTES`, `ACCEPTED_LOGO_TYPES` (Task 1)
- Produces: `<FileUpload value={File | string | null} onChange={(file: File | null) => void} accept hint label />` with internal preview/replace/remove and inline type/size error — consumed by Task 12.

- [ ] **Step 1: Write the failing test**

```tsx
// src/components/shared/file-upload.test.tsx
import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { FileUpload } from "@/components/shared/file-upload";

function makeFile(name: string, type: string, sizeBytes: number): File {
  const file = new File([new Uint8Array(sizeBytes)], name, { type });
  return file;
}

describe("FileUpload", () => {
  it("shows the upload prompt when empty", () => {
    render(<FileUpload label="Facility Logo" value={null} onChange={vi.fn()} />);
    expect(screen.getByText("+ Upload Logo")).toBeInTheDocument();
  });

  it("accepts a valid PNG under the size limit", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(<FileUpload label="Facility Logo" value={null} onChange={onChange} />);

    const file = makeFile("logo.png", "image/png", 1024);
    await user.upload(screen.getByLabelText("Facility Logo"), file);

    expect(onChange).toHaveBeenCalledWith(file);
  });

  it("rejects a file over 5MB with an inline message", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(<FileUpload label="Facility Logo" value={null} onChange={onChange} />);

    const tooBig = makeFile("logo.png", "image/png", 6 * 1024 * 1024);
    await user.upload(screen.getByLabelText("Facility Logo"), tooBig);

    expect(onChange).not.toHaveBeenCalled();
    expect(await screen.findByText(/must be smaller than 5MB/i)).toBeInTheDocument();
  });

  it("rejects an unsupported file type", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(<FileUpload label="Facility Logo" value={null} onChange={onChange} />);

    const badType = makeFile("logo.gif", "image/gif", 1024);
    await user.upload(screen.getByLabelText("Facility Logo"), badType);

    expect(onChange).not.toHaveBeenCalled();
    expect(await screen.findByText(/PNG, JPG, JPEG or WebP/i)).toBeInTheDocument();
  });

  it("shows Replace and Remove once a file is set, and Remove clears it", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    const file = makeFile("logo.png", "image/png", 1024);
    render(<FileUpload label="Facility Logo" value={file} onChange={onChange} />);

    expect(screen.getByRole("button", { name: "Replace" })).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Remove" }));

    expect(onChange).toHaveBeenCalledWith(null);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/components/shared/file-upload.test.tsx`
Expected: FAIL — `Cannot find module '@/components/shared/file-upload'`

- [ ] **Step 3: Write the implementation**

```tsx
// src/components/shared/file-upload.tsx
"use client";

import * as React from "react";
import { Button } from "@/components/ui/button";
import { FieldError } from "@/features/auth/components/text-field";
import { ACCEPTED_LOGO_TYPES, MAX_LOGO_SIZE_BYTES } from "@/features/onboarding/constants";
import { cn } from "@/lib/utils";

export interface FileUploadProps {
  id?: string;
  label: string;
  hint?: string;
  value: File | string | null;
  onChange: (file: File | null) => void;
  className?: string;
}

const ACCEPT_ATTR = ACCEPTED_LOGO_TYPES.join(",");

function previewSrc(value: File | string | null): string | null {
  if (!value) return null;
  return typeof value === "string" ? value : URL.createObjectURL(value);
}

export function FileUpload({ id = "facility-logo", label, hint, value, onChange, className }: FileUploadProps) {
  const inputRef = React.useRef<HTMLInputElement>(null);
  const [error, setError] = React.useState<string | null>(null);
  const preview = React.useMemo(() => previewSrc(value), [value]);

  React.useEffect(() => {
    return () => {
      if (preview && typeof value !== "string") URL.revokeObjectURL(preview);
    };
  }, [preview, value]);

  function handleFiles(files: FileList | null) {
    const file = files?.[0];
    if (!file) return;

    if (!ACCEPTED_LOGO_TYPES.includes(file.type)) {
      setError("Upload a PNG, JPG, JPEG or WebP image.");
      return;
    }
    if (file.size > MAX_LOGO_SIZE_BYTES) {
      setError("File must be smaller than 5MB.");
      return;
    }

    setError(null);
    onChange(file);
  }

  return (
    <div className={cn("space-y-2", className)}>
      <input
        ref={inputRef}
        id={id}
        aria-label={label}
        type="file"
        accept={ACCEPT_ATTR}
        className="sr-only"
        onChange={(e) => handleFiles(e.target.files)}
      />

      {!value ? (
        <button
          type="button"
          onClick={() => inputRef.current?.click()}
          className="flex h-24 w-full items-center justify-center rounded-lg border border-dashed border-input text-sm font-medium text-muted-foreground transition-colors hover:border-primary hover:text-primary"
        >
          + Upload Logo
        </button>
      ) : (
        <div className="flex items-center gap-4">
          {preview && (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={preview}
              alt="Facility logo preview"
              className="h-16 w-16 rounded-lg border border-border object-cover"
            />
          )}
          <div className="flex gap-2">
            <Button type="button" variant="outline" size="sm" onClick={() => inputRef.current?.click()}>
              Replace
            </Button>
            <Button type="button" variant="ghost" size="sm" onClick={() => onChange(null)}>
              Remove
            </Button>
          </div>
        </div>
      )}

      {hint && !error && <p className="text-xs text-muted-foreground">{hint}</p>}
      {error && <FieldError>{error}</FieldError>}
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/components/shared/file-upload.test.tsx`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add src/components/shared/file-upload.tsx src/components/shared/file-upload.test.tsx
git commit -m "feat(shared): add FileUpload component for facility logo"
```

---

## Task 7: OnboardingProgress component

**Files:**
- Create: `src/features/onboarding/components/onboarding-progress.tsx`
- Test: `src/features/onboarding/components/onboarding-progress.test.tsx`

**Interfaces:**
- Produces: `<OnboardingProgress currentStep={number} />` with a fixed 5-step label list — consumed by Task 14 (onboarding layout).

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/onboarding/components/onboarding-progress.test.tsx
import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { OnboardingProgress } from "@/features/onboarding/components/onboarding-progress";

describe("OnboardingProgress", () => {
  it("lists all five steps", () => {
    render(<OnboardingProgress currentStep={1} />);

    for (const step of ["Facility Details", "Sports", "Courts", "Operating Hours", "Pricing"]) {
      expect(screen.getAllByText(step).length).toBeGreaterThan(0);
    }
  });

  it("marks the current step for assistive tech", () => {
    render(<OnboardingProgress currentStep={1} />);
    expect(screen.getByText("Facility Details")).toHaveAttribute("aria-current", "step");
  });

  it("shows the compact mobile summary", () => {
    render(<OnboardingProgress currentStep={1} />);
    expect(screen.getByText("Step 1 of 5")).toBeInTheDocument();
  });

  it("renders no clickable step controls", () => {
    render(<OnboardingProgress currentStep={1} />);
    expect(screen.queryAllByRole("button")).toHaveLength(0);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/onboarding/components/onboarding-progress.test.tsx`
Expected: FAIL — `Cannot find module '@/features/onboarding/components/onboarding-progress'`

- [ ] **Step 3: Write the implementation**

```tsx
// src/features/onboarding/components/onboarding-progress.tsx
import { Check } from "lucide-react";
import { cn } from "@/lib/utils";

const STEPS = ["Facility Details", "Sports", "Courts", "Operating Hours", "Pricing"];

export function OnboardingProgress({ currentStep }: { currentStep: number }) {
  return (
    <div role="status" aria-label={`Step ${currentStep} of ${STEPS.length}`}>
      {/* Desktop: horizontal stepper */}
      <ol className="hidden items-center gap-2 md:flex">
        {STEPS.map((label, index) => {
          const step = index + 1;
          const state = step < currentStep ? "done" : step === currentStep ? "current" : "upcoming";

          return (
            <li key={label} className="flex items-center gap-2">
              {index > 0 && <span className="h-px w-6 bg-border" aria-hidden="true" />}
              <span
                aria-current={state === "current" ? "step" : undefined}
                className={cn(
                  "flex items-center gap-1.5 text-xs font-medium",
                  state === "current" && "text-primary",
                  state === "done" && "text-foreground",
                  state === "upcoming" && "text-muted-foreground",
                )}
              >
                <span
                  className={cn(
                    "flex h-4 w-4 items-center justify-center rounded-full border text-[10px]",
                    state === "current" && "border-primary bg-primary text-primary-foreground",
                    state === "done" && "border-foreground bg-foreground text-background",
                    state === "upcoming" && "border-muted-foreground",
                  )}
                >
                  {state === "done" ? <Check className="h-2.5 w-2.5" aria-hidden="true" /> : null}
                </span>
                {label}
              </span>
            </li>
          );
        })}
      </ol>

      {/* Mobile: compact bar */}
      <div className="space-y-2 md:hidden">
        <p className="text-xs font-medium text-muted-foreground">
          Step {currentStep} of {STEPS.length}
        </p>
        <div className="h-1.5 w-full overflow-hidden rounded-full bg-secondary">
          <div
            className="h-full rounded-full bg-primary transition-all"
            style={{ width: `${(currentStep / STEPS.length) * 100}%` }}
          />
        </div>
        <p aria-current="step" className="text-sm font-semibold text-foreground">
          {STEPS[currentStep - 1]}
        </p>
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/onboarding/components/onboarding-progress.test.tsx`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/onboarding/components/onboarding-progress.tsx src/features/onboarding/components/onboarding-progress.test.tsx
git commit -m "feat(onboarding): add onboarding progress indicator"
```

---

## Task 8: SaveStatus component

**Files:**
- Create: `src/features/onboarding/components/save-status.tsx`
- Test: `src/features/onboarding/components/save-status.test.tsx`

**Interfaces:**
- Consumes: `useDebouncedValue` from `@/hooks/use-debounced-value` (existing)
- Produces: `<SaveStatus dirtyToken={unknown} delayMs?={number} />` — re-mount-friendly status text; consumed by Task 13.

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/onboarding/components/save-status.test.tsx
import { describe, expect, it } from "vitest";
import { act, render, screen } from "@testing-library/react";
import { SaveStatus } from "@/features/onboarding/components/save-status";

describe("SaveStatus", () => {
  it("shows Saving immediately after the tracked value changes, then Saved", async () => {
    const { rerender } = render(<SaveStatus dirtyToken="a" delayMs={20} />);
    expect(screen.getByText("Saved")).toBeInTheDocument();

    rerender(<SaveStatus dirtyToken="b" delayMs={20} />);
    expect(screen.getByText("Saving…")).toBeInTheDocument();

    await act(() => new Promise((resolve) => setTimeout(resolve, 40)));
    expect(screen.getByText("Saved")).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/onboarding/components/save-status.test.tsx`
Expected: FAIL — `Cannot find module '@/features/onboarding/components/save-status'`

- [ ] **Step 3: Write the implementation**

```tsx
// src/features/onboarding/components/save-status.tsx
"use client";

import { useDebouncedValue } from "@/hooks/use-debounced-value";

/**
 * `dirtyToken` is any value that changes on every draft edit (e.g. a
 * JSON.stringify of the draft, or an incrementing counter). While the
 * debounced copy hasn't caught up to the latest token, the save is "in
 * flight" from the user's point of view.
 */
export function SaveStatus({ dirtyToken, delayMs = 400 }: { dirtyToken: unknown; delayMs?: number }) {
  const settled = useDebouncedValue(dirtyToken, delayMs);
  const saving = settled !== dirtyToken;

  return (
    <p className="text-xs text-muted-foreground" role="status" aria-live="polite">
      {saving ? "Saving…" : "Saved"}
    </p>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/onboarding/components/save-status.test.tsx`
Expected: PASS (1 test)

- [ ] **Step 5: Commit**

```bash
git add src/features/onboarding/components/save-status.tsx src/features/onboarding/components/save-status.test.tsx
git commit -m "feat(onboarding): add debounced save status indicator"
```

---

## Task 9: LeaveConfirmDialog

**Files:**
- Create: `src/features/onboarding/components/leave-confirm-dialog.tsx`
- Test: `src/features/onboarding/components/leave-confirm-dialog.test.tsx`

**Interfaces:**
- Consumes: `Dialog`, `DialogContent`, `DialogHeader`, `DialogTitle`, `DialogDescription`, `DialogFooter` from `@/components/ui/dialog` (existing); `Button` (existing)
- Produces: `<LeaveConfirmDialog open onOpenChange onLeave />` — consumed by Task 14 (Back button, in the onboarding layout).

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/onboarding/components/leave-confirm-dialog.test.tsx
import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { LeaveConfirmDialog } from "@/features/onboarding/components/leave-confirm-dialog";

describe("LeaveConfirmDialog", () => {
  it("shows the saved-progress message when open", () => {
    render(<LeaveConfirmDialog open onOpenChange={vi.fn()} onLeave={vi.fn()} />);
    expect(screen.getByText("Your progress has been saved.")).toBeInTheDocument();
  });

  it("calls onLeave when Leave is clicked", async () => {
    const user = userEvent.setup();
    const onLeave = vi.fn();
    render(<LeaveConfirmDialog open onOpenChange={vi.fn()} onLeave={onLeave} />);

    await user.click(screen.getByRole("button", { name: "Leave" }));
    expect(onLeave).toHaveBeenCalled();
  });

  it("closes without leaving when Continue Setup is clicked", async () => {
    const user = userEvent.setup();
    const onOpenChange = vi.fn();
    const onLeave = vi.fn();
    render(<LeaveConfirmDialog open onOpenChange={onOpenChange} onLeave={onLeave} />);

    await user.click(screen.getByRole("button", { name: "Continue Setup" }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
    expect(onLeave).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/onboarding/components/leave-confirm-dialog.test.tsx`
Expected: FAIL — `Cannot find module '@/features/onboarding/components/leave-confirm-dialog'`

- [ ] **Step 3: Write the implementation**

```tsx
// src/features/onboarding/components/leave-confirm-dialog.tsx
"use client";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

export function LeaveConfirmDialog({
  open,
  onOpenChange,
  onLeave,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onLeave: () => void;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Your progress has been saved.</DialogTitle>
          <DialogDescription>You can pick up right where you left off.</DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            Continue Setup
          </Button>
          <Button type="button" onClick={onLeave}>
            Leave
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/onboarding/components/leave-confirm-dialog.test.tsx`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/onboarding/components/leave-confirm-dialog.tsx src/features/onboarding/components/leave-confirm-dialog.test.tsx
git commit -m "feat(onboarding): add leave-confirmation dialog"
```

---

## Task 10: Facility Information section

**Files:**
- Create: `src/features/onboarding/components/facility-information-section.tsx`
- Test: `src/features/onboarding/components/facility-information-section.test.tsx`

**Interfaces:**
- Consumes: `TextField` (`@/features/auth/components/text-field`), `SelectField` (Task 5), `FACILITY_TYPE_OPTIONS` (Task 1), `UseFormRegister`/`FieldErrors`/`Control` types from `react-hook-form`
- Produces: `<FacilityInformationSection register errors facilityType onFacilityTypeChange businessEmail />` — consumed by Task 13.

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/onboarding/components/facility-information-section.test.tsx
import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { useForm } from "react-hook-form";
import { FacilityInformationSection } from "@/features/onboarding/components/facility-information-section";

function Harness({ facilityType = "MULTI_SPORT" }: { facilityType?: string }) {
  const { register, formState } = useForm({ defaultValues: { facilityName: "", businessPhone: "" } });
  return (
    <FacilityInformationSection
      register={register}
      errors={formState.errors}
      facilityType={facilityType}
      onFacilityTypeChange={vi.fn()}
      businessEmail="owner@yourturf.com"
    />
  );
}

describe("FacilityInformationSection", () => {
  it("renders the core fields", () => {
    render(<Harness />);
    expect(screen.getByLabelText("Facility Name")).toBeInTheDocument();
    expect(screen.getByText("Facility Type")).toBeInTheDocument();
    expect(screen.getByLabelText("Business Contact Number")).toBeInTheDocument();
  });

  it("shows the business email as verified and not editable", () => {
    render(<Harness />);
    expect(screen.getByText("owner@yourturf.com")).toBeInTheDocument();
    expect(screen.getByText("Verified")).toBeInTheDocument();
    expect(screen.queryByLabelText("Business Email")).not.toBeInTheDocument();
  });

  it("shows the custom type field only when facility type is Other", () => {
    const { rerender } = render(<Harness facilityType="MULTI_SPORT" />);
    expect(screen.queryByLabelText("Specify Facility Type")).not.toBeInTheDocument();

    rerender(<Harness facilityType="OTHER" />);
    expect(screen.getByLabelText("Specify Facility Type")).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/onboarding/components/facility-information-section.test.tsx`
Expected: FAIL — `Cannot find module '@/features/onboarding/components/facility-information-section'`

- [ ] **Step 3: Write the implementation**

```tsx
// src/features/onboarding/components/facility-information-section.tsx
"use client";

import type { FieldErrors, UseFormRegister } from "react-hook-form";
import { BadgeCheck } from "lucide-react";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/form/select-field";
import { TextField } from "@/features/auth/components/text-field";
import { FACILITY_TYPE_OPTIONS } from "@/features/onboarding/constants";
import type { FacilityDetailsInput } from "@/features/onboarding/validation";

export interface FacilityInformationSectionProps {
  register: UseFormRegister<FacilityDetailsInput>;
  errors: FieldErrors<FacilityDetailsInput>;
  facilityType: string;
  onFacilityTypeChange: (value: string) => void;
  businessEmail: string;
}

export function FacilityInformationSection({
  register,
  errors,
  facilityType,
  onFacilityTypeChange,
  businessEmail,
}: FacilityInformationSectionProps) {
  return (
    <div className="space-y-5">
      <div className="grid gap-5 sm:grid-cols-2">
        <TextField
          id="facility-name"
          label="Facility Name"
          placeholder="e.g. GameAll Sports Arena"
          hint="Use the name your customers know your facility by."
          error={errors.facilityName?.message}
          {...register("facilityName")}
        />
        <SelectField
          id="facility-type"
          label="Facility Type"
          options={FACILITY_TYPE_OPTIONS}
          value={facilityType}
          onValueChange={onFacilityTypeChange}
          error={errors.facilityType?.message as string | undefined}
        />
      </div>

      {facilityType === "OTHER" && (
        <TextField
          id="custom-facility-type"
          label="Specify Facility Type"
          placeholder="e.g. Basketball Court"
          maxLength={50}
          error={errors.customFacilityType?.message}
          {...register("customFacilityType")}
        />
      )}

      <TextField
        id="business-phone"
        label="Business Contact Number"
        type="tel"
        inputMode="tel"
        placeholder="+91 XXXXX XXXXX"
        hint="The facility's own contact number — it doesn't have to match your personal number."
        error={errors.businessPhone?.message}
        {...register("businessPhone")}
      />

      <div className="space-y-2">
        <Label>Business Email</Label>
        <div className="flex h-11 items-center justify-between rounded-md border border-input bg-secondary/60 px-3 text-sm">
          <span>{businessEmail}</span>
          <span className="flex items-center gap-1 text-xs font-medium text-success">
            <BadgeCheck className="h-3.5 w-3.5" aria-hidden="true" />
            Verified
          </span>
        </div>
        <p className="text-xs text-muted-foreground">This email is linked to your account.</p>
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/onboarding/components/facility-information-section.test.tsx`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/onboarding/components/facility-information-section.tsx src/features/onboarding/components/facility-information-section.test.tsx
git commit -m "feat(onboarding): add facility information section"
```

---

## Task 11: Facility Location section

**Files:**
- Create: `src/features/onboarding/components/facility-location-section.tsx`
- Test: `src/features/onboarding/components/facility-location-section.test.tsx`

**Interfaces:**
- Consumes: `TextField`, `SelectField` (Task 5), `INDIAN_STATES` (Task 1)
- Produces: `<FacilityLocationSection register errors state onStateChange />` — consumed by Task 13.

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/onboarding/components/facility-location-section.test.tsx
import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { useForm } from "react-hook-form";
import { FacilityLocationSection } from "@/features/onboarding/components/facility-location-section";

function Harness() {
  const { register, formState } = useForm({
    defaultValues: { addressLine: "", area: "", city: "", pinCode: "" },
  });
  return (
    <FacilityLocationSection
      register={register}
      errors={formState.errors}
      state=""
      onStateChange={vi.fn()}
    />
  );
}

describe("FacilityLocationSection", () => {
  it("renders every location field", () => {
    render(<Harness />);
    expect(screen.getByLabelText("Address")).toBeInTheDocument();
    expect(screen.getByLabelText("Area / Locality")).toBeInTheDocument();
    expect(screen.getByLabelText("City")).toBeInTheDocument();
    expect(screen.getByText("State")).toBeInTheDocument();
    expect(screen.getByLabelText("PIN Code")).toBeInTheDocument();
  });

  it("uses a numeric keyboard for PIN code", () => {
    render(<Harness />);
    expect(screen.getByLabelText("PIN Code")).toHaveAttribute("inputMode", "numeric");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/onboarding/components/facility-location-section.test.tsx`
Expected: FAIL — `Cannot find module '@/features/onboarding/components/facility-location-section'`

- [ ] **Step 3: Write the implementation**

```tsx
// src/features/onboarding/components/facility-location-section.tsx
"use client";

import type { FieldErrors, UseFormRegister } from "react-hook-form";
import { SelectField } from "@/components/form/select-field";
import { TextField } from "@/features/auth/components/text-field";
import { INDIAN_STATES } from "@/features/onboarding/constants";
import type { FacilityDetailsInput } from "@/features/onboarding/validation";

const STATE_OPTIONS = INDIAN_STATES.map((state) => ({ value: state, label: state }));

export interface FacilityLocationSectionProps {
  register: UseFormRegister<FacilityDetailsInput>;
  errors: FieldErrors<FacilityDetailsInput>;
  state: string;
  onStateChange: (value: string) => void;
}

export function FacilityLocationSection({
  register,
  errors,
  state,
  onStateChange,
}: FacilityLocationSectionProps) {
  return (
    <div className="space-y-5">
      <TextField
        id="address-line"
        label="Address"
        placeholder="Enter your facility address"
        maxLength={250}
        error={errors.addressLine?.message}
        {...register("addressLine")}
      />

      <div className="grid gap-5 sm:grid-cols-2">
        <TextField
          id="area"
          label="Area / Locality"
          placeholder="e.g. Ambattur"
          maxLength={100}
          error={errors.area?.message}
          {...register("area")}
        />
        <TextField
          id="city"
          label="City"
          placeholder="e.g. Chennai"
          error={errors.city?.message}
          {...register("city")}
        />
      </div>

      <div className="grid gap-5 sm:grid-cols-2">
        <SelectField
          id="state"
          label="State"
          options={STATE_OPTIONS}
          value={state}
          onValueChange={onStateChange}
          placeholder="Select a state"
          error={errors.state?.message as string | undefined}
        />
        <TextField
          id="pin-code"
          label="PIN Code"
          inputMode="numeric"
          placeholder="600053"
          maxLength={6}
          error={errors.pinCode?.message}
          {...register("pinCode")}
        />
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/onboarding/components/facility-location-section.test.tsx`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/onboarding/components/facility-location-section.tsx src/features/onboarding/components/facility-location-section.test.tsx
git commit -m "feat(onboarding): add facility location section"
```

---

## Task 12: Facility Branding section

**Files:**
- Create: `src/components/ui/textarea.tsx`
- Create: `src/features/onboarding/components/facility-branding-section.tsx`
- Test: `src/features/onboarding/components/facility-branding-section.test.tsx`

**Interfaces:**
- Consumes: `FileUpload` (Task 6)
- Produces: `Textarea` (shadcn-style primitive), `<FacilityBrandingSection description onDescriptionChange logo onLogoChange />` — consumed by Task 13.

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/onboarding/components/facility-branding-section.test.tsx
import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { FacilityBrandingSection } from "@/features/onboarding/components/facility-branding-section";

describe("FacilityBrandingSection", () => {
  it("shows the character counter starting at 0/500", () => {
    render(
      <FacilityBrandingSection description="" onDescriptionChange={vi.fn()} logo={null} onLogoChange={vi.fn()} />,
    );
    expect(screen.getByText("0 / 500")).toBeInTheDocument();
  });

  it("updates the counter as the user types", async () => {
    const user = userEvent.setup();
    const onDescriptionChange = vi.fn();
    render(
      <FacilityBrandingSection
        description=""
        onDescriptionChange={onDescriptionChange}
        logo={null}
        onLogoChange={vi.fn()}
      />,
    );

    await user.type(screen.getByLabelText("About Your Facility"), "Great courts");
    expect(onDescriptionChange).toHaveBeenCalled();
  });

  it("renders the optional logo upload", () => {
    render(
      <FacilityBrandingSection description="" onDescriptionChange={vi.fn()} logo={null} onLogoChange={vi.fn()} />,
    );
    expect(screen.getByText("+ Upload Logo")).toBeInTheDocument();
    expect(screen.getByText(/Optional/)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/onboarding/components/facility-branding-section.test.tsx`
Expected: FAIL — `Cannot find module '@/features/onboarding/components/facility-branding-section'`

- [ ] **Step 3: Write `textarea.tsx`**

```tsx
// src/components/ui/textarea.tsx
import * as React from "react";
import { cn } from "@/lib/utils";

export type TextareaProps = React.TextareaHTMLAttributes<HTMLTextAreaElement>;

const Textarea = React.forwardRef<HTMLTextAreaElement, TextareaProps>(
  ({ className, ...props }, ref) => (
    <textarea
      ref={ref}
      className={cn(
        "flex min-h-[6rem] w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50",
        className,
      )}
      {...props}
    />
  ),
);
Textarea.displayName = "Textarea";

export { Textarea };
```

- [ ] **Step 4: Write `facility-branding-section.tsx`**

```tsx
// src/features/onboarding/components/facility-branding-section.tsx
"use client";

import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { FileUpload } from "@/components/shared/file-upload";

const DESCRIPTION_MAX = 500;

export interface FacilityBrandingSectionProps {
  description: string;
  onDescriptionChange: (value: string) => void;
  logo: File | string | null;
  onLogoChange: (file: File | null) => void;
}

export function FacilityBrandingSection({
  description,
  onDescriptionChange,
  logo,
  onLogoChange,
}: FacilityBrandingSectionProps) {
  return (
    <div className="space-y-5">
      <FileUpload
        label="Facility Logo"
        hint="Optional. You can add your logo later."
        value={logo}
        onChange={onLogoChange}
      />

      <div className="space-y-2">
        <Label htmlFor="facility-description">About Your Facility</Label>
        <Textarea
          id="facility-description"
          placeholder="Tell customers a little about your facility..."
          maxLength={DESCRIPTION_MAX}
          value={description}
          onChange={(e) => onDescriptionChange(e.target.value)}
          className="min-h-[6rem]"
        />
        <p className="text-right text-xs text-muted-foreground">
          {description.length} / {DESCRIPTION_MAX}
        </p>
      </div>
    </div>
  );
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `npx vitest run src/features/onboarding/components/facility-branding-section.test.tsx`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add src/components/ui/textarea.tsx src/features/onboarding/components/facility-branding-section.tsx src/features/onboarding/components/facility-branding-section.test.tsx
git commit -m "feat(onboarding): add facility branding section and Textarea primitive"
```

---

## Task 13: FacilityDetailsForm (integration)

**Files:**
- Create: `src/features/onboarding/components/facility-details-form.tsx`
- Test: `src/features/onboarding/components/facility-details-form.test.tsx`

**Interfaces:**
- Consumes: `facilityDetailsSchema`, `FacilityDetailsInput` (Task 2); `useOnboardingStore` (Task 3); `MockFacilityService` (Task 4); `FacilityInformationSection` (Task 10); `FacilityLocationSection` (Task 11); `FacilityBrandingSection` (Task 12); `SaveStatus` (Task 8); `SubmitButton` (`@/features/auth/components/submit-button`, existing); `FormMessage` (`@/features/auth/components/form-message`, existing); `useCurrentUser` (`@/features/auth/hooks/use-auth`, existing, for `businessEmail`/`ownerId`). Note: `LeaveConfirmDialog` (Task 9) is NOT consumed here — it's wired to the Back button in Task 14's onboarding layout, not inside this form.
- Produces: `<FacilityDetailsForm />` — consumed by Task 14 (the page).

This is the integration point: it owns the `react-hook-form` instance, seeds defaults from the store's persisted `draft`, writes every change back to the store (driving `SaveStatus`), and on submit calls the mock service and navigates.

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/onboarding/components/facility-details-form.test.tsx
import { beforeEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { FacilityDetailsForm } from "@/features/onboarding/components/facility-details-form";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import { installFakeAuthService, renderWithProviders } from "@/test/harness";
import { routerMock } from "@/test/router-mock";

const VALID = {
  facilityName: "GameAll Sports Arena",
  businessPhone: "9876543210",
  addressLine: "123 Anna Salai",
  area: "Ambattur",
  city: "Chennai",
  pinCode: "600053",
};

const FAKE_USER = {
  id: "user-1",
  name: "Ravi Kumar",
  email: "owner@yourturf.com",
  emailVerified: true,
  onboardingCompleted: false,
};

/**
 * FacilityDetailsForm reads the signed-in user via useCurrentUser(), which
 * calls getCurrentUser() — the harness default for that method resolves to
 * null, so every test here must override it or the submit handler's
 * `if (!user) return;` guard will silently no-op.
 */
function installAuth() {
  return installFakeAuthService({ getCurrentUser: vi.fn(async () => FAKE_USER) });
}

async function fillValidForm(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText("Facility Name"), VALID.facilityName);
  await user.type(screen.getByLabelText("Business Contact Number"), VALID.businessPhone);
  await user.type(screen.getByLabelText("Address"), VALID.addressLine);
  await user.type(screen.getByLabelText("Area / Locality"), VALID.area);
  await user.type(screen.getByLabelText("City"), VALID.city);
  await user.click(screen.getByRole("combobox", { name: /state/i }));
  await user.click(await screen.findByRole("option", { name: "Tamil Nadu" }));
  await user.type(screen.getByLabelText("PIN Code"), VALID.pinCode);
}

describe("FacilityDetailsForm", () => {
  beforeEach(() => {
    window.localStorage.clear();
    useOnboardingStore.getState().reset();
  });

  it("keeps Continue disabled until every required field is valid", async () => {
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    const submit = await screen.findByRole("button", { name: /Continue/ });
    expect(submit).toBeDisabled();
  });

  it("reports an empty facility name on blur", async () => {
    const user = userEvent.setup();
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await user.click(await screen.findByLabelText("Facility Name"));
    await user.tab();

    expect(await screen.findByText("Facility name must be at least 2 characters")).toBeInTheDocument();
  });

  it("requires a custom type when Other is selected", async () => {
    const user = userEvent.setup();
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await user.click(await screen.findByRole("combobox", { name: /facility type/i }));
    await user.click(await screen.findByRole("option", { name: "Other" }));

    expect(await screen.findByLabelText("Specify Facility Type")).toBeInTheDocument();
  });

  it("saves the facility and navigates to Sports Setup on submit", async () => {
    const user = userEvent.setup();
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await fillValidForm(user);
    const submit = await screen.findByRole("button", { name: /Continue/ });
    await waitFor(() => expect(submit).toBeEnabled());
    await user.click(submit);

    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/sports"));
    expect(useOnboardingStore.getState().facilityDetailsCompleted).toBe(true);
  });

  it("restores a previously entered draft after remounting", async () => {
    const user = userEvent.setup();
    installAuth();
    const { unmount } = renderWithProviders(<FacilityDetailsForm />);

    await user.type(await screen.findByLabelText("Facility Name"), VALID.facilityName);
    await waitFor(() => expect(useOnboardingStore.getState().draft.facilityName).toBe(VALID.facilityName));
    unmount();

    renderWithProviders(<FacilityDetailsForm />);
    expect(await screen.findByDisplayValue(VALID.facilityName)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/onboarding/components/facility-details-form.test.tsx`
Expected: FAIL — `Cannot find module '@/features/onboarding/components/facility-details-form'`

- [ ] **Step 3: Write the implementation**

```tsx
// src/features/onboarding/components/facility-details-form.tsx
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { SubmitButton } from "@/features/auth/components/submit-button";
import { FormMessage } from "@/features/auth/components/form-message";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { FacilityInformationSection } from "@/features/onboarding/components/facility-information-section";
import { FacilityLocationSection } from "@/features/onboarding/components/facility-location-section";
import { FacilityBrandingSection } from "@/features/onboarding/components/facility-branding-section";
import { SaveStatus } from "@/features/onboarding/components/save-status";
import { DEFAULT_FACILITY_TYPE } from "@/features/onboarding/constants";
import { MockFacilityService } from "@/features/onboarding/services/mock-facility-service";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import type { FacilityType } from "@/features/onboarding/types";
import { facilityDetailsSchema, type FacilityDetailsInput } from "@/features/onboarding/validation";

export function FacilityDetailsForm() {
  const router = useRouter();
  const { data: user } = useCurrentUser();
  const draft = useOnboardingStore((s) => s.draft);
  const setDraft = useOnboardingStore((s) => s.setDraft);
  const completeFacilityDetails = useOnboardingStore((s) => s.completeFacilityDetails);
  const [logo, setLogo] = useState<File | string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);

  const {
    register,
    handleSubmit,
    watch,
    setValue,
    formState: { errors, isSubmitting, isValid },
  } = useForm<FacilityDetailsInput>({
    resolver: zodResolver(facilityDetailsSchema),
    mode: "onTouched",
    defaultValues: {
      facilityName: draft.facilityName ?? "",
      facilityType: draft.facilityType ?? DEFAULT_FACILITY_TYPE,
      customFacilityType: draft.customFacilityType ?? "",
      businessPhone: draft.businessPhone ?? "",
      addressLine: draft.addressLine ?? "",
      area: draft.area ?? "",
      city: draft.city ?? "",
      state: draft.state ?? "",
      pinCode: draft.pinCode ?? "",
      description: draft.description ?? "",
    },
  });

  const values = watch();
  const facilityType = watch("facilityType");
  const state = watch("state");
  const description = watch("description") ?? "";

  function persistDraft(patch: Partial<FacilityDetailsInput>) {
    setDraft(patch);
  }

  const onSubmit = async (input: FacilityDetailsInput) => {
    if (!user) return;
    setSaveError(null);

    try {
      const facility = await MockFacilityService.saveFacility({
        ownerId: user.id,
        name: input.facilityName.trim(),
        // Safe: zod validated facilityType against the same literal values as FacilityType.
        type: input.facilityType as FacilityType,
        customType: input.facilityType === "OTHER" ? input.customFacilityType : undefined,
        businessEmail: user.email,
        businessPhone: input.businessPhone.trim(),
        address: {
          line1: input.addressLine.trim(),
          area: input.area.trim(),
          city: input.city.trim(),
          state: input.state,
          country: "India",
          pinCode: input.pinCode,
        },
        logoUrl: typeof logo === "string" ? logo : undefined,
        description: input.description?.trim() || undefined,
      });

      completeFacilityDetails(facility);
      router.push("/onboarding/sports");
    } catch {
      setSaveError("We couldn't save your facility details. Please try again.");
    }
  };

  return (
    <form
      onSubmit={handleSubmit(onSubmit)}
      onChange={() => persistDraft(values)}
      className="space-y-8"
      noValidate
    >
      {saveError && <FormMessage>{saveError}</FormMessage>}

      <section className="space-y-4 rounded-xl border border-border bg-card p-5 sm:p-6">
        <h2 className="text-sm font-semibold">Facility Information</h2>
        <FacilityInformationSection
          register={register}
          errors={errors}
          facilityType={facilityType}
          onFacilityTypeChange={(value) => {
            setValue("facilityType", value as FacilityDetailsInput["facilityType"], {
              shouldValidate: true,
            });
            persistDraft({ facilityType: value as FacilityDetailsInput["facilityType"] });
          }}
          businessEmail={user?.email ?? ""}
        />
      </section>

      <section className="space-y-4 rounded-xl border border-border bg-card p-5 sm:p-6">
        <h2 className="text-sm font-semibold">Facility Location</h2>
        <FacilityLocationSection
          register={register}
          errors={errors}
          state={state}
          onStateChange={(value) => {
            setValue("state", value, { shouldValidate: true });
            persistDraft({ state: value });
          }}
        />
      </section>

      <section className="space-y-4 rounded-xl border border-border bg-card p-5 sm:p-6">
        <h2 className="text-sm font-semibold">Facility Branding</h2>
        <p className="text-xs text-muted-foreground">Optional — you can add these later.</p>
        <FacilityBrandingSection
          description={description}
          onDescriptionChange={(value) => {
            setValue("description", value);
            persistDraft({ description: value });
          }}
          logo={logo}
          onLogoChange={setLogo}
        />
      </section>

      <div className="flex items-center justify-between gap-4">
        <SaveStatus dirtyToken={JSON.stringify(values)} />
        <SubmitButton
          pending={isSubmitting}
          disabled={!isValid}
          pendingLabel="Saving…"
          className="w-auto sm:min-w-[10rem]"
        >
          Continue →
        </SubmitButton>
      </div>
    </form>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/onboarding/components/facility-details-form.test.tsx`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/onboarding/components/facility-details-form.tsx src/features/onboarding/components/facility-details-form.test.tsx
git commit -m "feat(onboarding): add FacilityDetailsForm integration"
```

---

## Task 14: Onboarding route — layout, facility page, sports placeholder

**Files:**
- Create: `src/app/onboarding/layout.tsx`
- Create: `src/app/onboarding/facility/page.tsx`
- Create: `src/app/onboarding/sports/page.tsx`

**Interfaces:**
- Consumes: `OnboardingProgress` (Task 7), `FacilityDetailsForm` (Task 13), `LeaveConfirmDialog` (Task 9), `useOnboardingStore` (Task 3)
- Produces: the `/onboarding/facility` and `/onboarding/sports` routes.

No new automated test in this task — page/layout wiring in this codebase is verified by the component tests underneath plus a manual pass (Task 16). Follow this exactly; there is nothing to infer.

- [ ] **Step 1: Write `src/app/onboarding/layout.tsx`**

```tsx
// src/app/onboarding/layout.tsx
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { OnboardingProgress } from "@/features/onboarding/components/onboarding-progress";
import { LeaveConfirmDialog } from "@/features/onboarding/components/leave-confirm-dialog";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";

export default function OnboardingLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const currentStep = useOnboardingStore((s) => s.currentStep);
  const draft = useOnboardingStore((s) => s.draft);
  const [confirmOpen, setConfirmOpen] = useState(false);

  const hasUnsavedProgress = Object.values(draft).some((value) => Boolean(value));

  function handleBack() {
    if (hasUnsavedProgress) {
      setConfirmOpen(true);
      return;
    }
    router.replace("/login");
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
        onLeave={() => router.replace("/login")}
      />
    </div>
  );
}
```

- [ ] **Step 2: Write `src/app/onboarding/facility/page.tsx`**

```tsx
// src/app/onboarding/facility/page.tsx
import type { Metadata } from "next";
import { FacilityDetailsForm } from "@/features/onboarding/components/facility-details-form";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Facility Details — ${PRODUCT_NAME}`,
};

export default function FacilityDetailsPage() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">
          Let&apos;s set up your facility
        </h1>
        <p className="mt-2 text-sm text-muted-foreground sm:text-base">
          Tell us a little about your facility. You can update these details later.
        </p>
      </div>

      <FacilityDetailsForm />
    </div>
  );
}
```

- [ ] **Step 3: Write `src/app/onboarding/sports/page.tsx`**

```tsx
// src/app/onboarding/sports/page.tsx
import type { Metadata } from "next";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Sports Setup — ${PRODUCT_NAME}`,
};

export default function SportsSetupPlaceholderPage() {
  return (
    <div className="space-y-2 text-center">
      <h1 className="text-2xl font-semibold tracking-tight">Sports Setup — Coming Next</h1>
      <p className="text-sm text-muted-foreground">
        Great! Now let&apos;s add the sports you operate. This step is being built next.
      </p>
    </div>
  );
}
```

- [ ] **Step 4: Manual verification**

Run: `npm run dev`, sign in with a test account, and confirm:
- `/onboarding/facility` renders the shell (Back + progress + heading + three sections)
- Selecting "Other" as facility type reveals "Specify Facility Type"
- Filling every required field enables Continue; submitting navigates to `/onboarding/sports`
- Refreshing mid-fill restores the entered values

- [ ] **Step 5: Commit**

```bash
git add src/app/onboarding
git commit -m "feat(onboarding): add onboarding layout, facility page, and sports placeholder"
```

---

## Task 15: Wire entry-route and splash screen

**Files:**
- Modify: `src/features/auth/entry-route.ts`
- Modify: `src/features/auth/entry-route.test.ts`
- Modify: `src/features/auth/components/splash-screen.tsx`
- Modify: `src/app/page.tsx`

**Interfaces:**
- Consumes: `getCurrentAuthUser` (`@/features/auth/api/auth.api`, existing, already request-cached)
- Produces: `resolveEntryRoute({ signedIn, deviceOnboarded, onboardingCompleted })` — the new third parameter.

- [ ] **Step 1: Update the failing/changed tests first**

Replace the `resolveEntryRoute` describe block in `src/features/auth/entry-route.test.ts`:

```ts
// src/features/auth/entry-route.test.ts (resolveEntryRoute block only — safeRedirectPath block unchanged)
describe("resolveEntryRoute", () => {
  it("sends a first-time visitor from splash to welcome", () => {
    expect(
      resolveEntryRoute({ signedIn: false, deviceOnboarded: false, onboardingCompleted: false }),
    ).toBe("/welcome");
  });

  it("sends a returning signed-out visitor from splash to login", () => {
    expect(
      resolveEntryRoute({ signedIn: false, deviceOnboarded: true, onboardingCompleted: false }),
    ).toBe("/login");
  });

  it("sends a signed-in, fully onboarded user from splash to the dashboard", () => {
    expect(
      resolveEntryRoute({ signedIn: true, deviceOnboarded: true, onboardingCompleted: true }),
    ).toBe("/dashboard");
  });

  it("sends a signed-in user who hasn't finished facility setup to onboarding", () => {
    expect(
      resolveEntryRoute({ signedIn: true, deviceOnboarded: true, onboardingCompleted: false }),
    ).toBe("/onboarding/facility");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/auth/entry-route.test.ts`
Expected: FAIL — `resolveEntryRoute` doesn't accept/use `onboardingCompleted` yet, so the new "hasn't finished facility setup" case returns `/dashboard` instead of `/onboarding/facility`.

- [ ] **Step 3: Update `entry-route.ts`**

```ts
// src/features/auth/entry-route.ts
import type { EntryRoute } from "@/features/auth/types";

/**
 * The splash screen's routing decision, kept separate from the component so the
 * rule is testable on its own:
 *
 *   signed in, onboarding incomplete → facility onboarding
 *   signed in, onboarding complete   → dashboard
 *   signed out, returning            → login
 *   signed out, first run            → welcome
 */
export function resolveEntryRoute({
  signedIn,
  deviceOnboarded,
  onboardingCompleted,
}: {
  signedIn: boolean;
  deviceOnboarded: boolean;
  onboardingCompleted: boolean;
}): EntryRoute {
  if (signedIn) return onboardingCompleted ? "/dashboard" : "/onboarding/facility";
  return deviceOnboarded ? "/login" : "/welcome";
}
```

- [ ] **Step 4: Update `EntryRoute` type**

In `src/features/auth/types.ts`, change:

```ts
export type EntryRoute = "/welcome" | "/login" | "/dashboard";
```

to:

```ts
export type EntryRoute = "/welcome" | "/login" | "/dashboard" | "/onboarding/facility";
```

- [ ] **Step 5: Run test to verify it passes**

Run: `npx vitest run src/features/auth/entry-route.test.ts`
Expected: PASS (6 tests)

- [ ] **Step 6: Update `SplashScreen` and the root page**

In `src/features/auth/components/splash-screen.tsx`, change the props and the `resolveEntryRoute` call:

```tsx
// src/features/auth/components/splash-screen.tsx
export function SplashScreen({
  signedIn,
  onboardingCompleted,
}: {
  signedIn: boolean;
  onboardingCompleted: boolean;
}) {
  const router = useRouter();

  useEffect(() => {
    const next = resolveEntryRoute({
      signedIn,
      deviceOnboarded: hasDeviceOnboarded(),
      onboardingCompleted,
    });
    router.prefetch(next);

    const timer = window.setTimeout(() => router.replace(next), SPLASH_DURATION_MS);
    return () => window.clearTimeout(timer);
  }, [router, signedIn, onboardingCompleted]);

  // ...rest of the component is unchanged
```

In `src/app/page.tsx`, fetch the cached auth user instead of only the boolean:

```tsx
// src/app/page.tsx
import { getCurrentAuthUser } from "@/features/auth/api/auth.api";
import { SplashScreen } from "@/features/auth/components/splash-screen";

export default async function RootPage() {
  const user = await getCurrentAuthUser();

  return <SplashScreen signedIn={Boolean(user)} onboardingCompleted={user?.onboardingCompleted ?? false} />;
}
```

- [ ] **Step 7: Run the full auth test suite to confirm nothing else broke**

Run: `npx vitest run src/features/auth`
Expected: PASS (all files, including the unchanged `splash-screen` has no dedicated test file — confirm with `ls src/features/auth/components/*.test.tsx` that none references `SplashScreen`'s old single-prop signature)

- [ ] **Step 8: Commit**

```bash
git add src/features/auth/entry-route.ts src/features/auth/entry-route.test.ts src/features/auth/types.ts src/features/auth/components/splash-screen.tsx src/app/page.tsx
git commit -m "feat(onboarding): route onboarding-incomplete users from splash to facility setup"
```

---

## Task 16: Wire login/signup redirects

**Files:**
- Modify: `src/features/auth/hooks/use-auth.ts`
- Modify: `src/test/harness.tsx`
- Modify: `src/features/auth/components/login-form.test.tsx`
- Modify: `src/features/auth/components/signup-form.test.tsx`

**Interfaces:**
- Consumes: `AuthUser.onboardingCompleted` (existing field, already present on the type and on every service implementation)

- [ ] **Step 1: Update the harness default and existing tests first**

In `src/test/harness.tsx`, the default fake `login` mock currently returns `onboardingCompleted: false`. Change it to `true` — the harness default now represents a normal *returning, fully-onboarded* user, which is what every existing test outside this task actually exercises:

```ts
// src/test/harness.tsx — inside installFakeAuthService, the login mock:
login: vi.fn(async ({ email }) => ({
  id: "user-1",
  name: "Ravi Kumar",
  email,
  emailVerified: true,
  onboardingCompleted: true,
})),
```

In `src/features/auth/components/login-form.test.tsx`, add a new test case (keep the existing "signs in and opens the dashboard" test as-is — it now passes against the new `true` default):

```tsx
// src/features/auth/components/login-form.test.tsx — add to the describe block
it("sends an onboarding-incomplete user to facility setup instead of the dashboard", async () => {
  const user = userEvent.setup();
  installFakeAuthService({
    login: vi.fn(async ({ email }) => ({
      id: "user-1",
      name: "Ravi Kumar",
      email,
      emailVerified: true,
      onboardingCompleted: false,
    })),
  });
  renderWithProviders(<LoginForm />);

  await signIn(user);

  await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/facility"));
});
```

Add `vi` to the existing `vitest` import at the top of that file if it isn't already imported (it is not — `login-form.test.tsx` currently imports only `describe, expect, it`):

```ts
import { describe, expect, it, vi } from "vitest";
```

In `src/features/auth/components/signup-form.test.tsx`, add one new test case for the active-session branch (today `register()` never has a test exercising `sessionActive: true`, so this is additive, nothing else changes):

```tsx
// src/features/auth/components/signup-form.test.tsx — add to the describe block
it("sends a brand-new account straight to facility setup when the session is already active", async () => {
  const user = userEvent.setup();
  const service = installFakeAuthService({
    register: vi.fn(async ({ email }) => ({ email, sessionActive: true })),
  });
  renderWithProviders(<SignupForm />);

  await fillValidForm(user);
  await user.click(await screen.findByRole("button", { name: "Create Account" }));

  await waitFor(() => expect(service.register).toHaveBeenCalled());
  await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/facility"));
});
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `npx vitest run src/features/auth/components/login-form.test.tsx src/features/auth/components/signup-form.test.tsx`
Expected: the two new tests FAIL (redirect still goes to `/dashboard`); every pre-existing test still PASSes because of the harness default change in Step 1.

- [ ] **Step 3: Update `use-auth.ts`**

```ts
// src/features/auth/hooks/use-auth.ts — useSignup's onSuccess
onSuccess: (result) => {
  markDeviceOnboarded();
  if (result.sessionActive) {
    // A brand-new account can never have completed onboarding yet.
    router.replace("/onboarding/facility");
    router.refresh();
    return;
  }
  router.push(`/verify-email?email=${encodeURIComponent(result.email)}`);
},
```

```ts
// src/features/auth/hooks/use-auth.ts — useLogin's onSuccess
onSuccess: async (user) => {
  markDeviceOnboarded();
  queryClient.setQueryData(CURRENT_USER_KEY, user);
  router.replace(user.onboardingCompleted ? "/dashboard" : "/onboarding/facility");
  // Server components hold the old (signed-out) session until refreshed.
  router.refresh();
},
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run src/features/auth`
Expected: PASS (all files)

- [ ] **Step 5: Commit**

```bash
git add src/features/auth/hooks/use-auth.ts src/test/harness.tsx src/features/auth/components/login-form.test.tsx src/features/auth/components/signup-form.test.tsx
git commit -m "feat(onboarding): redirect onboarding-incomplete accounts to facility setup after sign in"
```

---

## Task 17: Full verification pass

**Files:** none created — this task only runs checks and fixes anything they surface.

- [ ] **Step 1: Typecheck**

Run: `npx tsc --noEmit`
Expected: no errors. If any appear in files touched by this plan, fix them before proceeding.

- [ ] **Step 2: Full test suite**

Run: `npx vitest run`
Expected: every test file passes, including all pre-existing auth/dashboard/members suites untouched by this plan.

- [ ] **Step 3: Lint**

Run: `npm run lint`
Expected: no new errors in files touched by this plan.

- [ ] **Step 4: Manual responsive pass**

Use the `run` skill (or `npm run dev`) to check `/onboarding/facility` at 375px, 768px, and 1440px widths:
- No horizontal overflow at any width
- Two-column field pairs (name/type, area/city, state/PIN) collapse to one column below `sm`
- The desktop stepper (`onboarding-progress.tsx`'s `hidden md:flex` block) is hidden below `md`; the mobile compact bar (`md:hidden`) is hidden at/above `md`
- Continue button is full-width on mobile, auto-width on desktop, and never clipped off-screen

- [ ] **Step 5: Confirm existing flows are unbroken**

Manually walk: Splash → Welcome → Create Account → (mock/real) Sign In → lands on `/onboarding/facility` for a fresh account. Then sign in again with an account that already completed onboarding and confirm it still lands on `/dashboard`.

- [ ] **Step 6: Final commit (only if Steps 1–3 required fixes)**

```bash
git add -A
git commit -m "fix(onboarding): address verification pass findings"
```

If no fixes were needed, skip this step — there is nothing to commit.

---

## Self-Review Notes

- **Spec coverage:** every spec section (§3 routing, §4 title/subtitle in Task 14, §5 progress in Task 7, §6–§17 field-by-field in Tasks 10–12, §18 sections in Task 13, §19–§20 Continue/Back in Tasks 13/14, §21–§23 persistence/autosave/leave in Tasks 3/8/9, §24 validation UX in Task 2/13, §25 continue flow in Task 13, §26 onboarding state in Task 3, §27–§28 data model in Task 1, §37 accessibility woven through TextField/SelectField/FileUpload reuse, §41 mock service in Task 4, §42 testing in every task) has a task. §29–§31 (future multi-facility/DB relationship, role consideration) are architecture notes already satisfied by `ownerId` on `Facility` (Task 1) — no separate task needed, nothing further to build now.
- **No placeholders:** every step has real, complete code — confirmed by re-reading each task.
- **Type consistency:** `FacilityDetailsInput` (Task 2) is the single form-values type threaded through Tasks 3, 10, 11, 13. `Facility`/`FacilityInput` (Task 1) is the single persisted-record type threaded through Tasks 3, 4, 13. Store field names (`draft`, `setDraft`, `completeFacilityDetails`, `facilityDetailsCompleted`, `currentStep`) match between Task 3's definition and every consumer in Tasks 13–14.