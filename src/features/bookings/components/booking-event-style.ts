import type { CalEventKind } from "@/features/bookings/calendar-events";

/** Block colours per kind — tinted fill + a solid left edge, readable in light and dark. */
export const EVENT_BLOCK_STYLE: Record<CalEventKind, string> = {
  GUEST: "border-blue-500 bg-blue-500/15 text-blue-900 dark:text-blue-100",
  COACHING: "border-purple-500 bg-purple-500/15 text-purple-900 dark:text-purple-100",
  SESSION: "border-emerald-500 bg-emerald-500/15 text-emerald-900 dark:text-emerald-100",
  // Diagonal stripes: the court is out of use for this time.
  MAINTENANCE:
    "border-red-500 bg-[repeating-linear-gradient(135deg,rgb(239_68_68/0.18)_0,rgb(239_68_68/0.18)_6px,rgb(239_68_68/0.08)_6px,rgb(239_68_68/0.08)_12px)] text-red-900 dark:text-red-100",
};

/** Small pill / dot colour per kind, for lists and the legend. */
export const EVENT_CHIP_STYLE: Record<CalEventKind, string> = {
  GUEST: "bg-blue-500/15 text-blue-700 dark:text-blue-300",
  COACHING: "bg-purple-500/15 text-purple-700 dark:text-purple-300",
  SESSION: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300",
  MAINTENANCE: "bg-red-500/15 text-red-700 dark:text-red-300",
};

export const EVENT_DOT_STYLE: Record<CalEventKind, string> = {
  GUEST: "bg-blue-500",
  COACHING: "bg-purple-500",
  SESSION: "bg-emerald-500",
  MAINTENANCE: "bg-red-500",
};

/** The "on" colour of each kind's switch in the legend bar. */
export const EVENT_TOGGLE_STYLE: Record<CalEventKind, string> = {
  SESSION: "bg-emerald-500",
  GUEST: "bg-blue-500",
  COACHING: "bg-purple-500",
  MAINTENANCE: "bg-red-500",
};

export function formatClock(d: Date): string {
  return d.toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true });
}

export function formatRange(start: Date, end: Date): string {
  return `${formatClock(start)} – ${formatClock(end)}`;
}

export function paymentChip(status: string | undefined): { label: string; cls: string } | null {
  switch (status) {
    case "PAID":
      return { label: "Paid", cls: "bg-success/15 text-success" };
    case "PENDING":
      return { label: "Pending", cls: "bg-warning/15 text-warning" };
    case "REFUNDED":
      return { label: "Refunded", cls: "bg-secondary text-muted-foreground" };
    default:
      return null;
  }
}

export function statusChip(status: string | undefined): { label: string; cls: string; dot: string } {
  switch (status) {
    case "pending":
      return { label: "Pending", cls: "text-warning", dot: "bg-warning" };
    case "completed":
      return { label: "Completed", cls: "text-muted-foreground", dot: "bg-muted-foreground" };
    default:
      return { label: "Confirmed", cls: "text-success", dot: "bg-success" };
  }
}

/** Short type names for pills and the legend ("Members - C01"). */
export const EVENT_SHORT_LABEL: Record<CalEventKind, string> = {
  GUEST: "Guest",
  SESSION: "Members",
  COACHING: "Coaching",
  MAINTENANCE: "Maintenance",
};

/** "Court 1" → "C01", "Court 12" → "C12"; names without a number fall back to their initials. */
export function courtShortName(name: string): string {
  const n = name.match(/(\d+)\s*$/);
  if (n) return `C${n[1]!.padStart(2, "0")}`;
  const initials = name
    .split(/\s+/)
    .map((w) => w[0]?.toUpperCase() ?? "")
    .join("");
  return initials.slice(0, 3) || name.slice(0, 3);
}
