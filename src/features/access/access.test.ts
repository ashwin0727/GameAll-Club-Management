import { describe, expect, it } from "vitest";
import { ACCESS_PAGES, COACHING_OWN_ONLY, accessPage, editorLevelFor, expandAccess, levelFor, levelsFromKeys } from "./access";
import { pageForPath } from "./routes";

const page = (k: string) => accessPage(k)!;
const held = (...keys: string[]) => new Set(keys);

describe("page access levels", () => {
  it("owners are Edit everywhere; a role with no keys is None everywhere", () => {
    for (const p of ACCESS_PAGES) {
      expect(levelFor(p, held(), true)).toBe("edit");
      expect(levelFor(p, held(), false)).toBe("none");
    }
  });

  it("View keys alone give View; any Edit key gives Edit; a page without Edit keys never goes past View", () => {
    const guests = page("GUEST_BOOKINGS");
    expect(levelFor(guests, held("GUEST_BOOKINGS_VIEW"), false)).toBe("view");
    expect(levelFor(guests, held("GUEST_BOOKINGS_VIEW", "GUEST_BOOKINGS_CREATE"), false)).toBe("edit");
    expect(levelFor(guests, held("GUEST_BOOKINGS_CREATE"), false)).toBe("none"); // no View → hidden regardless
    expect(levelFor(page("HOME"), held("DASHBOARD_VIEW"), false)).toBe("view");
  });

  it("the editor distinguishes a half-edit role as custom", () => {
    const cal = page("CALENDAR");
    const base = ["BOOKINGS_VIEW", "COURTS_VIEW"];
    expect(editorLevelFor(cal, held(...base))).toBe("view");
    expect(editorLevelFor(cal, held(...base, "BOOKINGS_CREATE"))).toBe("custom");
    expect(editorLevelFor(cal, held(...base, ...cal.editKeys))).toBe("edit");
  });
});

describe("expanding the matrix into permission keys", () => {
  it("View grants only View keys, Edit adds the Edit keys, None grants nothing", () => {
    const keys = new Set(expandAccess({ CALENDAR: "edit", GUEST_PLAYERS: "view", FINANCE_PNL: "none" }, new Set(), false));
    expect(keys.has("BOOKINGS_CANCEL")).toBe(true);
    expect(keys.has("GUEST_PLAYERS_VIEW")).toBe(true);
    expect(keys.has("GUEST_PLAYERS_EDIT")).toBe(false);
    expect(keys.has("FINANCE_VIEW_PNL")).toBe(false);
  });

  it("round-trips through levelsFromKeys", () => {
    const levels = { CALENDAR: "edit", MEMBERSHIP_PLANS: "view", REPORT_REVENUE: "edit" } as const;
    const keys = new Set(expandAccess({ ...levels }, new Set(), false));
    const back = levelsFromKeys(keys);
    expect(back.CALENDAR).toBe("edit");
    expect(back.MEMBERSHIP_PLANS).toBe("view");
    expect(back.REPORT_REVENUE).toBe("edit");
    expect(back.FINANCE_EXPENSES).toBe("none");
  });

  it("keeps unmanaged keys, drops extras of a hidden page, and adds the coach restriction only when asked", () => {
    const keep = new Set(["INVENTORY_VIEW", "BOOKINGS_VIEW_CUSTOMER"]);
    const keys = new Set(expandAccess({ CALENDAR: "none" }, new Set(["BOOKINGS_VIEW_CUSTOMER"]), false, keep));
    expect(keys.has("INVENTORY_VIEW")).toBe(true);
    expect(keys.has("BOOKINGS_VIEW_CUSTOMER")).toBe(false);
    expect(expandAccess({}, new Set(), true)).toContain(COACHING_OWN_ONLY);
    expect(expandAccess({}, new Set(), false)).not.toContain(COACHING_OWN_ONLY);
  });

  it("leaves a custom page exactly as it was", () => {
    const keep = new Set(["BOOKINGS_VIEW", "COURTS_VIEW", "BOOKINGS_CREATE"]);
    const keys = new Set(expandAccess({ CALENDAR: "custom" }, new Set(), false, keep));
    expect(keys).toEqual(keep);
  });
});

describe("which page guards a URL", () => {
  it("maps the sub-pages to their own page and write routes to Edit", () => {
    expect(pageForPath("/dashboard")).toEqual({ page: "HOME", needs: "view" });
    expect(pageForPath("/memberships/v1/plans")).toEqual({ page: "MEMBERSHIP_PLANS", needs: "view" });
    expect(pageForPath("/memberships/v1/plans/new")).toEqual({ page: "MEMBERSHIP_PLANS", needs: "edit" });
    expect(pageForPath("/memberships/v1")?.page).toBe("MEMBERSHIP_DASHBOARD");
    expect(pageForPath("/coaching/sessions/new")).toEqual({ page: "COACHING_SESSIONS", needs: "edit" });
    expect(pageForPath("/coaching")?.page).toBe("COACHING_OVERVIEW");
    expect(pageForPath("/finance/pending-payments/abc/record")).toEqual({ page: "FINANCE_PAYMENTS", needs: "edit" });
    expect(pageForPath("/users-roles/roles/123/edit")).toEqual({ page: "ROLES", needs: "edit" });
  });

  it("leaves unguarded pages open", () => {
    expect(pageForPath("/profile")).toBeNull();
    expect(pageForPath("/profile/personal")).toBeNull();
    expect(pageForPath("/profile/facility")?.page).toBe("FACILITY_SETTINGS");
  });
});
