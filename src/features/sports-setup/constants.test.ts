import { describe, expect, it } from "vitest";
import { OTHER_SPORT_CODE, SINGLE_SPORT_TYPE_CODE_MAP, presentSport } from "@/features/sports-setup/constants";

const CATALOG_ROWS = [
  { id: "1", key: "badminton", name: "Badminton", is_active: true },
  { id: "2", key: "pickleball", name: "Pickleball", is_active: true },
  { id: "3", key: "cricket", name: "Cricket", is_active: true },
  { id: "4", key: "football", name: "Football", is_active: true },
  { id: "5", key: "tennis", name: "Tennis", is_active: true },
  { id: "6", key: "other", name: "Other", is_active: true },
];

describe("sports-setup constants", () => {
  it("presents every catalog row with a non-empty icon/description, matching its uppercased key as code", () => {
    const sports = CATALOG_ROWS.map(presentSport);
    expect(sports).toHaveLength(6);
    expect(sports.every((sport) => sport.isActive)).toBe(true);
    expect(sports[sports.length - 1]?.code).toBe(OTHER_SPORT_CODE);
    for (const sport of sports) {
      expect(sport.icon.length).toBeGreaterThan(0);
      expect(sport.description.length).toBeGreaterThan(0);
      expect(sport.code).toBe(sport.code.toUpperCase());
    }
  });

  it("maps only the five single-sport facility types to a preselected sport code", () => {
    expect(SINGLE_SPORT_TYPE_CODE_MAP.BADMINTON).toBe("BADMINTON");
    expect(SINGLE_SPORT_TYPE_CODE_MAP.PICKLEBALL).toBe("PICKLEBALL");
    expect(SINGLE_SPORT_TYPE_CODE_MAP.CRICKET).toBe("CRICKET");
    expect(SINGLE_SPORT_TYPE_CODE_MAP.FOOTBALL).toBe("FOOTBALL");
    expect(SINGLE_SPORT_TYPE_CODE_MAP.TENNIS).toBe("TENNIS");
    expect(SINGLE_SPORT_TYPE_CODE_MAP.MULTI_SPORT).toBeUndefined();
    expect(SINGLE_SPORT_TYPE_CODE_MAP.OTHER).toBeUndefined();
  });
});