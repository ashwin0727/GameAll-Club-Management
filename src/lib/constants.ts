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

export const NAV_ITEMS: {
  label: string;
  href: string;
  roles: Role[];
}[] = [
  { label: "Dashboard", href: "/dashboard", roles: ["admin", "staff", "member"] },
  { label: "Memberships", href: "/memberships", roles: ["admin", "staff"] },
  { label: "Membership Sessions", href: "/membership-sessions", roles: ["admin", "staff"] },
  { label: "Bookings", href: "/bookings", roles: ["admin", "staff", "member"] },
  { label: "Guest Bookings", href: "/guest-bookings", roles: ["admin", "staff"] },
  { label: "Guest Players", href: "/guests", roles: ["admin", "staff"] },
  { label: "Finance", href: "/finance", roles: ["admin", "staff"] },
  // Collecting what is owed is daily work, not something to reach through
  // the Finance overview for.
  { label: "Pending Payments", href: "/finance/pending-payments", roles: ["admin", "staff"] },
  { label: "Refunds", href: "/refunds", roles: ["admin", "staff"] },
  { label: "Inventory", href: "/inventory", roles: ["admin", "staff"] },
];

export const QUERY_STALE_TIME_MS = 30_000;