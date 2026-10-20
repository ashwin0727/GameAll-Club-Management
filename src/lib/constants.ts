/** The brand: "GameAll" reading over "Club Management" wherever the logo lockup appears. */
export const APP_NAME = "GameAll";
export const APP_SUBTITLE = "Club Management";
/** The logo asset, served from /public (and mirrored at mobile/assets/images). */
export const APP_LOGO_SRC = "/logo-icon.png";

/** Product wordmark and pitch used across splash, welcome and the auth screens. */
export const PRODUCT_NAME = APP_NAME;
export const PRODUCT_TAGLINE = "Manage your facility. Grow your business.";

/** Sports the platform ships with; mirrors the seeded `sports` table. */
export const SUPPORTED_SPORTS = [
  "Badminton",
  "Pickleball",
  "Cricket",
  "Football",
  "Tennis",
] as const;

/** Seconds a user must wait between verification-email resends. */
export const RESEND_COOLDOWN_SECONDS = 30;

export const ROLES = ["admin", "staff", "member"] as const;
export type Role = (typeof ROLES)[number];

export const MEMBERSHIP_STATUSES = ["active", "expired", "cancelled", "pending"] as const;
export const PAYMENT_STATUSES = ["created", "paid", "failed", "refunded"] as const;
export const BOOKING_STATUSES = ["pending", "confirmed", "cancelled", "completed"] as const;
export const INVENTORY_TXN_TYPES = ["checkout", "return", "restock", "damage"] as const;

export type NavGroup =
  | "main"
  | "guest"
  | "memberships"
  | "coaching"
  | "maintenance"
  | "staff"
  | "inventory"
  | "finance"
  | "reports";

/** Sidebar sections in display order. */
export const NAV_GROUP_ORDER: NavGroup[] = ["main", "guest", "memberships", "coaching", "maintenance", "staff", "inventory", "finance", "reports"];

export const NAV_GROUP_LABELS: Record<NavGroup, string | null> = {
  main: null,
  guest: "Guest Management",
  memberships: "Memberships Management",
  coaching: "Coaching Management",
  maintenance: "Maintenance Management",
  staff: "Staff Management",
  inventory: "Inventory Management",
  finance: "Finance Management",
  reports: "Report & Analytics Management",
};

export interface NavItem {
  label: string;
  /** Sidebar section the item is listed under. */
  group: NavGroup;
  href: string;
  roles: Role[];
  /**
   * A facility permission key gating the item. When set, the item is hidden
   * unless the signed-in user holds it for the active facility. This is UX
   * only — the page's own guard and the database enforce access.
   */
  permission?: string;
  /**
   * Optional sub-pages shown when the item is expanded. No section uses this today — every section lists its
   * pages directly as flat items.
   */
  children?: { label: string; href: string }[];
}

const STAFF_ROLES: Role[] = ["admin", "staff"];

/**
 * Master switch for Inventory Management. While false the menu entries, search results and every /inventory page are
 * gone for everyone; the module's code and data are untouched, so turning it back on is changing this to true.
 */
export const INVENTORY_ENABLED = false;

const INVENTORY_NAV_ITEMS: NavItem[] = [
  { label: "Inventory Tracker", group: "inventory", href: "/inventory", roles: STAFF_ROLES, permission: "INVENTORY_VIEW" },
  { label: "Items", group: "inventory", href: "/inventory/items", roles: STAFF_ROLES, permission: "INVENTORY_VIEW" },
  { label: "Stock Movement", group: "inventory", href: "/inventory/movements", roles: STAFF_ROLES, permission: "INVENTORY_VIEW" },
  { label: "Purchase Orders", group: "inventory", href: "/inventory/purchase-orders", roles: STAFF_ROLES, permission: "INVENTORY_VIEW" },
  { label: "Vendors", group: "inventory", href: "/inventory/vendors", roles: STAFF_ROLES, permission: "INVENTORY_VIEW" },
  { label: "Categories", group: "inventory", href: "/inventory/categories", roles: STAFF_ROLES, permission: "INVENTORY_VIEW" },
];

export const NAV_ITEMS: NavItem[] = [
  { label: "Home", group: "main", href: "/dashboard", roles: ["admin", "staff", "member"] },
  { label: "Calendar", group: "main", href: "/calendar", roles: ["admin", "staff", "member"] },
  { label: "Tournaments", group: "main", href: "/tournaments", roles: STAFF_ROLES },

  // Guest Management
  { label: "Guest Booking", group: "guest", href: "/guest-bookings", roles: STAFF_ROLES },
  { label: "Guest Players", group: "guest", href: "/guests", roles: STAFF_ROLES },

  // Memberships Management
  { label: "Dashboard", group: "memberships", href: "/memberships/v1", roles: STAFF_ROLES },
  { label: "Membership Schedule", group: "memberships", href: "/memberships/v1/schedule", roles: STAFF_ROLES },
  { label: "Membership Plan", group: "memberships", href: "/memberships/v1/plans", roles: STAFF_ROLES },
  { label: "Membership Sessions", group: "memberships", href: "/membership-sessions", roles: STAFF_ROLES },

  // Coaching Management
  { label: "Coaching", group: "coaching", href: "/coaching", roles: STAFF_ROLES, permission: "COACHING_VIEW" },
  { label: "Program", group: "coaching", href: "/coaching/programs", roles: STAFF_ROLES, permission: "COACHING_VIEW" },
  { label: "Students", group: "coaching", href: "/coaching/students", roles: STAFF_ROLES, permission: "COACHING_VIEW" },
  { label: "Coaching Schedule", group: "coaching", href: "/coaching/schedule", roles: STAFF_ROLES, permission: "COACHING_VIEW" },
  { label: "Report", group: "coaching", href: "/coaching/reports", roles: STAFF_ROLES, permission: "COACHING_VIEW" },

  // Maintenance Management (Court Schedule is no longer in the menu; its page still exists)
  { label: "Maintenance", group: "maintenance", href: "/maintenance", roles: STAFF_ROLES },
  { label: "Maintenance Tracker", group: "maintenance", href: "/maintenance/tickets", roles: STAFF_ROLES },
  { label: "Issue Category", group: "maintenance", href: "/maintenance/issue-categories", roles: STAFF_ROLES },

  // Staff Management
  { label: "Staff", group: "staff", href: "/users-roles/staff", roles: STAFF_ROLES, permission: "USERS_VIEW" },
  { label: "Roles & Permission", group: "staff", href: "/users-roles/roles", roles: STAFF_ROLES, permission: "USERS_VIEW" },
  { label: "Access History", group: "staff", href: "/users-roles/access-history", roles: STAFF_ROLES, permission: "USERS_VIEW" },

  // Inventory Management (switched off while INVENTORY_ENABLED is false)
  ...(INVENTORY_ENABLED ? INVENTORY_NAV_ITEMS : []),

  // Finance Management
  { label: "Overview", group: "finance", href: "/finance", roles: STAFF_ROLES },
  { label: "Transactions", group: "finance", href: "/finance/transactions", roles: STAFF_ROLES },
  { label: "Payments", group: "finance", href: "/finance/pending-payments", roles: STAFF_ROLES },
  { label: "Expenses", group: "finance", href: "/finance/expenses", roles: STAFF_ROLES },
  { label: "Daily Closing", group: "finance", href: "/finance/daily-closing", roles: STAFF_ROLES },
  { label: "P&L", group: "finance", href: "/finance/profit-loss", roles: STAFF_ROLES },
  { label: "Refunds", group: "finance", href: "/refunds", roles: STAFF_ROLES },

  // Report & Analytics Management
  { label: "Overview", group: "reports", href: "/reports", roles: STAFF_ROLES },
  { label: "Court Utilization", group: "reports", href: "/reports/court-utilization", roles: STAFF_ROLES },
  { label: "Revenue", group: "reports", href: "/reports/revenue", roles: STAFF_ROLES },
  { label: "Memberships", group: "reports", href: "/reports/memberships", roles: STAFF_ROLES },
  { label: "Guest Bookings", group: "reports", href: "/reports/guest-bookings", roles: STAFF_ROLES },
];

export const QUERY_STALE_TIME_MS = 30_000;