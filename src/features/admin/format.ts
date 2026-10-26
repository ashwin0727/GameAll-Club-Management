/** ₹12,345 — whole rupees (the admin RPCs report amounts in rupees). */
export function inr(value: number | null | undefined): string {
  return `₹${Math.round(Number(value ?? 0)).toLocaleString("en-IN")}`;
}

export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("en-IN", { day: "numeric", month: "short", year: "numeric", hour: "numeric", minute: "2-digit" });
}

export function formatDate(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });
}

export function placeLabel(city: string | null, state?: string | null): string {
  return [city, state].filter(Boolean).join(", ") || "—";
}

/** "COMPLETED" → "Completed", "OPERATING_HOURS" → "Operating hours". */
export function humanize(value: string): string {
  const s = value.toLowerCase().replace(/_/g, " ");
  return s.charAt(0).toUpperCase() + s.slice(1);
}
