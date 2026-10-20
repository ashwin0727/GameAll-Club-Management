import { describe, expect, it } from "vitest";
import { INVENTORY_ENABLED, NAV_GROUP_LABELS, NAV_GROUP_ORDER, NAV_ITEMS } from "@/lib/constants";
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
      "Finance Management",
      "Report & Analytics Management",
    ]);
  });

  it("has exactly the agreed items in each section", () => {
    expect(labelsIn("main")).toEqual(["Home", "Calendar", "Tournaments"]);
    expect(labelsIn("guest")).toEqual(["Guest Booking", "Guest Players"]);
    expect(labelsIn("memberships")).toEqual(["Dashboard", "Membership Schedule", "Membership Plan", "Membership Sessions"]);
    expect(labelsIn("coaching")).toEqual(["Coaching", "Program", "Students", "Coaching Schedule", "Report"]);
    expect(labelsIn("maintenance")).toEqual(["Maintenance", "Maintenance Tracker", "Issue Category"]);
    expect(labelsIn("staff")).toEqual(["Staff", "Roles & Permission", "Access History"]);
    expect(labelsIn("finance")).toEqual(["Overview", "Transactions", "Payments", "Expenses", "Daily Closing", "P&L", "Refunds"]);
    expect(labelsIn("reports")).toEqual(["Overview", "Court Utilization", "Revenue", "Memberships", "Guest Bookings"]);
    expect(labelsIn("inventory")).toEqual(
      INVENTORY_ENABLED ? ["Inventory Tracker", "Items", "Stock Movement", "Purchase Orders", "Vendors", "Categories"] : [],
    );
  });

  it("no longer lists Court Schedule anywhere", () => {
    const all = NAV_ITEMS.flatMap((i) => [i.label, ...(i.children ?? []).map((c) => c.label)]);
    expect(all).not.toContain("Court Schedule");
    expect(NAV_ITEMS.some((i) => i.href === "/maintenance/court-schedule")).toBe(false);
  });

  it("every section is flat — Finance Management and Report & Analytics Management list their pages directly", () => {
    for (const item of NAV_ITEMS) expect(item.children).toBeUndefined();
  });

  it("keeps Finance and Reports as two separate sections with their own pages", () => {
    expect(NAV_ITEMS.filter((i) => i.group === "finance").every((i) => i.href.startsWith("/finance") || i.href === "/refunds")).toBe(true);
    expect(NAV_ITEMS.filter((i) => i.group === "reports").every((i) => i.href.startsWith("/reports"))).toBe(true);
  });

  it("keeps the permission gates on the sections that had them", () => {
    for (const i of NAV_ITEMS.filter((x) => x.group === "coaching")) expect(i.permission).toBe("COACHING_VIEW");
    for (const i of NAV_ITEMS.filter((x) => x.group === "staff")) expect(i.permission).toBe("USERS_VIEW");
    for (const i of NAV_ITEMS.filter((x) => x.group === "inventory")) expect(i.permission).toBe("INVENTORY_VIEW");
  });
});

describe("activeHrefFor — the most specific entry wins", () => {
  // Inventory is listed explicitly so this rule stays covered while the module is switched off.
  const hrefs = [
    ...NAV_ITEMS.flatMap((i) => [i.href, ...(i.children ?? []).map((c) => c.href)]),
    "/inventory",
    "/inventory/purchase-orders",
  ];

  it("lights only the child, not the parent that shares its prefix", () => {
    expect(activeHrefFor("/coaching", hrefs)).toBe("/coaching");
    expect(activeHrefFor("/coaching/programs", hrefs)).toBe("/coaching/programs");
    expect(activeHrefFor("/coaching/programs/abc-123", hrefs)).toBe("/coaching/programs");
    expect(activeHrefFor("/coaching/students/new", hrefs)).toBe("/coaching/students");
    expect(activeHrefFor("/coaching/schedule", hrefs)).toBe("/coaching/schedule");
    expect(activeHrefFor("/maintenance/tickets/42", hrefs)).toBe("/maintenance/tickets");
    expect(activeHrefFor("/inventory/purchase-orders/7", hrefs)).toBe("/inventory/purchase-orders");
  });

  it("keeps Membership Plan distinct from Dashboard, including a plan detail page", () => {
    expect(activeHrefFor("/memberships/v1/plans", hrefs)).toBe("/memberships/v1/plans");
    expect(activeHrefFor("/memberships/v1/plans/abc", hrefs)).toBe("/memberships/v1/plans");
  });

  it("keeps Dashboard and Membership Schedule distinct", () => {
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
