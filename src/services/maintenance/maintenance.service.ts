import type {
  AffectedBooking,
  AffectedSession,
  CreateMaintenanceTicketInput,
  MaintenanceIssueCategory,
  MaintenanceOverview,
  MaintenanceTicketDetail,
  MaintenanceTicketFilters,
  MaintenanceTicketPage,
} from "@/features/maintenance/types";

/**
 * The Maintenance boundary the UI codes against. Every write is a single
 * server RPC (migration 0068) — never a client-side status update — so the
 * lifecycle, availability integration, and audit trail stay authoritative
 * in one place.
 */
export interface FacilityStaffOption {
  userId: string;
  fullName: string;
  role: "owner" | "manager" | "staff";
}

export interface MaintenanceService {
  getOverview(facilityId: string): Promise<MaintenanceOverview>;
  listAssignableStaff(facilityId: string): Promise<FacilityStaffOption[]>;

  listIssueCategories(facilityId: string, includeInactive?: boolean): Promise<MaintenanceIssueCategory[]>;
  createIssueCategory(input: { facilityId: string; name: string; icon: string; description?: string | null; sortOrder?: number }): Promise<MaintenanceIssueCategory>;
  updateIssueCategory(input: { categoryId: string; name: string; icon: string; description?: string | null; sortOrder?: number; isActive?: boolean }): Promise<MaintenanceIssueCategory>;

  listTickets(facilityId: string, filters: MaintenanceTicketFilters, limit: number, offset: number): Promise<MaintenanceTicketPage>;
  getTicketDetail(ticketId: string): Promise<MaintenanceTicketDetail>;
  createTicket(input: CreateMaintenanceTicketInput): Promise<MaintenanceTicketDetail>;
  updateTicket(input: { ticketId: string; title: string; description: string; issueCategoryId: string; priority: string; notes?: string | null }): Promise<void>;
  assignTicket(ticketId: string, assignedTo: string): Promise<void>;
  scheduleMaintenance(ticketId: string, start: string, end: string): Promise<void>;
  startMaintenance(ticketId: string): Promise<void>;
  addNote(ticketId: string, note: string): Promise<void>;
  updateCost(input: {
    ticketId: string;
    estimatedCostMinor?: number | null;
    actualCostMinor?: number | null;
    postToExpenses?: boolean;
    expenseCategoryId?: string | null;
    paymentMethod?: string | null;
    vendor?: string | null;
  }): Promise<void>;
  resolveTicket(ticketId: string, actualEnd?: string | null): Promise<void>;
  reopenTicket(ticketId: string): Promise<void>;
  closeTicket(ticketId: string, reason?: string | null): Promise<void>;

  /** Live preview before the user confirms a schedule — the same RPC create/schedule call internally. */
  detectAffectedBookings(courtId: string, start: string, end: string, excludeTicketId?: string | null): Promise<AffectedBooking[]>;
  detectAffectedSessions(courtId: string, start: string, end: string): Promise<AffectedSession[]>;

  addAttachment(ticketId: string, storagePath: string, fileName: string, contentType?: string | null, sizeBytes?: number | null): Promise<void>;
  /** Uploads directly to the maintenance-attachments Storage bucket and records it. Returns a signed URL for immediate preview. */
  uploadAttachment(facilityId: string, ticketId: string, file: File): Promise<{ storagePath: string; signedUrl: string | null }>;
  getAttachmentUrl(storagePath: string): Promise<string | null>;
}
