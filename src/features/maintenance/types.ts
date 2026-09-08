/**
 * Maintenance & Court Operations — domain types. Mirrors the shapes
 * migration 0068_maintenance_module.sql's RPCs return; the service layer is
 * the only place that translates between snake_case rows and these.
 */

export type MaintenancePriority = "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";

export type MaintenanceStatus = "REPORTED" | "ASSIGNED" | "SCHEDULED" | "IN_PROGRESS" | "RESOLVED" | "CLOSED";

export type CourtMaintenanceStatus = "AVAILABLE" | "IN_USE" | "UNDER_MAINTENANCE" | "BLOCKED";

export interface MaintenanceIssueCategory {
  id: string;
  facilityId: string | null;
  name: string;
  icon: string;
  description: string | null;
  isActive: boolean;
  sortOrder: number;
  issueCount: number;
  isShared: boolean;
}

export interface MaintenanceTicketListRow {
  ticketId: string;
  code: string;
  courtId: string;
  courtName: string;
  sportName: string | null;
  issueCategoryId: string;
  categoryName: string;
  title: string;
  priority: MaintenancePriority;
  status: MaintenanceStatus;
  reportedByName: string;
  assignedToName: string | null;
  scheduledStart: string | null;
  reportedAt: string;
  actualCostMinor: number | null;
  estimatedCostMinor: number | null;
}

export interface MaintenanceTicketFilters {
  search?: string;
  status?: MaintenanceStatus;
  priority?: MaintenancePriority;
  courtId?: string;
  facilitySportId?: string;
  issueCategoryId?: string;
  assignedTo?: string;
  from?: string;
  to?: string;
  sort?: "NEWEST" | "OLDEST" | "PRIORITY";
}

export interface MaintenanceTicketPage {
  tickets: MaintenanceTicketListRow[];
  totalCount: number;
}

export interface AffectedBooking {
  bookingId: string;
  customerType: "MEMBER" | "GUEST";
  guestName: string | null;
  memberId: string | null;
  startTime: string;
  endTime: string;
  status: string;
  paymentStatus: string;
  amountMinor: number | null;
}

export interface AffectedSession {
  batchId: string;
  batchName: string;
  sessionDate: string;
  startTime: string;
  endTime: string;
  memberBookedCount: number;
  guestBookedCount: number;
}

export interface MaintenanceActivityEntry {
  id: string;
  eventType: string;
  note: string | null;
  metadata: Record<string, unknown>;
  actorName: string | null;
  createdAt: string;
}

export interface MaintenanceAttachment {
  id: string;
  storagePath: string;
  fileName: string;
  contentType: string | null;
  sizeBytes: number | null;
  createdAt: string;
}

export interface MaintenanceTicketDetail {
  id: string;
  code: string;
  facilityId: string;
  court: { id: string; name: string };
  sportName: string | null;
  category: { id: string; name: string; icon: string };
  title: string;
  description: string;
  priority: MaintenancePriority;
  status: MaintenanceStatus;
  reportedBy: { id: string; name: string };
  reportedAt: string;
  assignedTo: { id: string; name: string } | null;
  scheduledStart: string | null;
  scheduledEnd: string | null;
  actualStart: string | null;
  actualEnd: string | null;
  estimatedCostMinor: number | null;
  actualCostMinor: number | null;
  expenseId: string | null;
  notes: string | null;
  currency: string;
  activeBlock: { id: string; startTime: string; endTime: string; status: string } | null;
  attachments: MaintenanceAttachment[];
  activity: MaintenanceActivityEntry[];
  affectedBookings: AffectedBooking[];
  affectedSessions: AffectedSession[];
}

export interface CourtMaintenanceStatusRow {
  courtId: string;
  courtName: string;
  sportName: string | null;
  status: CourtMaintenanceStatus;
}

export interface MaintenanceOverview {
  openIssues: number;
  inProgress: number;
  scheduled: number;
  resolvedThisMonth: number;
  courtsBlocked: number;
  repairCostThisMonthMinor: number;
  courtStatus: CourtMaintenanceStatusRow[];
  recentTickets: {
    ticketId: string;
    code: string;
    courtName: string;
    title: string;
    priority: MaintenancePriority;
    status: MaintenanceStatus;
    reportedAt: string;
    assignedToName: string | null;
  }[];
  upcomingSchedule: { ticketId: string; courtName: string; title: string; startTime: string; endTime: string }[];
  recentActivity: { id: string; ticketId: string; eventType: string; note: string | null; actorName: string | null; createdAt: string }[];
}

export interface CreateMaintenanceTicketInput {
  facilityId: string;
  courtId: string;
  issueCategoryId: string;
  priority: MaintenancePriority;
  title: string;
  description: string;
  scheduledStart?: string | null;
  scheduledEnd?: string | null;
  assignedTo?: string | null;
  estimatedCostMinor?: number | null;
  notes?: string | null;
}

export interface MaintenanceBlockRow {
  id: string;
  facilityId: string;
  courtId: string;
  ticketId: string;
  startTime: string;
  endTime: string;
  status: "ACTIVE" | "ENDED" | "CANCELLED";
}

/** The 10 default categories this project seeds — a fixed, reviewed icon set (spec §10: "use the existing icon registry"). */
export const MAINTENANCE_ICON_KEYS = [
  "court",
  "lightbulb",
  "grid",
  "snowflake",
  "cog",
  "droplet",
  "lock",
  "paint",
  "wrench",
  "more",
] as const;
export type MaintenanceIconKey = (typeof MAINTENANCE_ICON_KEYS)[number];
