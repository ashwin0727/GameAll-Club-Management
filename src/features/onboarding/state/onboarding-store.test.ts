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
  onboardingStep: "FACILITY_DETAILS" as const,
  createdAt: "2026-08-20T00:00:00.000Z",
  updatedAt: "2026-08-20T00:00:00.000Z",
  membershipAccessDays: [0, 1, 2, 3, 4, 5, 6],
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
