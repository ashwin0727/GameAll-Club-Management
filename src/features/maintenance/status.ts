import type { CourtMaintenanceStatus, MaintenancePriority, MaintenanceStatus } from "@/features/maintenance/types";

export const PRIORITY_LABEL: Record<MaintenancePriority, string> = {
  LOW: "Low",
  MEDIUM: "Medium",
  HIGH: "High",
  CRITICAL: "Critical",
};

/** Badge classes — semantic colour AND the label text always carries the meaning (never colour alone). */
export const PRIORITY_BADGE_CLASS: Record<MaintenancePriority, string> = {
  LOW: "border-transparent bg-success/15 text-success",
  MEDIUM: "border-transparent bg-[#FFB020]/15 text-[#FFB020]",
  HIGH: "border-transparent bg-destructive/15 text-destructive",
  CRITICAL: "border-transparent bg-destructive/25 text-destructive font-semibold",
};

export const STATUS_LABEL: Record<MaintenanceStatus, string> = {
  REPORTED: "Open",
  ASSIGNED: "Assigned",
  SCHEDULED: "Scheduled",
  IN_PROGRESS: "In Progress",
  RESOLVED: "Resolved",
  CLOSED: "Closed",
};

export const STATUS_BADGE_CLASS: Record<MaintenanceStatus, string> = {
  REPORTED: "border-transparent bg-destructive/15 text-destructive",
  ASSIGNED: "border-transparent bg-[#5B6CFF]/15 text-[#5B6CFF]",
  SCHEDULED: "border-transparent bg-[#FFB020]/15 text-[#FFB020]",
  IN_PROGRESS: "border-transparent bg-[#5B6CFF]/15 text-[#5B6CFF]",
  RESOLVED: "border-transparent bg-success/15 text-success",
  CLOSED: "border-transparent bg-secondary text-muted-foreground",
};

export const COURT_STATUS_LABEL: Record<CourtMaintenanceStatus, string> = {
  AVAILABLE: "Available",
  IN_USE: "In Use",
  UNDER_MAINTENANCE: "Under Maintenance",
  BLOCKED: "Blocked",
};

export const COURT_STATUS_DOT_CLASS: Record<CourtMaintenanceStatus, string> = {
  AVAILABLE: "bg-success",
  IN_USE: "bg-[#5B6CFF]",
  UNDER_MAINTENANCE: "bg-destructive",
  BLOCKED: "bg-muted-foreground",
};

export const STATUS_ORDER: MaintenanceStatus[] = ["REPORTED", "ASSIGNED", "SCHEDULED", "IN_PROGRESS", "RESOLVED", "CLOSED"];

export function formatMoney(minor: number | null | undefined, currency = "INR"): string {
  if (minor === null || minor === undefined) return "—";
  const symbol = currency === "INR" ? "₹" : `${currency} `;
  return `${symbol}${(minor / 100).toLocaleString("en-IN", { maximumFractionDigits: 0 })}`;
}

export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("en-IN", { day: "2-digit", month: "short", year: "numeric", hour: "numeric", minute: "2-digit", hour12: true });
}

export function formatDate(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

export function formatTime(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true });
}
