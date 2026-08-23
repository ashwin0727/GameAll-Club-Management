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
  completeCourts: () => void;
  completeOperatingHours: () => void;
  completePricing: () => void;
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
      completeCourts: () =>
        set((s) => ({
          courtsCompleted: true,
          currentStep: 4,
          completedSteps: s.completedSteps.includes(3) ? s.completedSteps : [...s.completedSteps, 3],
        })),
      completeOperatingHours: () =>
        set((s) => ({
          operatingHoursCompleted: true,
          currentStep: 5,
          completedSteps: s.completedSteps.includes(4) ? s.completedSteps : [...s.completedSteps, 4],
        })),
      completePricing: () => set({ pricingCompleted: true }),
      reset: () => set({ ...INITIAL_STATE }),
    }),
    { name: "turf.onboarding.v1", skipHydration: true },
  ),
);
