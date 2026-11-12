import { describe, expect, it } from "vitest";
import { applyToSport, newCourtDraft, nextCourtName, validateCourtDrafts, type CourtDraft } from "@/features/courts-setup/court-draft";
import { courtDefaultsFor, surfaceOptionsFor } from "@/features/courts-setup/constants";

const draft = (over: Partial<CourtDraft> = {}): CourtDraft => ({
  id: "c1",
  sportId: "s-bad",
  name: "Badminton Court 1",
  type: "INDOOR",
  surface: "Wooden",
  lighting: "LED",
  amenities: [],
  ...over,
});

const SPORTS = [{ id: "s-bad", name: "Badminton", code: "BADMINTON" }];

describe("court names", () => {
  it("numbers from the highest used number, not the count", () => {
    expect(nextCourtName("BADMINTON", [])).toBe("Court 1");
    expect(nextCourtName("BADMINTON", ["Court 1", "Court 2"])).toBe("Court 3");
    expect(nextCourtName("BADMINTON", ["Court 2"])).toBe("Court 3"); // Court 1 was removed
    expect(nextCourtName("CRICKET", ["Turf 1"])).toBe("Turf 2");
  });
});

describe("a new court", () => {
  it("starts from the sport's usual settings", () => {
    const c = newCourtDraft({ id: "n", sportId: "s-bad", sportCode: "BADMINTON", sportName: "Badminton", existing: [] });
    expect(c).toMatchObject({ name: "Badminton Court 1", type: "INDOOR", surface: "Wooden", lighting: "LED", amenities: [] });
    const f = newCourtDraft({ id: "n", sportId: "s-foot", sportCode: "FOOTBALL", sportName: "Football", existing: [] });
    expect(f).toMatchObject({ name: "Football Turf 1", type: "OUTDOOR", surface: "Artificial Turf", lighting: "FLOODLIGHT" });
  });

  it("copies the sport's last court, so adding another is one click", () => {
    const first = draft({ id: "c1", surface: "Synthetic (PU)", lighting: "FLOODLIGHT", amenities: ["ac", "shower"] });
    const second = newCourtDraft({ id: "c2", sportId: "s-bad", sportCode: "BADMINTON", sportName: "Badminton", existing: [first] });
    expect(second).toMatchObject({ name: "Badminton Court 2", surface: "Synthetic (PU)", lighting: "FLOODLIGHT", amenities: ["ac", "shower"] });
    expect(second.amenities).not.toBe(first.amenities); // a copy, not shared
  });

  it("other sports' courts are not copied", () => {
    const cricket = draft({ id: "x", sportId: "s-cri", surface: "Turf" });
    const c = newCourtDraft({ id: "n", sportId: "s-bad", sportCode: "BADMINTON", sportName: "Badminton", existing: [cricket] });
    expect(c.surface).toBe("Wooden");
  });
});

describe("bulk apply", () => {
  it("changes every court of that sport and leaves the others alone", () => {
    const list = [draft({ id: "a" }), draft({ id: "b" }), draft({ id: "c", sportId: "s-cri", surface: "Turf" })];
    const out = applyToSport(list, "s-bad", { type: "OUTDOOR", amenities: ["locker"] });
    expect(out.filter((c) => c.sportId === "s-bad").every((c) => c.type === "OUTDOOR" && c.amenities.join() === "locker")).toBe(true);
    expect(out[2]).toEqual(list[2]);
  });
});

describe("validation", () => {
  it("accepts a complete court", () => {
    expect(validateCourtDrafts([draft()], SPORTS).ok).toBe(true);
  });

  it("needs a name of 2-50 characters, unique within the sport", () => {
    expect(validateCourtDrafts([draft({ name: "" })], SPORTS).byCourt["c1"]?.name).toBe("Name must be between 2 and 50 characters.");
    expect(validateCourtDrafts([draft({ name: "x".repeat(51) })], SPORTS).ok).toBe(false);
    const dupes = validateCourtDrafts([draft({ id: "a", name: "Court A" }), draft({ id: "b", name: "court a" })], SPORTS);
    expect(dupes.byCourt["b"]?.name).toBe("This name is already used for this sport.");
    expect(dupes.byCourt["a"]).toBeUndefined();
  });

  it("the same name is fine on two different sports", () => {
    const sports = [...SPORTS, { id: "s-cri", name: "Cricket", code: "CRICKET" }];
    const ok = validateCourtDrafts([draft({ id: "a", name: "Net 1" }), draft({ id: "b", sportId: "s-cri", name: "Net 1" })], sports);
    expect(ok.ok).toBe(true);
  });

  it("needs a surface and lighting", () => {
    const r = validateCourtDrafts([draft({ surface: " ", lighting: "" })], SPORTS);
    expect(r.byCourt["c1"]).toMatchObject({ surface: "Select a surface.", lighting: "Select lighting." });
  });

  it("every selected sport needs at least one court", () => {
    const r = validateCourtDrafts([], [...SPORTS, { id: "s-foot", name: "Football", code: "FOOTBALL" }]);
    expect(r.bySport["s-bad"]).toBe("Add at least one court for Badminton.");
    expect(r.bySport["s-foot"]).toBe("Add at least one turf for Football.");
    expect(r.ok).toBe(false);
  });
});

describe("option lists", () => {
  it("every sport offers its own surfaces, and defaults are among them", () => {
    for (const code of ["BADMINTON", "PICKLEBALL", "TENNIS", "CRICKET", "FOOTBALL", "BASKETBALL"]) {
      expect(surfaceOptionsFor(code)).toContain(courtDefaultsFor(code).surface);
    }
    expect(surfaceOptionsFor("OTHER").length).toBeGreaterThan(2);
  });
});
