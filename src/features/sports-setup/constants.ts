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