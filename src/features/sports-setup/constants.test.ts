import { describe, expect, it } from "vitest";
import { AVAILABLE_SPORTS, OTHER_SPORT_ID, SINGLE_SPORT_TYPE_MAP } from "@/features/sports-setup/constants";

describe("sports-setup constants", () => {
  it("lists exactly six sports, each active, ending with Other", () => {
    expect(AVAILABLE_SPORTS).toHaveLength(6);
    expect(AVAILABLE_SPORTS.every((sport) => sport.isActive)).toBe(true);
    expect(AVAILABLE_SPORTS[AVAILABLE_SPORTS.length - 1]!.id).toBe(OTHER_SPORT_ID);
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