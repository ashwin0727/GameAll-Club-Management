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
    { name: "turf.onboarding.v1", skipHydration: true },
  ),
);
