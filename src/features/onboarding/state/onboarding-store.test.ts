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
