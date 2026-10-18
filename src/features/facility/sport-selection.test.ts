import { describe, expect, it } from "vitest";
import { resolveSportSelection, sportSelectionLabel, toggleSportSelection } from "@/features/facility/sport-selection";

const ALL = ["bad", "cri", "foo"];

describe("resolveSportSelection", () => {
  it("is All Sports by default", () => {
    expect(resolveSportSelection(null, ALL)).toEqual({ ids: ALL, isAll: true });
  });
  it("keeps an explicit subset, in the facility's own order", () => {
    expect(resolveSportSelection(["cri", "bad"], ALL)).toEqual({ ids: ["bad", "cri"], isAll: false });
  });
  it("drops ids that are not this facility's, and falls back to All when nothing is left", () => {
    expect(resolveSportSelection(["bad", "gone"], ALL)).toEqual({ ids: ["bad"], isAll: false });
    expect(resolveSportSelection(["gone"], ALL)).toEqual({ ids: ALL, isAll: true });
  });
  it("treats every sport ticked as All Sports", () => {
    expect(resolveSportSelection(["foo", "bad", "cri"], ALL).isAll).toBe(true);
  });
});

describe("toggleSportSelection", () => {
  it("unticking one sport from All leaves the others", () => {
    expect(toggleSportSelection(null, ALL, "foo")).toEqual(["bad", "cri"]);
  });
  it("ticking it back returns to All Sports (null)", () => {
    expect(toggleSportSelection(["bad", "cri"], ALL, "foo")).toBeNull();
  });
  it("never leaves nothing selected", () => {
    expect(toggleSportSelection(["bad"], ALL, "bad")).toEqual(["bad"]);
  });
  it("builds a combination one tick at a time", () => {
    let sel: ReturnType<typeof toggleSportSelection> = ["bad"];
    sel = toggleSportSelection(sel, ALL, "foo");
    expect(sel).toEqual(["bad", "foo"]);
  });
});

describe("sportSelectionLabel", () => {
  const names = new Map([["bad", "Badminton"], ["cri", "Cricket"], ["foo", "Football"]]);
  it("labels each case", () => {
    expect(sportSelectionLabel(resolveSportSelection(null, ALL), names)).toBe("All Sports");
    expect(sportSelectionLabel(resolveSportSelection(["bad"], ALL), names)).toBe("Badminton");
    expect(sportSelectionLabel(resolveSportSelection(["bad", "cri"], ALL), names)).toBe("Badminton, Cricket");
    expect(sportSelectionLabel(resolveSportSelection(["bad", "cri", "foo"], ["bad", "cri", "foo", "ten"]), names)).toBe("Badminton +2");
  });
});
