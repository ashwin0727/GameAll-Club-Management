"use client";

import { Ban } from "lucide-react";
import type { ScheduleBlock, ScheduleBlockKind } from "@/features/memberships/member-schedule";
import { cn } from "@/lib/utils";

const DAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** The default visible window, matching the design — 6 AM to 10 PM. It widens (by whole hours) when a
 *  member slot, guest booking or maintenance block falls outside it, so nothing is ever left undrawn. */
const DEFAULT_START_MIN = 6 * 60;
const DEFAULT_END_MIN = 22 * 60;
const HOUR_PX = 56;
const PX_PER_MIN = HOUR_PX / 60;

/** The visible hour range for these day columns: 6 AM–10 PM, stretched to take in every block. */
export function viewWindow(days: { blocks: ScheduleBlock[] }[]): { startMin: number; endMin: number } {
  let startMin = DEFAULT_START_MIN;
  let endMin = DEFAULT_END_MIN;
  for (const { blocks } of days) {
    for (const b of blocks) {
      if (b.kind === "CLOSED") continue;
      const s = minutesFromClock(b.startTime);
      const e = minutesFromClock(b.endTime);
      if (e <= s) continue;
      startMin = Math.min(startMin, Math.floor(s / 60) * 60);
      endMin = Math.max(endMin, Math.ceil(e / 60) * 60);
    }
  }
  return { startMin, endMin: Math.min(endMin, 24 * 60) };
}

function clockLabel(hour: number): string {
  const h12 = hour % 12 === 0 ? 12 : hour % 12;
  return `${h12}:00 ${hour < 12 ? "AM" : "PM"}`;
}

function minutesFromClock(t: string): number {
  const [h, m] = t.split(":").map(Number);
  return (h ?? 0) * 60 + (m ?? 0);
}

const BLOCK_STYLES: Record<ScheduleBlockKind, string> = {
  MEMBER: "border-success/40 bg-success/15 text-success",
  GUEST: "border-blue-500/40 bg-blue-500/15 text-blue-700 dark:text-blue-400",
  MAINTENANCE: "border-muted-foreground/30 bg-muted text-muted-foreground",
  CLOSED: "border-destructive/20 bg-destructive/5 text-destructive/70",
};

function BlockCard({ block, viewStartMin, viewEndMin }: { block: ScheduleBlock; viewStartMin: number; viewEndMin: number }) {
  const startMin = Math.max(minutesFromClock(block.startTime), viewStartMin);
  const endMin = Math.min(minutesFromClock(block.endTime), viewEndMin);
  if (endMin <= startMin) return null;
  const top = (startMin - viewStartMin) * PX_PER_MIN;
  const height = Math.max((endMin - startMin) * PX_PER_MIN, 20);

  return (
    <div
      className={cn("absolute inset-x-0.5 overflow-hidden rounded-md border px-1.5 py-1 text-[11px] leading-tight", BLOCK_STYLES[block.kind])}
      style={{ top, height }}
      title={`${block.title} · ${block.subtitle} · ${clockLabel(startMin / 60)}`}
    >
      <p className="truncate font-semibold">{block.title}</p>
      {block.subtitle && <p className="truncate opacity-80">{block.subtitle}</p>}
    </div>
  );
}

function formatClock12(t: string): string {
  const [h, m] = t.split(":").map(Number);
  const h12 = (h ?? 0) % 12 === 0 ? 12 : (h ?? 0) % 12;
  return `${h12}:${String(m ?? 0).padStart(2, "0")} ${(h ?? 0) < 12 ? "AM" : "PM"}`;
}

export interface DayColumnData {
  date: Date;
  blocks: ScheduleBlock[];
}

/**
 * The weekly Time × Day calendar, matching the design: an hour-labelled left rail, 7 day
 * columns each with its own Court Closed / Member Slot / Guest Booking / Maintenance blocks,
 * absolutely positioned by clock time. `blocksForDay` (the pure logic) already decided what
 * goes in each column — this only lays it out.
 */
export function MemberScheduleGrid({ days, today }: { days: DayColumnData[]; today: Date }) {
  const { startMin: VIEW_START_MIN, endMin: VIEW_END_MIN } = viewWindow(days);
  const BODY_HEIGHT = ((VIEW_END_MIN - VIEW_START_MIN) / 60) * HOUR_PX;
  const HOURS = Array.from({ length: (VIEW_END_MIN - VIEW_START_MIN) / 60 }, (_, i) => VIEW_START_MIN / 60 + i);
  return (
    <div className="overflow-x-auto rounded-lg border border-border">
      <div
        className="grid"
        style={{ minWidth: days.length > 1 ? 760 : 320, gridTemplateColumns: `64px repeat(${days.length}, 1fr)` }}
      >
        <div className="flex items-center justify-center border-b border-r border-border py-2 text-xs font-semibold text-foreground">Time</div>
        {days.map(({ date }) => {
          const isToday = date.toDateString() === today.toDateString();
          return (
            <div
              key={date.toISOString()}
              className={cn("border-b border-r border-border px-2 py-2 text-center last:border-r-0", isToday && "bg-success/10")}
            >
              <p className={cn("text-xs font-semibold", isToday ? "text-success" : "text-foreground")}>{DAY_LABELS[date.getDay()]}</p>
              <p className="text-[11px] text-muted-foreground">
                {date.getDate()} {MONTHS[date.getMonth()]}
              </p>
            </div>
          );
        })}

        <div className="relative border-r border-border" style={{ height: BODY_HEIGHT }}>
          {HOURS.map((h, i) => (
            <p
              key={h}
              // Anchored just below its gridline rather than straddling it (-translate-y-1/2
              // would push the very first label, at top: 0, half outside the grid — hidden
              // behind the day-header row above it).
              className={cn("absolute inset-x-0 text-center text-[10px] tabular-nums text-muted-foreground", i === 0 ? "top-0.5" : "-translate-y-1/2")}
              style={{ top: i === 0 ? undefined : (h * 60 - VIEW_START_MIN) * PX_PER_MIN }}
            >
              {clockLabel(h)}
            </p>
          ))}
        </div>

        {days.map(({ date, blocks }) => {
          const closed = blocks.length === 1 && blocks[0]!.kind === "CLOSED";
          return (
            <div key={date.toISOString()} className="relative border-r border-border last:border-r-0" style={{ height: BODY_HEIGHT }}>
              {HOURS.map((h, i) => (
                <div key={h} className="absolute inset-x-0 border-t border-border/50 first:border-t-0" style={{ top: i * HOUR_PX }} />
              ))}
              {closed ? (
                <div className="absolute inset-0 flex flex-col items-center justify-center gap-1 bg-destructive/5 text-destructive/70">
                  <Ban className="h-4 w-4" aria-hidden />
                  <p className="text-xs font-medium">Court Closed</p>
                </div>
              ) : (
                blocks.map((block, i) => <BlockCard key={`${block.kind}-${i}-${block.startTime}`} block={block} viewStartMin={VIEW_START_MIN} viewEndMin={VIEW_END_MIN} />)
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

export { formatClock12 };
