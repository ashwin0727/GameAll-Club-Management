"use client";

import { Ban } from "lucide-react";
import type { ScheduleBlock, ScheduleBlockKind } from "@/features/memberships/member-schedule";
import { cn } from "@/lib/utils";

const DAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** The visible window, matching the design — 6 AM to 10 PM. A member/guest/maintenance block
 *  outside this range simply isn't drawn; the vast majority of court activity falls inside it. */
const VIEW_START_MIN = 6 * 60;
const VIEW_END_MIN = 22 * 60;
const HOUR_PX = 56;
const PX_PER_MIN = HOUR_PX / 60;
const BODY_HEIGHT = ((VIEW_END_MIN - VIEW_START_MIN) / 60) * HOUR_PX;

const HOURS = Array.from({ length: (VIEW_END_MIN - VIEW_START_MIN) / 60 }, (_, i) => VIEW_START_MIN / 60 + i);

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

function BlockCard({ block }: { block: ScheduleBlock }) {
  const startMin = Math.max(minutesFromClock(block.startTime), VIEW_START_MIN);
  const endMin = Math.min(minutesFromClock(block.endTime), VIEW_END_MIN);
  if (endMin <= startMin) return null;
  const top = (startMin - VIEW_START_MIN) * PX_PER_MIN;
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
                blocks.map((block, i) => <BlockCard key={`${block.kind}-${i}-${block.startTime}`} block={block} />)
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

export { formatClock12 };
