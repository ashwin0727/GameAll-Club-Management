"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import {
  addDays,
  addMonths,
  endOfMonth,
  endOfWeek,
  format,
  isAfter,
  isBefore,
  isSameDay,
  isSameMonth,
  parseISO,
  startOfMonth,
  startOfWeek,
} from "date-fns";
import { CalendarDays } from "lucide-react";
import { cn } from "@/lib/utils";

/** "2026-08-03" */
function toIso(d: Date): string {
  return format(d, "yyyy-MM-dd");
}

const PRESETS: { label: string; days: number }[] = [
  { label: "Last 7 days", days: 7 },
  { label: "Last 30 days", days: 30 },
  { label: "Last 90 days", days: 90 },
];

/**
 * One popover, one calendar: click a start day then an end day. Emits ISO
 * date strings (YYYY-MM-DD). Self-contained — no calendar dependency.
 */
export function DateRangePicker({
  from,
  to,
  onChange,
  className,
}: {
  from: string;
  to: string;
  onChange: (from: string, to: string) => void;
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const [month, setMonth] = useState(() => startOfMonth(parseISO(from)));
  const [anchor, setAnchor] = useState<Date | null>(null); // first click, awaiting the second
  const rootRef = useRef<HTMLDivElement>(null);

  const fromDate = parseISO(from);
  const toDate = parseISO(to);

  useEffect(() => {
    if (!open) return;
    setMonth(startOfMonth(parseISO(from)));
    setAnchor(null);
    function onDocClick(e: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", onDocClick);
    return () => document.removeEventListener("mousedown", onDocClick);
  }, [open, from]);

  const days = useMemo(() => {
    const start = startOfWeek(startOfMonth(month), { weekStartsOn: 1 });
    const end = endOfWeek(endOfMonth(month), { weekStartsOn: 1 });
    const out: Date[] = [];
    for (let d = start; !isAfter(d, end); d = addDays(d, 1)) out.push(d);
    return out;
  }, [month]);

  function pick(day: Date) {
    if (!anchor) {
      setAnchor(day);
      return;
    }
    const a = anchor;
    const [s, e] = isBefore(day, a) ? [day, a] : [a, day];
    setAnchor(null);
    onChange(toIso(s), toIso(e));
    setOpen(false);
  }

  function applyPreset(days: number) {
    const end = new Date();
    const start = addDays(end, -(days - 1));
    onChange(toIso(start), toIso(end));
    setOpen(false);
  }

  const rangeStart = anchor ?? fromDate;
  const rangeEnd = anchor ?? toDate;
  const lo = isBefore(rangeStart, rangeEnd) ? rangeStart : rangeEnd;
  const hi = isBefore(rangeStart, rangeEnd) ? rangeEnd : rangeStart;

  return (
    <div ref={rootRef} className={cn("relative", className)}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="flex h-9 items-center gap-2 rounded-md border border-input bg-secondary/60 px-3 text-sm"
      >
        <CalendarDays className="h-4 w-4 text-muted-foreground" />
        {format(fromDate, "dd MMM")} – {format(toDate, "dd MMM yyyy")}
      </button>

      {open && (
        <div className="absolute right-0 z-50 mt-1 w-[280px] rounded-lg border border-border bg-popover p-3 shadow-lg">
          <div className="mb-2 flex items-center justify-between">
            <button type="button" onClick={() => setMonth((m) => addMonths(m, -1))} className="rounded p-1 hover:bg-accent">
              ‹
            </button>
            <span className="text-sm font-medium">{format(month, "MMMM yyyy")}</span>
            <button type="button" onClick={() => setMonth((m) => addMonths(m, 1))} className="rounded p-1 hover:bg-accent">
              ›
            </button>
          </div>

          <div className="grid grid-cols-7 gap-0.5 text-center text-[11px] text-muted-foreground">
            {["M", "T", "W", "T", "F", "S", "S"].map((d, i) => (
              <span key={i} className="py-1">
                {d}
              </span>
            ))}
          </div>
          <div className="grid grid-cols-7 gap-0.5">
            {days.map((day) => {
              const inMonth = isSameMonth(day, month);
              const isEndpoint = isSameDay(day, lo) || isSameDay(day, hi);
              const inRange = !anchor && (isAfter(day, lo) || isSameDay(day, lo)) && (isBefore(day, hi) || isSameDay(day, hi));
              return (
                <button
                  key={day.toISOString()}
                  type="button"
                  onClick={() => pick(day)}
                  className={cn(
                    "h-8 rounded text-xs",
                    !inMonth && "text-muted-foreground/40",
                    isEndpoint
                      ? "bg-primary font-medium text-primary-foreground"
                      : inRange
                        ? "bg-primary/15"
                        : "hover:bg-accent",
                  )}
                >
                  {format(day, "d")}
                </button>
              );
            })}
          </div>

          {anchor && (
            <p className="mt-2 text-center text-[11px] text-muted-foreground">Pick the end date…</p>
          )}

          <div className="mt-3 flex flex-wrap gap-1.5 border-t border-border pt-2">
            {PRESETS.map((p) => (
              <button
                key={p.label}
                type="button"
                onClick={() => applyPreset(p.days)}
                className="rounded-md border border-input px-2 py-1 text-[11px] hover:bg-accent"
              >
                {p.label}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}