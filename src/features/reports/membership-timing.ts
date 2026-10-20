import type { MembershipBatchRow } from "@/features/reports/types";

const DAY = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/** "05:00:00" → "5:00 AM". */
export function formatClock(hhmmss: string | null): string {
  if (!hhmmss) return "";
  const [h, m] = hhmmss.split(":").map(Number);
  const hour = h ?? 0;
  const hour12 = hour % 12 === 0 ? 12 : hour % 12;
  return `${hour12}:${String(m ?? 0).padStart(2, "0")} ${hour < 12 ? "AM" : "PM"}`;
}

/** "5:00 AM – 6:00 AM". */
export function formatTiming(start: string | null, end: string | null): string {
  return start && end ? `${formatClock(start)} – ${formatClock(end)}` : "";
}

/** Weekdays as ranges: [1,2,3,4,5,6] → "Mon–Sat", [0,6] → "Sat, Sun", [1,3,5] → "Mon, Wed, Fri". Monday-first. */
export function formatDays(days: number[]): string {
  const order = [...new Set(days)].sort((a, b) => ((a + 6) % 7) - ((b + 6) % 7));
  if (order.length === 7) return "Every day";
  const runs: number[][] = [];
  for (const d of order) {
    const last = runs[runs.length - 1];
    if (last && (last[last.length - 1]! + 1) % 7 === d && d !== 0) last.push(d);
    else runs.push([d]);
  }
  return runs.map((r) => (r.length >= 3 ? `${DAY[r[0]!]}–${DAY[r[r.length - 1]!]}` : r.map((d) => DAY[d]).join(", "))).join(", ");
}

export interface TimingGroup {
  sportName: string;
  /** Distinct people in the sport. */
  members: number;
  courts: { courtName: string; members: number; timings: MembershipBatchRow[] }[];
}

/** Rows (already ordered sport → court → time) folded into sport → court → timings. The unassigned row is left out. */
export function groupByCourt(rows: MembershipBatchRow[]): TimingGroup[] {
  const groups: TimingGroup[] = [];
  for (const r of rows) {
    if (r.batchId === null) continue;
    let sport = groups.find((g) => g.sportName === r.sportName);
    if (!sport) {
      sport = { sportName: r.sportName, members: r.sportMembers, courts: [] };
      groups.push(sport);
    }
    let court = sport.courts.find((c) => c.courtName === (r.courtName ?? ""));
    if (!court) {
      court = { courtName: r.courtName ?? "", members: r.courtMembers, timings: [] };
      sport.courts.push(court);
    }
    court.timings.push(r);
  }
  return groups;
}
