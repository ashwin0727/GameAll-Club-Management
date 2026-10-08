import { describe, expect, it } from "vitest";
import { NAV_GROUP_LABELS, NAV_GROUP_ORDER, NAV_ITEMS } from "@/lib/constants";
import { activeHrefFor } from "@/lib/nav-active";

const labelsIn = (group: (typeof NAV_GROUP_ORDER)[number]) => NAV_ITEMS.filter((i) => i.group === group).map((i) => i.label);

describe("sidebar menu structure", () => {
  it("lists the sections in the agreed order with the agreed headings", () => {
    expect(NAV_GROUP_ORDER.map((g) => NAV_GROUP_LABELS[g])).toEqual([
      null,
      "Guest Management",
      "Memberships Management",
      "Coaching Management",
      "Maintenance Management",
      "Staff Management",
      "Inventory Management",
      "Finance",
    ]);
  });

  it("has exactly the agreed items in each section", () => {
    expect(labelsIn("main")).toEqual(["Home", "Calendar", "Tournaments"]);
    expect(labelsIn("guest")).toEqual(["Guest Booking", "Guest Players"]);
    expect(labelsIn("memberships")).toEqual(["Dashboard", "Membership Schedule", "Membership Sessions", "Members"]);
    expect(labelsIn("coaching")).toEqual(["Coaching", "Program", "Students", "Report"]);
    expect(labelsIn("maintenance")).toEqual(["Maintenance", "Maintenance Tracker", "Issue Category"]);
    expect(labelsIn("staff")).toEqual(["Staff", "Roles & Permission", "Access History"]);
    expect(labelsIn("inventory")).toEqual(["Inventory Tracker", "Items", "Stock Movement", "Purchase Orders", "Vendors", "Categories"]);
  });

  it("no longer lists Court Schedule anywhere", () => {
    const all = NAV_ITEMS.flatMap((i) => [i.label, ...(i.children ?? []).map((c) => c.label)]);
    expect(all).not.toContain("Court Schedule");
    expect(NAV_ITEMS.some((i) => i.href === "/maintenance/court-schedule")).toBe(false);
  });

  it("only the Finance group still nests pages; every other section is flat", () => {
    for (const item of NAV_ITEMS) {
      if (item.group !== "finance") expect(item.children).toBeUndefined();
    }
  });

  it("keeps the permission gates on the sections that had them", () => {
    for (const i of NAV_ITEMS.filter((x) => x.group === "coaching")) expect(i.permission).toBe("COACHING_VIEW");
    for (const i of NAV_ITEMS.filter((x) => x.group === "staff")) expect(i.permission).toBe("USERS_VIEW");
    for (const i of NAV_ITEMS.filter((x) => x.group === "inventory")) expect(i.permission).toBe("INVENTORY_VIEW");
  });
});

describe("activeHrefFor — the most specific entry wins", () => {
  const hrefs = NAV_ITEMS.flatMap((i) => [i.href, ...(i.children ?? []).map((c) => c.href)]);

  it("lights only the child, not the parent that shares its prefix", () => {
    expect(activeHrefFor("/coaching", hrefs)).toBe("/coaching");
    expect(activeHrefFor("/coaching/programs", hrefs)).toBe("/coaching/programs");
    expect(activeHrefFor("/coaching/programs/abc-123", hrefs)).toBe("/coaching/programs");
    expect(activeHrefFor("/coaching/students/new", hrefs)).toBe("/coaching/students");
    expect(activeHrefFor("/maintenance/tickets/42", hrefs)).toBe("/maintenance/tickets");
    expect(activeHrefFor("/inventory/purchase-orders/7", hrefs)).toBe("/inventory/purchase-orders");
  });

  it("keeps Members, Dashboard and Membership Schedule distinct", () => {
    expect(activeHrefFor("/memberships", hrefs)).toBe("/memberships");
    expect(activeHrefFor("/memberships/new", hrefs)).toBe("/memberships");
    expect(activeHrefFor("/memberships/v1", hrefs)).toBe("/memberships/v1");
    expect(activeHrefFor("/memberships/v1/schedule", hrefs)).toBe("/memberships/v1/schedule");
  });

  it("falls back to the nearest parent for a page with no entry (Court Schedule)", () => {
    expect(activeHrefFor("/maintenance/court-schedule", hrefs)).toBe("/maintenance");
  });

  it("never matches a sibling that merely shares a string prefix", () => {
    expect(activeHrefFor("/guests", hrefs)).toBe("/guests");
    expect(activeHrefFor("/guest-bookings", hrefs)).toBe("/guest-bookings");
    expect(activeHrefFor("/unknown-page", hrefs)).toBeNull();
  });

  it("resolves Finance sub-pages", () => {
    expect(activeHrefFor("/finance", hrefs)).toBe("/finance");
    expect(activeHrefFor("/finance/expenses", hrefs)).toBe("/finance/expenses");
    expect(activeHrefFor("/refunds", hrefs)).toBe("/refunds");
  });
});
