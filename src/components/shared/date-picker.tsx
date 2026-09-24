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
  setMonth as setMonthOfYear,
  setYear,
  startOfMonth,
  startOfWeek,
} from "date-fns";
import { CalendarDays, ChevronLeft, ChevronRight } from "lucide-react";
import { cn } from "@/lib/utils";

const WEEKDAYS = ["M", "T", "W", "T", "F", "S", "S"];
const MONTH_NAMES = Array.from({ length: 12 }, (_, i) => format(new Date(2000, i, 1), "MMMM"));

/** "2026-09-23" */
function toIso(d: Date): string {
  return format(d, "yyyy-MM-dd");
}

/**
 * A single-date picker in the app's own calendar style (the sibling of `DateRangePicker`,
 * for one date rather than a range) — Month and Year dropdowns for jumping straight to a
 * decade rather than clicking back a month at a time, which is what a birth date needs. The
 * calendar opens on the selected date's month, or on the current month (today's, so always the
 * real current year) when nothing is picked yet — never a stale hardcoded one.
 */
export function DatePicker({
  value,
  onChange,
  min,
  max,
  placeholder = "Select date",
  triggerClassName,
  align = "left",
}: {
  /** ISO "yyyy-MM-dd", or "" for nothing picked. */
  value: string;
  onChange: (iso: string) => void;
  /** ISO bounds; dates outside them aren't selectable. */
  min?: string;
  max?: string;
  placeholder?: string;
  triggerClassName?: string;
  align?: "left" | "right";
}) {
  const [open, setOpen] = useState(false);
  const selected = value ? parseISO(value) : null;
  const [month, setMonth] = useState(() => startOfMonth(selected ?? new Date()));
  const rootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    setMonth(startOfMonth(selected ?? new Date()));
    function onDocClick(e: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", onDocClick);
    return () => document.removeEventListener("mousedown", onDocClick);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- re-syncs to `value` only on open
  }, [open]);

  const minDate = min ? parseISO(min) : null;
  const maxDate = max ? parseISO(max) : null;
  const years = useMemo(() => {
    const hi = maxDate ? maxDate.getFullYear() : new Date().getFullYear();
    const lo = minDate ? minDate.getFullYear() : hi - 100;
    return Array.from({ length: hi - lo + 1 }, (_, i) => hi - i);
  }, [minDate, maxDate]);

  const days = useMemo(() => {
    const start = startOfWeek(startOfMonth(month), { weekStartsOn: 1 });
    const end = endOfWeek(endOfMonth(month), { weekStartsOn: 1 });
    const out: Date[] = [];
    for (let d = start; !isAfter(d, end); d = addDays(d, 1)) out.push(d);
    return out;
  }, [month]);

  function disabled(day: Date): boolean {
    return (minDate != null && isBefore(day, minDate)) || (maxDate != null && isAfter(day, maxDate));
  }

  function pick(day: Date) {
    if (disabled(day)) return;
    onChange(toIso(day));
    setOpen(false);
  }

  return (
    <div ref={rootRef} className={cn("relative", triggerClassName ? "" : "w-full")}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className={
          triggerClassName ??
          cn(
            "flex h-10 w-full items-center justify-between gap-2 rounded-lg border border-input bg-card px-3 text-left text-sm outline-none transition-colors hover:border-foreground/30",
            !selected && "text-muted-foreground/60",
          )
        }
      >
        <span>{selected ? format(selected, "dd MMM yyyy") : placeholder}</span>
        <CalendarDays className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
      </button>

      {open && (
        <div
          className={cn(
            "absolute z-50 mt-1 w-[260px] rounded-lg border border-border bg-popover p-3 shadow-lg",
            align === "left" ? "left-0" : "right-0",
          )}
        >
          <div className="mb-2 flex items-center gap-1.5">
            <button
              type="button"
              aria-label="Previous month"
              onClick={() => setMonth((m) => addMonths(m, -1))}
              className="flex h-7 w-7 shrink-0 items-center justify-center rounded hover:bg-accent"
            >
              <ChevronLeft className="h-4 w-4" aria-hidden />
            </button>

            <select
              aria-label="Month"
              value={month.getMonth()}
              onChange={(e) => setMonth((m) => setMonthOfYear(m, Number(e.target.value)))}
              className="h-7 flex-1 rounded border border-input bg-card px-1 text-xs outline-none"
            >
              {MONTH_NAMES.map((name, i) => (
                <option key={name} value={i}>
                  {name}
                </option>
              ))}
            </select>

            <select
              aria-label="Year"
              value={month.getFullYear()}
              onChange={(e) => setMonth((m) => setYear(m, Number(e.target.value)))}
              className="h-7 w-[76px] rounded border border-input bg-card px-1 text-xs outline-none"
            >
              {years.map((y) => (
                <option key={y} value={y}>
                  {y}
                </option>
              ))}
            </select>

            <button
              type="button"
              aria-label="Next month"
              onClick={() => setMonth((m) => addMonths(m, 1))}
              className="flex h-7 w-7 shrink-0 items-center justify-center rounded hover:bg-accent"
            >
              <ChevronRight className="h-4 w-4" aria-hidden />
            </button>
          </div>

          <div className="grid grid-cols-7 gap-0.5 text-center text-[11px] text-muted-foreground">
            {WEEKDAYS.map((d, i) => (
              <span key={i} className="py-1">
                {d}
              </span>
            ))}
          </div>
          <div className="grid grid-cols-7 gap-0.5">
            {days.map((day) => {
              const inMonth = isSameMonth(day, month);
              const isSelected = selected != null && isSameDay(day, selected);
              const isToday = isSameDay(day, new Date());
              const off = disabled(day);
              return (
                <button
                  key={day.toISOString()}
                  type="button"
                  disabled={off}
                  onClick={() => pick(day)}
                  className={cn(
                    "h-8 rounded text-xs transition-colors",
                    off && "cursor-not-allowed text-muted-foreground/30",
                    !off && !inMonth && "text-muted-foreground/40",
                    isSelected
                      ? "bg-primary font-medium text-primary-foreground"
                      : !off && (isToday ? "font-semibold text-primary hover:bg-accent" : "hover:bg-accent"),
                  )}
                >
                  {format(day, "d")}
                </button>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
