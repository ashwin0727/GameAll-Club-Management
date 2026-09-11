// ═══════════════════════════════════════════════════════════════════════════
// Staff / Roles / Permissions — the shapes the UI works with.
//
// Every authorization decision is the database's (has_permission, RLS). This
// module only describes what the RPCs return and gates UI affordances with a
// permission set the session loaded once.
// ═══════════════════════════════════════════════════════════════════════════

export type StaffStatus = "ACTIVE" | "INACTIVE" | "INVITED";
export type BaseRole = "owner" | "manager" | "staff";

/** Every permission key the platform ships with (mirrors the `permissions` table). */
export type PermissionKey =
  | "DASHBOARD_VIEW"
  | "BOOKINGS_VIEW" | "BOOKINGS_CREATE" | "BOOKINGS_EDIT" | "BOOKINGS_CANCEL"
  | "BOOKINGS_MANAGE_PAYMENTS" | "BOOKINGS_VIEW_CUSTOMER"
  | "COURTS_VIEW" | "COURTS_CREATE" | "COURTS_EDIT" | "COURTS_BLOCK"
  | "MEMBERSHIPS_VIEW" | "MEMBERSHIPS_CREATE" | "MEMBERSHIPS_EDIT" | "MEMBERSHIPS_CANCEL"
  | "GUEST_BOOKINGS_VIEW" | "GUEST_BOOKINGS_CREATE" | "GUEST_BOOKINGS_EDIT" | "GUEST_BOOKINGS_CANCEL"
  | "FINANCE_VIEW" | "FINANCE_RECORD_PAYMENT" | "FINANCE_REFUND" | "FINANCE_MANAGE_EXPENSES"
  | "FINANCE_DAILY_CLOSING" | "FINANCE_REOPEN_CLOSING" | "FINANCE_VIEW_PNL"
  | "REPORTS_VIEW" | "REPORTS_VIEW_FINANCIAL"
  | "MAINTENANCE_VIEW" | "MAINTENANCE_CREATE" | "MAINTENANCE_ASSIGN" | "MAINTENANCE_SCHEDULE"
  | "MAINTENANCE_BLOCK_COURT" | "MAINTENANCE_RESOLVE"
  | "USERS_VIEW" | "USERS_CREATE" | "USERS_EDIT" | "USERS_MANAGE_ROLES"
  | "USERS_MANAGE_FACILITY_ACCESS" | "USERS_DEACTIVATE"
  | "INVENTORY_VIEW" | "INVENTORY_CREATE_ITEM" | "INVENTORY_EDIT_ITEM"
  | "INVENTORY_STOCK_IN" | "INVENTORY_STOCK_OUT" | "INVENTORY_ADJUST"
  | "INVENTORY_MANAGE_CATEGORIES"
  | "PURCHASE_VIEW" | "PURCHASE_CREATE" | "PURCHASE_EDIT" | "PURCHASE_RECEIVE" | "PURCHASE_CANCEL"
  | "VENDOR_VIEW" | "VENDOR_CREATE" | "VENDOR_EDIT"
  | "COACHING_VIEW" | "COACHING_MANAGE_COACHES" | "COACHING_MANAGE_PROGRAMS"
  | "COACHING_CREATE_SESSION" | "COACHING_EDIT_SESSION" | "COACHING_CANCEL_SESSION"
  | "COACHING_MANAGE_ENROLLMENTS" | "COACHING_MANAGE_PRICING"
  | "COACHING_VIEW_PROGRESS" | "COACHING_MANAGE_PROGRESS";

export interface Permission {
  key: string;
  module: string;
  action: string;
  label: string;
  description: string | null;
  isDangerous: boolean;
  sortOrder: number;
}

export interface StaffRow {
  assignmentId: string;
  userId: string;
  fullName: string;
  email: string;
  phone: string | null;
  avatarUrl: string | null;
  roleId: string | null;
  roleName: string;
  baseRole: BaseRole;
  status: StaffStatus;
  isPrimary: boolean;
  title: string | null;
  facilityCount: number;
  lastLoginAt: string | null;
  joinedAt: string;
}

export interface StaffPage {
  staff: StaffRow[];
  totalCount: number;
}

export interface StaffFilters {
  search?: string | null;
  status?: StaffStatus | null;
  roleId?: string | null;
}

export interface StaffFacilityAccess {
  facilityId: string;
  facilityName: string;
  roleId: string | null;
  roleName: string;
  baseRole: BaseRole;
  status: StaffStatus;
  isPrimary: boolean;
}

export interface StaffActivity {
  id: string;
  event: string;
  summary: string;
  actorName: string | null;
  createdAt: string;
  detail: Record<string, unknown>;
}

export interface StaffDetail {
  userId: string;
  fullName: string;
  email: string;
  phone: string | null;
  avatarUrl: string | null;
  mustResetPassword: boolean;
  assignment: {
    assignmentId: string;
    roleId: string | null;
    roleName: string;
    baseRole: BaseRole;
    status: StaffStatus;
    isPrimary: boolean;
    title: string | null;
    notes: string | null;
    joinedAt: string;
    invitedAt: string | null;
    activatedAt: string | null;
    lastLoginAt: string | null;
  } | null;
  facilityAccess: StaffFacilityAccess[];
  permissions: string[];
  recentActivity: StaffActivity[];
}

export interface RoleRow {
  id: string;
  key: string | null;
  name: string;
  description: string | null;
  isSystem: boolean;
  isCustom: boolean;
  isActive: boolean;
  version: number;
  staffCount: number;
  permissionCount: number;
}

export interface RoleDetail {
  id: string;
  key: string | null;
  name: string;
  description: string | null;
  isSystem: boolean;
  isTemplate: boolean;
  isActive: boolean;
  baseRole: BaseRole | null;
  version: number;
  facilityId: string | null;
  permissionKeys: string[];
}

export interface RoleTemplate {
  id: string;
  name: string;
  description: string | null;
  permissionKeys: string[];
}

export interface SecurityEvent {
  id: string;
  event: string;
  summary: string;
  actorName: string | null;
  targetName: string | null;
  detail: Record<string, unknown>;
  createdAt: string;
}

export interface SecurityEventPage {
  events: SecurityEvent[];
  totalCount: number;
}

export interface SecurityEventFilters {
  event?: string | null;
  targetUserId?: string | null;
  from?: string | null;
  to?: string | null;
}

export interface CreateStaffInput {
  facilityId: string;
  fullName: string;
  email: string;
  phone?: string | null;
  roleId: string;
  isPrimary?: boolean;
  title?: string | null;
  notes?: string | null;
  avatarUrl?: string | null;
}

export interface CreateStaffResult {
  userId: string;
  linked: boolean;
  temporaryPassword: string | null;
}
