import { describe, expect, it } from "vitest";
import {
  COURT_STATUS_LABEL,
  PRIORITY_BADGE_CLASS,
  PRIORITY_LABEL,
  STATUS_BADGE_CLASS,
  STATUS_LABEL,
  STATUS_ORDER,
  formatDate,
  formatMoney,
} from "@/features/maintenance/status";
import type { MaintenancePriority, MaintenanceStatus } from "@/features/maintenance/types";

describe("maintenance status helpers", () => {
  it("formats money from minor units, em-dash for null", () => {
    expect(formatMoney(1850000)).toBe("₹18,500");
    expect(formatMoney(0)).toBe("₹0");
    expect(formatMoney(null)).toBe("—");
    expect(formatMoney(undefined)).toBe("—");
  });

  it("formatDate is em-dash for null/undefined", () => {
    expect(formatDate(null)).toBe("—");
    expect(formatDate("2026-09-01T10:30:00Z")).toMatch(/2026/);
  });

  it("every priority and status has a label + a badge class", () => {
    for (const p of ["LOW", "MEDIUM", "HIGH", "CRITICAL"] as MaintenancePriority[]) {
      expect(PRIORITY_LABEL[p]).toBeTruthy();
      expect(PRIORITY_BADGE_CLASS[p]).toBeTruthy();
    }
    for (const s of STATUS_ORDER) {
      expect(STATUS_LABEL[s]).toBeTruthy();
      expect(STATUS_BADGE_CLASS[s]).toBeTruthy();
    }
  });

  it("REPORTED renders as 'Open' — the web/Flutter shared convention", () => {
    expect(STATUS_LABEL.REPORTED).toBe("Open");
  });

  it("STATUS_ORDER is the full forward lifecycle", () => {
    expect(STATUS_ORDER).toEqual<MaintenanceStatus[]>(["REPORTED", "ASSIGNED", "SCHEDULED", "IN_PROGRESS", "RESOLVED", "CLOSED"]);
  });

  it("court statuses cover all four operational states", () => {
    expect(Object.keys(COURT_STATUS_LABEL).sort()).toEqual(["AVAILABLE", "BLOCKED", "IN_USE", "UNDER_MAINTENANCE"]);
  });
});
